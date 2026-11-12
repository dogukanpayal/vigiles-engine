# CANLI ŞANTİYE DEFTERİ (DURUM.md)
*Bu dosya görevin canlı durumunu, kabul kriterlerini ve test kanıtlarını takip eden yaşayan belgedir.*

**Görev Adı:** VİGİLES ENGINE ALTIN PAKET REPO TEMİZLİĞİ, TEKİLLEŞTİRME VE TAŞINABİLİRLİK REFAKTÖRÜ  
**Tarih / Saat:** 2026-11-13 01:28:00  
**Çalışma Vitesi:** 🏛️ Vigiles Engine Protocol (20 Elemanlı Fabrika)  
**Git & Dağıtım Modu:** TAM MANUEL KONTROL (Sıfır Otomatik Git / Kullanıcı Kontrollü `/push`)  
**Nihai Karar:** ✅ GÖREV EKSİKSİZ TAMAMLANDI VE MÜHÜRLENDİ (Yargıç Onayı: 20/20 Test & Kaos Paketi Geçti)  

---

## 🎯 1. Görev Özeti ve Vizyon
*Şirket Sahibinin (Sizin) verdiği vizyon ve temel beklenti:*
> "/vigiles altın paketi uygula" (GitHub'a pushlanan projeden gereksiz dosyaları, oyuncak servisleri, `ui/` kopyalarını ve kişisel `hooks.json` sızıntılarını uygulamayı hiç bozmadan kaldırmak; testleri `tests/` altında toplayıp tek gerçek kaynak mimarisine geçmek).

---

## 📐 2. Baş Mimar Kabul Kriterleri
| # | Kabul Kriteri | Beklenen Çıktı / Davranış | Doğrulama Yöntemi | Durum |
| :-: | :--- | :--- | :--- | :-: |
| 1 | Sıfır Riskli Çöplerin Silinmesi | Kök `live_mission_control.html`, `ui/live_mission_control_light.html`, `ui/live_state.*`, `ui/live_events.jsonl`, `start_10_workers_demo.ps1`, `ui/system_architecture_diagram.html` kaldırılır; `.gitignore` güncellenir. | `git status` & `.gitignore` doğrulaması | ✅ Tamamlandı |
| 2 | Oyuncak Demo Servislerin Kaldırılması | `Auth`, `Coupon`, `Wallet`, `TwoFactor`, `AuditLog` (17 dosya) kaldırılır; `Run-MasterVerification.ps1` ve `README.md` gerçek sistem testleriyle güncellenir. | `Run-MasterVerification.ps1` (20/20) | ✅ Tamamlandı |
| 3 | `ui/` → `core/templates/` Tekilleştirme | `telemetry_server.ps1`, `ensure_live_mission_control.ps1` ve tüm testlerdeki `ui\` referansları `core\templates\` (ve `$PSScriptRoot`) yapılır; `ui/` klasörü kaldırılır; `playground_template.html` ile `live_playground.html` birleştirilir. | HTTP `localhost:9999/` (200) & `/playground` (200) & HUD testleri | ✅ Tamamlandı |
| 4 | Testlerin `tests/` Altına Toplanması | Kök dizindeki 16 gerçek sistem/kaos testi `tests/` altına taşınır (toplam 20 paket); `$PSScriptRoot` yolları güncellenir; `Test-AntigravityDbTitles.ps1` canlı SQLite DB'ye göre taşınabilir hale getirilir; `/think` Seçenek B güncellemeleri korunur. | `Run-MasterVerification.ps1` (20 / 20 Geçti) | ✅ Tamamlandı |
| 5 | Güvenli `hooks.json` & Taşınabilir `install.ps1` | `core/hooks.json` içindeki kişisel `statuslantern` kancaları ve `C:\Users\Dogukan` yolları temizlenir; `install.ps1` lokal kullanıcı kancalarını (`statuslantern`, `statuslantern_personal`) koruyarak merge eder ve `~/.gemini/config` ile senkronize olur. | `install.ps1` & `~/.gemini/config/hooks.json` JSON/BOM doğrulaması | ✅ Tamamlandı |
| 6 | Anayasa & Dokümantasyon Senkronizasyonu | `KURALLAR.md` mükerrer `[KURAL-017]` düzeltilir (`[KURAL-017]`..`[KURAL-021]`), `core/templates/KURALLAR.template.md` senkronize edilir ve `README.md` temiz 20 testli repo yapısını yansıtır. | Dosya & tutarlılık taraması | ✅ Tamamlandı |

---

## 🚧 3. Şantiye İlerleme Çizelgesi
- [x] **Aşama 1: Baş Mimar `DURUM.md` & Planlama** (Tamamlandı)
- [x] **Aşama 2: `core/` Script, Template, `hooks.json` & `install.ps1` Tekilleştirme & Taşınabilirlik** (Tamamlandı)
- [x] **Aşama 3: Testlerin `tests/` Altına Taşınması & Yol Güncellemeleri (16 + 4 = 20 Test)** (Tamamlandı)
- [x] **Aşama 4: Gereksiz Çöplerin, Oyuncak Servislerin ve `ui/` Klasörünün Temizlenmesi** (Tamamlandı)
- [x] **Aşama 5: `.gitignore`, `Run-MasterVerification.ps1`, `KURALLAR.md`, `KURALLAR.template.md` & `README.md` Güncellemesi** (Tamamlandı)
- [x] **Aşama 6: Kurulum (`install.ps1`), Port 9999 Yenileme, 20/20 Tam Doğrulama & Yargıç Onayı** (Tamamlandı)

---

## ❌ 4. Açık Kusurlar ve Düzeltme Kayıtları
*Açık kusur yok. Uygulama sırasında tespit edilip çözülen bulgu:*
- `tests\Test-AntigravityDbTitles.ps1` içerisindeki sabitlenmiş eski/silinmiş kişisel sohbet başlıkları ve UUID kontrolleri, yerel `conversation_summaries.db` ile dinamik karşılaştırma yapacak şekilde taşınabilir hale getirildi; PowerShell 5.1 `ConvertFrom-Json` dizi sarmalama hatası düzeltildi ve tüm 6 alt test (`Test 1..6`, 0 hata, ortalama 14.56 ms/istek) geçirildi.

---

## 🏆 5. Yargıç (Judge) Nihai Mührü ve Kanıt Özeti
- **Ana Doğrulama Koşumu:** `.\Run-MasterVerification.ps1` → **20 / 20 Geçti, 0 Başarısız** (`Test-VigilesConsiliumIntegrity.ps1` 21/21 ve `Test-ConsiliumScenarioSimulation.ps1` Seçenek B dahil).
- **Canlı Telemetri Sunucusu:** `http://localhost:9999/` (`200 OK`, `92801` bayt) ve `http://localhost:9999/playground` (`200 OK`, `5181` bayt), `/status` = `running`.
- **Kodlama ve Git Güvenliği:** Tüm `.ps1` betikleri UTF-8 BOM ile doğrulandı; `~/.gemini/config/hooks.json` UTF-8 (BOM'suz) olarak mevcut 4 kancayla (`statuslantern`, `statuslantern_personal`, `sentinel-guard`, `live-mission-control`) doğrulandı. Hiçbir otomatik `git add / commit / push` komutu çalıştırılmadı.
