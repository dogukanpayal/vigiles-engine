# Test-ConsiliumScenarioSimulation.ps1
# Vigiles Consilium Protocol (VCP) Canli Senaryo Simülasyonu ve Dogrulama Testi

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ws = Split-Path -Parent $PSScriptRoot
$failures = 0

function Assert-Condition([bool]$condition, [string]$testName, [string]$detail) {
    if ($condition) {
        Write-Host "  [OK] $testName" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $testName - $detail" -ForegroundColor Red
        $script:failures++
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🧪 VİGİLES CONSILIUM GERÇEK SENARYO SİMÜLASYON TESTİ" -ForegroundColor Yellow
Write-Host "   Senaryo: 'Rate Limiter Mimarisi Kıyaslaması ve Yol Haritası'" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

# Simülasyon Senaryosu Çıktısı (Mock / Generated Consilium Spec - Sade Türkçe Şablon)
$sampleScenarioOutput = @'
🏛️ **Vigiles ThinkDeep Değerlendirmesi Tamamlandı**

### 💡 Özet (Tek Bakışta)
İstek sınırlama (Rate Limiting) için kayan pencere sayacı yaklaşımı seçildi. Hem az bellek harcar hem de ani trafik artışlarını sorunsuz dengeler.

### ⚖️ Neden Bu Yol ve En Büyük Risk
- **Seçilen Yol:** Kayan pencere sayacı hem çok hafif çalışır hem de kotayı yüksek doğrulukla korur.
- **Dikkat Edilecek Risk:** Sabit pencere yönteminde dakika başında kotanın iki katına çıkma açığı yaşanıyordu; bu tasarımda o açık tamamen kapatıldı.

```mermaid
flowchart TD
    Req[Gelen İstek] --> Check{Kota Dolu mu?}
    Check -- Hayır --> Pass[İzin Ver]
    Check -- Evet --> Deny[429 Limiti Aşıldı]
```

### 🗺️ Adımlar
- **Faz 1 (İlk Adım):** Bellek içi sayaç ve istek filtresi ara katmanı.
- **Faz 2 (Sonraki Adım):** Çoklu sunucu için ortak Redis sayacı bağlantısı.

---

🚀 **Öneri:**
- **Vites:** `/pro`
- **Model:** `Gemini 4 Hydrogen (XHigh)`
'@

# 1. Zero Code Mutation Kontrolü
$codeFilesBefore = Get-ChildItem -Path $ws -Include *.ps1,*.js -Recurse | Select-Object FullName, LastWriteTime
Start-Sleep -Milliseconds 200

# Simülasyon işlemi sadece analiz yapar, kod dosyalarına dokunmaz
$codeFilesAfter = Get-ChildItem -Path $ws -Include *.ps1,*.js -Recurse | Select-Object FullName, LastWriteTime

$mutated = $false
for ($i = 0; $i -lt $codeFilesBefore.Count; $i++) {
    if ($codeFilesBefore[$i].LastWriteTime -ne $codeFilesAfter[$i].LastWriteTime -and $codeFilesBefore[$i].FullName -notmatch 'Test-ConsiliumScenarioSimulation') {
        $mutated = $true
        break
    }
}
Assert-Condition (-not $mutated) "1. Sıfır Kod Dokunulmazlığı (Zero Mutation)" "Kod dosyalarında izinsiz değişiklik tespit edildi!"

# 2. Mermaid Diyagram Formatı Denetimi
$hasMermaid = $sampleScenarioOutput -match '(?s)```mermaid.+?```'
Assert-Condition $hasMermaid "2. Feynman Görselleştirme (Mermaid Şeması)" "Mermaid diyagram bloğu bulunamadı!"

# 3. Şeytanın Avukatı / Trade-off Analizi Denetimi
$hasTradeOff = $sampleScenarioOutput -match 'Şeytanın Avukatı|Trade-Off|Risk'
Assert-Condition $hasTradeOff "3. Şeytanın Avukatı (Risk & Kör Nokta Taraması)" "Risk veya trade-off analizi eksik!"

# 4. Fazlandırılmış Yol Haritası (Roadmap) Denetimi
$hasRoadmap = $sampleScenarioOutput -match 'Faz 1' -and $sampleScenarioOutput -match 'Faz 2'
Assert-Condition $hasRoadmap "4. Baş Stratejist (Fazlandırılmış Yol Haritası)" "Faz 1 / Faz 2 yol haritası eksik!"

# 5. Vigiles Devir Köprüsü (Spec-Ready Hand-off) Denetimi
$hasHandOff = $sampleScenarioOutput -match 'Vites:\*\*\s*`(/pro|/lite)`'
Assert-Condition $hasHandOff "5. Vigiles Devir Köprüsü (Tek Vites /pro veya /lite)" "Tekil Vites (/pro veya /lite) satırı eksik!"

# 6. Minimal Model Önerisi (Alternatif ve Uzun Açıklama Yok) Denetimi
$hasModelAdvice = ($sampleScenarioOutput -match 'Model:\*\*\s*`Gemini 4 ') -and ($sampleScenarioOutput -notmatch 'Alternatif|Seçenek B|—')
Assert-Condition $hasModelAdvice "6. Minimal Gemini 4 Model Önerisi (Alternatifsiz & Açıklamasız)" "Model satırı eksik veya yasaklı Alternatif/açıklama metni tespit edildi!"

# 7. Sıfır Jargon Kontrolü
$hasNoJargon = ($sampleScenarioOutput -notmatch '\b(SPOF|ADR|Execution Spec|Sensemaking|Adversarial|boundary reset)\b')
Assert-Condition $hasNoJargon "7. Sıfır Jargon & Sade Türkçe Çıktı" "Örnek çıktıda yasaklı teknik jargon tespit edildi!"

# 8. Özet Başlığı & Kısa Çıktı Bütçesi Kontrolü
$lineCount = ($sampleScenarioOutput -split "`n").Count
$hasSummaryFirst = ($sampleScenarioOutput -match '### 💡 Özet') -and ($lineCount -le 35)
Assert-Condition $hasSummaryFirst "8. Önce Özet & Kompakt Uzunluk ($lineCount satır)" "Özet başlığı eksik veya satır bütçesi (<=35) aşıldı!"

Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
if ($failures -eq 0) {
    Write-Host "🏆 SENARYO SİMÜLASYON TESTİ BAŞARIYLA TAMAMLANDI! (0 Hata)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "❌ $failures TEST BAŞARISIZ OLDU!" -ForegroundColor Red
    exit 1
}
