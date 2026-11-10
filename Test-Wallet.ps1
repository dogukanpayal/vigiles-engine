# Test-Wallet.ps1
# Cüzdan Servisi Birim Testleri (TDD Kırmızı -> Yeşil)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "WalletService.ps1")

$passCount = 0
$failCount = 0

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

Write-Host "=== CUZDAN SERVISI BIRIM TESTLERI (TDD) ===" -ForegroundColor Cyan

# Test 1: Pozitif Bakiye Yukleme
Assert-Test "Pozitif Bakiye Yukleme (Top-Up)" {
    $wallet = [WalletService]::new("user_101", 500)
    $res = $wallet.TopUp(250)
    if ($res.NewBalance -ne 750) { throw "Beklenen 750, alinan $($res.NewBalance)" }
}

# Test 2: Negatif veya Sifir Bakiye Yukleme Reddi
Assert-Test "Negatif Bakiye Yukleme Reddi (400)" {
    $wallet = [WalletService]::new("user_102", 100)
    try {
        $wallet.TopUp(-50)
        throw "Negatif yukleme kabul edilmemeliydi!"
    } catch {
        if ($_.Exception.Message -notlike "*GecersizTutar*") { throw $_.Exception.Message }
    }
}

# Test 3: Basarili Harcama
Assert-Test "Basarili Harcama" {
    $wallet = [WalletService]::new("user_103", 1000)
    $res = $wallet.Spend(300, "Siparis #991")
    if ($res.NewBalance -ne 700) { throw "Beklenen 700, alinan $($res.NewBalance)" }
}

# Test 4: Yetersiz Bakiye Reddi
Assert-Test "Yetersiz Bakiye Reddi" {
    $wallet = [WalletService]::new("user_104", 200)
    try {
        $wallet.Spend(500, "Siparis #992")
        throw "Yetersiz bakiye kabul edilmemeliydi!"
    } catch {
        if ($_.Exception.Message -notlike "*YetersizBakiye*") { throw $_.Exception.Message }
    }
}

# Test 5: Hediye Kuponu ile Bakiye Yukleme
Assert-Test "Gecerli Kupon Yukleme" {
    $wallet = [WalletService]::new("user_105", 100)
    $res = $wallet.RedeemVoucher("HEDIYE100")
    if ($res.NewBalance -ne 200) { throw "Beklenen 200, alinan $($res.NewBalance)" }
}

# Test 6: Ayni Kuponu Ikinci Kez Kullanma Reddi (409 Conflict)
Assert-Test "Cift Kupon Kullanimi Reddi" {
    $wallet = [WalletService]::new("user_106", 100)
    $null = $wallet.RedeemVoucher("HEDIYE100")
    try {
        $wallet.RedeemVoucher("HEDIYE100")
        throw "Kupon cift kullanilamamaliydi!"
    } catch {
        if ($_.Exception.Message -notlike "*KuponZatenKullanildi*") { throw $_.Exception.Message }
    }
}

# Test 7: Karar Suzgeci Kurali - Bakiye Tavani Asimi (Strict Cap 10,000 TL)
Assert-Test "Maksimum Bakiye Tavani Asimi Reddi (Strict Cap 10.000 TL)" {
    $wallet = [WalletService]::new("user_107", 9000)
    try {
        $wallet.TopUp(2000) # 9000 + 2000 = 11000 > 10000 -> RED
        throw "10.000 TL tavan asimi kabul edilmemeliydi!"
    } catch {
        if ($_.Exception.Message -notlike "*BakiyeTavaniAsildi*") { throw $_.Exception.Message }
    }
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Sonuc: $global:passCount GECTI, $global:failCount BASARISIZ"

if ($global:failCount -gt 0) {
    exit 1
}
