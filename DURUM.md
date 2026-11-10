# CANLI ŞANTİYE DEFTERİ (DURUM.md)
*Bu dosya görevin canlı durumunu, kabul kriterlerini ve test kanıtlarını takip eden yaşayan belgedir.*

**Görev Adı:** PROJE BAZLI SOHBET AYIKLAMA (WORKSPACE PILLS) & LRU SON KULLANILANA GÖRE SIRALAMA (Model A)  
**Tarih / Saat:** 2026-11-11 01:56:00  
**Çalışma Vitesi:** 🏛️ Vigiles Engine Protocol (20 Elemanlı Fabrika)  
**Git & Dağıtım Modu:** TAM MANUEL KONTROL (Sıfır Otomatik Git / Kullanıcı Kontrollü /push)  
**Nihai Karar:** ✅ GÖREV EKSİKSİZ TAMAMLANDI VE MÜHÜRLENDİ  

---

## 🎯 1. Görev Özeti ve Vizyon
*Şirket Sahibinin (Sizin) verdiği vizyon ve temel beklenti:*
> "/vigiles model A ile ilerliyelim"
> 1. Sıralama: Windows klasör tarihi yerine `transcript.jsonl`'in gerçek son yazılma anı baz alınarak, Antigravity IDE'de olduğu gibi en son aktif olunan / mesaj yazılan sohbetin daima en üstte yer alması (LRU).
> 2. Proje Ayıklama (Model A): Arama kutusunun altında yatay kaydırılabilir modern proje hapları/sekmeleri (`[🌐 Tümü (16)]`, `[🚀 Antigravity (3)]`, `[📱 QRMenuHotel (9)]`, `[🏮 StatusLantern (2)]`, `[🖥️ WispDock (1)]`, `[📊 UsageGauge (1)]`) ile sohbetlerin projelerine göre filtrelenmesi ve varsayılan olarak o an çalışılan projenin otomatik seçili gelmesi.

---

## 📐 2. Baş Mimar Kabul Kriterleri ve Sonuçlar
| # | Kabul Kriteri | Beklenen Çıktı / Davranış | Doğrulama Yöntemi | Durum |
| :-: | :--- | :--- | :--- | :-: |
| 1 | Gerçek LRU Sıralaması | `transcript.jsonl` dosyasının `LastWriteTime` değerine göre azalan sıralama yapılmalı; en son konuşulan sohbet en tepede gelmeli. | `Test-ProjectPillsAndRecency.ps1` (Test 3) | ✅ BAŞARILI |
| 2 | Proje / Workspace Tespiti | Her oturum için `projectName` (`Antigravity Improvement`, `QRMenuHotel`, `StatusLantern`, `WispDock`, `UsageGauge`) tespit edilmeli. | Payload Assertion (Test 1-2) | ✅ BAŞARILI |
| 3 | Proje Hapları (UI Pills) | Menüde arama kutusunun altına tıklanabilir proje filtre hapları eklenmeli. | UI DOM & Event Test (Test 5) | ✅ BAŞARILI |
| 4 | Aktif Proje Otomatik Seçimi | Kullanıcı o an hangi çalışma alanındaysa (`Antigravity Improvement`), o projenin hapı varsayılan aktif gelmeli. | UI State Assertion (Test 4) | ✅ BAŞARILI |
| 5 | Anlık Çift Katmanlı Süzme | Hem seçili proje hapı hem de arama kutusu sorgusu birlikte senkron çalışmalı. | Filter Assertion (Test 5) | ✅ BAŞARILI |
| 6 | Sıfır Regresyon | Mevcut `📌 SABİT` mekanizması, SSE yayını ve test oturumları akordeonu bozulmadan çalışmalı. | `Test-AllChatsDiscovery.ps1` (5/5) | ✅ BAŞARILI |

---

## 🚧 3. Şantiye İlerleme Çizelgesi
- [x] **Aşama 1: Baş Mimar DURUM.md & Planlama** (Tamamlandı)
- [x] **Aşama 2: Backend: LRU Sıralama & Proje Tespiti (`telemetry_server.ps1`)** (Tamamlandı)
- [x] **Aşama 3: Frontend: Proje Hapları (Pills) & Otomatik Aktif Proje Seçimi (`live_mission_control.html`)** (Tamamlandı)
- [x] **Aşama 4: TDD Doğrulama Betiği (`Test-ProjectPillsAndRecency.ps1`)** (6/6 Geçti)
- [x] **Aşama 5: Şablon Senkronizasyonu & Daemon Sunucu Yeniden Başlatma** (Tamamlandı)
- [x] **Aşama 6: Bağımsız Yargıç Onayı ve Şirket Sahibine Teslim** (Tamamlandı)

---

## 🧪 4. Doğrulama ve Test Kanıtları
1. **Model A & LRU Doğrulama:** `tests/Test-ProjectPillsAndRecency.ps1` -> **6/6 Başarılı** (4 ms)
   - Test 1: 16 oturumun tamamında `projectName` mevcut.
   - Test 2: `Antigravity Improvement`, `QRMenuHotel`, `StatusLantern`, `WispDock`, `UsageGauge` projeleri başarıyla ayrıştırıldı.
   - Test 3: Arşiv oturumları `transcript.jsonl`'in gerçek son yazılma anına göre tam azalan (LRU) sırada.
   - Test 4: Aktif oturum (`05b9c7d2`) `Antigravity Improvement` projesiyle eşleşti.
   - Test 5: UI DOM'da `#project-filter-pills`, `selectProjectFilter`, `renderProjectPills` ve `PROJECT_CONFIG` doğrulandı.
   - Test 6: API yanıt süresi 4 ms.
2. **Sohbet Keşfi Regresyon:** `tests/Test-AllChatsDiscovery.ps1` -> **5/5 Başarılı** (4 ms)
   - Test 1: 16 oturum (1 Canlı, 15 Arşiv) eksiksiz döndü.
   - Test 2: Anlamlı başlıklar ve tarihler doğrulandı.
   - Test 3: Salt metin arşiv oturumları güvenli 'ARŞİV' durum nesnesi döndü.
   - Test 4: 15 sn in-memory önbellek hızı (4 ms).
   - Test 5: Arama, Canlı Liste, Arşiv Listesi ve arşiv render fonksiyonu korundu.

---

## ❌ 5. Açık Kusurlar ve Düzeltme Kayıtları
*Açık kusur kalmadı. Sıfır hata.*
