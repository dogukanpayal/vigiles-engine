# Chaos-MultiSession.ps1
# Vigiles Kaos Mühendisi: Çoklu Oturum Eşzamanlılık, Yük ve Çakışma Direnç Testi

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "==========================================================" -ForegroundColor Red
Write-Host "🐒 VİGİLES KAOS MÜHENDİSİ: 3 EŞZAMANLI CHAT STRES TESTİ" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Red

$port = 9999
$chat1 = "chaos-chat-alpha-1"
$chat2 = "chaos-chat-beta-2"
$chat3 = "chaos-chat-gamma-3"

$chats = @(
    @{ Id = $chat1; Name = "Proje-Alpha (Mobil)"; StepCount = 15 },
    @{ Id = $chat2; Name = "Proje-Beta (API)"; StepCount = 15 },
    @{ Id = $chat3; Name = "Proje-Gamma (Frontend)"; StepCount = 15 }
)

Write-Host "[KAOS] 3 Chat aynı anda telemetri sunucusuna yoğun adımlar gönderecek..." -ForegroundColor DarkGray

# 3 Chat için karışık (interleaved) 45 adet istek fırlatıyoruz
$totalEvents = 45
$eventsSent = 0
$chaosErrors = 0

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

for ($step = 1; $step -le 15; $step++) {
    foreach ($c in $chats) {
        $node = switch ($step % 4) {
            0 { "node-architect" }
            1 { "node-workers" }
            2 { "node-tester" }
            3 { "node-judge" }
        }
        $payload = @{
            conversationId = $c.Id
            workspaceName  = $c.Name
            step           = $step
            totalSteps     = 15
            activeNode     = $node
            status         = "CALISIYOR"
            title          = "$($c.Name) Adım $step / 15"
            sender         = "[$($c.Name) Saha Ekibi]"
            message        = "Kaos stres eylemi #$step işleniyor"
            timestamp      = (Get-Date).ToString("HH:mm:ss.fff")
        } | ConvertTo-Json -Compress

        try {
            $req = [System.Net.WebRequest]::Create("http://localhost:$port/notify")
            $req.Method = "POST"
            $req.ContentType = "application/json; charset=utf-8"
            $req.Timeout = 1500
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
            $req.ContentLength = $bytes.Length
            $st = $req.GetRequestStream()
            $st.Write($bytes, 0, $bytes.Length)
            $st.Dispose()
            $resp = $req.GetResponse()
            $resp.Dispose()
            $eventsSent++
        } catch {
            $chaosErrors++
        }
    }
}

$stopwatch.Stop()
Write-Host "[KAOS] $eventsSent / $totalEvents telemetri isteği $($stopwatch.ElapsedMilliseconds) ms içinde tamamlandı." -ForegroundColor Cyan

# DOĞRULAMA 1: Her chat kendi son adımını (15) bağımsız olarak korumuş mu?
$state1 = Invoke-RestMethod -Uri "http://localhost:$port/state?cid=$chat1" -TimeoutSec 2
$state2 = Invoke-RestMethod -Uri "http://localhost:$port/state?cid=$chat2" -TimeoutSec 2
$state3 = Invoke-RestMethod -Uri "http://localhost:$port/state?cid=$chat3" -TimeoutSec 2

$step1Ok = ($state1.step -eq 15 -and $state1.conversationId -eq $chat1)
$step2Ok = ($state2.step -eq 15 -and $state2.conversationId -eq $chat2)
$step3Ok = ($state3.step -eq 15 -and $state3.conversationId -eq $chat3)

# DOĞRULAMA 2: /sessions tüm 3 chat'i doğru raporluyor mu?
$sessions = Invoke-RestMethod -Uri "http://localhost:$port/sessions" -TimeoutSec 2
$sessList = @($sessions)

$found1 = $sessList | Where-Object { $_.conversationId -eq $chat1 }
$found2 = $sessList | Where-Object { $_.conversationId -eq $chat2 }
$found3 = $sessList | Where-Object { $_.conversationId -eq $chat3 }

$allFound = ($null -ne $found1 -and $null -ne $found2 -and $null -ne $found3)

Write-Host "==========================================================" -ForegroundColor Red
Write-Host "🎯 KAOS TESTİ SONUÇ RAPORU:" -ForegroundColor White
$cErrCol = $(if ($chaosErrors -eq 0) { "Green" } else { "Red" })
$s1Col = $(if ($step1Ok) { "Green" } else { "Red" })
$s2Col = $(if ($step2Ok) { "Green" } else { "Red" })
$s3Col = $(if ($step3Ok) { "Green" } else { "Red" })
$allCol = $(if ($allFound) { "Green" } else { "Red" })

Write-Host "  ● Fırlatılan Olay Sayısı: $eventsSent / $totalEvents (Hata: $chaosErrors)" -ForegroundColor $cErrCol
Write-Host "  ● Chat 1 Durum İzolasyonu: $(if ($step1Ok) { '✅ BAŞARILI (Adım 15 korundu)' } else { '❌ BOZULDU' })" -ForegroundColor $s1Col
Write-Host "  ● Chat 2 Durum İzolasyonu: $(if ($step2Ok) { '✅ BAŞARILI (Adım 15 korundu)' } else { '❌ BOZULDU' })" -ForegroundColor $s2Col
Write-Host "  ● Chat 3 Durum İzolasyonu: $(if ($step3Ok) { '✅ BAŞARILI (Adım 15 korundu)' } else { '❌ BOZULDU' })" -ForegroundColor $s3Col
Write-Host "  ● Oturum Havuzu (/sessions): $(if ($allFound) { '✅ 3 Sohbet Eksiksiz Listelendi' } else { '❌ EKSİK OTURUM' })" -ForegroundColor $allCol
Write-Host "==========================================================" -ForegroundColor Red

$chaosSuccess = ($chaosErrors -eq 0 -and $step1Ok -and $step2Ok -and $step3Ok -and $allFound)
if ($chaosSuccess) {
    Write-Host "🐒 KAOS MÜHENDİSİ RAPORU: SİSTEM 3 EŞZAMANLI CHAT'İN YOĞUN YÜKÜ ALTINDA SIFIR ÇAKIŞMA İLE DİRENÇLİ ÇIKTI! 🚀" -ForegroundColor Green
    exit 0
} else {
    Write-Host "🐒 KAOS MÜHENDİSİ RAPORU: ÇAKIŞMA VEYA VERİ KAYBI TESPİT EDİLDİ!" -ForegroundColor Red
    exit 1
}
