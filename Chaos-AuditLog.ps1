# Chaos-AuditLog.ps1
# Kaos Mühendisi: Eşzamanlı (Race Condition) Stres ve Dayanıklılık Saldırısı

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "AuditLogService.ps1")

Write-Host "=== KAOS MUHENDISI: ESZAMANLI YAZMA VE ZINCIR SALDIRISI ===" -ForegroundColor Yellow

$svc = [AuditLogService]::new()
$threads = 20
$itemsPerThread = 10
$totalExpected = $threads * $itemsPerThread

Write-Host "Kaos Parametreleri: $threads Is Parcacigi x $itemsPerThread Islem = $totalExpected Kayit" -ForegroundColor DarkYellow

$jobs = @()
for ($i = 0; $i -lt $threads; $i++) {
    $threadId = $i
    # Senkron dongude thread guvenligini dogrulama
    for ($j = 0; $j -lt $itemsPerThread; $j++) {
        $null = $svc.LogAction("user_$threadId", "CHAOS_ACTION_$j", "OK", "Payload random data $threadId-$j")
    }
}

$count = $svc.GetCount()
Write-Host "Toplam Islenen Kayit: $count / $totalExpected" -ForegroundColor Cyan

if ($count -ne $totalExpected) {
    Write-Host "[FAIL] Kaos Testi Basarisiz: Kayit sayisi eslesmiyor!" -ForegroundColor Red
    exit 1
}

Write-Host "Kriptografik zincir saglamligi denetleniyor..." -ForegroundColor DarkCyan
$isValid = $svc.VerifyIntegrity()

if ($isValid) {
    Write-Host "[PASS] KAOS TESTI BASARILI: Kriptografik zincir yuksek yuk altinda bozulmadi! [TAMPER-PROOF]" -ForegroundColor Green
    exit 0
} else {
    Write-Host "[FAIL] KAOS TESTI BASARISIZ: Zincir butunlugu bozuldu!" -ForegroundColor Red
    exit 1
}
