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
$hasItemsStart    = $htmlContent -match 'md:grid-cols-3[^>]*items-start'
Assert-Test "1. HTML Alt Ağaç ve Konteyner Yapısı Doğrulaması" ($hasTreeContainer -and $hasSubList -and $hasBadgeWorkers -and $hasItemsStart) "workers-sub-tree, workers-sub-list ve items-start elemanları mevcut."

# Test 2: Bağlantı Hattı (Dikey Stem ve Yatay Branch Arm) CSS Varlığı
$hasStemLine   = $htmlContent -match 'border-dashed' -and $htmlContent -match 'border-emerald-500'
$hasWorkerCard = $htmlContent -match 'worker-sub-card'
Assert-Test "2. Hiyerarşik Ağaç Bağlantı Çizgileri ve Kart Stili Doğrulaması" ($hasStemLine -and $hasWorkerCard) "Stem dikey hattı ve branch bağlantı kolları CSS'te mevcut."

# Test 3: Sınırsız Dinamik Kapasite Kuralı (Sıfır Hardcoded Cap)
$hasNoCapSlice = -not ($htmlContent -match 'workers\.slice\(0,\s*\d+\)')
$hasDynamicLoop = $htmlContent -match 'function\s+renderWorkers' -or $htmlContent -match 'renderWorkerNodes'
Assert-Test "3. Sınırsız Dinamik Kapasite Kuralı (Sıfır Hardcoded Cap)" ($hasNoCapSlice -and $hasDynamicLoop) "Kodda hiçbir yapay üst sınır (cap) bulunmuyor; döngü dinamik çalışıyor."

# Test 4: JavaScript Render Fonksiyonunun 5 ve 12 İşçi Çıktısı (Simülasyon)
# Node.js ile renderWorkers fonksiyonunu doğrudan test et
$jsTestScript = @"
const fs = require('fs');
const html = fs.readFileSync('$($htmlPath.Replace('\', '/'))', 'utf8');

const startIdx = html.indexOf('function renderWorkers');
if (startIdx === -1) {
    console.log(JSON.stringify({ success: false, error: 'renderWorkers bulunamadi' }));
    process.exit(0);
}

let braceCount = 0;
let endIdx = -1;
for (let i = startIdx; i < html.length; i++) {
    if (html[i] === '{') braceCount++;
    else if (html[i] === '}') {
        braceCount--;
        if (braceCount === 0) {
            endIdx = i + 1;
            break;
        }
    }
}

if (endIdx === -1) {
    console.log(JSON.stringify({ success: false, error: 'Suslu parantez dengesi kurulamadi' }));
    process.exit(0);
}

const funcStr = html.substring(startIdx, endIdx);

// Simüle DOM ortamı
const mockDoc = {
    elements: {},
    getElementById(id) {
        if (!this.elements[id]) {
            this.elements[id] = {
                innerHTML: '',
                className: '',
                innerText: '',
                style: {},
                classList: {
                    add: (c) => {},
                    remove: (c) => {}
                }
            };
        }
        return this.elements[id];
    }
};

global.document = mockDoc;
global.fixMojibake = (s) => s || '';
global.defaultWorkerRoles = [
    { role: 'TDD Full-Stack', detail: 'Kaynak kod yazılıyor' },
    { role: 'Birim Testçi', detail: 'Birim test yazılıyor' }
];

eval(funcStr);

// 1. Senaryo: 5 İşçi
renderWorkers({
    activeNode: 'node-workers',
    workerCount: 5,
    workers: [
        { id: 1, name: 'İşçi #1', role: 'Full-Stack', detail: 'Kod yazıyor', statusLabel: 'Aktif 🟢' },
        { id: 2, name: 'İşçi #2', role: 'Birim Test', detail: 'Test-Auth.ps1', statusLabel: 'Aktif 🟢' },
        { id: 3, name: 'İşçi #3', role: 'Entegrasyon', detail: 'API bağlantısı', statusLabel: 'Aktif 🟢' },
        { id: 4, name: 'İşçi #4', role: 'UI Geliştirici', detail: 'Bileşenler', statusLabel: 'Aktif 🟢' },
        { id: 5, name: 'İşçi #5', role: 'Veri Katmanı', detail: 'Model doğrulama', statusLabel: 'Aktif 🟢' }
    ]
});

const listHtml5 = mockDoc.getElementById('workers-sub-list').innerHTML;
const count5 = (listHtml5.match(/worker-sub-card/g) || []).length;

// 2. Senaryo: 12 İşçi (Sınırsız Kapasite Kontrolü)
renderWorkers({
    activeNode: 'node-workers',
    workerCount: 12
});
const listHtml12 = mockDoc.getElementById('workers-sub-list').innerHTML;
const count12 = (listHtml12.match(/worker-sub-card/g) || []).length;

console.log(JSON.stringify({ success: true, count5, count12 }));
"@

$tempJs = Join-Path $env:TEMP "test_workers_render.js"
[System.IO.File]::WriteAllText($tempJs, $jsTestScript, [System.Text.Encoding]::UTF8)

$jsResult = $null
try {
    $out = node $tempJs 2>&1
    $jsResult = $out | ConvertFrom-Json
} catch {}
Remove-Item $tempJs -ErrorAction SilentlyContinue

$nodeTestPass = $false
if ($jsResult -and $jsResult.success -and $jsResult.count5 -eq 5 -and $jsResult.count12 -eq 12) {
    $nodeTestPass = $true
}
Assert-Test "4. JavaScript Render Motoru: 5 ve 12 İşçi Dinamik Üretim Doğrulaması" $nodeTestPass "5 işçide 5 kutu, 12 işçide 12 kutu başarıyla üretildi."

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
