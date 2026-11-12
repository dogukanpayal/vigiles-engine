# Test-GitPushManager.ps1
# Unit & Integration Tests for git_push_manager.ps1 (Add -> Commit -> Push Pipeline)

$ErrorActionPreference = "Continue"

$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) "core\scripts\git_push_manager.ps1"
if (-not (Test-Path $scriptPath)) {
    Write-Host "HATA: git_push_manager.ps1 bulunamadi!" -ForegroundColor Red
    exit 1
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "TEST: Git Pipeline (Add/Commit/Push) Birim Testleri" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$passed = 0
$total = 0

# Test 1: Mevcut Depoda -DryRun Testi
$total++
Write-Host -NoNewline "Test 1: Mevcut Depoda -DryRun Testi ... "
$dryRunOut = (& powershell -NoProfile -File $scriptPath -DryRun 2>&1 | Out-String)
if ($dryRunOut -match "Uzak depo zaten guncel|DRY-RUN|Pushlanacak Commitler") {
    Write-Host "[GECTI OK]" -ForegroundColor Green
    $passed++
} else {
    Write-Host "[BASARISIZ]: $dryRunOut" -ForegroundColor Red
}

# Test 2: Git Olmayan Dizinde Guvenlik Engeli
$total++
Write-Host -NoNewline "Test 2: Git Olmayan Dizinde Guvenlik Engeli ... "
$tempNonGit = Join-Path $env:TEMP ("nongit_" + [System.Guid]::NewGuid().ToString().Substring(0,8))
New-Item -ItemType Directory -Path $tempNonGit -Force | Out-Null
try {
    Push-Location $tempNonGit
    $nonGitOut = (& powershell -NoProfile -File $scriptPath 2>&1 | Out-String)
    if ($nonGitOut -match "Git deposu degil") {
        Write-Host "[GECTI OK]" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[BASARISIZ]: $nonGitOut" -ForegroundColor Red
    }
} finally {
    Pop-Location
    Remove-Item -Path $tempNonGit -Recurse -Force -ErrorAction SilentlyContinue
}

# Test 3: Izole Repo uzerinde Tek Komutla (Add -> Commit -> Push) Uctan Uca Test
$total++
Write-Host -NoNewline "Test 3: Uctan Uca Pipeline (Add -> Commit -> Push) ... "
$tempBare = Join-Path $env:TEMP ("bare_" + [System.Guid]::NewGuid().ToString().Substring(0,8))
$tempClone = Join-Path $env:TEMP ("clone_" + [System.Guid]::NewGuid().ToString().Substring(0,8))
try {
    # 1. Bare repo olustur (Uzak sunucu)
    New-Item -ItemType Directory -Path $tempBare -Force | Out-Null
    & git init --bare $tempBare | Out-Null

    # 2. Calisma reposu olustur
    New-Item -ItemType Directory -Path $tempClone -Force | Out-Null
    Push-Location $tempClone
    & git init -b main | Out-Null
    & git config user.email "test@vigiles.local"
    & git config user.name "Vigiles Tester"
    & git remote add origin $tempBare

    # Dosya olusturuldu ama add veya commit YAPILMADI (Dirty state)
    "Hello Vigiles Pipeline" | Set-Content "pipeline_test.txt"

    # Pipeline yoneticisini calistir (Tek komutla add + commit + push yapmali)
    $pushOut = (& powershell -NoProfile -File $scriptPath -CommitMessage "feat: test all-in-one pipeline" 2>&1 | Out-String)
    if ($pushOut -match "Pipeline tamamlandi|BASARILI") {
        # Bare repo uzerinde commit ulasti mi kontrol et
        Push-Location $tempBare
        $bareLog = (& git log --all --oneline 2>&1 | Out-String)
        Pop-Location

        if ($bareLog -match "feat: test all-in-one pipeline") {
            Write-Host "[GECTI OK]" -ForegroundColor Green
            $passed++
        } else {
            Write-Host "[BASARISIZ]: Commit bare repoya ulasmadi: $bareLog" -ForegroundColor Red
        }
    } else {
        Write-Host "[BASARISIZ]: Pipeline calismadi: $pushOut" -ForegroundColor Red
    }
} finally {
    Pop-Location
    Remove-Item -Path $tempBare -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $tempClone -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
Write-Host "SONUC: $passed / $total Test Basariyla Gecti." -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Red" })

if ($passed -ne $total) {
    exit 1
}
