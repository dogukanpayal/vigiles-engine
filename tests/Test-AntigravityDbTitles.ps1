# Test-AntigravityDbTitles.ps1
# Vigiles QA & Chaos: Antigravity Resmi Sohbet Basliklari (conversation_summaries.db) ve Proje Eslestirme Testi

param(
    [string]$BaseUrl = "http://localhost:9999"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$passed = 0
$total = 6

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "VIGILES TEST: ANTIGRAVITY RESMI SOHBET BASLIKLARI KOPRUSU" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Test 1: agy-node SQLite Read-Only Koprusu Dogrulamasi
try {
    $dbPath = Join-Path $HOME ".gemini\antigravity\conversation_summaries.db"
    $agyNode = Join-Path $env:APPDATA "Antigravity\bin\agy-node.cmd"
    $dbPathForward = $dbPath.Replace('\', '/')
    $jsCode = "const { DatabaseSync } = require('node:sqlite'); const db = new DatabaseSync('$dbPathForward', { open: true, readOnly: true }); const rows = db.prepare('SELECT conversation_id, title FROM conversation_summaries WHERE title != \'\'').all(); console.log(Buffer.from(JSON.stringify(rows), 'utf8').toString('base64'));"
    $b64Out = & $agyNode -e $jsCode 2>$null
    $jsonStr = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(($b64Out -join '').Trim()))
    $dbRows = $jsonStr | ConvertFrom-Json

    if ($dbRows.Count -ge 5) {
        Write-Host "[PASS] Test 1: conversation_summaries.db Read-Only SQLite koprusu aktif ($($dbRows.Count) baslikli sohbet okundu)." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] Test 1: Veritabanindan yeterli baslik okunamadi." -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 1: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: GET /sessions Icinde Birebir Resmi Antigravity Basliklari
try {
    $resp = Invoke-WebRequest -Uri "$BaseUrl/sessions" -UseBasicParsing -TimeoutSec 5
    $sessJson = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
    $sessions = $sessJson | ConvertFrom-Json

    $titles = @($sessions | Select-Object -ExpandProperty chatTitle)
    $expectedTitles = @(
        "Housekeeping Demo To-Do List",
        "Live Streaming Setup",
        "Görev Planı Ve Devam Planlaması",
        "ChatGPT-Antigravity Sisteminden Vigiles'e Geçiş",
        "Proje Dosya Düzeni Önerisi"
    )

    $missing = @()
    foreach ($exp in $expectedTitles) {
        if ($titles -notcontains $exp) {
            $missing += $exp
        }
    }

    if ($missing.Count -eq 0) {
        Write-Host "[PASS] Test 2: Antigravity yan menüsündeki tüm resmi sohbet isimleri %100 birebir eşleşti." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] Test 2: Eksik veya hatalı başlıklar: $($missing -join ', ')" -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 2: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: workspace_uris Tabanli Kesin Proje Eslestirmesi (Yanlis Pozitif Engeli)
try {
    $chatGptConv = $sessions | Where-Object { $_.conversationId -eq "7b039f6a-519c-45b2-a65a-53179d00341a" } | Select-Object -First 1
    $liveStreamConv = $sessions | Where-Object { $_.conversationId -eq "1df45171-0a68-41c8-83a8-19d5a33c3682" } | Select-Object -First 1

    if ($chatGptConv.projectName -eq "QRMenuHotel" -and $liveStreamConv.projectName -eq "QRMenuHotel") {
        Write-Host "[PASS] Test 3: workspace_uris uzerinden kesin proje tespiti basarili ('ChatGPT-Antigravity...' ve 'Live Streaming Setup' -> QRMenuHotel)." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] Test 3: Yanlis proje siniflandirmasi: ChatGPT=$($chatGptConv.projectName), LiveStream=$($liveStreamConv.projectName)" -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 3: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Alt Ajan (Subagent parent_conversation_id != '') ve Ping Filtrelemesi
try {
    $subagentConv = $sessions | Where-Object { $_.conversationId -eq "3246a0e9-3dc2-4d6e-acbe-88f19568ffdc" }
    $pingConvs = $sessions | Where-Object { $_.chatTitle -eq "ping" }

    if ($null -eq $subagentConv -and $null -eq $pingConvs) {
        Write-Host "[PASS] Test 4: Alt ajanlar (parent_conversation_id) ve kota ping oturumlari basariyla filtrelendi." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] Test 4: Alt ajan veya ping oturumu listeye sizdi!" -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 4: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 5: UI Header Label 'Sohbet #1:' On Eki Kaldirilmasi Dogrulamasi
try {
    $htmlContent = Get-Content -Raw -Encoding UTF8 "C:\Users\Dogukan\Desktop\Antigravity Improvement\ui\live_mission_control.html"
    $hasOldPrefixLogic = $htmlContent.Contains('(s.sessionNumber ? `${s.sessionNumber}: ` : '''')')
    $hasCleanTitleLogic = $htmlContent.Contains('const cleanTitle = fixMojibake(s.chatTitle || s.title || ''Sohbet'');')

    if (-not $hasOldPrefixLogic -and $hasCleanTitleLogic) {
        Write-Host "[PASS] Test 5: UI ust basliginda 'Sohbet #1:' on eki kaldirildi, dogrudan saf Antigravity basligi gosteriliyor." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] Test 5: UI baslik formati guncellenmemis!" -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 5: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 6: Kaos & Stres Testi (25x Ardisik Hizli /sessions Sorgusu & TTL Cache)
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $errCount = 0
    for ($i = 0; $i -lt 25; $i++) {
        try {
            $r = Invoke-RestMethod -Uri "$BaseUrl/sessions" -TimeoutSec 2
            if ($r.Count -lt 5) { $errCount++ }
        } catch {
            $errCount++
        }
    }
    $sw.Stop()
    $avgMs = [math]::Round($sw.ElapsedMilliseconds / 25.0, 2)

    if ($errCount -eq 0 -and $avgMs -lt 50) {
        Write-Host "[PASS] Test 6: Kaos 25x seri spam testi basarili (0 hata, ortalama $avgMs ms/istek)." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] Test 6: Kaos testinde $errCount hata veya yuksek gecikme ($avgMs ms)." -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 6: $($_.Exception.Message)" -ForegroundColor Red
}

$color = if ($passed -eq $total) { "Green" } else { "Red" }
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "TEST SONUCU: $passed / $total Basarili" -ForegroundColor $color
Write-Host "==========================================================" -ForegroundColor Cyan

if ($passed -eq $total) { exit 0 } else { exit 1 }
