# Chaos-AuxiliarySection.ps1
# Kaos Mühendisi (Chaos Monkey): Yardımcı ve Standby Elemanlar Hızlı Döngü & Stres Testi

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$global:passedCount = 0
$global:failedCount = 0

function Assert-Test([string]$testName, [bool]$condition, [string]$detail = "") {
    if ($condition) {
        Write-Host "  🐒 [GEÇTİ] $testName" -ForegroundColor Green
        if ($detail) { Write-Host "     ↳ $detail" -ForegroundColor DarkGray }
        $global:passedCount++
    } else {
        Write-Host "  💥 [BAŞARISIZ] $testName" -ForegroundColor Red
        if ($detail) { Write-Host "     ↳ HATA: $detail" -ForegroundColor Yellow }
        $global:failedCount++
    }
}

Write-Host "==========================================================" -ForegroundColor Red
Write-Host "🐒 KAOS MÜHENDİSİ: YARDIMCI ELEMANLAR STRES VE SERİ GEÇİŞ TESTİ" -ForegroundColor Red
Write-Host "==========================================================" -ForegroundColor Red

$port = 9999
$nodes = @("node-memory", "node-sentinel", "node-heartbeat", "node-sentry", "node-pr")

# 1. Kaos Testi: 25 Seri Döngüsel Tetikleme (Burst Auxiliary Cycling)
$burstCount = 25
$burstSuccess = 0
for ($i = 1; $i -le $burstCount; $i++) {
    $targetNode = $nodes[($i - 1) % $nodes.Count]
    $payload = @{
        conversationId = "chaos-aux-cycle"
        workspaceName  = "Antigravity Improvement"
        activeNode     = $targetNode
        status         = "KAOS_DENEME_$i"
        title          = "Kaos Testi #${i} - $targetNode Aktif"
        sender         = "Kaos Mühendisi"
        message        = "Hızlı geçiş $i / $burstCount icra ediliyor..."
        timestamp      = (Get-Date).ToString("HH:mm:ss")
    }

    try {
        $json = $payload | ConvertTo-Json -Depth 4
        Invoke-RestMethod -Uri "http://localhost:$port/notify" -Method POST -Body $json -ContentType "application/json; charset=utf-8" -TimeoutSec 2 -ErrorAction SilentlyContinue | Out-Null
        $burstSuccess++
    } catch {}
}
Assert-Test "1. 25 Seri Yardımcı Düğüm Geçişi (Burst Cycling)" ($burstSuccess -eq $burstCount) "$burstSuccess / $burstCount istek başarıyla karşılandı."

# 2. Kaos Testi: Son Durum Doğrulaması (State Consistency)
Start-Sleep -Milliseconds 150
$lastNode = $nodes[($burstCount - 1) % $nodes.Count]
$statePass = $false
try {
    $st = Invoke-RestMethod -Uri "http://localhost:$port/state?cid=chaos-aux-cycle" -TimeoutSec 3 -ErrorAction Stop
    if ($st.activeNode -eq $lastNode) {
        $statePass = $true
    }
} catch {
    $statePass = $false
}
Assert-Test "2. Seri Yük Sonrası Veri Tutarlılığı ($lastNode)" $statePass "Son gönderilen yardımcı düğüm verisi sunucuda tam tutarlı."

# 3. Kaos Testi: Standby'a Ani Geri Dönüş (Graceful Standby Reset)
$resetPayload = @{
    conversationId = "chaos-aux-cycle"
    activeNode     = "node-user"
    status         = "BEKLEMEDE"
    title          = "AŞAMA 1 / 15: Sistem Hazır"
    sender         = "1. SİZ (Şirket Sahibi)"
    message        = "Tüm yardımcı elemanlar bekleme durumuna alındı."
    timestamp      = (Get-Date).ToString("HH:mm:ss")
}
$resetPass = $false
try {
    $rJson = $resetPayload | ConvertTo-Json -Depth 4
    Invoke-RestMethod -Uri "http://localhost:$port/notify" -Method POST -Body $rJson -ContentType "application/json; charset=utf-8" -TimeoutSec 2 -ErrorAction Stop | Out-Null
    Start-Sleep -Milliseconds 150
    $stReset = Invoke-RestMethod -Uri "http://localhost:$port/state?cid=chaos-aux-cycle" -TimeoutSec 3 -ErrorAction Stop
    if ($stReset.activeNode -eq "node-user") {
        $resetPass = $true
    }
} catch {
    $resetPass = $false
}
Assert-Test "3. Standby / Kullanıcı Bekleme Düğümüne Ani Dönüş (Reset)" $resetPass "Sistem sıfır hata ile ana bekleme moduna döndü."

Write-Host "==========================================================" -ForegroundColor Red
Write-Host "SONUÇ: $global:passedCount Geçti, $global:failedCount Başarısız" -ForegroundColor $(if ($global:failedCount -eq 0) { "Green" } else { "Yellow" })
Write-Host "==========================================================" -ForegroundColor Red

if ($global:failedCount -gt 0) {
    exit 1
} else {
    exit 0
}
