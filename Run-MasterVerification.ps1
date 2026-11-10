# Run-MasterVerification.ps1
# 20 Elemanlı Veteran Otonom Fabrika - Büyük Sistem Doğrulama Testi

$ErrorActionPreference = "Continue"
$ws = "c:\Users\Dogukan\Desktop\Antigravity Improvement"
$suites = @(
    "Test-Auth.ps1",
    "Test-Coupon.ps1",
    "Test-Wallet.ps1",
    "Test-TwoFactor.ps1",
    "Test-GitPushManager.ps1",
    "Test-Heartbeat.ps1",
    "Test-MultiSessionTelemetri.ps1",
    "Test-WorkersSubNodes.ps1",
    "Test-AuxiliarySection.ps1",
    "Test-VigilesLightIntegrity.ps1",
    "Test-VigilesIsolation.ps1",
    "Test-VigilesConsiliumIntegrity.ps1",
    "Test-ConsiliumScenarioSimulation.ps1",
    "Test-SentinelGuardRoleDispatch.ps1",
    "Chaos-Coupon.ps1",
    "Chaos-Wallet.ps1",
    "Chaos-TwoFactor.ps1",
    "Chaos-Heartbeat.ps1",
    "Chaos-MultiSession.ps1",
    "Chaos-WorkersSubNodes.ps1",
    "Chaos-AuxiliarySection.ps1"
)

Write-Host "===========================================================" -ForegroundColor Cyan
Write-Host "🏆 ASAMA 7: BUYUK UCTAN UCA SISTEM DOGRULAMA TESTI" -ForegroundColor Yellow
Write-Host "   Calisma Dizini: $ws" -ForegroundColor Gray
Write-Host "   Tarih / Saat   : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "===========================================================" -ForegroundColor Cyan

$total = 0
$passed = 0
$failed = 0

foreach ($s in $suites) {
    $fullPath = Join-Path $ws $s
    if (Test-Path $fullPath) {
        $total++
        Write-Host -NoNewline "Koşuluyor: $s ... "
        $output = & powershell -ExecutionPolicy Bypass -NoProfile -File $fullPath 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[BASARILI ✅]" -ForegroundColor Green
            $passed++
        } else {
            Write-Host "[BASARISIZ ❌]" -ForegroundColor Red
            Write-Host $output -ForegroundColor DarkYellow
            $failed++
        }
    } else {
        Write-Host "Bulunamadi: $s [ATLANDI]" -ForegroundColor DarkGray
    }
}

Write-Host "-----------------------------------------------------------" -ForegroundColor Cyan
Write-Host "KONSOLİDE RAPOR: $passed / $total Test Paketi Basariyla Gecti." -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })

if ($failed -gt 0) {
    exit 1
}
