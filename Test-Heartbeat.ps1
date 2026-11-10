param(
    [switch]$VerboseOutput
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$scriptRoot = $PSScriptRoot
$sentinelScript = Join-Path $scriptRoot "core\scripts\heartbeat_sentinel.ps1"
$managerScript = Join-Path $scriptRoot "core\scripts\manage_heartbeat.ps1"
$testLog = Join-Path $scriptRoot "test_heartbeat.log"

Write-Host "🧪 [ÖZEL TESTER]: TDD Birim Testleri Başlatılıyor (Kota Dürtücüsü)..." -ForegroundColor Cyan

$passed = 0
$failed = 0

function Assert-Test([string]$name, [scriptblock]$condition) {
    try {
        $result = & $condition
        if ($result) {
            Write-Host "  ✅ [GEÇTİ] $name" -ForegroundColor Green
            $script:passed++
        } else {
            Write-Host "  ❌ [BAŞARISIZ] $name" -ForegroundColor Red
            $script:failed++
        }
    } catch {
        Write-Host "  ❌ [HATA] $name -> $($_.Exception.Message)" -ForegroundColor Red
        $script:failed++
    }
}

# 1. Dosya Varlığı Testi
Assert-Test "1. heartbeat_sentinel.ps1 betik dosyası mevcut olmalı" {
    Test-Path $sentinelScript
}

Assert-Test "2. manage_heartbeat.ps1 yönetim betiği mevcut olmalı" {
    Test-Path $managerScript
}

# 2. Kuru Koşum (DryRun) Testi
if (Test-Path $testLog) { Remove-Item $testLog -Force }

Assert-Test "3. DryRun ve Once modu ile hatasız çalışmalı ve log üretmeli" {
    if (-not (Test-Path $sentinelScript)) { return $false }
    & powershell -NoProfile -ExecutionPolicy Bypass -File $sentinelScript -Once -DryRun -LogPath $testLog
    $exitCode = $LASTEXITCODE
    $hasLog = Test-Path $testLog
    return ($exitCode -eq 0 -and $hasLog)
}

# 3. Log İçeriği Doğrulaması
Assert-Test "4. Log dosyası geçerli zaman damgası ve DRY-RUN kaydı içermeli" {
    if (-not (Test-Path $testLog)) { return $false }
    $content = Get-Content $testLog -Raw -Encoding UTF8
    return ($content -match "DRY-RUN" -and $content -match "\d{4}-\d{2}-\d{2}")
}

# 4. Parametre Denetimi
Assert-Test "5. IntervalHours parametresi varsayılan 5 saat olarak yapılandırılmalı" {
    if (-not (Test-Path $sentinelScript)) { return $false }
    $cmd = Get-Command $sentinelScript
    $param = $cmd.Parameters["IntervalHours"]
    return ($param -ne $null)
}

# 5. Yönetim Betiği 'status' Testi
Assert-Test "6. manage_heartbeat.ps1 'status' aksiyonunu desteklemeli" {
    if (-not (Test-Path $managerScript)) { return $false }
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $managerScript -Action status 2>&1
    return ($LASTEXITCODE -eq 0)
}

# Temizlik
if (Test-Path $testLog) { Remove-Item $testLog -Force }

Write-Host "---"
Write-Host "Sonuç: $passed Geçti, $failed Başarısız" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })

if ($failed -gt 0) {
    exit 1
} else {
    exit 0
}
