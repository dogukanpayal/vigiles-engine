# Test-AuxiliarySection.ps1
# Vigiles TDD Test Paketi: Canlı Operasyon Merkezi Yardımcı ve Standby Elemanlar Ayrı Bölüm Doğrulaması

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
Write-Host "🧪 VİGİLES TDD: YARDIMCI ELEMANLAR AYRI BÖLÜM TESTİ" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$htmlPath = Join-Path (Split-Path -Parent $PSScriptRoot) "core\templates\live_mission_control.html"
$htmlContent = if (Test-Path $htmlPath) { [System.IO.File]::ReadAllText($htmlPath, [System.Text.Encoding]::UTF8) } else { "" }

# Test 1: Ayrı Bölüm Konteyneri ve Başlık Doğrulaması
$hasAuxSection = $htmlContent -match 'id="auxiliary-section"'
$hasAuxHeader  = $htmlContent -match 'YARDIMCI.*ELEMANLAR|STANDBY.*BİRİMLER'
$hasAuxBadge   = $htmlContent -match 'id="badge-aux-summary"'
Assert-Test "1. Ayrı Bölüm Konteyneri ve Başlık Doğrulaması" ($hasAuxSection -and $hasAuxHeader -and $hasAuxBadge) "auxiliary-section konteyneri, başlığı ve durum rozeti mevcut."

# Test 2: Mimari Hiyerarşi (Ana Üretim Hattından Sonra Yerleşim)
$idxJudge = $htmlContent.IndexOf('id="node-judge"')
$idxAux   = $htmlContent.IndexOf('id="auxiliary-section"')
$isAfterJudge = ($idxJudge -gt 0 -and $idxAux -gt $idxJudge)
Assert-Test "2. Mimari Konumlandırma (13. Yargıç sonrasında ayrı bölüm)" $isAfterJudge "Yardımcı elemanlar ana üretim hattının altında bağımsız bir bölümdedir."

# Test 3: Sürekli Aktif Olmayan 4 Yardımcı Eleman Düğümü ve Rozetleri (Kota Dürtücüsü kaldırıldı)
$hasMemory    = $htmlContent -match 'id="node-memory"' -and $htmlContent -match 'id="badge-memory"'
$hasSentinel  = $htmlContent -match 'id="node-sentinel"' -and $htmlContent -match 'id="badge-sentinel"'
$hasSentry    = $htmlContent -match 'id="node-sentry"' -and $htmlContent -match 'id="badge-sentry"'
$hasGitPr     = $htmlContent -match 'id="node-pr"' -and $htmlContent -match 'id="badge-pr"'
$noHeartbeat  = ($htmlContent -notmatch 'node-heartbeat') -and ($htmlContent -notmatch 'badge-heartbeat') -and ($htmlContent -notmatch 'KOTA DÜRTÜCÜSÜ')
$hasAux7      = $htmlContent -match '7 Yardımcı Birim Standby'
$allNodesOk   = ($hasMemory -and $hasSentinel -and $hasSentry -and $hasGitPr -and $noHeartbeat -and $hasAux7)
Assert-Test "3. 4 Yardımcı Düğüm Varlığı ve Kota Dürtücüsü İmhası (Hafıza, Gece, Sentry, Git)" $allNodesOk "4 yardımcı birim mevcut, node-heartbeat tamamen kaldırılmış, 7 Yardımcı Birim etiketi güncel."

# Test 4: Tetikleyici ve Görev Bilgileri (Trigger Context) Doğrulaması
$hasMemoryCtx    = $htmlContent -match 'KURALLAR\.md|Post-Mortem|Görev Sonu'
$hasSentinelCtx  = $htmlContent -match '03:00|Gece Nöbet|Regresyon'
$hasSentryCtx    = $htmlContent -match 'Sentry|Log|İstisna|Hata' -and $htmlContent -match '18\. CANLI HATA DEDEKTİFİ'
$hasGitCtx       = $htmlContent -match '/push|Sıfır Otomatik Git|Dağıtım' -and $htmlContent -match '19\. GİT & DAĞITIM FABRİKASI'
$allCtxOk        = ($hasMemoryCtx -and $hasSentinelCtx -and $hasSentryCtx -and $hasGitCtx)
Assert-Test "4. Yardımcı Eleman Tetikleyici ve Güncel Numara Bilgisi" $allCtxOk "Tüm elemanlar ne zaman uyandıklarını ve 18/19 numaralandırmasını net yansıtıyor."

# Test 5: JavaScript allNodeIds ve Reset Entegrasyonu
$hasJsNodes = ($htmlContent -match "'node-memory'" -and 
               $htmlContent -match "'node-sentinel'" -and 
               $htmlContent -match "'node-sentry'" -and 
               $htmlContent -match "'node-pr'" -and
               $htmlContent -notmatch "'node-heartbeat'")
$hasResetLogic = $htmlContent -match 'badge-memory' -and $htmlContent -match 'badge-sentinel'
Assert-Test "5. JavaScript Animasyon ve Standby Reset Entegrasyonu" ($hasJsNodes -and $hasResetLogic) "allNodeIds ve renderState reset mantığı kalan yardımcı düğümleri kapsıyor ve heartbeat izini taşımıyordur."

# Test 6: Telemetri Sunucusu (Port 9999) Yardımcı Düğüm İletişim Doğrulaması
$port = 9999
$auxTelemetriPass = $false
try {
    $testPayload = @{
        conversationId = "test-aux-session"
        workspaceName  = "Antigravity Improvement"
        activeNode     = "node-memory"
        status         = "HAFIZA_KAYDEDILIYOR"
        title          = "AŞAMA 15: Hafıza Uzmanı KURALLAR.md Güncelliyor"
        sender         = "[14. HAFIZA UZMANI (Post-Mortem)]"
        message        = "Alınan dersler kurumsal anayasaya mühürleniyor."
        timestamp      = (Get-Date).ToString("HH:mm:ss")
        badge          = @{ id = "badge-memory"; text = "Yazıyor ⚡"; class = "bg-purple-500/20 text-purple-300 border-purple-500/40" }
    }

    $jsonBody = $testPayload | ConvertTo-Json -Depth 6
    $res = Invoke-RestMethod -Uri "http://localhost:$port/notify" -Method POST -Body $jsonBody -ContentType "application/json; charset=utf-8" -TimeoutSec 3 -ErrorAction SilentlyContinue
    
    Start-Sleep -Milliseconds 150
    $stateRes = Invoke-RestMethod -Uri "http://localhost:$port/state?cid=test-aux-session" -TimeoutSec 3 -ErrorAction SilentlyContinue
    if ($stateRes -and $stateRes.activeNode -eq "node-memory") {
        $auxTelemetriPass = $true
    }
} catch {
    $auxTelemetriPass = $false
}
Assert-Test "6. Telemetri Sunucusu (Port 9999) Yardımcı Eleman State İletişimi" $auxTelemetriPass "node-memory durumu Port 9999 üzerinden kayıpsız aktarıldı."

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "SONUÇ: $global:passedCount Geçti, $global:failedCount Başarısız" -ForegroundColor $(if ($global:failedCount -eq 0) { "Green" } else { "Yellow" })
Write-Host "==========================================================" -ForegroundColor Cyan

if ($global:failedCount -gt 0) {
    exit 1
} else {
    exit 0
}
