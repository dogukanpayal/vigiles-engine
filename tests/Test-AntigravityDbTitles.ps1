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
$dbRows = @()
$sessions = @()
try {
    $dbPath = Join-Path $HOME ".gemini\antigravity\conversation_summaries.db"
    $agyNode = Join-Path $env:APPDATA "Antigravity\bin\agy-node.cmd"
    if (-not (Test-Path $agyNode)) {
        $cmd = Get-Command "agy-node*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { $agyNode = $cmd.Source }
    }
    $dbPathForward = $dbPath.Replace('\', '/')
    $jsCode = "const { DatabaseSync } = require('node:sqlite'); const db = new DatabaseSync('$dbPathForward', { open: true, readOnly: true }); const rows = db.prepare('SELECT conversation_id, title, parent_conversation_id, workspace_uris FROM conversation_summaries').all(); console.log(Buffer.from(JSON.stringify(rows), 'utf8').toString('base64'));"
    $b64Out = & $agyNode -e $jsCode 2>$null
    $jsonStr = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(($b64Out -join '').Trim()))
    $dbRows = $jsonStr | ConvertFrom-Json
    if ($null -eq $dbRows) { $dbRows = @() } elseif ($dbRows -isnot [array]) { $dbRows = @($dbRows) }
    $titledRootRows = @($dbRows | Where-Object { [string]::IsNullOrWhiteSpace($_.parent_conversation_id) -and -not [string]::IsNullOrWhiteSpace($_.title) -and $_.title.Trim().ToLower() -ne 'ping' })

    if ($titledRootRows.Count -ge 1) {
        Write-Host "[PASS] Test 1: conversation_summaries.db Read-Only SQLite koprusu aktif ($($titledRootRows.Count) baslikli ana sohbet okundu)." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] Test 1: Veritabanindan yeterli baslikli ana sohbet okunamadi." -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 1: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: GET /sessions Icinde DB Basliklariyla %100 Birebir Aynalama
try {
    $resp = Invoke-WebRequest -Uri "$BaseUrl/sessions" -UseBasicParsing -TimeoutSec 5
    $sessJson = [System.Text.Encoding]::UTF8.GetString($resp.RawContentStream.ToArray())
    $sessions = $sessJson | ConvertFrom-Json
    if ($null -eq $sessions) { $sessions = @() } elseif ($sessions -isnot [array]) { $sessions = @($sessions) }

    $sessById = @{}
    foreach ($s in $sessions) { $sessById[$s.conversationId] = $s }

    $mismatches = @()
    foreach ($row in $titledRootRows) {
        if (-not $sessById.ContainsKey($row.conversation_id)) {
            $mismatches += "$($row.title) (eksik)"
        } elseif ($sessById[$row.conversation_id].chatTitle -ne $row.title) {
            $mismatches += "$($row.title) != $($sessById[$row.conversation_id].chatTitle)"
        }
    }

    if ($titledRootRows.Count -ge 1 -and $mismatches.Count -eq 0) {
        Write-Host "[PASS] Test 2: DB'deki tum resmi sohbet isimleri ($($titledRootRows.Count)/$($titledRootRows.Count)) /sessions ile %100 birebir eslesti." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] Test 2: Eksik veya hatalı başlık eşleşmeleri: $($mismatches -join ', ')" -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 2: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: workspace_uris Tabanli Kesin Proje Eslestirmesi (Dinamik & Tasinabilir Dogrulama)
try {
    $wsRows = @($titledRootRows | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.workspace_uris) -and $_.workspace_uris.Trim() -ne '[]'
    })
    $badClassifications = @()
    $matchedProjects = @()

    foreach ($row in $wsRows) {
        $sess = $sessById[$row.conversation_id]
        $pname = if ($sess) { $sess.projectName } else { "" }
        if ([string]::IsNullOrWhiteSpace($pname) -or $pname -eq 'Genel') {
            $badClassifications += "$($row.conversation_id)=$pname"
        } else {
            $matchedProjects += $pname
        }
    }

    $currentRepoMatch = @($wsRows | Where-Object { $_.workspace_uris -match 'Antigravity(%20|\s)Improvement' } | Select-Object -First 1)
    $repoProjectOk = ($currentRepoMatch.Count -eq 0) -or ($sessById[$currentRepoMatch[0].conversation_id].projectName -eq 'Antigravity Improvement')

    if ($wsRows.Count -ge 1 -and $badClassifications.Count -eq 0 -and $repoProjectOk) {
        $uniqueProjects = @($matchedProjects | Sort-Object -Unique)
        Write-Host "[PASS] Test 3: workspace_uris tabanli proje siniflandirmasi basarili ($($wsRows.Count) sohbet -> $($uniqueProjects -join ', '))." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] Test 3: Yanlis proje siniflandirmasi: $($badClassifications -join ', ') (repoProjectOk=$repoProjectOk)" -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 3: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Alt Ajan (Subagent parent_conversation_id != '') ve Ping Filtrelemesi
try {
    $excludedIds = @($dbRows | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.parent_conversation_id) -or
        (-not [string]::IsNullOrWhiteSpace($_.title) -and $_.title.Trim().ToLower() -eq 'ping')
    } | Select-Object -ExpandProperty conversation_id)

    $leakedIds = @($sessions | Where-Object {
        $excludedIds -contains $_.conversationId -or
        (-not [string]::IsNullOrWhiteSpace($_.chatTitle) -and $_.chatTitle.Trim().ToLower() -eq 'ping')
    } | Select-Object -ExpandProperty conversationId)

    if ($leakedIds.Count -eq 0) {
        Write-Host "[PASS] Test 4: Tum alt ajanlar ($($excludedIds.Count) kayit) ve ping oturumlari /sessions listesinden tamamen elendi." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] Test 4: Alt ajan veya ping oturumu listeye sizdi ($($leakedIds -join ', '))!" -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 4: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 5: UI Header Label 'Sohbet #1:' On Eki Kaldirilmasi Dogrulamasi
try {
    $htmlContent = Get-Content -Raw -Encoding UTF8 (Join-Path (Split-Path -Parent $PSScriptRoot) "core\templates\live_mission_control.html")
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
    $null = Invoke-RestMethod -Uri "$BaseUrl/sessions" -TimeoutSec 5
    $avgMs = 0
    $errCount = 0
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $errCount = 0
        for ($i = 0; $i -lt 25; $i++) {
            try {
                $r = Invoke-RestMethod -Uri "$BaseUrl/sessions" -TimeoutSec 5
                if ($r.Count -lt 5) { $errCount++ }
            } catch {
                $errCount++
            }
        }
        $sw.Stop()
        $avgMs = [math]::Round($sw.ElapsedMilliseconds / 25.0, 2)
        if ($errCount -eq 0 -and $avgMs -lt 50) { break }
    }

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
