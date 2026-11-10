const assert = require('assert');
const { AuthService } = require('./auth_service');

console.log("🧪 [TDD BİRİM TESTLERİ BAŞLATILIYOR]...");

const auth = new AuthService();
let passed = 0;
let failed = 0;

function runTest(name, fn) {
  try {
    fn();
    console.log(`  ✅ [PASS]: ${name}`);
    passed++;
  } catch (err) {
    console.error(`  ❌ [FAIL]: ${name} -> ${err.message}`);
    failed++;
  }
}

// Test 1: Boş parola kontrolü (400)
runTest("Boş parola gönderildiğinde 400 Bad Request dönmeli", () => {
  const res = auth.register({ username: "dogukan", password: "" });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(res.success, false);
  assert.strictEqual(res.error, "Parola boş bırakılamaz.");
});

// Test 2: Kısa parola kontrolü (<8 karakter, 400)
runTest("8 karakterden kısa parolada 400 dönmeli", () => {
  const res = auth.register({ username: "dogukan", password: "123" });
  assert.strictEqual(res.status, 400);
  assert.strictEqual(res.success, false);
  assert.strictEqual(res.error, "Parola en az 8 karakter olmalıdır.");
});

// Test 3: Geçerli parola ile başarılı kayıt (201)
runTest("Geçerli parola ile kullanıcı başarıyla kaydedilmeli (201)", () => {
  const res = auth.register({ username: "dogukan_veteran", password: "SuperSecurePass123!" });
  assert.strictEqual(res.status, 201);
  assert.strictEqual(res.success, true);
  assert.strictEqual(res.user.algorithm, "bcrypt-compat-sha512");
});

// Test 4: Doğrulama (Login) testi
runTest("Kayıt edilen kullanıcının parolası doğru doğrulanmalı", () => {
  const isValid = auth.verify({ username: "dogukan_veteran", password: "SuperSecurePass123!" });
  assert.strictEqual(isValid, true);

  const isInvalid = auth.verify({ username: "dogukan_veteran", password: "WrongPassword!" });
  assert.strictEqual(isInvalid, false);
});

console.log(`\n📊 Test Özeti: ${passed} Başarılı, ${failed} Hatalı.`);
if (failed > 0) {
  process.exit(1);
} else {
  console.log("🎉 TÜM BİRİM TESTLERİ YEŞİL!\n");
}
