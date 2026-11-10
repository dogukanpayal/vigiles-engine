# Test-SentinelGuardRoleDispatch.ps1
# Vigiles TDD Test Paketi: Akilli Rol Dagitimi ve Telemetri Ziplamasi Onleme Dogrulamasi

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$global:passedCount = 0
$global:failedCount = 0

function Assert-Test([string]$testName, [bool]$condition, [string]$detail = "") {
    if ($condition) {
        Write-Host "  [GECTI] $testName" -ForegroundColor Green
        if ($detail) { Write-Host "     -> $detail" -ForegroundColor DarkGray }
        $global:passedCount++
    } else {
        Write-Host "  [BASARISIZ] $testName" -ForegroundColor Red
        if ($detail) { Write-Host "     -> HATA: $detail" -ForegroundColor Yellow }
        $global:failedCount++
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "VIGILES TDD: AKILLI ROL DAGITIMI & TELEMETRI TESTI" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$scriptToTest = "c:\Users\Dogukan\Desktop\Antigravity Improvement\core\scripts\sentinel_guard.ps1"
if (-not (Test-Path $scriptToTest)) {
    $scriptToTest = Join-Path $HOME ".gemini\config\scripts\sentinel_guard.ps1"
}

$tempTestDir = Join-Path ([System.IO.Path]::GetTempPath()) "vigiles_role_test_$(Get-Random)"
New-Item -ItemType Directory -Path $tempTestDir -Force | Out-Null
# Vigiles aktiflik isareti
New-Item -ItemType File -Path (Join-Path $tempTestDir ".vigiles_active") -Force | Out-Null

function Run-GuardSimulation([hashtable]$toolCallPayload) {
    $payloadObj = @{
        conversationId        = "role-test-session-001"
        artifactDirectoryPath = $tempTestDir
        workspacePaths        = @("C:\TestWorkspace")
        toolCall              = $toolCallPayload
    }
    $json = $payloadObj | ConvertTo-Json -Depth 6 -Compress

    $stateFile = Join-Path $tempTestDir "live_state.json"
    if (Test-Path $stateFile) { Remove-Item $stateFile -Force }

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "powershell.exe"
    $pinfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptToTest`""
    $pinfo.RedirectStandardInput = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false

    $p = [System.Diagnostics.Process]::Start($pinfo)
    $p.StandardInput.Write($json)
    $p.StandardInput.Close()
    $stdout = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()

    $state = $null
    if (Test-Path $stateFile) {
        try {
            $state = Get-Content -Raw -Encoding UTF8 $stateFile | ConvertFrom-Json
        } catch {}
    }
    return @{ State = $state; Stdout = $stdout }
}

try {
    # 1. Salt-Okunur Git Komutlari (Asla Git Fabrikasi Olmamali -> Bas Mimar Kesif Olmali)
    Write-Host "`n[Grup 1: Salt-Okunur Git Komutlari]" -ForegroundColor Yellow
    $gitReadOnlyCmds = @("git status", "git status -s", "git diff", "git diff HEAD~1", "git log -n 5 --oneline", "git branch -a", "git remote -v", "git show --stat")
    foreach ($cmd in $gitReadOnlyCmds) {
        $res = Run-GuardSimulation @{ name = "run_command"; args = @{ CommandLine = $cmd } }
        $node = if ($res.State) { $res.State.activeNode } else { "null" }
        Assert-Test "'$cmd' -> node-architect olmali (node-pr DEGIL)" ($node -eq "node-architect") "Aktif Düğüm: $node"
    }

    # 2. Gercek Dagitim Git Komutlari (Git & PR Fabrikasi Olmali)
    Write-Host "`n[Grup 2: Gercek Versiyonlama ve Dagitim Git Komutlari]" -ForegroundColor Yellow
    $gitWriteCmds = @("git commit -m 'feat: test'", "git push origin feature-x", "powershell -File C:\scripts\git_push_manager.ps1", "gh pr create --title 'Test PR'")
    foreach ($cmd in $gitWriteCmds) {
        $res = Run-GuardSimulation @{ name = "run_command"; args = @{ CommandLine = $cmd } }
        $node = if ($res.State) { $res.State.activeNode } else { "null" }
        Assert-Test "'$cmd' -> node-pr olmali" ($node -eq "node-pr") "Aktif Düğüm: $node"
    }

    # 3. Dosya ve Dizin Kesif Komutlari (Isciler DEGIL -> Bas Mimar Kesif Olmali)
    Write-Host "`n[Grup 3: Dosya ve Dizin Kesif Komutlari]" -ForegroundColor Yellow
    $discoveryCmds = @("dir C:\test", "Get-ChildItem -Recurse", "ls", "tree /F", "Get-Content app.json", "type config.txt", "cat package.json", "findstr /i error log.txt", "Select-String -Path *.js -Pattern test")
    foreach ($cmd in $discoveryCmds) {
        $res = Run-GuardSimulation @{ name = "run_command"; args = @{ CommandLine = $cmd } }
        $node = if ($res.State) { $res.State.activeNode } else { "null" }
        Assert-Test "'$cmd' -> node-architect olmali (node-workers DEGIL)" ($node -eq "node-architect") "Aktif Düğüm: $node"
    }

    # 4. Genel Dosya Okuma (read_file) Kor Noktasinin Giderilmesi
    Write-Host "`n[Grup 4: read_file Kor Noktasi ve Mimari Inceleme]" -ForegroundColor Yellow
    $readFiles = @("C:\src\index.js", "C:\config\package.json", "C:\README.md", "C:\hooks.json")
    foreach ($f in $readFiles) {
        $res = Run-GuardSimulation @{ name = "read_file"; args = @{ Path = $f } }
        $node = if ($res.State) { $res.State.activeNode } else { "null" }
        Assert-Test "read_file '$f' -> node-architect olmali" ($node -eq "node-architect") "Aktif Düğüm: $node"
    }

    # 5. Ozel Santiye Dosyalari (DURUM, KURALLAR)
    Write-Host "`n[Grup 5: Ozel Santiye Dosyalari]" -ForegroundColor Yellow
    $res = Run-GuardSimulation @{ name = "write_file"; args = @{ Path = "C:\workspace\DURUM.md"; Content = "# Plan" } }
    Assert-Test "write_file DURUM.md -> node-architect" ($res.State -and $res.State.activeNode -eq "node-architect") "Aktif Düğüm: $($res.State.activeNode)"

    $res = Run-GuardSimulation @{ name = "write_file"; args = @{ Path = "C:\workspace\KURALLAR.md"; Content = "# Kurallar" } }
    Assert-Test "write_file KURALLAR.md -> node-memory" ($res.State -and $res.State.activeNode -eq "node-memory") "Aktif Düğüm: $($res.State.activeNode)"

    # 6. Isciler, Testci, Kaos ve Diger Roller
    Write-Host "`n[Grup 6: Isciler, Testci, Kaos, Saha Sefi]" -ForegroundColor Yellow
    $res = Run-GuardSimulation @{ name = "write_file"; args = @{ Path = "C:\src\server.js"; Content = "const a = 1;" } }
    Assert-Test "write_file server.js -> node-workers (Asama 6)" ($res.State -and $res.State.activeNode -eq "node-workers") "Aktif Düğüm: $($res.State.activeNode)"

    $res = Run-GuardSimulation @{ name = "run_command"; args = @{ CommandLine = "node server.js" } }
    Assert-Test "run_command 'node server.js' -> node-workers (Asama 7)" ($res.State -and $res.State.activeNode -eq "node-workers") "Aktif Düğüm: $($res.State.activeNode)"

    $res = Run-GuardSimulation @{ name = "run_command"; args = @{ CommandLine = "npm test" } }
    Assert-Test "run_command 'npm test' -> node-tester (Asama 5)" ($res.State -and $res.State.activeNode -eq "node-tester") "Aktif Düğüm: $($res.State.activeNode)"

    $res = Run-GuardSimulation @{ name = "run_command"; args = @{ CommandLine = "powershell -File .\Chaos-LoadTest.ps1" } }
    Assert-Test "run_command 'Chaos-LoadTest.ps1' -> node-chaos (Asama 8)" ($res.State -and $res.State.activeNode -eq "node-chaos") "Aktif Düğüm: $($res.State.activeNode)"

    $res = Run-GuardSimulation @{ name = "invoke_subagent"; args = @{ Role = "Backend Dev" } }
    Assert-Test "invoke_subagent -> node-chief (Asama 4)" ($res.State -and $res.State.activeNode -eq "node-chief") "Aktif Düğüm: $($res.State.activeNode)"

    $res = Run-GuardSimulation @{ name = "ask_question"; args = @{ questions = @() } }
    Assert-Test "ask_question -> node-gatekeeper (Asama 3)" ($res.State -and $res.State.activeNode -eq "node-gatekeeper") "Aktif Düğüm: $($res.State.activeNode)"

} finally {
    if (Test-Path $tempTestDir) {
        Remove-Item -Path $tempTestDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
$color = if ($global:failedCount -eq 0) { "Green" } else { "Red" }
Write-Host "TEST SONUCLARI: $global:passedCount Gecti | $global:failedCount Basarisiz" -ForegroundColor $color
Write-Host "==========================================================" -ForegroundColor Cyan

if ($global:failedCount -gt 0) {
    exit 1
} else {
    exit 0
}
