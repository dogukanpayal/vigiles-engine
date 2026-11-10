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
    "Chaos-Coupon.ps1",
    "Chaos-Wallet.ps1",
    "Chaos-TwoFactor.ps1",
    "Chaos-Heartbeat.ps1"
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
        $output = & powershell -NoProfile -File $fullPath 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[BASARILI ✅]" -ForegroundColor Green
            $passed++
        } else {
            Write-Host "[BASARISIZ ❌]" -ForegroundColor Red
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
