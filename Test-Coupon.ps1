[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

. "c:\Users\Dogukan\Desktop\Antigravity Improvement\CouponService.ps1"

Write-Host "--- TDD KUPON MOTORU BIRIM TESTLERI BASLATILIYOR ---" -ForegroundColor Cyan

$svc = [CouponService]::new()
$passed = 0
$failed = 0

function Run-Test([string]$name, [scriptblock]$action) {
    try {
        & $action
        Write-Host "  [PASS]: $name" -ForegroundColor Green
        $script:passed++
    } catch {
        Write-Host "  [FAIL]: $name -> $_" -ForegroundColor Red
        $script:failed++
    }
}

# Test 1: Boş veya geçersiz kod (400)
Run-Test "Gecersiz kupon kodu 400 Bad Request donmeli" {
    $res = $svc.ApplyCoupon("GECERSIZ_KOD", 300.0, "user_1", "client_1")
    if ($res.Status -ne 400) { throw "Status expected 400, got $($res.Status)" }
    if ($res.Success -ne $false) { throw "Success expected false" }
}

# Test 2: Sepet alt limit kontrolü (Min 200 TL)
Run-Test "Sepet 200 TL altindayken VETERAN20 kuponu 400 vermeli" {
    $res = $svc.ApplyCoupon("VETERAN20", 150.0, "user_2", "client_2")
    if ($res.Status -ne 400) { throw "Status expected 400, got $($res.Status)" }
    if (-not $res.Error.Contains("minimum sepet tutari")) { throw "Unexpected error: $($res.Error)" }
}

# Test 3: Standart %20 indirim (300 TL -> 60 TL indirim, 240 TL kalmali)
Run-Test "300 TL sepete VETERAN20 ile 60 TL indirim uygulanmali" {
    $res = $svc.ApplyCoupon("VETERAN20", 300.0, "user_3", "client_3")
    if ($res.Status -ne 200) { throw "Status expected 200, got $($res.Status)" }
    if ($res.Data.DiscountAmount -ne 60.0) { throw "Discount expected 60, got $($res.Data.DiscountAmount)" }
    if ($res.Data.FinalTotal -ne 240.0) { throw "Final expected 240, got $($res.Data.FinalTotal)" }
}

# Test 4: Tavan sınırı (800 TL sepete %20 = 160 TL yerine tavan 100 TL uygulanmali)
Run-Test "800 TL sepette 100 TL tavan indirim siniri calismali" {
    $res = $svc.ApplyCoupon("VETERAN20", 800.0, "user_4", "client_4")
    if ($res.Status -ne 200) { throw "Status expected 200, got $($res.Status)" }
    if ($res.Data.DiscountAmount -ne 100.0) { throw "Discount expected 100 ceiling, got $($res.Data.DiscountAmount)" }
    if ($res.Data.FinalTotal -ne 700.0) { throw "Final expected 700, got $($res.Data.FinalTotal)" }
}

# Test 5: Tek kullanımlık kuralı (İkinci kez harcama 409 dönmeli)
Run-Test "Ayni kullanici ayni kuponu ikinci kez kullanamamali (409 Conflict)" {
    $first = $svc.ApplyCoupon("VETERAN20", 250.0, "single_use_user", "client_5a")
    if ($first.Status -ne 200) { throw "First application failed" }

    $second = $svc.ApplyCoupon("VETERAN20", 250.0, "single_use_user", "client_5b")
    if ($second.Status -ne 409) { throw "Status expected 409 Conflict, got $($second.Status)" }
    if ($second.Success -ne $false) { throw "Success expected false" }
}

Write-Host "Test Ozeti: $passed Basarili, $failed Hatali." -ForegroundColor Cyan
if ($failed -gt 0) {
    exit 1
} else {
    Write-Host "TUM BIRIM TESTLERI YESIL!" -ForegroundColor Green
    exit 0
}
