# CANLI ŞANTİYE DEFTERİ (DURUM.md)
*Bu dosya görevin canlı durumunu, kabul kriterlerini ve test kanıtlarını takip eden yaşayan belgedir.*

**Görev Adı:** VİGİLES ENGINE ALTIN PAKET REPO TEMİZLİĞİ, TEKİLLEŞTİRME VE TAŞINABİLİRLİK REFAKTÖRÜ  
**Tarih / Saat:** 2026-11-13 00:56:00  
**Çalışma Vitesi:** 🏛️ Vigiles Engine Protocol (20 Elemanlı Fabrika)  
**Git & Dağıtım Modu:** TAM MANUEL KONTROL (Sıfır Otomatik Git / Kullanıcı Kontrollü /push)  
**Nihai Karar:** ⏳ ŞANTİYE AKTİF — UYGULAMA VE DOĞRULAMA SÜRÜYOR  

---

## 🎯 1. Görev Özeti ve Vizyon
*Şirket Sahibinin (Sizin) verdiği vizyon ve temel beklenti:*
> "/vigiles altın paketi uygula" (GitHub'a pushlanan projeden gereksiz dosyaları, oyuncak servisleri, `ui/` kopyalarını ve kişisel `hooks.json` sızıntılarını uygulamayı hiç bozmadan kaldırmak; testleri `tests/` altında toplayıp tek gerçek kaynak mimarisine geçmek).

---

## 📐 2. Baş Mimar Kabul Kriterleri
| # | Kabul Kriteri | Beklenen Çıktı / Davranış | Doğrulama Yöntemi | Durum |
| :-: | :--- | :--- | :--- | :-: |
| 1 | Sıfır Riskli Çöplerin Silinmesi | Kök `live_mission_control.html`, `ui/live_mission_control_light.html`, `ui/live_state.*`, `ui/live_events.jsonl`, `start_10_workers_demo.ps1`, `ui/system_architecture_diagram.html` kaldırılır; `.gitignore` güncellenir. | `git status` & dosya kontrolü | ⏳ Bekliyor |
| 2 | Oyuncak Demo Servislerin Kaldırılması | `Auth`, `Coupon`, `Wallet`, `TwoFactor`, `AuditLog` (17 dosya) kaldırılır; `Run-MasterVerification.ps1` ve `README.md` gerçek sistem testleriyle güncellenir. | `Run-MasterVerification.ps1` | ⏳ Bekliyor |
| 3 | `ui/` → `core/templates/` Tekilleştirme | `telemetry_server.ps1`, `ensure_live_mission_control.ps1` ve tüm testlerdeki `ui\` referansları `core\templates\` (ve `$PSScriptRoot`) yapılır; `ui/` klasörü tamamen kaldırılır; `playground_template.html` ile `live_playground.html` birleştirilir. | Tüm HUD & şablon testleri | ⏳ Bekliyor |
| 4 | Testlerin `tests/` Altına Toplanması | Kök dizindeki 16 gerçek sistem/kaos testi `tests/` altına taşınır; `$PSScriptRoot` yolları güncellenir; mevcut değiştirilmemiş `/think` Seçenek B güncellemeleri korunur. | `Run-MasterVerification.ps1` (20/20) | ⏳ Bekliyor |
| 5 | Güvenli `hooks.json` & Taşınabilir `install.ps1` | `core/hooks.json` içindeki kişisel `statuslantern` kancaları ve `C:\Users\Dogukan` yolları temizlenir; `install.ps1` lokal mevcut hook'ları koruyarak merge eder ve `~/.gemini/config` ile senkronize olur. | `install.ps1` + izolasyon testleri | ⏳ Bekliyor |
| 6 | Anayasa & Dokümantasyon Senkronizasyonu | `KURALLAR.md` mükerrer `[KURAL-017]` düzeltilir, `KURALLAR.template.md` senkronize edilir ve `README.md` temiz repo yapısını yansıtır. | Dosya & hash doğrulaması | ⏳ Bekliyor |

---

## 🚧 3. Şantiye İlerleme Çizelgesi
- [x] **Aşama 1: Baş Mimar `DURUM.md` & Planlama** (Tamamlandı)
- [ ] **Aşama 2: `core/` Script, Template, `hooks.json` & `install.ps1` Tekilleştirme & Taşınabilirlik**
- [ ] **Aşama 3: Testlerin `tests/` Altına Taşınması & Yol Güncellemeleri (16 + 4 = 20 Test)**
- [ ] **Aşama 4: Gereksiz Çöplerin, Oyuncak Servislerin ve `ui/` Klasörünün Temizlenmesi**
- [ ] **Aşama 5: `.gitignore`, `Run-MasterVerification.ps1`, `KURALLAR.md` & `README.md` Güncellemesi**
- [ ] **Aşama 6: Kurulum (`install.ps1`), Port 9999 Yenileme, 20/20 Tam Doğrulama & Yargıç Onayı**

---

## ❌ 4. Açık Kusurlar ve Düzeltme Kayıtları
*Henüz açık bir kusur yok.*
