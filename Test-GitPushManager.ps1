# Test-GitPushManager.ps1
# Unit & Integration Tests for git_push_manager.ps1

$ErrorActionPreference = "Continue"

$scriptPath = Join-Path $PSScriptRoot "core\scripts\git_push_manager.ps1"
if (-not (Test-Path $scriptPath)) {
    Write-Host "HATA: git_push_manager.ps1 bulunamadi!" -ForegroundColor Red
    exit 1
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "TEST: Git Push Yoneticisi Birim Testleri" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$passed = 0
$total = 0

# Test 1: Mevcut Depoda -DryRun Testi
$total++
Write-Host -NoNewline "Test 1: Mevcut Depoda -DryRun Testi ... "
$dryRunOut = (& powershell -NoProfile -File $scriptPath -DryRun 2>&1 | Out-String)
if ($dryRunOut -match "Uzak depo zaten guncel|DRY-RUN") {
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

# Test 3: Izole Gecici Repo ve Remote Simulasyonu
$total++
Write-Host -NoNewline "Test 3: Izole Gecici Repo ve Remote Simulasyonu ... "
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

    # Ilk commit
    "init" | Set-Content "file.txt"
    & git add file.txt
    & git commit -m "chore: initial commit" | Out-Null

    # Push yoneticisi ile calistir
    $pushOut = (& powershell -NoProfile -File $scriptPath 2>&1 | Out-String)
    if ($pushOut -match "GitHub'a basariyla pushlandi|BASARILI") {
        # Ikinci cagri: Zaten guncel olmali
        $secondOut = (& powershell -NoProfile -File $scriptPath 2>&1 | Out-String)
        if ($secondOut -match "Uzak depo zaten guncel") {
            Write-Host "[GECTI OK]" -ForegroundColor Green
            $passed++
        } else {
            Write-Host "[BASARISIZ]: Ikinci cagri 'zaten guncel' demedi: $secondOut" -ForegroundColor Red
        }
    } else {
        Write-Host "[BASARISIZ]: Ilk push basarisiz: $pushOut" -ForegroundColor Red
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
