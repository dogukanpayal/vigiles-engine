# Test-AuditLog.ps1
# Kriptografik Denetim Günlüğü Servisi Birim Testleri (TDD)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "AuditLogService.ps1")

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

Write-Host "=== AUDIT LOG SERVISI BIRIM TESTLERI (TDD) ===" -ForegroundColor Cyan

# Test 1: Başarılı Günlük Kaydı ve Hash Üretimi
Assert-Test "Basarili Gunluk Kaydi ve Hash Uretimi" {
    $svc = [AuditLogService]::new()
    $entry = $svc.LogAction("admin_01", "LOGIN", "SUCCESS", "IP: 192.168.1.1")
    if (-not $entry.Hash -or $entry.Hash.Length -ne 64) {
        throw "Gecersiz SHA256 hash degeri!"
    }
    if ($svc.GetCount() -ne 1) {
        throw "Beklenen kayit sayisi 1 fakat $($svc.GetCount())"
    }
}

# Test 2: Geçersiz Kullanıcı veya Aksiyon Doğrulaması
Assert-Test "Gecersiz Girdi Dogrulamasi (Hata Firlatma)" {
    $svc = [AuditLogService]::new()
    try {
        $svc.LogAction("", "ACTION", "FAIL", "")
        throw "Bos kullanici adi kabul edilmemeliydi!"
    } catch {
        if ($_.Exception.Message -notlike "*GecersizKullanici*") { throw $_.Exception.Message }
    }
}

# Test 3: Kriptografik Bütünlük (Tamper-Proof) Doğrulaması
Assert-Test "Kriptografik Zincir Butunlugu Dogrulamasi" {
    $svc = [AuditLogService]::new()
    $svc.LogAction("user_1", "ORDER_CREATED", "OK", "Order #1001")
    $svc.LogAction("user_2", "PAYMENT_DONE", "OK", "Amount: 150 TL")
    $svc.LogAction("user_1", "ORDER_SHIPPED", "OK", "Cargo: MNG")
    
    if (-not $svc.VerifyIntegrity()) {
        throw "Zincir butunlugu dogrulanamadi!"
    }
}

# Test 4: Kurcalanmış Kayıt Tespiti (Tamper Detection)
Assert-Test "Kurcalanmis Kayit Tespiti" {
    $svc = [AuditLogService]::new()
    $svc.LogAction("user_1", "TRANSFER", "OK", "1000 TL")
    $svc.LogAction("user_2", "TRANSFER", "OK", "2000 TL")
    
    # Kötü niyetli manipülasyon simülasyonu
    $svc.Logs[0].Details = "1000000 TL" # Tutar degistirildi
    
    if ($svc.VerifyIntegrity()) {
        throw "Kurcalanmis kayit yakalanamadi, zincir basarisiz!"
    }
}

Write-Host "-----------------------------------------------------------" -ForegroundColor Cyan
Write-Host "Sonuc: $passCount Basarili, $failCount Basarisiz" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })

if ($failCount -gt 0) {
    exit 1
} else {
    exit 0
}
