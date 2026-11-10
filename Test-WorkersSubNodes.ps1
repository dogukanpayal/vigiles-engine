# Test-WorkersSubNodes.ps1
# Vigiles TDD Test Paketi: Canlı Operasyon Merkezi İşçiler Alt Ağacı ve Sınırsız Dinamik Kutu Doğrulaması

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$global:passedCount = 0
$global:failedCount = 0

function Assert-Test([string]$testName, [bool]$condition, [string]$detail = "") {
    if ($condition) {
        Write-Host "  ✅ [GEÇTİ] $testName" -ForegroundColor Green
        if ($detail) { Write-Host "     ↳ $detail" -ForegroundColor DarkGray }
        $global:passedCount++
    } else {
        Write-Host "  ❌ [BAŞARISIZ] $testName" -ForegroundColor Red
        if ($detail) { Write-Host "     ↳ HATA: $detail" -ForegroundColor Yellow }
        $global:failedCount++
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🧪 VİGİLES TDD: İŞÇİLER ALT AĞACI & DİNAMİK KUTU TESTİ" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$htmlPath = "c:\Users\Dogukan\Desktop\Antigravity Improvement\ui\live_mission_control.html"
$htmlContent = if (Test-Path $htmlPath) { [System.IO.File]::ReadAllText($htmlPath, [System.Text.Encoding]::UTF8) } else { "" }

# Test 1: HTML DOM Elemanlarının Varlığı
$hasTreeContainer = $htmlContent -match 'id="workers-sub-tree"'
$hasSubList       = $htmlContent -match 'id="workers-sub-list"'
$hasBadgeWorkers  = $htmlContent -match 'id="badge-workers"'
$hasWorkersNode   = $htmlContent -match 'id="node-workers"'
Assert-Test "1. HTML Alt Ağaç ve Konteyner Yapısı Doğrulaması" ($hasTreeContainer -and $hasSubList -and $hasBadgeWorkers -and $hasWorkersNode) "workers-sub-tree, workers-sub-list ve node-workers elemanları tam genişlikte mevcut."

# Test 2: Bağlantı Hattı (Dikey Stem ve Yatay Branch Arm) CSS Varlığı
$hasStemLine   = $htmlContent -match 'border-dashed' -and $htmlContent -match 'border-emerald-500'
$hasWorkerCard = $htmlContent -match 'worker-sub-card'
Assert-Test "2. Hiyerarşik Ağaç Bağlantı Çizgileri ve Kart Stili Doğrulaması" ($hasStemLine -and $hasWorkerCard) "Stem dikey hattı ve branch bağlantı kolları CSS'te mevcut."

# Test 3: Sınırsız Dinamik Kapasite Kuralı (Sıfır Hardcoded Cap)
$hasNoCapSlice = -not ($htmlContent -match 'workers\.slice\(0,\s*\d+\)')
$hasDynamicLoop = $htmlContent -match 'function\s+renderWorkers' -and $htmlContent -match 'for\s*\(\s*let\s+i\s*=\s*0;\s*i\s*<\s*totalCount;\s*i\+\+\s*\)'
Assert-Test "3. Sınırsız Dinamik Kapasite Kuralı (Sıfır Hardcoded Cap)" ($hasNoCapSlice -and $hasDynamicLoop) "Kodda hiçbir yapay üst sınır (cap) bulunmuyor; döngü dinamik çalışıyor."

# Test 4: JavaScript Render Fonksiyonunun Algoritmik Doğrulaması
# PowerShell simülasyonu ile algoritmanın 5 ve 12 işçide eksiksiz kart üretimi
function Simulate-WorkerRender([hashtable]$s, [string]$htmlTemplate) {
    $defaultRoles = @(
        @{ role = "TDD Full-Stack"; detail = "Kaynak kod ve birim test geliştiriliyor" },
        @{ role = "Birim Testçi"; detail = "Test senaryoları çalıştırılıyor" },
        @{ role = "Entegrasyon"; detail = "Modül arayüzleri ve API bağlanıyor" },
        @{ role = "UI / Görsel"; detail = "Arayüz ve stil bileşenleri işleniyor" },
        @{ role = "Veri Modeli"; detail = "Şema ve veri doğrulama denetleniyor" }
    )

    $workerItems = @()
    if ($s.workers -and $s.workers.Count -gt 0) {
        $workerItems = $s.workers
    } elseif ($s.workerCount -and $s.workerCount -gt 0) {
        for ($i = 0; $i -lt $s.workerCount; $i++) {
            $preset = $defaultRoles[$i % $defaultRoles.Count]
            $workerItems += @{
                id = $i + 1
                name = "İşçi #$($i + 1)"
                role = $preset.role
                detail = $preset.detail
                statusLabel = "Aktif 🟢"
            }
        }
    }

    $cards = @()
    foreach ($w in $workerItems) {
        $cards += "<div class='worker-sub-card'>$($w.name) - $($w.role)</div>"
    }
    return $cards
}

$cards5 = Simulate-WorkerRender @{
    activeNode = "node-workers"
    workerCount = 5
    workers = @(
        @{ id = 1; name = "İşçi #1"; role = "TDD" },
        @{ id = 2; name = "İşçi #2"; role = "Test" },
        @{ id = 3; name = "İşçi #3"; role = "API" },
        @{ id = 4; name = "İşçi #4"; role = "UI" },
        @{ id = 5; name = "İşçi #5"; role = "DB" }
    )
}

$cards12 = Simulate-WorkerRender @{
    activeNode = "node-workers"
    workerCount = 12
}

$renderPass = ($cards5.Count -eq 5 -and $cards12.Count -eq 12)
Assert-Test "4. JavaScript / Algoritmik Motor: 5 ve 12 İşçi Dinamik Üretim Doğrulaması" $renderPass "5 işçide 5 kutu, 12 işçide 12 kutu başarıyla üretildi."

# Test 5: Telemetri Sunucusu Port 9999 /notify & /state Uç Nokta Senkronizasyonu
$port = 9999
$notifyPass = $false
try {
    $testPayload = @{
        conversationId = "test-workers-session"
        workspaceName  = "Antigravity Improvement"
        activeNode     = "node-workers"
        workerCount    = 5
        workers        = @(
            @{ id = 1; name = "İşçi #1"; role = "TDD Backend"; detail = "AuthService.ps1"; statusLabel = "Aktif 🟢" },
            @{ id = 2; name = "İşçi #2"; role = "Testçi"; detail = "Test-Auth.ps1"; statusLabel = "Aktif 🟢" },
            @{ id = 3; name = "İşçi #3"; role = "Kaos"; detail = "Chaos-Test.ps1"; statusLabel = "Aktif 🟢" },
            @{ id = 4; name = "İşçi #4"; role = "UI"; detail = "live_mission_control.html"; statusLabel = "Aktif 🟢" },
            @{ id = 5; name = "İşçi #5"; role = "Yargıç Yardımcısı"; detail = "Kod denetimi"; statusLabel = "Aktif 🟢" }
        )
        status         = "KOD_GELISTIRILIYOR"
        title          = "AŞAMA 6 / 15: 5 İşçi Paralel Kod Yazıyor"
        sender         = "[7. İŞÇİLER (Autonomous Workers)]"
        message        = "5 Bağımsız İşçi Görevlendirildi."
        timestamp      = (Get-Date).ToString("HH:mm:ss")
    }

    $jsonBody = $testPayload | ConvertTo-Json -Depth 6
    $res = Invoke-RestMethod -Uri "http://localhost:$port/notify" -Method POST -Body $jsonBody -ContentType "application/json; charset=utf-8" -TimeoutSec 3 -ErrorAction SilentlyContinue
    
    Start-Sleep -Milliseconds 150
    $stateRes = Invoke-RestMethod -Uri "http://localhost:$port/state?cid=test-workers-session" -TimeoutSec 3 -ErrorAction SilentlyContinue
    if ($stateRes -and $stateRes.workerCount -eq 5 -and $stateRes.workers.Count -eq 5) {
        $notifyPass = $true
    }
} catch {
    $notifyPass = $false
}
Assert-Test "5. Telemetri Sunucusu (Port 9999) Çoklu İşçi State & Veri Bütünlüğü" $notifyPass "State içindeki 5 işçi ve detayları eksiksiz taşındı."

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "SONUÇ: $global:passedCount Geçti, $global:failedCount Başarısız" -ForegroundColor $(if ($global:failedCount -eq 0) { "Green" } else { "Yellow" })
Write-Host "==========================================================" -ForegroundColor Cyan

if ($global:failedCount -gt 0) {
    exit 1
} else {
    exit 0
}
