# Test-PillsClickKeepOpen.ps1
# Vigiles Light QA: Proje Haplarina Tiklandiginda Menunun Acik Kalmasi Testi

$htmlPath = "ui\live_mission_control.html"
$content = Get-Content -Raw -Encoding UTF8 $htmlPath

$passed = 0
$total = 4

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "VIGILES LIGHT TEST: PROJE HAPLARI TIKLAMA KORUMASI TESTI" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Test 1: session-popover-panel onclick stopPropagation
if ($content -match 'id="session-popover-panel"\s+onclick="event\.stopPropagation\(\)"') {
    Write-Host "[PASS] Test 1: session-popover-panel elementine 'onclick=event.stopPropagation()' eklendi." -ForegroundColor Green
    $passed++
} else {
    Write-Host "[FAIL] Test 1: session-popover-panel onclick stopPropagation eksik!" -ForegroundColor Red
}

# Test 2: selectProjectFilter fonksiyonu event durdurma
if ($content -match 'function selectProjectFilter\(e,\s*projectName\)\s*\{\s*if\s*\(e\)\s*\{\s*if\s*\(e\.preventDefault\)\s*e\.preventDefault\(\);\s*if\s*\(e\.stopPropagation\)\s*e\.stopPropagation\(\);') {
    Write-Host "[PASS] Test 2: selectProjectFilter(e, projectName) event'i e.stopPropagation() ve preventDefault() ile guvenle yakaliyor." -ForegroundColor Green
    $passed++
} else {
    Write-Host "[FAIL] Test 2: selectProjectFilter event durdurma mekanizmasi eksik!" -ForegroundColor Red
}

# Test 3: document click listener re-render / disconnected node korumasi
if ($content -match 'if\s*\(!e\.target\s*\|\|\s*!e\.target\.isConnected\)\s*return;' -and $content -match 'e\.target\.closest\s*&&\s*e\.target\.closest\(.*?#session-popover-panel') {
    Write-Host "[PASS] Test 3: Document click listener disconnected node ve closest(#session-popover-panel) denetimi yapiyor." -ForegroundColor Green
    $passed++
} else {
    Write-Host "[FAIL] Test 3: Document click listener disconnected / closest denetimi eksik!" -ForegroundColor Red
}

# Test 4: renderProjectPills icinde selectProjectFilter(event, ...) cagrisi
if ($content -match 'selectProjectFilter\(event,\s*''ALL''\)' -and $content -match 'selectProjectFilter\(event,\s*''\$\{pName') {
    Write-Host "[PASS] Test 4: renderProjectPills icerisindeki butonlar 'selectProjectFilter(event, ...)' ile olayi aktariyor." -ForegroundColor Green
    $passed++
} else {
    Write-Host "[FAIL] Test 4: renderProjectPills icerisindeki butonlarda event aktarimi eksik!" -ForegroundColor Red
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "TEST SONUCU: $passed / $total Basarili" -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Red" })
Write-Host "==========================================================" -ForegroundColor Cyan

if ($passed -eq $total) { exit 0 } else { exit 1 }
