# Chaos-WorkersSubNodes.ps1
# Kaos Mühendisi (Chaos Monkey): İşçiler Alt Ağacı ve Sınırsız Dinamik Kutu Stres & Aşırı Yük Testi

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
Write-Host "🐒 KAOS MÜHENDİSİ: İŞÇİLER ALT AĞACI VE AŞIRI YÜK TESTİ" -ForegroundColor Red
Write-Host "==========================================================" -ForegroundColor Red

$port = 9999
$sw = [System.Diagnostics.Stopwatch]::StartNew()

# 1. Kaos Testi: 100 İşçili Devasa State Yükü (Massive Worker Swarm)
$swarm100 = @()
for ($i = 1; $i -le 100; $i++) {
    $swarm100 += @{
        id          = $i
        name        = "İşçi #$i"
        role        = "Otonom Alt Ajan $i"
        detail      = "Mikro servis modül-$i test ediliyor..."
        statusLabel = "Aktif 🟢"
    }
}

$payload100 = @{
    conversationId = "chaos-swarm-session"
    workspaceName  = "Chaos Swarm"
    activeNode     = "node-workers"
    workerCount    = 100
    workers        = $swarm100
    status         = "DEVASA_ISCI_SURUSU"
    title          = "AŞAMA 6 / 15: 100 Paralel İşçi Sürüsü"
    sender         = "[7. İŞÇİLER (Autonomous Workers Swarm)]"
    message        = "100 Bağımsız İşçi Devreye Alındı."
    timestamp      = (Get-Date).ToString("HH:mm:ss")
}

$swarmPass = $false
try {
    $json = $payload100 | ConvertTo-Json -Depth 6
    $res = Invoke-RestMethod -Uri "http://localhost:$port/notify" -Method POST -Body $json -ContentType "application/json; charset=utf-8" -TimeoutSec 5 -ErrorAction Stop
    Start-Sleep -Milliseconds 100
    $state100 = Invoke-RestMethod -Uri "http://localhost:$port/state?cid=chaos-swarm-session" -TimeoutSec 3 -ErrorAction Stop
    if ($state100.workerCount -eq 100 -and $state100.workers.Count -eq 100) {
        $swarmPass = $true
    }
} catch {
    $swarmPass = $false
}
Assert-Test "1. 100 İşçili Devasa Sürü (Massive Swarm) Veri Bütünlüğü" $swarmPass "100 işçilik dev veri kümesi kayıpsız iletildi ve depolandı."

# 2. Kaos Testi: Seri Dalgalanma ve Hızlı Adım Atlaması (Burst & Rapid Jitter)
# 20 ardışık bildirim: İşçi sayısı hızla değişiyor (1 -> 5 -> 15 -> 50 -> 2 -> 80...)
$burstCount = 20
$burstSuccess = 0
for ($b = 1; $b -le $burstCount; $b++) {
    $randomWorkers = ($b * 7) % 65 + 1
    $miniPayload = @{
        conversationId = "chaos-burst-session"
        activeNode     = "node-workers"
        workerCount    = $randomWorkers
        status         = "DALGALANMA_$b"
        timestamp      = (Get-Date).ToString("HH:mm:ss")
    }
    try {
        $miniJson = $miniPayload | ConvertTo-Json -Depth 4
        Invoke-RestMethod -Uri "http://localhost:$port/notify" -Method POST -Body $miniJson -ContentType "application/json; charset=utf-8" -TimeoutSec 2 -ErrorAction SilentlyContinue | Out-Null
        $burstSuccess++
    } catch {}
}
Assert-Test "2. Dinamik İşçi Sayısı Hızlı Dalgalanma Testi (20 Burst İstek)" ($burstSuccess -eq $burstCount) "$burstSuccess / $burstCount istek başarıyla karşılandı."

# 3. Kaos Testi: Sıfır İşçi ve İşçi Dışı Düğüme Ani Geçiş (Graceful Collapse)
$collapsePayload = @{
    conversationId = "chaos-burst-session"
    activeNode     = "node-judge"
    workerCount    = 0
    workers        = @()
    status         = "YARGIC_DENETIMI"
    timestamp      = (Get-Date).ToString("HH:mm:ss")
}
$collapsePass = $false
try {
    $cJson = $collapsePayload | ConvertTo-Json -Depth 4
    Invoke-RestMethod -Uri "http://localhost:$port/notify" -Method POST -Body $cJson -ContentType "application/json; charset=utf-8" -TimeoutSec 2 -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Milliseconds 80
    $stateCol = Invoke-RestMethod -Uri "http://localhost:$port/state?cid=chaos-burst-session" -TimeoutSec 2 -ErrorAction SilentlyContinue
    if ($stateCol.activeNode -eq "node-judge" -and $stateCol.workerCount -eq 0) {
        $collapsePass = $true
    }
} catch {}
Assert-Test "3. İşçi Aşamasından Yargıç Aşamasına Geçişte Zarif Kapanma" $collapsePass "İşçi sayısı sıfırlandı, aktif düğüm sorunsuz aktarıldı."

$sw.Stop()
Write-Host "==========================================================" -ForegroundColor Red
Write-Host "KAOS RAPORU: $($sw.ElapsedMilliseconds) ms sürede tamamlandı. $global:passedCount Geçti, $global:failedCount Başarısız" -ForegroundColor $(if ($global:failedCount -eq 0) { "Green" } else { "Yellow" })
Write-Host "==========================================================" -ForegroundColor Red

if ($global:failedCount -gt 0) {
    exit 1
} else {
    exit 0
}
