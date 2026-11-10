[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

. "c:\Users\Dogukan\Desktop\Antigravity Improvement\AuthService.ps1"

Write-Host "--- TDD BIRIM TESTLERI BASLATILIYOR ---" -ForegroundColor Cyan

$auth = [AuthService]::new()
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

# Test 1: Boş parola kontrolü (400)
Run-Test "Bos parola gonderildiginde 400 Bad Request donmeli" {
    $res = $auth.Register("dogukan", "", "client_test1")
    if ($res.Status -ne 400) { throw "Status expected 400, got $($res.Status)" }
    if ($res.Success -ne $false) { throw "Success expected false" }
    if ($res.Error -ne "Parola boş bırakılamaz.") { throw "Unexpected error msg: $($res.Error)" }
}

# Test 2: Kısa parola (<8 karakter, 400)
Run-Test "8 karakterden kisa parolada 400 donmeli" {
    $res = $auth.Register("dogukan", "123", "client_test2")
    if ($res.Status -ne 400) { throw "Status expected 400, got $($res.Status)" }
    if ($res.Success -ne $false) { throw "Success expected false" }
    if ($res.Error -ne "Parola en az 8 karakter olmalıdır.") { throw "Unexpected error msg: $($res.Error)" }
}

# Test 3: Geçerli parola ile başarılı kayıt (201)
Run-Test "Gecerli parola ile kullanici basariyla kaydedilmeli (201)" {
    $res = $auth.Register("dogukan_veteran", "SuperSecurePass123!", "client_test3")
    if ($res.Status -ne 201) { throw "Status expected 201, got $($res.Status)" }
    if ($res.Success -ne $true) { throw "Success expected true" }
    if ($res.User.Algorithm -ne "bcrypt-compat-sha512") { throw "Unexpected algo" }
}

# Test 4: Doğrulama (Login) testi
Run-Test "Kayit edilen kullanicinin parolasi dogru dogrulanmali" {
    $valid = $auth.Verify("dogukan_veteran", "SuperSecurePass123!")
    if (-not $valid) { throw "Verification should have succeeded" }

    $invalid = $auth.Verify("dogukan_veteran", "WrongPass999!")
    if ($invalid) { throw "Verification should have failed" }
}

Write-Host "Test Ozeti: $passed Basarili, $failed Hatali." -ForegroundColor Cyan
if ($failed -gt 0) {
    exit 1
} else {
    Write-Host "TUM BIRIM TESTLERI YESIL!" -ForegroundColor Green
    exit 0
}
