# Test-TwoFactor.ps1
# 2FA / OTP Servisi Birim Testleri (TDD)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "TwoFactorService.ps1")

$global:passCount = 0
$global:failCount = 0

function Assert-Test([string]$testName, [scriptblock]$block) {
    try {
        & $block
        Write-Host "  [PASS] $testName" -ForegroundColor Green
        $global:passCount++
    }
    catch {
        Write-Host "  [FAIL] $testName - $($_.Exception.Message)" -ForegroundColor Red
        $global:failCount++
    }
}

Write-Host "=== 2FA / OTP SERVISI BIRIM TESTLERI (TDD) ===" -ForegroundColor Cyan

# Test 1: 6 Haneli Sayısal Kod Üretimi
Assert-Test "6 Haneli OTP Kod Uretimi" {
    $svc = [TwoFactorService]::new()
    $otp = $svc.GenerateOtp("user_201")
    if ($otp.Length -ne 6) { throw "Kod 6 haneli olmali, alinan: $($otp.Length)" }
    if ($otp -notmatch '^\d{6}$') { throw "Kod yalnizca rakamlardan olusmali: $otp" }
}

# Test 2: Basarili Dogrulama ve Tek Kullanimlik Kuralı
Assert-Test "Basarili Dogrulama ve Tek Kullanimlik Imha" {
    $svc = [TwoFactorService]::new()
    $otp = $svc.GenerateOtp("user_202")
    $res = $svc.VerifyOtp("user_202", $otp)
    if (-not $res.Success) { throw "Gecerli kod basarisiz oldu!" }

    # Ayni kodu ikinci kez dene -> REDDETMELI
    try {
        $svc.VerifyOtp("user_202", $otp)
        throw "Kod tek kullanimlik olmaliydi; ikinci deneme kabul edilmemeliydi!"
    } catch {
        if ($_.Exception.Message -notlike "*GecersizVeyaKullanilmisKod*") { throw $_.Exception.Message }
    }
}

# Test 3: Yanlis Kod ve Hata Sayaci
Assert-Test "Yanlis Kod Reddi" {
    $svc = [TwoFactorService]::new()
    $null = $svc.GenerateOtp("user_203")
    try {
        $svc.VerifyOtp("user_203", "000000")
        throw "Hatali kod kabul edilmemeliydi!"
    } catch {
        if ($_.Exception.Message -notlike "*HataliKod*") { throw $_.Exception.Message }
    }
}

# Test 4: Brute-Force Korumasi (3 Hatali Denemede Kilitleme)
Assert-Test "3 Hatali Denemede Hesap Kilitleme (429 Rate Limit)" {
    $svc = [TwoFactorService]::new()
    $null = $svc.GenerateOtp("user_204")

    # 1. Deneme
    try { $svc.VerifyOtp("user_204", "111111") } catch {}
    # 2. Deneme
    try { $svc.VerifyOtp("user_204", "222222") } catch {}
    # 3. Deneme
    try { $svc.VerifyOtp("user_204", "333333") } catch {}

    # 4. Deneme -> Hesap Kilitli Hatasi Vermeli
    try {
        $svc.VerifyOtp("user_204", "444444")
        throw "Hesap 3 hatali denemeden sonra kilitlenmeliydi!"
    } catch {
        if ($_.Exception.Message -notlike "*HesapKilitlendi*") { throw $_.Exception.Message }
    }
}

# Test 5: Süresi Dolan Kod (TTL)
Assert-Test "Suresi Dolan Kod Reddi (Expired)" {
    $svc = [TwoFactorService]::new()
    # Gecmis tarihli kod enjekte et
    $svc.InjectExpiredOtp("user_205", "123456")
    try {
        $svc.VerifyOtp("user_205", "123456")
        throw "Suresi dolan kod kabul edilmemeliydi!"
    } catch {
        if ($_.Exception.Message -notlike "*KodunSuresiDolmus*") { throw $_.Exception.Message }
    }
}

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Sonuc: $global:passCount GECTI, $global:failCount BASARISIZ"

if ($global:failCount -gt 0) {
    exit 1
}
