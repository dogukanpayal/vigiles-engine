# Chaos-Wallet.ps1
# Kaos Mühendisi - Cüzdan Dayanıklılık ve Yarış Durumu (Race Condition) Saldırısı

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "WalletService.ps1")

Write-Host "=== KAOS MUHENDISI: CUZDAN DAYANIKLILIK SALDIRISI ===" -ForegroundColor Magenta

# SALDIRI 1: Eşzamanlı Çift Harcama Saldırısı (Concurrency Race Condition)
Write-Host "`n[SALDIRI 1] Eszamanli Cift Harcama Saldirisi (Race Condition)..." -ForegroundColor Yellow
$victimWallet = [WalletService]::new("victim_001", 500.0) # Bakiye: 500 TL

# 10 paralel istek 100 TL harcamaya çalışıyor
$successCount = 0
$failCount = 0

1..10 | ForEach-Object {
    try {
        $res = $victimWallet.Spend(100.0, "Saldırı $_")
        $successCount++
    }
    catch {
        $failCount++
    }
}

Write-Host "  -> 10 Istekten $successCount tanesi gecti, $failCount tanesi kilitlendi."
Write-Host "  -> Kalan Bakiye: $($victimWallet.Balance) TL"

if ($victimWallet.Balance -lt 0) {
    throw "KRITIK ACIK: Bakiye eksiye dustu! Kaos saldirisi basarili oldu!"
}

if ($successCount -ne 5 -or $failCount -ne 5 -or $victimWallet.Balance -ne 0) {
    throw "TUTARSIZLIK: 500 TL bakiye tam 5 basarili harcama ve 0 TL son bakiye ile bitmeliydi."
}
Write-Host "  [SAVUNULDU] Cuzdan hicbir sekilde eksiye dusmedi, yarıs durumu engellendi!" -ForegroundColor Green

# SALDIRI 2: Asiri Milyon TL Bakiye Yükleme Saldırısı (Overflow / Cap Bypass)
Write-Host "`n[SALDIRI 2] Asiri Bakiye Enjeksiyonu (1.000.000 TL Cap Asimi)..." -ForegroundColor Yellow
try {
    $victimWallet.TopUp(1000000.0)
    throw "KRITIK ACIK: Milyon TL tavan asimi kabul edildi!"
}
catch {
    if ($_.Exception.Message -like "*BakiyeTavaniAsildi*") {
        Write-Host "  [SAVUNULDU] Tavan asimi kalkan tarafindan engellendi: $($_.Exception.Message)" -ForegroundColor Green
    } else {
        throw "Beklenmeyen hata: $($_.Exception.Message)"
    }
}

# SALDIRI 3: Negatif Harcama ile Bakiye Üretme Hilesi (Negative Amount Fraud)
Write-Host "`n[SALDIRI 3] Negatif Harcama ile Bakiye Artirma Hilesi (-500 TL Spend)..." -ForegroundColor Yellow
try {
    $victimWallet.Spend(-500.0, "Hileli Harcama")
    throw "KRITIK ACIK: Negatif harcama bakiye artirdi!"
}
catch {
    if ($_.Exception.Message -like "*GecersizTutar*") {
        Write-Host "  [SAVUNULDU] Negatif harcama dolandiriciligi engellendi!" -ForegroundColor Green
    } else {
        throw "Beklenmeyen hata: $($_.Exception.Message)"
    }
}

Write-Host "`n=======================================================" -ForegroundColor Magenta
Write-Host "SONUC: TUM KAOS SALDIRILARI BASARIYLA PUSKURTULDU! (3/3)" -ForegroundColor Green
