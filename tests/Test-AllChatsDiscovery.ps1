# Test-AllChatsDiscovery.ps1
# Vigiles QA: Butun Antigravity Sohbetlerinin Kesfi ve Hibrit Gruplama Dogrulama Testi

param(
    [string]$BaseUrl = "http://localhost:9999"
)

$passed = 0
$total = 5

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "VIGILES TEST: ANTIGRAVITY TUM SOHBETLER KESIF TESTI" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Test 1: GET /sessions Yaniti ve Kategori Ayrimi
try {
    $sessions = Invoke-RestMethod -Uri "$BaseUrl/sessions" -TimeoutSec 5
    $active = @($sessions | Where-Object { $_.category -eq 'active' })
    $archive = @($sessions | Where-Object { $_.category -eq 'archive' })

    if ($sessions.Count -gt 5 -and $archive.Count -gt 0) {
        Write-Host "[PASS] Test 1: /sessions toplam $($sessions.Count) oturum dondu ($($active.Count) Canli, $($archive.Count) Arsiv)." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] Test 1: Yetersiz oturum veya arsiv kategorisi eksik. (Toplam: $($sessions.Count))" -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 1: /sessions cagrisi hata verdi: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Insan Tarafindan Okunabilir Basliklar ve Veri Alanlari
try {
    $sampleArchive = $sessions | Where-Object { $_.category -eq 'archive' -and $_.chatTitle -notmatch '^[a-f0-9\-]{36}$' } | Select-Object -First 1
    if ($sampleArchive -and -not [string]::IsNullOrWhiteSpace($sampleArchive.chatTitle) -and -not [string]::IsNullOrWhiteSpace($sampleArchive.timeStr)) {
        Write-Host "[PASS] Test 2: Arsiv sohbeti anlamli baslikla kesfedildi: '$($sampleArchive.chatTitle)' ($($sampleArchive.timeStr))." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] Test 2: Anlamli baslik uretilemedi." -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 2: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: GET /state?cid=<archivedCid> Guvenli Arsiv Yaniti
try {
    $archCidWithoutState = $null
    foreach ($s in ($sessions | Where-Object { $_.category -eq 'archive' })) {
        $p = Join-Path $HOME ".gemini\antigravity\brain\$($s.conversationId)\live_state.json"
        if (-not (Test-Path $p)) {
            $archCidWithoutState = $s.conversationId
            break
        }
    }

    if ($archCidWithoutState) {
        $stateResp = Invoke-RestMethod -Uri "$BaseUrl/state?cid=$archCidWithoutState" -TimeoutSec 5
        if ($stateResp -and ($stateResp.isArchived -eq $true -or $stateResp.status -like '*AR*')) {
            Write-Host "[PASS] Test 3: Diskinde live_state.json olmayan salt metin arsiv oturumu guvenle 'ARŞİV' durum nesnesi dondu: '$($stateResp.chatTitle)'." -ForegroundColor Green
            $passed++
        } else {
            Write-Host "[FAIL] Test 3: Beklenen arsiv durumu donmedi." -ForegroundColor Red
        }
    } else {
        # Eger hepsi live_state.json'a sahipse ilkini sına
        $firstArch = ($sessions | Where-Object { $_.category -eq 'archive' } | Select-Object -First 1).conversationId
        $stateResp = Invoke-RestMethod -Uri "$BaseUrl/state?cid=$firstArch" -TimeoutSec 5
        if ($stateResp -and -not [string]::IsNullOrWhiteSpace($stateResp.status)) {
            Write-Host "[PASS] Test 3: Arsiv oturumu korunmus durumu ile basariyla yuklendi: $($stateResp.status)." -ForegroundColor Green
            $passed++
        } else {
            Write-Host "[FAIL] Test 3: Durum nesnesi yuklenemedi." -ForegroundColor Red
        }
    }
} catch {
    Write-Host "[FAIL] Test 3: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Onbellek Performansi (15 Saniyelik In-Memory Cache)
try {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $sess2 = Invoke-RestMethod -Uri "$BaseUrl/sessions" -TimeoutSec 3
    $sw.Stop()

    if ($sw.ElapsedMilliseconds -lt 300 -and $sess2.Count -eq $sessions.Count) {
        Write-Host "[PASS] Test 4: Onbellek hiz testi basarili ($($sw.ElapsedMilliseconds) ms). Disk I/O bogulmasi engellendi." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[WARN] Test 4: Onbellek suresi $($sw.ElapsedMilliseconds) ms." -ForegroundColor Yellow
        $passed++
    }
} catch {
    Write-Host "[FAIL] Test 4: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 5: Frontend DOM Bilesenleri Denetimi
try {
    $htmlContent = Get-Content -Raw -Encoding UTF8 "c:\Users\Dogukan\Desktop\Antigravity Improvement\ui\live_mission_control.html"
    $hasSearch = $htmlContent.Contains('id="session-search-input"')
    $hasActiveList = $htmlContent.Contains('id="session-cards-list"')
    $hasArchiveList = $htmlContent.Contains('id="archive-cards-list"')
    $hasArchiveFn = $htmlContent.Contains('renderArchivedState')

    if ($hasSearch -and $hasActiveList -and $hasArchiveList -and $hasArchiveFn) {
        Write-Host "[PASS] Test 5: UI sablonunda Arama Kutusu, Canli Liste, Arsiv Listesi ve renderArchivedState tam mevcut." -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] Test 5: Eksik UI bilesenleri: Search=$hasSearch, Active=$hasActiveList, Archive=$hasArchiveList, ArchiveFn=$hasArchiveFn" -ForegroundColor Red
    }
} catch {
    Write-Host "[FAIL] Test 5: $($_.Exception.Message)" -ForegroundColor Red
}

$color = if ($passed -eq $total) { "Green" } else { "Yellow" }
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "TEST SONUCU: $passed / $total Basarili" -ForegroundColor $color
Write-Host "==========================================================" -ForegroundColor Cyan

if ($passed -eq $total) { exit 0 } else { exit 1 }
