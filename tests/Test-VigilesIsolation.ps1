# ==============================================================================
# Test-VigilesIsolation.ps1
# Vigiles Çift Bayraklı İzolasyon ve Yalnızca /live Başlatma TDD Test Paketi
# ==============================================================================
param()

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

function Invoke-HookWithStdin([string]$scriptPath, [hashtable]$payloadObj) {
    $json = $payloadObj | ConvertTo-Json -Depth 6 -Compress
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "powershell.exe"
    $pinfo.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`""
    $pinfo.RedirectStandardInput = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $proc = [System.Diagnostics.Process]::Start($pinfo)
    $proc.StandardInput.Write($json)
    $proc.StandardInput.Close()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    return ($stdout -replace '[\r\n]+$', '').Trim()
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🧪 VİGİLES TDD: ÇİFT BAYRAKLI İZOLASYON & YALNIZCA /LIVE TESTİ" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$configScripts = "$HOME\.gemini\config\scripts"
$ensureScript = Join-Path $configScripts "ensure_live_mission_control.ps1"
$sentinelScript = Join-Path $configScripts "sentinel_guard.ps1"
$stopScript = Join-Path $configScripts "on_mission_complete.ps1"

# Ephemeral izole test ortami (gercek ~/.gemini/config/active_mission.json ve Port 9999 korunur)
$tempBase = Join-Path $env:TEMP "vigiles_isolation_test_$(Get-Random)"
$tempConfigDir = Join-Path $tempBase "cfg"
$tempNonVigiles = Join-Path $tempBase "non_vigiles"
$tempPlan = Join-Path $tempBase "plan_command"
$tempThinkDeep = Join-Path $tempBase "thinkdeep_command"
$tempPro = Join-Path $tempBase "pro_command"
$tempLite = Join-Path $tempBase "lite_command"
$tempLive = Join-Path $tempBase "live_command"

New-Item -ItemType Directory -Path $tempConfigDir, $tempNonVigiles, $tempPlan, $tempThinkDeep, $tempPro, $tempLite, $tempLive -Force | Out-Null

# Bos bir ephemeral port sec
$testPort = 19991
for ($p = 19991; $p -lt 20050; $p++) {
    $inUse = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    if (-not $inUse) {
        $testPort = $p
        break
    }
}

$prevConfigEnv = $env:VIGILES_CONFIG_DIR
$prevPortEnv = $env:VIGILES_TELEMETRY_PORT
$env:VIGILES_CONFIG_DIR = $tempConfigDir
$env:VIGILES_TELEMETRY_PORT = "$testPort"

try {
    # --------------------------------------------------------------------------
    # TEST 1: Normal Sohbet -> ensure_live_mission_control {} dönmeli
    # --------------------------------------------------------------------------
    $res1 = Invoke-HookWithStdin $ensureScript @{
        lastUserInput = "Merhaba bu fonksiyonu açıklar mısın?"
        conversationId = "test-plain-chat"
        artifactDirectoryPath = $tempNonVigiles
        invocationNum = 1
    }
    $marker1 = Test-Path (Join-Path $tempNonVigiles ".vigiles_active")
    $live1 = Test-Path (Join-Path $tempNonVigiles ".live_active")

    Assert-Test "1. Normal sohbette {} dönmeli, .vigiles_active ve .live_active oluşmamalı" `
        ($res1 -eq "{}" -and -not $marker1 -and -not $live1) `
        "Sonuç: $res1 | Vigiles: $marker1 | Live: $live1"

    # --------------------------------------------------------------------------
    # TEST 2: Başka Slash Komutları (/plan ve /thinkdeep) -> tetiklenmemeli
    # --------------------------------------------------------------------------
    $res2a = Invoke-HookWithStdin $ensureScript @{
        lastUserInput = "/plan yeni bir e-ticaret sitesi tasarlayalım"
        conversationId = "test-plan-chat"
        artifactDirectoryPath = $tempPlan
        invocationNum = 1
    }
    $res2b = Invoke-HookWithStdin $ensureScript @{
        lastUserInput = "/thinkdeep ne zaman /lite ya da /pro kullansam /live çalışıyor"
        conversationId = "test-thinkdeep-chat"
        artifactDirectoryPath = $tempThinkDeep
        invocationNum = 1
    }
    $marker2 = (Test-Path (Join-Path $tempPlan ".vigiles_active")) -or (Test-Path (Join-Path $tempThinkDeep ".vigiles_active"))

    Assert-Test "2. /plan ve /thinkdeep komutlarında Vigiles/Live tetiklenmemeli" `
        ($res2a -eq "{}" -and $res2b -eq "{}" -and -not $marker2) `
        "/plan=$res2a | /thinkdeep=$res2b | Marker=$marker2"

    # --------------------------------------------------------------------------
    # TEST 3: /pro Komutu -> .vigiles_active oluşmalı AMA .live_active, HTML, Server ve Mesaj OLMAMALI
    # --------------------------------------------------------------------------
    $res3 = Invoke-HookWithStdin $ensureScript @{
        lastUserInput = "/pro mikroservis mimarisi ve testleri kur"
        conversationId = "test-pro-isolated"
        artifactDirectoryPath = $tempPro
        invocationNum = 1
    }
    $proVigiles = Test-Path (Join-Path $tempPro ".vigiles_active")
    $proLive = Test-Path (Join-Path $tempPro ".live_active")
    $proHtml = Test-Path (Join-Path $tempPro "live_mission_control.html")
    $proState = Test-Path (Join-Path $tempPro "live_state.json")
    $proActiveFile = Test-Path (Join-Path $tempConfigDir "active_mission.json")
    $proPortListening = [bool](Get-NetTCPConnection -LocalPort $testPort -State Listen -ErrorAction SilentlyContinue)

    Assert-Test "3. /pro komutunda sayfa/port/mesaj açılmamalı, yalnızca .vigiles_active + sessiz kayıt olmalı" `
        ($res3 -eq "{}" -and $proVigiles -and -not $proLive -and -not $proHtml -and $proState -and -not $proActiveFile -and -not $proPortListening) `
        "Çıktı=$res3 | Vigiles=$proVigiles | Live=$proLive | HTML=$proHtml | State=$proState | ActiveMission=$proActiveFile | Port=$proPortListening"

    # --------------------------------------------------------------------------
    # TEST 4: /lite Komutu -> .vigiles_active oluşmalı AMA .live_active, HTML, Server ve Mesaj OLMAMALI
    # --------------------------------------------------------------------------
    $res4 = Invoke-HookWithStdin $ensureScript @{
        lastUserInput = "/lite CSS padding hatasını düzelt"
        conversationId = "test-lite-isolated"
        artifactDirectoryPath = $tempLite
        invocationNum = 1
    }
    $liteVigiles = Test-Path (Join-Path $tempLite ".vigiles_active")
    $liteLive = Test-Path (Join-Path $tempLite ".live_active")
    $liteHtml = Test-Path (Join-Path $tempLite "live_mission_control.html")
    $liteState = Test-Path (Join-Path $tempLite "live_state.json")
    $litePortListening = [bool](Get-NetTCPConnection -LocalPort $testPort -State Listen -ErrorAction SilentlyContinue)

    Assert-Test "4. /lite komutunda sayfa/port/mesaj açılmamalı, yalnızca .vigiles_active + sessiz kayıt olmalı" `
        ($res4 -eq "{}" -and $liteVigiles -and -not $liteLive -and -not $liteHtml -and $liteState -and -not $litePortListening) `
        "Çıktı=$res4 | Vigiles=$liteVigiles | Live=$liteLive | HTML=$liteHtml | State=$liteState | Port=$litePortListening"

    # --------------------------------------------------------------------------
    # TEST 5: Normal Oturumda sentinel_guard.ps1 (PreToolUse) -> allow + telemetrisiz
    # --------------------------------------------------------------------------
    $res5 = Invoke-HookWithStdin $sentinelScript @{
        toolCall = @{
            name = "write_file"
            args = @{ Path = "C:\test\sample.js"; Content = "console.log('hello');" }
        }
        conversationId = "test-plain-chat"
        artifactDirectoryPath = $tempNonVigiles
    }
    $state5Exists = Test-Path (Join-Path $tempNonVigiles "live_state.json")

    Assert-Test "5. Vigiles olmayan oturumda sentinel_guard anında allow vermeli ve dosya yazmamalı" `
        ($res5 -match '"decision"\s*:\s*"allow"' -and -not $state5Exists) `
        "Yanıt: $res5 | live_state.json: $state5Exists"

    # --------------------------------------------------------------------------
    # TEST 6: /pro Sessiz Oturumda Güvenlik Kalkanı (Zero-Leak) + Sessiz Yerel Kayıt
    # --------------------------------------------------------------------------
    $syntheticSecret = ("sk-" + ("a1b2c3d4e5" * 3))
    $leakRes = Invoke-HookWithStdin $sentinelScript @{
        toolCall = @{
            name = "write_file"
            args = @{ Path = "C:\test\secret.js"; Content = "const k = '$syntheticSecret';" }
        }
        conversationId = "test-pro-isolated"
        artifactDirectoryPath = $tempPro
    }
    $testCmdRes = Invoke-HookWithStdin $sentinelScript @{
        toolCall = @{
            name = "run_command"
            args = @{ CommandLine = "npm test" }
        }
        conversationId = "test-pro-isolated"
        artifactDirectoryPath = $tempPro
    }
    $proStateAfterTool = Get-Content -Raw -Encoding UTF8 (Join-Path $tempPro "live_state.json") | ConvertFrom-Json

    Assert-Test "6. /pro sessiz oturumunda Zero-Leak engeli ve yerel adım kaydı (node-tester, step=5) çalışmalı" `
        (($leakRes -match '"decision"\s*:\s*"deny"') -and ($testCmdRes -match '"decision"\s*:\s*"allow"') -and $proStateAfterTool.activeNode -eq "node-tester" -and $proStateAfterTool.step -eq 5) `
        "ZeroLeakDeny=$($leakRes -match 'deny') | Node=$($proStateAfterTool.activeNode) | Step=$($proStateAfterTool.step)"

    # --------------------------------------------------------------------------
    # TEST 7: /live Komutu -> .live_active, HTML, Metadata, active_mission.json, Server ve Mesaj AÇILMALI
    # --------------------------------------------------------------------------
    $res7 = Invoke-HookWithStdin $ensureScript @{
        lastUserInput = "/live"
        conversationId = "test-live-session"
        artifactDirectoryPath = $tempLive
        invocationNum = 1
    }
    $liveVigiles = Test-Path (Join-Path $tempLive ".vigiles_active")
    $liveActive = Test-Path (Join-Path $tempLive ".live_active")
    $liveHtml = Test-Path (Join-Path $tempLive "live_mission_control.html")
    $liveMeta = Test-Path (Join-Path $tempLive "live_mission_control.html.metadata.json")
    $livePortListening = [bool](Get-NetTCPConnection -LocalPort $testPort -State Listen -ErrorAction SilentlyContinue)
    $liveInjected = ($res7 -match "CANLI OPERASYON MERKEZI DEVREDE")
    $activeObj7 = Get-Content -Raw -Encoding UTF8 (Join-Path $tempConfigDir "active_mission.json") | ConvertFrom-Json

    Assert-Test "7. /live komutunda .live_active, HTML, Metadata, Server ve Sistem Mesajı devreye girmeli" `
        ($liveVigiles -and $liveActive -and $liveHtml -and $liveMeta -and $livePortListening -and $liveInjected -and $activeObj7.conversationId -eq "test-live-session") `
        "Live=$liveActive | HTML=$liveHtml | Port=$livePortListening | Injected=$liveInjected | ActiveCid=$($activeObj7.conversationId)"

    # --------------------------------------------------------------------------
    # TEST 8: /live Açıkken Başka Bir Sohbette /lite & /pro Açık Panele SIZMAMALI
    # --------------------------------------------------------------------------
    Invoke-HookWithStdin $sentinelScript @{
        toolCall = @{
            name = "write_file"
            args = @{ Path = "C:\test\button.css"; Content = ".btn { padding: 8px; }" }
        }
        conversationId = "test-lite-isolated"
        artifactDirectoryPath = $tempLite
    } | Out-Null
    Invoke-HookWithStdin $stopScript @{
        conversationId = "test-lite-isolated"
        artifactDirectoryPath = $tempLite
    } | Out-Null

    $activeObjAfterLite = Get-Content -Raw -Encoding UTF8 (Join-Path $tempConfigDir "active_mission.json") | ConvertFrom-Json
    $sessionsList = Invoke-RestMethod -Uri "http://localhost:$testPort/sessions" -TimeoutSec 15 -ErrorAction Stop
    $liteInSessions = @($sessionsList | Where-Object { $_.conversationId -eq "test-lite-isolated" }).Count -gt 0
    $proInSessionsBefore = @($sessionsList | Where-Object { $_.conversationId -eq "test-pro-isolated" }).Count -gt 0

    Assert-Test "8. /live açıkken diğer /lite ve /pro sohbetleri /sessions listesine düşmemeli ve active_mission'ı ezmemeli" `
        ($activeObjAfterLite.conversationId -eq "test-live-session" -and -not $liteInSessions -and -not $proInSessionsBefore) `
        "ActiveCid=$($activeObjAfterLite.conversationId) | LiteLeaked=$liteInSessions | ProLeaked=$proInSessionsBefore"

    # --------------------------------------------------------------------------
    # TEST 9: Sohbet Ortasında /live (/pro -> sessiz adımlar -> /live) Kaldığı Yerden Yakalamalı
    # --------------------------------------------------------------------------
    $res9 = Invoke-HookWithStdin $ensureScript @{
        lastUserInput = "/live"
        conversationId = "test-pro-isolated"
        artifactDirectoryPath = $tempPro
        invocationNum = 1
    }
    Start-Sleep -Milliseconds 150
    $proStateAfterLive = Get-Content -Raw -Encoding UTF8 (Join-Path $tempPro "live_state.json") | ConvertFrom-Json
    $serverProState = Invoke-RestMethod -Uri "http://localhost:$testPort/state?cid=test-pro-isolated" -TimeoutSec 10 -ErrorAction Stop
    $proLiveNow = Test-Path (Join-Path $tempPro ".live_active")

    Assert-Test "9. Sohbet ortası /live çağrısında birikmiş aşama (step=5, node-tester) ezilmeden sunucuya aktarılmalı" `
        ($proLiveNow -and ($res9 -match "CANLI OPERASYON MERKEZI DEVREDE") -and $proStateAfterLive.step -eq 5 -and $serverProState.step -eq 5 -and $serverProState.activeNode -eq "node-tester") `
        "LocalStep=$($proStateAfterLive.step) | ServerStep=$($serverProState.step) | ServerNode=$($serverProState.activeNode)"

    # --------------------------------------------------------------------------
    # TEST 10: Normal ve Boş Stop Hook İzolasyonu (Açık /live oturumunu ezmemeli)
    # --------------------------------------------------------------------------
    $stopPlain = Invoke-HookWithStdin $stopScript @{
        conversationId = "test-plain-chat"
        artifactDirectoryPath = $tempNonVigiles
    }
    $stopEmpty = Invoke-HookWithStdin $stopScript @{}
    $liveStateAfterOtherStop = Invoke-RestMethod -Uri "http://localhost:$testPort/state?cid=test-live-session" -TimeoutSec 10 -ErrorAction Stop

    Assert-Test "10. Normal veya kimliksiz Stop hook {} dönmeli ve açık /live oturumunu TESLIM_EDILDI yapmamalı" `
        ($stopPlain -eq "{}" -and $stopEmpty -eq "{}" -and $liveStateAfterOtherStop.status -ne "TESLIM_EDILDI") `
        "Plain=$stopPlain | Empty=$stopEmpty | LiveStatus=$($liveStateAfterOtherStop.status)"

    # --------------------------------------------------------------------------
    # TEST 11: /live Oturumunda Stop Hook (on_mission_complete.ps1) Teslimat Bildirimi
    # --------------------------------------------------------------------------
    Invoke-HookWithStdin $stopScript @{
        conversationId = "test-live-session"
        artifactDirectoryPath = $tempLive
    } | Out-Null
    Start-Sleep -Milliseconds 150
    $liveDeliveredState = Invoke-RestMethod -Uri "http://localhost:$testPort/state?cid=test-live-session" -TimeoutSec 10 -ErrorAction Stop

    Assert-Test "11. /live oturumunda on_mission_complete 'TESLIM_EDILDI' durumunu sunucuya işlemeli" `
        ($liveDeliveredState.status -eq "TESLIM_EDILDI") `
        "Sunucu Durumu: $($liveDeliveredState.status)"

    # --------------------------------------------------------------------------
    # TEST 12: Kota Dürtücüsü İmha Doğrulaması (Negatif Kontrol)
    # --------------------------------------------------------------------------
    $wsRoot = Split-Path -Parent $PSScriptRoot
    $hbTask = Get-ScheduledTask -TaskName "VigilesKotaDurtucusu" -ErrorAction SilentlyContinue
    $hasGlobalHb = (Test-Path (Join-Path $configScripts "heartbeat_sentinel.ps1")) -or (Test-Path (Join-Path $configScripts "manage_heartbeat.ps1"))
    $hasCoreHb = (Test-Path (Join-Path $wsRoot "core\scripts\heartbeat_sentinel.ps1")) -or (Test-Path (Join-Path $wsRoot "core\scripts\manage_heartbeat.ps1"))
    $hasLogHb = (Test-Path (Join-Path $HOME ".gemini\heartbeat.log")) -or (Test-Path (Join-Path $wsRoot "heartbeat.log"))

    Assert-Test "12. VigilesKotaDurtucusu görevi ve tüm heartbeat kalıntıları sistemden tamamen kaldırılmış olmalı" `
        ($null -eq $hbTask -and -not $hasGlobalHb -and -not $hasCoreHb -and -not $hasLogHb) `
        "Task: $($null -eq $hbTask) | GlobalScript: $(-not $hasGlobalHb) | CoreScript: $(-not $hasCoreHb) | Log: $(-not $hasLogHb)"

} catch {
    Assert-Test "Beklenmeyen Test Hatası Olmamalı" $false "$($_.Exception.Message)"
} finally {
    # Ephemeral test sunucusunu temizle
    try {
        $procs = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
                 Where-Object { $_.CommandLine -match "telemetry_server\.ps1" -and $_.CommandLine -match "-Port $testPort" }
        foreach ($p in $procs) {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
    } catch {}

    $env:VIGILES_CONFIG_DIR = $prevConfigEnv
    $env:VIGILES_TELEMETRY_PORT = $prevPortEnv
    Remove-Item -Path $tempBase -Recurse -Force -ErrorAction SilentlyContinue
}

if (($global:passedCount + $global:failedCount) -lt 12) {
    $global:failedCount++
    Write-Host "  ❌ [BAŞARISIZ] Beklenen 12 testin tamamı koşulamadı (Koşulan: $($global:passedCount + $global:failedCount))" -ForegroundColor Red
}

Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
$summaryColor = if ($global:failedCount -eq 0) { "Green" } else { "Red" }
Write-Host "SONUÇ: $global:passedCount Geçti | $global:failedCount Başarısız" -ForegroundColor $summaryColor
Write-Host "==========================================================" -ForegroundColor Cyan

exit $global:failedCount
