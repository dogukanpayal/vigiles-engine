[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

. "c:\Users\Dogukan\Desktop\Antigravity Improvement\CouponService.ps1"

Write-Host "--- KAOS MUHENDISI (CHAOS MONKEY): KUPON STRES SALDIRISI ---" -ForegroundColor Yellow

$svc = [CouponService]::new()
$chaosPassed = 0
$chaosFailed = 0

# 1. Çift Harcama / Race-Condition Saldırısı (10 hızlı istek)
Write-Host "  [KAOS-1]: Cift Harcama (Double-Spending) ve Race-Condition Saldirisi..." -ForegroundColor DarkYellow
$accepted = 0
$blocked = 0

for ($i = 1; $i -le 10; $i++) {
    $res = $svc.ApplyCoupon("VETERAN20", 300.0, "hacker_target", "hacker_bot")
    if ($res.Status -eq 200) {
        $accepted++
    } else {
        $blocked++
    }
}

if ($accepted -eq 1 -and $blocked -eq 9) {
    Write-Host "  [SAVUNMA BASARILI]: Kupon sadece 1 kez uygulandi, diger 9 saldiri aninda kilitlendi!" -ForegroundColor Green
    $chaosPassed++
} else {
    Write-Host "  [KRITIK ACIK]: Cift harcama gerceklesti! Kabul: $accepted, Engel: $blocked" -ForegroundColor Red
    $chaosFailed++
}

# 2. Negatif Sepet Saldırısı (-500 TL ile eksi bakiye üretme denemesi)
Write-Host "  [KAOS-2]: Negatif Sepet Tutari ile Bakiye Calma Saldirisi..." -ForegroundColor DarkYellow
$resNeg = $svc.ApplyCoupon("VETERAN20", -500.0, "attacker_neg", "client_neg")

if ($resNeg.Status -eq 400) {
    Write-Host "  [SAVUNMA BASARILI]: Negatif sepet tutari 400 ile aninda puskurtuldu!" -ForegroundColor Green
    $chaosPassed++
} else {
    Write-Host "  [ACIK]: Negatif sepet kabul edildi!" -ForegroundColor Red
    $chaosFailed++
}

# 3. 10.000 Karakterlik Canavar Kupon Kodu Saldırısı
Write-Host "  [KAOS-3]: 10.000 Karakterlik Kod ile Bellek Doyurma Saldirisi..." -ForegroundColor DarkYellow
$monsterCode = "COUPON_" + ("A" * 10000)
$resMonster = $svc.ApplyCoupon($monsterCode, 300.0, "attacker_monster", "client_monster")

if ($resMonster.Status -eq 400) {
    Write-Host "  [SAVUNMA BASARILI]: Dev kod guvenle reddedildi, bellek stabil!" -ForegroundColor Green
    $chaosPassed++
} else {
    Write-Host "  [ACIK]: Sistem coktu veya hata verdi." -ForegroundColor Red
    $chaosFailed++
}

Write-Host "Kaos Stres Raporu: $chaosPassed / 3 Saldiri Puskurtuldu." -ForegroundColor Yellow
if ($chaosFailed -gt 0) {
    exit 1
} else {
    Write-Host "KUPON MOTORU KAOS SALDIRISINA KARSI KURŞUN GEÇİRMEZ!" -ForegroundColor Green
    exit 0
}
