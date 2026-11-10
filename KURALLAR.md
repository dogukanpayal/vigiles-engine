# ŞİRKET ANAYASASI VE KALICI MÜHENDİSLİK KURALLARI (KURALLAR.md)
*Bu dosya projenin kurumsal hafızasıdır. Tüm alt ajanlar ve geliştiriciler çalışmaya başlamadan önce bu kuralları okumak ve harfiyen uymakla yükümlüdür.*

---

## 🏛️ 1. Temel Mühendislik İlkeleri
1. **Never Code Blindly (Kör Kodlama Yasağı):** Mimari plan çizilmeden, veri yapıları ve kabul kriterleri belirlenmeden doğrudan kod yazılamaz.
2. **Single Responsibility (Tek Sorumluluk):** Her ajan yalnızca kendi uzmanlık alanında çalışır. Mimar kod yazmaz, İşçi onay vermez, Yargıç kod üretmez.
3. **Closed-Loop TDD (Kapalı Döngü Test):** Kodu yazan İşçi, birim testlerini (unit/integration) yazmak ve yeşile çevirmekle yükümlüdür. Kullanıcıdan test yapması istenemez.
4. **Temiz İletişim (No-Noise Chat):** Ana sohbet ekranına devasa terminal logları, ham diff'ler veya ajanların iç tartışmaları basılamaz. Sonuç odaklı, net ve Türkçe iletişim esastır.

---

## 🛡️ 2. Güvenlik ve Gizlilik (Sıfır Sızıntı / Zero-Leak)
1. **Hassas Veri Yasağı:** `.env` dosyaları, veritabanı parolaları, Stripe/AWS/OpenAI API anahtarları veya JWT secret'ları ASLA doğrudan kodun içine gömülemez.
2. **Çevre Değişkeni Zorunluluğu:** Tüm gizli anahtarlar `process.env` veya ortam değişkenleri üzerinden okunmalı ve `.env.example` dosyasında dokümante edilmelidir.
3. **Sızıntı Taraması:** Gizli Veri Muhafızı uyarısı alan hiçbir kod commit edilemez veya Yargıç tarafından onaylanamaz.

---

## ⚡ 3. Performans ve Paket Yönetimi (Anti-Bloat)
1. **Şişkin Kütüphane Yasağı:** Basit işlemler için devasa (15MB+) harici paketler (örn: basit tarih için Moment.js, tek bir fonksiyon için tüm Lodash) projeye dahil edilemez.
2. **Yerel Alternatifler:** Mümkün olan her yerde yerel JavaScript/TypeScript API'leri ve hafif, ağaç-sallamalı (tree-shakeable) alternatifler tercih edilmelidir.
3. **Sorgu Verimliliği:** Veritabanı ve API çağrılarında N+1 sorgu kalıpları, gereksiz re-render'lar ve kapatılmamış stream/listener sızıntıları engellenmelidir.

---

## 🧪 4. Doğrulama ve Çift Kanatlı Test Standartları
1. **Görsel Kanıt Zorunluluğu:** Özel Tester, uygulamayı canlı ayağa kaldırıp kullanıcı akışını E2E olarak çalıştırmalı ve gerçek `.png` ekran görüntüsü üretmelidir.
2. **Kaos ve Stres Zorunluluğu:** Kaos Mühendisi butonları seri spamlamalı (minimum 300ms debounce kontrolü), sınır değerleri (10.000 karakter, boş payload) denemeli ve açık bulursa raporlamalıdır.
3. **Sıfır Güven (Zero-Trust):** Bağımsız Yargıç, hem birim testlerini hem görsel ekran görüntüsünü hem de kaos stres raporunu incelemeden ONAY MÜHRÜ basamaz.

---

## 🚦 5. Karar Süzgeci Matrisi (Ne Zaman Pop-Up Sorulur?)
1. **Tek Yönlü Kapılar (Irreversible):** Veritabanı şeması değişiklikleri, kimlik doğrulama mimarisi seçimi, dış ödeme sağlayıcısı ve geri alınması maliyetli kararlarda ASLA varsayımda bulunulamaz. Anında `ask_question` pop-up'ı açılarak Şirket Sahibine sorulur.
2. **İki Yönlü Kapılar (Reversible):** Değişken isimlendirmeleri, CSS/Tailwind stilleri, dosya içi refactoring gibi geri dönülebilir kararlar otonom olarak çözülür; kullanıcı gereksiz yere rahatsız edilmez.

---

## 🧠 6. Yaşayan Kurumsal Hafıza (Dersler ve Özel Kurallar)
*Bu bölüm Hafıza Uzmanı tarafından görevler tamamlandıkça veya çözülen krizlerden sonra otomatik olarak güncellenir.*

* [KURAL-001]: Tüm kullanıcı form butonlarında çift tıklama ve race condition'ları önlemek için minimum 300ms debounce uygulanmalıdır.
* [KURAL-002]: Dış dünyaya açık tüm API endpoint'lerinde gelen veriler controller/handler sınırında katı şema doğrulaması ile filtrelenmelidir.
* [KURAL-003]: Güvenli parola doğrulamasında salt uzunluğu minimum 16 byte olmalı ve timing-attack saldırılarına karşı sabit zamanlı karşılaştırma (timing-safe equal) zorunludur.
* [KURAL-004]: Kupon ve bakiye harcama gibi finansal işlemlerde tek kullanımlık kontrolü thread-safe kilit (lock/mutex) mekanizmasıyla korunmalı ve çift harcama (race-condition) engellenmelidir.
* [KURAL-005]: Cüzdan (Wallet) bakiyelerinde kesin tavan sınırı (Strict Cap) uygulanmalı; negatif harcama ve bakiye aşımı girişimleri veri tabanı ve iş katmanında eşzamanlı kilit ile engellenmelidir.
* [KURAL-006]: Tek kullanımlık şifre (OTP/2FA) üretiminde güvenli kriptografik rastgele üreteç kullanılmalı; doğrulanan kod anında imha edilmeli ve maksimum 3 hatalı denemeden sonra brute-force koruması devreye girmelidir.
