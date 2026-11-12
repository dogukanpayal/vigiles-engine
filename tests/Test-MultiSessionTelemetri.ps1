# Test-MultiSessionTelemetri.ps1
# Vigiles TDD Test Paketi: Canlı Operasyon Merkezi Çoklu Oturum ve İzolasyon Doğrulaması

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
Write-Host "🧪 VİGİLES TDD: ÇOKLU OTURUM (MULTI-SESSION) TELEMETRİ TESTİ" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Test 1: URL / Artifact Yolu Üzerinden Oturum ID Algılama Mantığı
$testUrls = @(
    @{
        Url = "file:///C:/Users/TestUser/.gemini/antigravity/brain/05b9c7d2-9fbf-41fc-8695-f21193f4f133/live_mission_control.html"
        Expected = "05b9c7d2-9fbf-41fc-8695-f21193f4f133"
    },
    @{
        Url = "http://localhost:9999/?cid=chat-alpha-123"
        Expected = "chat-alpha-123"
    },
    @{
        Url = "http://localhost:9999/live?cid=session-beta-456&theme=dark"
        Expected = "session-beta-456"
    }
)

$allRegexMatch = $true
foreach ($item in $testUrls) {
    $matchedId = ""
    if ($item.Url -match 'brain[\\/]([a-zA-Z0-9\-_]+)[\\/]') {
        $matchedId = $matches[1]
    } elseif ($item.Url -match '[?&]cid=([a-zA-Z0-9\-_]+)') {
        $matchedId = $matches[1]
    }
    if ($matchedId -ne $item.Expected) {
        $allRegexMatch = $false
        break
    }
}
Assert-Test "1. İstemci Oturum ID (conversationId) Regex Ayrıştırma Doğrulaması" $allRegexMatch "Artifact ve query string yollarından doğru cid çıkarıldı."

# Test 2: Canlı Telemetri Sunucusunun Çalıştığını veya Başlatılabileceğini Doğrula
$port = 9999
$serverLive = $false
try {
    $res = Invoke-RestMethod -Uri "http://localhost:$port/status" -TimeoutSec 2 -ErrorAction SilentlyContinue
    if ($res -and $res.status -eq "running") { $serverLive = $true }
} catch {}

Assert-Test "2. Port $port Telemetri Sunucusu Erişim Kontrolü" $serverLive "Sunucu ayakta ve /status yanıtı veriyor."

if ($serverLive) {
    # Test 3: 3 Farklı Oturumdan Bildirim Gönderimi (Notify Multiplexing)
    $session1 = "test-session-chat-1"
    $session2 = "test-session-chat-2"
    $session3 = "test-session-chat-3"

    $state1 = @{
        conversationId = $session1
        workspaceName  = "Workspace-Proje-A"
        step           = 3
        activeNode     = "node-architect"
        title          = "Chat 1 Mimari Tasarım"
        sender         = "[Chat 1 Mimar]"
        timestamp      = (Get-Date).ToString("HH:mm:ss")
    }

    $state2 = @{
        conversationId = $session2
        workspaceName  = "Workspace-Proje-B"
        step           = 7
        activeNode     = "node-tester"
        title          = "Chat 2 Birim Testler"
        sender         = "[Chat 2 Testçi]"
        timestamp      = (Get-Date).ToString("HH:mm:ss")
    }

    $state3 = @{
        conversationId = $session3
        workspaceName  = "Workspace-Proje-C"
        step           = 12
        activeNode     = "node-chaos"
        title          = "Chat 3 Kaos Stresi"
        sender         = "[Chat 3 Kaos]"
        timestamp      = (Get-Date).ToString("HH:mm:ss")
    }

    $notifySuccess = $true
    try {
        $body1 = $state1 | ConvertTo-Json -Compress
        $body2 = $state2 | ConvertTo-Json -Compress
        $body3 = $state3 | ConvertTo-Json -Compress

        Invoke-RestMethod -Uri "http://localhost:$port/notify" -Method POST -Body $body1 -ContentType "application/json; charset=utf-8" -TimeoutSec 2 | Out-Null
        Invoke-RestMethod -Uri "http://localhost:$port/notify" -Method POST -Body $body2 -ContentType "application/json; charset=utf-8" -TimeoutSec 2 | Out-Null
        Invoke-RestMethod -Uri "http://localhost:$port/notify" -Method POST -Body $body3 -ContentType "application/json; charset=utf-8" -TimeoutSec 2 | Out-Null
    } catch {
        $notifySuccess = $false
    }
    Assert-Test "3. Çoklu Oturum /notify Uç Noktasına Kayıt" $notifySuccess "3 ayrı sohbet için telemetri başarıyla iletildi."

    # Test 4: /sessions Uç Noktasının Çoklu Oturumları Listelemesi
    $hasSessionsList = $false
    try {
        $sessionsRes = Invoke-RestMethod -Uri "http://localhost:$port/sessions" -Method GET -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($sessionsRes -and ($sessionsRes.Count -ge 3 -or $sessionsRes.sessions.Count -ge 3)) {
            $hasSessionsList = $true
        }
    } catch {}
    Assert-Test "4. /sessions Uç Noktasından Aktif Oturumlar Listesi Alma" $hasSessionsList "Tüm aktif oturumlar JSON olarak dönebiliyor."

    # Test 5: /state?cid=... İzolasyonu (Cross-Talk Engeli)
    $crossTalkIsolated = $false
    try {
        $resChat1 = Invoke-RestMethod -Uri "http://localhost:$port/state?cid=$session1" -Method GET -TimeoutSec 2 -ErrorAction SilentlyContinue
        $resChat2 = Invoke-RestMethod -Uri "http://localhost:$port/state?cid=$session2" -Method GET -TimeoutSec 2 -ErrorAction SilentlyContinue

        if ($resChat1.conversationId -eq $session1 -and $resChat2.conversationId -eq $session2 -and $resChat1.step -eq 3 -and $resChat2.step -eq 7) {
            $crossTalkIsolated = $true
        }
    } catch {}
    Assert-Test "5. /state?cid=<id> Oturum İzolasyonu (Sıfır Çakışma)" $crossTalkIsolated "Chat 1 ve Chat 2 durumları birbirini ezmeden izole okundu."

    # Test 6: SSE /events?cid=... İstemci Filtreleme ve Cross-Talk Engeli
    $sseFilterPassed = $false
    try {
        $cidA = "test-sse-isolated-A"
        $cidB = "test-sse-isolated-B"

        $reqA = [System.Net.HttpWebRequest]::Create("http://localhost:$port/events?cid=$cidA")
        $reqA.Method = "GET"
        $reqA.Timeout = 4000
        $respA = $reqA.GetResponse()
        $streamA = $respA.GetResponseStream()
        $readerA = New-Object System.IO.StreamReader($streamA, [System.Text.Encoding]::UTF8)

        # İlk bağlantı satırlarını tüket
        $line1 = $readerA.ReadLine() # : connected
        $line2 = $readerA.ReadLine() # boş satır

        # Şimdi Cid B için notify fırlat
        $payloadB = @{ conversationId = $cidB; title = "Chat B Eylemi"; step = 9 } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "http://localhost:$port/notify" -Method POST -Body $payloadB -ContentType "application/json; charset=utf-8" | Out-Null

        # Şimdi Cid A için notify fırlat
        $payloadA = @{ conversationId = $cidA; title = "Chat A Eylemi"; step = 11 } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "http://localhost:$port/notify" -Method POST -Body $payloadA -ContentType "application/json; charset=utf-8" | Out-Null

        # A istemcisinin okuduğu ilk data satırı Cid A olmalı, Cid B gelmemeli!
        $receivedDataLine = ""
        $readTimeout = [datetime]::Now.AddSeconds(3)
        while ([datetime]::Now -lt $readTimeout) {
            $l = $readerA.ReadLine()
            if ($l -and $l.StartsWith("data:")) {
                $receivedDataLine = $l
                break
            }
        }

        $respA.Close()

        if ($receivedDataLine -match "Chat A Eylemi" -and -not ($receivedDataLine -match "Chat B Eylemi")) {
            $sseFilterPassed = $true
        }
    } catch {}
    Assert-Test "6. SSE /events?cid=... İstemci Filtreleme ve Sıfır Çakışma Doğrulaması" $sseFilterPassed "SSE istemcisi sadece kendi oturumuna ait olayları aldı, Chat B sızmadı."
}

Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
$summaryColor = if ($global:failedCount -eq 0) { "Green" } else { "Yellow" }
Write-Host "SONUÇ: $global:passedCount Geçti | $global:failedCount Başarısız" -ForegroundColor $summaryColor
Write-Host "==========================================================" -ForegroundColor Cyan

exit $global:failedCount
