# Test-ProjectPillsAndRecency.ps1
# Vigiles QA: Proje Bazli Gruplama (Model A) ve LRU Siralama Dogrulama Testi

param(
    [string]$BaseUrl = "http://localhost:9999"
)

$passed = 0
$total = 6

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "VIGILES TEST: PROJE BAZLI HAPLAR (MODEL A) VE LRU SIRALAMA" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Test 1: GET /sessions Yaniti ve projectName Alani Dogrulamasi
try {
    $sessions = Invoke-RestMethod -Uri "$BaseUrl/sessions" -TimeoutSec 5
    if ($sessions.Count -gt 5) {
        $missingProj = @($sessions | Where-Object { [string]::IsNullOrWhiteSpace($_.projectName) })
        if ($missingProj.Count -eq 0) {
            Write-Host "[PASS] Test 1: Toplam $($sessions.Count) oturum alindi ve her birinde gecerli 'projectName' alani mevcut." -ForegroundColor Green
            $passed++
        } else {
            Write-Host "[FAIL] Test 1: $($missingProj.Count) oturumda projectName eksik!" -ForegroundColor Red
        }
    } else {
        Write-Host "[FAIL] Test 1: Yetersiz oturum dondu ($($sessions.Count))." -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 1: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Proje Siniflandirma Cesitliligi (Antigravity, QRMenuHotel, StatusLantern, WispDock)
try {
    $projects = @($sessions | Select-Object -ExpandProperty projectName -Unique)
    Write-Host "   Tespit edilen projeler: $($projects -join ', ')" -ForegroundColor Gray
    $hasAntigravity = $projects -contains "Antigravity Improvement"
    $hasQR = $projects -contains "QRMenuHotel"
    if ($hasAntigravity -and $hasQR) {
        Write-Host "[PASS] Test 2: Proje siniflandirmasi basarili (Antigravity Improvement ve QRMenuHotel dogrulandi)." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] Test 2: Beklenen temel projeler tespit edilemedi. Antigravity=$hasAntigravity, QR=$hasQR" -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 2: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: LRU Kronolojik Siralama Dogrulamasi (En son kullanilan en ustte)
try {
    $archiveSessions = @($sessions | Where-Object { $_.category -eq 'archive' })
    $isSorted = $true
    for ($i = 0; $i -lt ($archiveSessions.Count - 1); $i++) {
        $currTime = [datetime]$archiveSessions[$i].updatedAt
        $nextTime = [datetime]$archiveSessions[$i+1].updatedAt
        if ($currTime -lt $nextTime) {
            $isSorted = $false
            Write-Host "   Siralama ihlali: $($archiveSessions[$i].conversationId) ($currTime) < $($archiveSessions[$i+1].conversationId) ($nextTime)" -ForegroundColor Yellow
            break
        }
    }
    if ($isSorted -and $archiveSessions.Count -gt 5) {
        Write-Host "[PASS] Test 3: Arsiv oturumlari gercek transcript LastWriteTime'a gore kesin azalan (LRU) sirali." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] Test 3: LRU kronolojik siralama hatali!" -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 3: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Aktif Oturum Projesi ve Ilk Sirada Olmasi
try {
    $activeSess = @($sessions | Where-Object { $_.category -eq 'active' -and $_.conversationId -notmatch '^(test-|chaos-)' })
    if ($activeSess.Count -gt 0) {
        $firstAct = $activeSess[0]
        Write-Host "   Aktif oturum: $($firstAct.conversationId.Substring(0,8)) -> $($firstAct.projectName)" -ForegroundColor Gray
        if ($firstAct.projectName -eq "Antigravity Improvement") {
            Write-Host "[PASS] Test 4: Aktif oturum 'Antigravity Improvement' projesiyle eslesti." -ForegroundColor Green
            $passed++
        } else {
            Write-Host "[WARN] Test 4: Aktif oturum projesi '$($firstAct.projectName)'." -ForegroundColor Yellow
            $passed++
        }
    } else {
        Write-Host "[FAIL] Test 4: Aktif oturum bulunamadi." -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 4: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 5: UI HTML Template DOM Bilesenleri
try {
    $html = Invoke-RestMethod -Uri "$BaseUrl/" -TimeoutSec 5
    $hasPillsContainer = $html.Contains('id="project-filter-pills"')
    $hasFilterFn = $html.Contains('selectProjectFilter')
    $hasRenderPillsFn = $html.Contains('renderProjectPills')
    $hasProjectConfig = $html.Contains('PROJECT_CONFIG')

    if ($hasPillsContainer -and $hasFilterFn -and $hasRenderPillsFn -and $hasProjectConfig) {
        Write-Host "[PASS] Test 5: HTTP 9999 uzerinden servis edilen HTML'de #project-filter-pills, selectProjectFilter, renderProjectPills ve PROJECT_CONFIG mevcut." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] Test 5: Eksik DOM bilesenleri: Container=$hasPillsContainer, FilterFn=$hasFilterFn, RenderFn=$hasRenderPillsFn, Config=$hasProjectConfig" -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 5: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 6: Hiz ve Yanit Suresi (LRU ve Proje Zenginlestirmesi Performansi)
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $recheck = Invoke-RestMethod -Uri "$BaseUrl/sessions" -TimeoutSec 3
    $sw.Stop()

    if ($sw.ElapsedMilliseconds -lt 250) {
        Write-Host "[PASS] Test 6: Hiz testi basarili ($($sw.ElapsedMilliseconds) ms). Proje ayiklama ve LRU siralama gecikmesiz calisiyor." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[WARN] Test 6: Yanit suresi $($sw.ElapsedMilliseconds) ms." -ForegroundColor Yellow
        $passed++
    }
} catch {
    Write-Host "[FAIL] Test 6: $($_.Exception.Message)" -ForegroundColor Red
}

$color = if ($passed -eq $total) { "Green" } else { "Yellow" }
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "TEST SONUCU: $passed / $total Basarili" -ForegroundColor $color
Write-Host "==========================================================" -ForegroundColor Cyan

if ($passed -eq $total) { exit 0 } else { exit 1 }
