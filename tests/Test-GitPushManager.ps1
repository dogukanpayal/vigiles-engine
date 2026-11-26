# Test-GitPushManager.ps1
# Unit, Integration & Chaos Tests for git_push_manager.ps1 (/pushprep -> /pushremove / /pushadd -> /push)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $repoRoot "core\scripts\git_push_manager.ps1"
$sentinelPath = Join-Path $repoRoot "core\scripts\sentinel_guard.ps1"

if (-not (Test-Path $scriptPath)) {
    Write-Host "HATA: git_push_manager.ps1 bulunamadi!" -ForegroundColor Red
    exit 1
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "TEST: Iki Asamali Git Pipeline (PushPrep / Remove / Add / Push)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$passed = 0
$total = 0

function Assert-Step([string]$name, [bool]$cond, [string]$detail = "") {
    $script:total++
    if ($cond) {
        Write-Host "  [GECTI OK] $name" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  [BASARISIZ] $name -> $detail" -ForegroundColor Red
    }
}

function Invoke-Manager([string[]]$ManagerArgs) {
    $allArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath, "-SkipTranscriptScan") + $ManagerArgs
    $out = (& powershell @allArgs 2>&1 | Out-String)
    return @{
        ExitCode = $LASTEXITCODE
        Output   = $out
    }
}

function New-IsolatedRepoPair {
    $id = [System.Guid]::NewGuid().ToString().Substring(0, 8)
    $bare = Join-Path $env:TEMP ("vig_bare_" + $id)
    $clone = Join-Path $env:TEMP ("vig_clone_" + $id)
    New-Item -ItemType Directory -Path $bare -Force | Out-Null
    & git init --bare $bare | Out-Null

    New-Item -ItemType Directory -Path $clone -Force | Out-Null
    Push-Location $clone
    & git init -b main | Out-Null
    & git config user.email "test@vigiles.local"
    & git config user.name "Vigiles Tester"
    & git config core.quotepath false
    & git remote add origin $bare
    "initial" | Set-Content -Encoding UTF8 "README_INIT.md"
    & git add README_INIT.md | Out-Null
    & git commit -m "chore: initial commit" | Out-Null
    & git push -u origin main 2>&1 | Out-Null
    Pop-Location

    return @{ Bare = $bare; Clone = $clone }
}

function Remove-IsolatedRepoPair($pair) {
    Remove-Item -Path $pair.Bare -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $pair.Clone -Recurse -Force -ErrorAction SilentlyContinue
}

# Test 1: Mevcut Depoda -DryRun Testi (Manifesto dosyasina dokunmamali)
$gdRes = (& git -C $repoRoot rev-parse --git-dir 2>$null).Trim()
$absGd = if ([System.IO.Path]::IsPathRooted($gdRes)) { $gdRes } else { [System.IO.Path]::GetFullPath((Join-Path $repoRoot $gdRes)) }
$wsManifestPath = Join-Path $absGd "vigiles\pushprep_cli.json"
$hadManifestBefore = Test-Path $wsManifestPath
Push-Location $repoRoot
$r1 = Invoke-Manager @("-DryRun")
Pop-Location
$hasManifestAfter = Test-Path $wsManifestPath
Assert-Step "Test 1: Mevcut Depoda -DryRun Onizleme / Guncel Kontrolu (Salt-Okunur)" `
    ($r1.ExitCode -eq 0 -and ($hadManifestBefore -eq $hasManifestAfter) -and ($r1.Output -match "Uzak depo zaten guncel|DRY-RUN|ZORUNLU ONIZLEME")) `
    "Exit=$($r1.ExitCode) Before=$hadManifestBefore After=$hasManifestAfter"

# Test 2: Git Olmayan Dizinde Guvenlik Engeli
$tempNonGit = Join-Path $env:TEMP ("nongit_" + [System.Guid]::NewGuid().ToString().Substring(0, 8))
New-Item -ItemType Directory -Path $tempNonGit -Force | Out-Null
try {
    Push-Location $tempNonGit
    $r2 = Invoke-Manager @()
    Assert-Step "Test 2: Git Olmayan Dizinde Guvenlik Engeli" `
        ($r2.ExitCode -eq 1 -and $r2.Output -match "Git deposu degil") `
        "Exit=$($r2.ExitCode) Out=$($r2.Output)"
} finally {
    Pop-Location
    Remove-Item -Path $tempNonGit -Recurse -Force -ErrorAction SilentlyContinue
}

# Test 3: Zorunlu Onizleme Kapisi (/pushprep olmadan dogrudan /push ExitCode 2 donmeli)
$p3 = New-IsolatedRepoPair
try {
    Push-Location $p3.Clone
    "hello" | Set-Content -Encoding UTF8 "feature_a.txt"
    $r3 = Invoke-Manager @("-Action", "Push", "-CommitMessage", "feat: direct push")
    Push-Location $p3.Bare
    $bareFiles3 = (& git ls-tree -r --name-only main 2>&1 | Out-String)
    Pop-Location
    Assert-Step "Test 3: Zorunlu Onizleme Kapisi (/pushprep yoksa ExitCode 2 & Push yok)" `
        ($r3.ExitCode -eq 2 -and $r3.Output -match "ONIZLEME GEREKLI" -and $bareFiles3 -notmatch "feature_a\.txt") `
        "Exit=$($r3.ExitCode) BareFiles=$bareFiles3"
} finally {
    Pop-Location
    Remove-IsolatedRepoPair $p3
}

# Test 4: /pushprep (-uall klasor acma + sifir calisma dizini kirliligi)
$p4 = New-IsolatedRepoPair
try {
    Push-Location $p4.Clone
    New-Item -ItemType Directory -Path "yeni_klasor" -Force | Out-Null
    "d1" | Set-Content -Encoding UTF8 "yeni_klasor\bir.txt"
    "d2" | Set-Content -Encoding UTF8 "yeni_klasor\iki.txt"
    $r4 = Invoke-Manager @("-Action", "Prep")
    $manifestExists = Test-Path (Join-Path $p4.Clone ".git\vigiles\pushprep_cli.json")
    $gitStatusRaw = (& git status --porcelain 2>&1 | Out-String)
    Assert-Step "Test 4: /pushprep -uall tekil numaralandirma & calisma agaci temizligi" `
        ($r4.ExitCode -eq 0 -and $manifestExists -and $r4.Output -match "yeni_klasor/bir\.txt" -and $r4.Output -match "yeni_klasor/iki\.txt" -and $gitStatusRaw -notmatch "pushprep") `
        "Manifest=$manifestExists Out=$($r4.Output)"
} finally {
    Pop-Location
    Remove-IsolatedRepoPair $p4
}

# Test 5: /pushremove Sira Numarasiyla Cikarma + Yerel Dosya Koruma + Secici /push
$p5 = New-IsolatedRepoPair
try {
    Push-Location $p5.Clone
    "aaa" | Set-Content -Encoding UTF8 "alpha.txt"
    "bbb" | Set-Content -Encoding UTF8 "beta_keep_local.txt"
    "ccc" | Set-Content -Encoding UTF8 "gamma.txt"

    Invoke-Manager @("-Action", "Prep") | Out-Null
    $m5 = Get-Content -Raw -Encoding UTF8 ".git\vigiles\pushprep_cli.json" | ConvertFrom-Json
    $betaId = ($m5.items | Where-Object { $_.path -eq "beta_keep_local.txt" }).id

    $rem5 = Invoke-Manager @("-Action", "Remove", "-Targets", "$betaId")
    $push5 = Invoke-Manager @("-Action", "Push", "-CommitMessage", "feat: selective push test")

    $localBetaStillExists = Test-Path (Join-Path $p5.Clone "beta_keep_local.txt")
    Push-Location $p5.Bare
    $bareTree5 = (& git ls-tree -r --name-only main 2>&1 | Out-String)
    Pop-Location

    Assert-Step "Test 5: /pushremove ile cikarilan dosya yerelde korunur, sadece onaylilar GitHub'a gider" `
        ($rem5.ExitCode -eq 0 -and $push5.ExitCode -eq 0 -and $localBetaStillExists -and ($bareTree5 -match "alpha\.txt") -and ($bareTree5 -match "gamma\.txt") -and ($bareTree5 -notmatch "beta_keep_local\.txt")) `
        "LocalBeta=$localBetaStillExists Bare=$bareTree5"
} finally {
    Pop-Location
    Remove-IsolatedRepoPair $p5
}

# Test 6: /pushremove -Ignore (.gitignore kalici gizleme)
$p6 = New-IsolatedRepoPair
try {
    Push-Location $p6.Clone
    "ok" | Set-Content -Encoding UTF8 "valid_code.txt"
    "local log" | Set-Content -Encoding UTF8 "scratch_note.log"

    Invoke-Manager @("-Action", "Prep") | Out-Null
    $rem6 = Invoke-Manager @("-Action", "Remove", "-Targets", "scratch_note.log", "-Ignore")
    $push6 = Invoke-Manager @("-Action", "Push", "-CommitMessage", "chore: add code and ignore scratch log")

    $giContent = Get-Content -Raw -Encoding UTF8 ".gitignore"
    $localLogExists = Test-Path "scratch_note.log"
    Push-Location $p6.Bare
    $bareTree6 = (& git ls-tree -r --name-only main 2>&1 | Out-String)
    Pop-Location

    Assert-Step "Test 6: /pushremove -Ignore .gitignore'a isler, yerel dosyayi korur ve pushlamaz" `
        ($rem6.ExitCode -eq 0 -and $push6.ExitCode -eq 0 -and $localLogExists -and ($giContent -match "scratch_note\.log") -and ($bareTree6 -match "valid_code\.txt") -and ($bareTree6 -match "\.gitignore") -and ($bareTree6 -notmatch "scratch_note\.log")) `
        "GI=$giContent Bare=$bareTree6"
} finally {
    Pop-Location
    Remove-IsolatedRepoPair $p6
}

# Test 7: /pushadd ile Geri Alma ve .gitignore Istisnasi Ekleme
$p7 = New-IsolatedRepoPair
try {
    Push-Location $p7.Clone
    "*.bak" | Set-Content -Encoding UTF8 ".gitignore"
    "backup data" | Set-Content -Encoding UTF8 "important.bak"
    "code1" | Set-Content -Encoding UTF8 "main.ps1"

    Invoke-Manager @("-Action", "Prep") | Out-Null
    Invoke-Manager @("-Action", "Remove", "-Targets", "main.ps1") | Out-Null
    $addBack = Invoke-Manager @("-Action", "Add", "-Targets", "main.ps1")
    $addIgnored = Invoke-Manager @("-Action", "Add", "-Targets", "important.bak")
    $push7 = Invoke-Manager @("-Action", "Push", "-CommitMessage", "feat: pushadd restore and gitignore exception")

    Push-Location $p7.Bare
    $bareTree7 = (& git ls-tree -r --name-only main 2>&1 | Out-String)
    Pop-Location

    Assert-Step "Test 7: /pushadd cikarilani geri alir ve guvenli .gitignore dosyasini pakete ekler" `
        ($addBack.ExitCode -eq 0 -and $addIgnored.ExitCode -eq 0 -and $push7.ExitCode -eq 0 -and ($bareTree7 -match "main\.ps1") -and ($bareTree7 -match "important\.bak")) `
        "Bare=$bareTree7"
} finally {
    Pop-Location
    Remove-IsolatedRepoPair $p7
}

# Test 8: Zero-Leak Guvenlik Kalkani (.env & API Anahtari Bloklama)
$p8 = New-IsolatedRepoPair
try {
    Push-Location $p8.Clone
    "SECRET=123" | Set-Content -Encoding UTF8 ".env"
    $fakeAws = "AKIA" + "IOSFODNN7EXAMPLE"
    "aws_key=$fakeAws" | Set-Content -Encoding UTF8 "leak_file.txt"
    "safe=1" | Set-Content -Encoding UTF8 "clean_file.txt"

    Invoke-Manager @("-Action", "Prep") | Out-Null
    $m8 = Get-Content -Raw -Encoding UTF8 ".git\vigiles\pushprep_cli.json" | ConvertFrom-Json
    $envItem = $m8.items | Where-Object { $_.path -eq ".env" }
    $leakItem = $m8.items | Where-Object { $_.path -eq "leak_file.txt" }

    $addEnvRes = Invoke-Manager @("-Action", "Add", "-Targets", ".env")
    $addLeakRes = Invoke-Manager @("-Action", "Add", "-Targets", "leak_file.txt")
    $push8 = Invoke-Manager @("-Action", "Push", "-CommitMessage", "feat: only clean file")

    Push-Location $p8.Bare
    $bareTree8 = (& git ls-tree -r --name-only main 2>&1 | Out-String)
    Pop-Location

    Assert-Step "Test 8: Zero-Leak Kalkan (.env ve API key dislanir, /pushadd ile bile eklenemez)" `
        ((-not $envItem.included) -and (-not $leakItem.included) -and $addEnvRes.ExitCode -eq 1 -and $addLeakRes.ExitCode -eq 1 -and $push8.ExitCode -eq 0 -and ($bareTree8 -match "clean_file\.txt") -and ($bareTree8 -notmatch "\.env") -and ($bareTree8 -notmatch "leak_file\.txt")) `
        "EnvInc=$($envItem.included) AddEnvExit=$($addEnvRes.ExitCode) Bare=$bareTree8"
} finally {
    Pop-Location
    Remove-IsolatedRepoPair $p8
}

# Test 9: Aralik (1-2) & Belirsiz Dosya Adi (Ambiguous) Kontrolu
$p9 = New-IsolatedRepoPair
try {
    Push-Location $p9.Clone
    New-Item -ItemType Directory -Path "dir1" -Force | Out-Null
    New-Item -ItemType Directory -Path "dir2" -Force | Out-Null
    "1" | Set-Content -Encoding UTF8 "dir1\same.txt"
    "2" | Set-Content -Encoding UTF8 "dir2\same.txt"
    "3" | Set-Content -Encoding UTF8 "z_last.txt"

    Invoke-Manager @("-Action", "Prep") | Out-Null
    $ambRes = Invoke-Manager @("-Action", "Remove", "-Targets", "same.txt")
    $rangeRes = Invoke-Manager @("-Action", "Remove", "-Targets", "1-2")
    $m9 = Get-Content -Raw -Encoding UTF8 ".git\vigiles\pushprep_cli.json" | ConvertFrom-Json
    $inc9 = @($m9.items | Where-Object { $_.included })

    Assert-Step "Test 9: Belirsiz dosya adi uyarisi & 1-2 aralikli toplu /pushremove" `
        ($ambRes.ExitCode -eq 1 -and $ambRes.Output -match "birden fazla dosya" -and $rangeRes.ExitCode -eq 0 -and $inc9.Count -eq 1 -and $inc9[0].path -eq "z_last.txt") `
        "AmbExit=$($ambRes.ExitCode) Remaining=$($inc9.path)"
} finally {
    Pop-Location
    Remove-IsolatedRepoPair $p9
}

# Test 10: Turkce/Bosluklu Dosya Adlari & Prep Sonrasi Drift Korumasi
$p10 = New-IsolatedRepoPair
try {
    Push-Location $p10.Clone
    $trDir = "yeni klasör"
    New-Item -ItemType Directory -Path $trDir -Force | Out-Null
    "merhaba dünya" | Set-Content -Encoding UTF8 "$trDir\türkçe şğüöçı not.txt"

    $prep10 = Invoke-Manager @("-Action", "Prep")
    "drift" | Set-Content -Encoding UTF8 "sonradan_gelen.txt"
    $driftRes = Invoke-Manager @("-Action", "Push", "-CommitMessage", "feat: turkish path")
    $push10 = Invoke-Manager @("-Action", "Push", "-Approved", "-CommitMessage", "feat: turkish path")

    Push-Location $p10.Bare
    $bareTree10 = (& git -c core.quotepath=false ls-tree -r --name-only main 2>&1 | Out-String)
    Pop-Location

    Assert-Step "Test 10: Turkce/bosluklu dosya adlari & /pushprep sonrasi Drift Korumasi" `
        ($prep10.ExitCode -eq 0 -and $driftRes.ExitCode -eq 2 -and $push10.ExitCode -eq 0 -and ($bareTree10 -match "şğüöçı") -and ($bareTree10 -notmatch "sonradan_gelen\.txt")) `
        "DriftExit=$($driftRes.ExitCode) Bare=$bareTree10"
} finally {
    Pop-Location
    Remove-IsolatedRepoPair $p10
}

# Test 11: Silinmis (D) ve Degismis (M) Dosyalarin Secici Sahnelenmesi
$p11 = New-IsolatedRepoPair
try {
    Push-Location $p11.Clone
    "v1" | Set-Content -Encoding UTF8 "to_delete.txt"
    "v2" | Set-Content -Encoding UTF8 "keep_modified.txt"
    & git add -A | Out-Null
    & git commit -m "chore: setup delete test" | Out-Null
    & git push origin main 2>&1 | Out-Null

    Remove-Item "to_delete.txt" -Force
    "v3" | Set-Content -Encoding UTF8 "keep_modified.txt"
    Invoke-Manager @("-Action", "Prep") | Out-Null
    $push11 = Invoke-Manager @("-Action", "Push", "-CommitMessage", "refactor: delete and update")

    Push-Location $p11.Bare
    $bareTree11 = (& git ls-tree -r --name-only main 2>&1 | Out-String)
    Pop-Location

    Assert-Step "Test 11: Silinmis (D) ve degismis (M) dosyalarin secici sahnelenmesi" `
        ($push11.ExitCode -eq 0 -and ($bareTree11 -notmatch "to_delete\.txt") -and ($bareTree11 -match "keep_modified\.txt")) `
        "Bare=$bareTree11"
} finally {
    Pop-Location
    Remove-IsolatedRepoPair $p11
}

# Test 12: sentinel_guard.ps1 -Action Add .env Engeli & UTF-8 BOM Kontrolu
$tempGuardDir = Join-Path ([System.IO.Path]::GetTempPath()) "vig_guard_$(Get-Random)"
New-Item -ItemType Directory -Path $tempGuardDir -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $tempGuardDir ".vigiles_active") -Force | Out-Null
try {
    $payload = @{
        conversationId        = "git-guard-test"
        artifactDirectoryPath = $tempGuardDir
        toolCall              = @{
            name = "run_command"
            args = @{ CommandLine = "powershell -File git_push_manager.ps1 -Action Add -Targets .env" }
        }
    } | ConvertTo-Json -Depth 5 -Compress

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "powershell.exe"
    $pinfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$sentinelPath`""
    $pinfo.RedirectStandardInput = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $proc = [System.Diagnostics.Process]::Start($pinfo)
    $proc.StandardInput.Write($payload)
    $proc.StandardInput.Close()
    $guardOut = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()

    $bomBytes = [System.IO.File]::ReadAllBytes($scriptPath)
    $hasBom = ($bomBytes.Length -ge 3 -and $bomBytes[0] -eq 0xEF -and $bomBytes[1] -eq 0xBB -and $bomBytes[2] -eq 0xBF)

    Assert-Step "Test 12: sentinel_guard.ps1 .env PushAdd Engeli & git_push_manager.ps1 UTF-8 BOM" `
        (($guardOut -match '"decision"\s*:\s*"deny"') -and $hasBom) `
        "GuardOut=$guardOut HasBOM=$hasBom"
} finally {
    Remove-Item -Path $tempGuardDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Test 13: Modern sk-proj-* OpenAI Anahtari Engeli & .env.example Izni
$p13 = New-IsolatedRepoPair
try {
    Push-Location $p13.Clone
    "API_KEY=" | Set-Content -Encoding UTF8 ".env.example"
    $fakeProjKey = "sk-proj-" + ("A1b2C3d4E5f6_" * 2)
    "key=$fakeProjKey" | Set-Content -Encoding UTF8 "proj_secret.txt"

    Invoke-Manager @("-Action", "Prep") | Out-Null
    $m13 = Get-Content -Raw -Encoding UTF8 ".git\vigiles\pushprep_cli.json" | ConvertFrom-Json
    $exItem = $m13.items | Where-Object { $_.path -eq ".env.example" }
    $projItem = $m13.items | Where-Object { $_.path -eq "proj_secret.txt" }
    $push13 = Invoke-Manager @("-Action", "Push", "-CommitMessage", "docs: add env example")

    Push-Location $p13.Bare
    $bareTree13 = (& git ls-tree -r --name-only main 2>&1 | Out-String)
    Pop-Location

    Assert-Step "Test 13: Modern sk-proj-* anahtari engellenirken .env.example guvenle pushlanir" `
        ($exItem.included -and (-not $projItem.included) -and $push13.ExitCode -eq 0 -and ($bareTree13 -match "\.env\.example") -and ($bareTree13 -notmatch "proj_secret\.txt")) `
        "ExInc=$($exItem.included) ProjInc=$($projItem.included)"
} finally {
    Pop-Location
    Remove-IsolatedRepoPair $p13
}

# Test 14: Rename (git mv) Durumunda Stage Parity & Basarili Push
$p14 = New-IsolatedRepoPair
try {
    Push-Location $p14.Clone
    1..10 | ForEach-Object { "line $_ original content" } | Set-Content -Encoding UTF8 "old_name.txt"
    & git add old_name.txt | Out-Null
    & git commit -m "feat: add old_name" | Out-Null
    & git push origin main 2>&1 | Out-Null

    & git mv old_name.txt renamed_name.txt | Out-Null
    Invoke-Manager @("-Action", "Prep") | Out-Null
    $push14 = Invoke-Manager @("-Action", "Push", "-CommitMessage", "refactor: rename file")

    Push-Location $p14.Bare
    $bareTree14 = (& git ls-tree -r --name-only main 2>&1 | Out-String)
    Pop-Location

    Assert-Step "Test 14: Rename (git mv) Stage Parity dogrulamasi & basarili push" `
        ($push14.ExitCode -eq 0 -and ($bareTree14 -match "renamed_name\.txt") -and ($bareTree14 -notmatch "old_name\.txt")) `
        "Bare=$bareTree14"
} finally {
    Pop-Location
    Remove-IsolatedRepoPair $p14
}

Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
Write-Host "SONUC: $passed / $total Test Basariyla Gecti." -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Red" })

if ($passed -ne $total) {
    exit 1
}
