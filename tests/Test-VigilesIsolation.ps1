# ==============================================================================
# Test-VigilesIsolation.ps1
# Vigiles İzolasyon ve Koşullu Tetikleme TDD Test Paketi
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

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🧪 VİGİLES TDD: İZOLASYON VE YALNIZCA /VIGILES TESTİ" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$configScripts = "$HOME\.gemini\config\scripts"
$ensureScript = Join-Path $configScripts "ensure_live_mission_control.ps1"
$sentinelScript = Join-Path $configScripts "sentinel_guard.ps1"
$stopScript = Join-Path $configScripts "on_mission_complete.ps1"

# Geçici test oturum dizinleri
$tempBase = Join-Path $env:TEMP "vigiles_isolation_test_$(Get-Random)"
$tempNonVigiles = Join-Path $tempBase "non_vigiles"
$tempPlan = Join-Path $tempBase "plan_command"
$tempVigiles = Join-Path $tempBase "vigiles_command"

New-Item -ItemType Directory -Path $tempNonVigiles -Force | Out-Null
New-Item -ItemType Directory -Path $tempPlan -Force | Out-Null
New-Item -ItemType Directory -Path $tempVigiles -Force | Out-Null

try {
    # --------------------------------------------------------------------------
    # TEST 1: Normal Girdi (Non-Vigiles) -> ensure_live_mission_control.ps1
    # --------------------------------------------------------------------------
    $p1 = @{
        lastUserInput = "Merhaba bu fonksiyonu açıklar mısın?"
        conversationId = "session-plain-chat"
        artifactDirectoryPath = $tempNonVigiles
        invocationNum = 1
    } | ConvertTo-Json -Compress

    $res1 = $p1 | powershell -ExecutionPolicy Bypass -NoProfile -File $ensureScript
    $marker1Exists = Test-Path (Join-Path $tempNonVigiles ".vigiles_active")

    Assert-Test "1. Normal sohbette ensure_live_mission_control {} dönmeli ve aktifleşmemeli" `
        ($res1 -eq "{}" -and -not $marker1Exists) `
        "Sonuç: $res1 | Marker: $marker1Exists"

    # --------------------------------------------------------------------------
    # TEST 2: Başka Slash Komutu (/plan) -> ensure_live_mission_control.ps1
    # --------------------------------------------------------------------------
    $p2 = @{
        lastUserInput = "/plan yeni bir e-ticaret sitesi tasarlayalım"
        conversationId = "session-plan-chat"
        artifactDirectoryPath = $tempPlan
        invocationNum = 1
    } | ConvertTo-Json -Compress

    $res2 = $p2 | powershell -ExecutionPolicy Bypass -NoProfile -File $ensureScript
    $marker2Exists = Test-Path (Join-Path $tempPlan ".vigiles_active")

    Assert-Test "2. /plan komutunda Vigiles tetiklenmemeli ve {} dönmeli" `
        ($res2 -eq "{}" -and -not $marker2Exists) `
        "Sonuç: $res2 | Marker: $marker2Exists"

    # --------------------------------------------------------------------------
    # TEST 3: /vigiles Komutu -> ensure_live_mission_control.ps1
    # --------------------------------------------------------------------------
    $p3 = @{
        lastUserInput = "/vigiles mikroservis mimarisi ve testleri kur"
        conversationId = "session-vigiles-chat"
        artifactDirectoryPath = $tempVigiles
        invocationNum = 1
    } | ConvertTo-Json -Compress

    $res3 = $p3 | powershell -ExecutionPolicy Bypass -NoProfile -File $ensureScript
    $marker3Exists = Test-Path (Join-Path $tempVigiles ".vigiles_active")
    $injectedMsg = $res3 -match "CANLI OPERASYON MERKEZI DEVREDE"

    Assert-Test "3. /vigiles komutunda .vigiles_active oluşturulmalı ve Canlı Merkez bildirilmeli" `
        ($marker3Exists -and $injectedMsg) `
        "Marker: $marker3Exists | Sistem Mesajı Enjekte: $injectedMsg"

    # --------------------------------------------------------------------------
    # TEST 4: Normal Oturumda sentinel_guard.ps1 (PreToolUse)
    # --------------------------------------------------------------------------
    $p4 = @{
        toolCall = @{
            name = "write_file"
            args = @{ Path = "C:\test\sample.js"; Content = "console.log('hello');" }
        }
        conversationId = "session-plain-chat"
        artifactDirectoryPath = $tempNonVigiles
    } | ConvertTo-Json -Compress

    $res4 = $p4 | powershell -ExecutionPolicy Bypass -NoProfile -File $sentinelScript
    $state4Exists = Test-Path (Join-Path $tempNonVigiles "live_state.json")

    Assert-Test "4. Vigiles olmayan oturumda sentinel_guard anında allow vermeli ve telemetri basmamalı" `
        ($res4 -match '"decision"\s*:\s*"allow"' -and -not $state4Exists) `
        "Yanıt: $res4 | live_state.json oluşmadı: $(-not $state4Exists)"

    # --------------------------------------------------------------------------
    # TEST 5: Vigiles Oturumunda sentinel_guard.ps1 (PreToolUse)
    # --------------------------------------------------------------------------
    $p5 = @{
        toolCall = @{
            name = "run_command"
            args = @{ CommandLine = "npm test" }
        }
        conversationId = "session-vigiles-chat"
        artifactDirectoryPath = $tempVigiles
    } | ConvertTo-Json -Compress

    $res5 = $p5 | powershell -ExecutionPolicy Bypass -NoProfile -File $sentinelScript
    $state5Exists = Test-Path (Join-Path $tempVigiles "live_state.json")
    $state5Content = if ($state5Exists) { Get-Content -Raw -Encoding UTF8 (Join-Path $tempVigiles "live_state.json") } else { "" }
    $testerMatched = $state5Content -match "node-tester"

    Assert-Test "5. Vigiles oturumunda sentinel_guard 20-eleman telemetrisini işletmeli" `
        ($state5Exists -and $testerMatched) `
        "live_state.json oluştu: $state5Exists | node-tester eşleşti: $testerMatched"

    # --------------------------------------------------------------------------
    # TEST 6: Normal Oturumda on_mission_complete.ps1 (Stop)
    # --------------------------------------------------------------------------
    $p6 = @{
        conversationId = "session-plain-chat"
        artifactDirectoryPath = $tempNonVigiles
    } | ConvertTo-Json -Compress

    $res6 = $p6 | powershell -ExecutionPolicy Bypass -NoProfile -File $stopScript
    $res6Empty = ($res6 -eq "{}")

    Assert-Test "6. Normal oturumda on_mission_complete {} dönmeli ve fabrika teslimi yapmamalı" `
        $res6Empty `
        "Sonuç: $res6"

    # --------------------------------------------------------------------------
    # TEST 7: Vigiles Oturumunda on_mission_complete.ps1 (Stop)
    # --------------------------------------------------------------------------
    $p7 = @{
        conversationId = "session-vigiles-chat"
        artifactDirectoryPath = $tempVigiles
    } | ConvertTo-Json -Compress

    $res7 = $p7 | powershell -ExecutionPolicy Bypass -NoProfile -File $stopScript
    $state7Content = if (Test-Path (Join-Path $tempVigiles "live_state.json")) {
        Get-Content -Raw -Encoding UTF8 (Join-Path $tempVigiles "live_state.json")
    } else { "" }
    $deliveredMatched = $state7Content -match "TESLIM_EDILDI"

    Assert-Test "7. Vigiles oturumunda on_mission_complete 'TESLIM_EDILDI' durumunu işlemeli" `
        $deliveredMatched `
        "Teslim Durumu: $deliveredMatched"

    # --------------------------------------------------------------------------
    # TEST 8: Kota Dürtücüsü Bütünlüğü (Heartbeat Sentinel)
    # --------------------------------------------------------------------------
    $task = Get-ScheduledTask -TaskName "VigilesKotaDurtucusu" -ErrorAction SilentlyContinue
    $taskState = if ($task) { $task.State.ToString() } else { "NotFound" }

    Assert-Test "8. VigilesKotaDurtucusu görevi sağlam ve 'Ready' durumunda olmalı" `
        ($taskState -eq "Ready") `
        "Görev Durumu: $taskState"

} finally {
    Remove-Item -Path $tempBase -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
$summaryColor = if ($global:failedCount -eq 0) { "Green" } else { "Red" }
Write-Host "SONUÇ: $global:passedCount Geçti | $global:failedCount Başarısız" -ForegroundColor $summaryColor
Write-Host "==========================================================" -ForegroundColor Cyan

exit $global:failedCount
