[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

. "c:\Users\Dogukan\Desktop\Antigravity Improvement\AuthService.ps1"

Write-Host "--- KAOS MUHENDISI (CHAOS MONKEY) SALDIRISI BASLATILIYOR ---" -ForegroundColor Yellow

$auth = [AuthService]::new()
$chaosPassed = 0
$chaosFailed = 0

# 1. Buton Spam Saldırısı (10 hızlı istek)
Write-Host "  [KAOS-1]: Buton Spam and Race-Condition Saldirisi..." -ForegroundColor DarkYellow
$blockedCount = 0
$acceptedCount = 0

for ($i = 1; $i -le 10; $i++) {
    $res = $auth.Register("spam_target", "ValidPassword123!", "spam_bot_client")
    if ($res.Status -eq 429) {
        $blockedCount++
    } elseif ($res.Status -eq 201) {
        $acceptedCount++
    }
}

if ($acceptedCount -eq 1 -and $blockedCount -eq 9) {
    Write-Host "  [SAVUNMA BASARILI]: 1 istek kabul edildi, 9 spam istek 429 ile kilitlendi!" -ForegroundColor Green
    $chaosPassed++
} else {
    Write-Host "  [GUVENLIK ACIGI]: Beklenmeyen spam davranisi! Kabul: $acceptedCount, Engel: $blockedCount" -ForegroundColor Red
    $chaosFailed++
}

# 2. Aşırı Yük / 10.000 Karakterlik Parola Saldırısı
Write-Host "  [KAOS-2]: 10.000 Karakterlik Canavar Payload Testi..." -ForegroundColor DarkYellow
$hugePass = "A" * 10000
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$resHuge = $auth.Register("huge_user", $hugePass, "huge_client")
$stopwatch.Stop()

if ($resHuge.Status -eq 201 -and $stopwatch.ElapsedMilliseconds -lt 2000) {
    Write-Host "  [SAVUNMA BASARILI]: 10.000 karakterlik yuk $($stopwatch.ElapsedMilliseconds)ms icinde hash'lendi!" -ForegroundColor Green
    $chaosPassed++
} else {
    Write-Host "  [ASIRI YUK PATLAMASI]: Sistem coktu veya zaman asimina ugradi." -ForegroundColor Red
    $chaosFailed++
}

# 3. Kötü Niyetli XSS / SQL Enjeksiyon Girdisi
Write-Host "  [KAOS-3]: XSS and SQL Injection Denemesi..." -ForegroundColor DarkYellow
$maliciousPass = "<script>alert('XSS')</script>' OR '1'='1"
$resMalicious = $auth.Register("hacker_x", $maliciousPass, "xss_client")

if ($resMalicious.Status -eq 201) {
    $isVerified = $auth.Verify("hacker_x", $maliciousPass)
    if ($isVerified) {
        Write-Host "  [SAVUNMA BASARILI]: Zararli payload duz metin olarak izole edildi ve hash'lendi!" -ForegroundColor Green
        $chaosPassed++
    } else {
        Write-Host "  [GUVENLIK HATASI]: Zararli girdi dogrulanamadi." -ForegroundColor Red
        $chaosFailed++
    }
} else {
    Write-Host "  [HATA]: Kayit basarisiz." -ForegroundColor Red
    $chaosFailed++
}

Write-Host "Kaos Stres Raporu: $chaosPassed / 3 Saldiri Puskurtuldu." -ForegroundColor Yellow
if ($chaosFailed -gt 0) {
    exit 1
} else {
    Write-Host "SISTEM KAOS SALDIRISINA KARSI KURSUN GECIRMEZ!" -ForegroundColor Green
    exit 0
}
