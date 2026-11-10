# Karar Süzgeci Matrisi (Decision Gatekeeper Protocol)

Bu protokol, ne zaman kullanıcıya `ask_question` aracıyla soru sorulacağını, ne zaman otonom karar alınacağını belirler.

---

## 🛑 TEK YÖNLÜ KAPILAR (Type 1 Doors - Geri Dönülemez / Kritik)
Aşağıdaki durumlarda **ASLA TAHMİN YÜRÜTÜLEMEZ**. Anında `ask_question` pop-up'ı açılarak Şirket Sahibine (Kullanıcıya) seçenekler sunulmalıdır:

1. **Veri Modeli & Şema Kararları:** Veritabanı tablosu silme, birincil anahtar türü değiştirme, geri dönüşü zor veri tabanı ilişkileri.
2. **Kimlik Doğrulama & Güvenlik:** Parola hash algoritması (Argon2 vs Bcrypt), token süresi, oturum modeli (JWT vs Session cookie).
3. **Harici Servis & Sağlayıcı Seçimi:** Stripe vs LemonSqueezy, AWS S3 vs Cloudflare R2, Postmark vs Resend.
4. **Yıkıcı İşlemler:** Var olan production kodunu silme, legacy bir modülü çöpe atma.

### Pop-Up Format Standardı:
* Kullanıcıya asla açık uçlu ("Ne yapalım?") soru sorulamaz.
* Mutlaka `(Tavsiye Edilen)` seçeneği ilk sırada yer almalıdır.
* Seçenekler kısa ve teknik gerekçesiyle sunulmalıdır.

---

## 🟢 İKİ YÖNLÜ KAPILAR (Type 2 Doors - Geri Dönülebilir / Önemsiz)
Aşağıdaki durumlarda **KULLANICI ASLA RAHATSIZ EDİLEMEZ**. Karar Süzgeci en iyi sektör standardını otonom olarak seçer ve `DURUM.md`'ye not düşer:

1. **Stil ve Tasarım:** Buton hover rengi, padding aralığı, gölge yoğunluğu.
2. **Kod İçi Refactoring:** Fonksiyon isimlendirmeleri, dosya içi yardımcı fonksiyon bölmeleri.
3. **Kütüphane İçi Detaylar:** Hafif yardımcı paket seçimi (örn: clsx vs cn).
4. **Test Senaryoları:** Hangi sınır değerin önce test edileceği.
