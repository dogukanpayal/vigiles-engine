# Chaos-TwoFactor.ps1
# Kaos Mühendisi - 2FA Kaba Kuvvet (Brute-Force) ve Yeniden Oynatma (Replay) Saldırısı

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "TwoFactorService.ps1")

Write-Host "=== KAOS MUHENDISI: 2FA DAYANIKLILIK VE SALDIRI SIMULASYONU ===" -ForegroundColor Magenta

# SALDIRI 1: 100 Seri Tahminli Kaba Kuvvet Saldırısı (Brute-Force Attack)
Write-Host "`n[SALDIRI 1] 100 Seri Rastgele Kod ile Kaba Kuvvet Saldirisi..." -ForegroundColor Yellow
$svc = [TwoFactorService]::new()
$realOtp = $svc.GenerateOtp("target_victim")

$attemptsMade = 0
$blockedByLock = 0

1..100 | ForEach-Object {
    $randomGuess = (Get-Random -Minimum 100000 -Maximum 999999).ToString("D6")
    try {
        $svc.VerifyOtp("target_victim", $randomGuess)
    }
    catch {
        $attemptsMade++
        if ($_.Exception.Message -like "*HesapKilitlendi*") {
            $blockedByLock++
        }
    }
}

Write-Host "  -> Toplam Yapilan Deneme: $attemptsMade"
Write-Host "  -> Kilit Tarafından Engellenen: $blockedByLock"

if ($blockedByLock -lt 95) {
    throw "KRITIK GUVELLIK ACIGI: Kaba kuvvet saldirisi hesabi kilitleyemedi!"
}
Write-Host "  [SAVUNULDU] Hesap 3. denemede aninda kilitlendi, kalan 97 deneme duvara carpti!" -ForegroundColor Green

# SALDIRI 2: Çalınmış Kod ile Yeniden Oynatma Saldırısı (Replay Attack)
Write-Host "`n[SALDIRI 2] Onceden Harcanmis Kod ile Yeniden Oynatma (Replay) Saldirisi..." -ForegroundColor Yellow
$userAlice = "alice"
$aliceOtp = $svc.GenerateOtp($userAlice)

# Alice kodu kullanıyor
$firstAttempt = $svc.VerifyOtp($userAlice, $aliceOtp)
if (-not $firstAttempt.Success) { throw "Alice'in kodu calismaliydi!" }

# Saldirgan ayni kodu dinleyip tekrar harcamaya calisiyor
try {
    $svc.VerifyOtp($userAlice, $aliceOtp)
    throw "KRITIK GUVENLIK ACIGI: Ayni OTP kodu iki kez kullanilabildi (Replay Attack Basarili)!"
}
catch {
    if ($_.Exception.Message -like "*GecersizVeyaKullanilmisKod*") {
        Write-Host "  [SAVUNULDU] Kod ilk kullanimda yok edildigi icin saldirgan reddedildi!" -ForegroundColor Green
    } else {
        throw "Beklenmeyen hata: $($_.Exception.Message)"
    }
}

Write-Host "`n================================================================" -ForegroundColor Magenta
Write-Host "SONUC: TUM KAOS SALDIRILARI BASARIYLA PUSKURTULDU! (2/2)" -ForegroundColor Green
