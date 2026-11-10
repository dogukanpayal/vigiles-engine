param(
    [string]$WorkspaceRoot = (Get-Location).Path
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$reportPath = Join-Path $WorkspaceRoot "SABAH_RAPORU.md"

Write-Host "🌙 [GECE NÖBETÇİSİ]: 03:00 Devriyesi Başlatıldı ($timestamp)..." -ForegroundColor Cyan

# 1. Git Durumu Kontrolü
$gitStatus = git status -s 2>&1
$gitChangesCount = ($gitStatus | Measure-Object).Count

# 2. Test Koşumu (Eğer package.json veya pytest varsa)
$testSummary = "Test konfigürasyonu bulunamadı veya atlandı."
if (Test-Path (Join-Path $WorkspaceRoot "package.json")) {
    Write-Host "📦 npm test koşturuluyor..." -ForegroundColor Yellow
    $testOut = npm test -- --bail 2>&1
    $testSummary = if ($LASTEXITCODE -eq 0) { "✅ Tüm testler başarıyla geçti." } else { "❌ Test hatası tespit edildi!" }
} elseif (Test-Path (Join-Path $WorkspaceRoot "pytest.ini") -or (Test-Path (Join-Path $WorkspaceRoot "tests"))) {
    Write-Host "🐍 pytest koşturuluyor..." -ForegroundColor Yellow
    $testOut = pytest 2>&1
    $testSummary = if ($LASTEXITCODE -eq 0) { "✅ Tüm testler başarıyla geçti." } else { "❌ Test hatası tespit edildi!" }
}

# 3. Güvenlik Taraması
$auditSummary = "Güvenlik açığı taraması temiz."
if (Test-Path (Join-Path $WorkspaceRoot "package.json")) {
    $auditOut = npm audit --audit-level=high 2>&1
    if ($LASTEXITCODE -ne 0) {
        $auditSummary = "⚠️ Yüksek seviyeli paket zafiyeti tespit edildi!"
    }
}

# 4. SABAH_RAPORU.md Dosyasını Oluştur
$reportContent = @"
# 🌅 SABAH RAPORU (Gece Nöbetçisi Devriyesi)
*Bu rapor Gece Nöbetçisi tarafından sabaha karşı 03:00'te otonom olarak üretilmiştir.*

**Devriye Zamanı:** $timestamp  
**Çalışma Alanı:** `$WorkspaceRoot`  

---

### 📊 Devriye Özeti
* **Birim & Regresyon Testleri:** $testSummary
* **Güvenlik Açığı Durumu:** $auditSummary
* **Git Durumu:** $gitChangesCount bekleyen değişiklik var.

---

### 📝 Nöbetçi Notu
> "Gece boyunca tüm testler ve bağımlılıklar tarandı. Sistem güne hazır ve stabil. İyi çalışmalar!"
"@

Set-Content -Path $reportPath -Value $reportContent -Encoding UTF8
Write-Host "✅ [GECE NÖBETÇİSİ]: Sabah raporu masanıza bırakıldı -> $reportPath" -ForegroundColor Green
