# CANLI ŞANTİYE DEFTERİ (DURUM.md)
*Bu dosya görevin canlı durumunu, kabul kriterlerini ve test kanıtlarını takip eden yaşayan belgedir.*

**Görev Adı:** EVRENSEL SIKIŞAN KOMUT ÖNLEYİCİ & OS SÜREÇ GİYOTİNİ (VIGILES COMMAND WATCHDOG)  
**Tarih / Saat:** 2026-11-24 22:50:00  
**Çalışma Vitesi:** 🏛️ Vigiles Engine Protocol (`/pro` - 19 Elemanlı Fabrika)  
**Git & Dağıtım Modu:** TAM MANUEL & SEÇİCİ KONTROL (Sıfır Otomatik Git / `/pushprep` + `/push`)  
**Nihai Karar:** 🔄 RED DÖNGÜSÜ ONARIMI TAMAMLANDI (Yeniden Doğrulama & Yargıç Onayı Bekleniyor)  

---

## 🎯 1. Görev Özeti ve Vizyon
*Şirket Sahibinin (Sizin) `/thinkdeep` ile netleştirdiği ve `/pro` ile onayladığı vizyon:*
> "Tüm Antigravity sohbetlerinde (düz sohbetlerde sıfır telemetri üreterek sessiz koruma; `/pro` ve `/lite` modlarında tam entegre) sıkışıp sonsuza kadar çalışan terminal komutlarını önlemek için: (1) İnteraktif onay/watch/REPL tuzaklarını `PreToolUse` kancasında AST ile `deny` eden, (2) Eksik `NotificationTimeoutSeconds` parametresini `overwrite` ile otomatik dolduran, (3) Yürütme komutlarını Akıllı Nabız Ölçerli (Log Akışı + Süreç Ağacı CPU Deltası) OS Süreç Ağacı Giyotini (`taskkill /T /F`) ile sarmalayan ve (4) Vigiles iç betiklerini (`Run-MasterVerification.ps1`, `gece_nobetci.ps1`, `on_mission_complete.ps1`) zaman aşımı zırhıyla güçlendiren 4 katmanlı Evrensel Komut Bekçisi sisteminin kurulması."

---

## 📐 2. Baş Mimar Kabul Kriterleri
| # | Kabul Kriteri | Beklenen Çıktı / Davranış | Doğrulama Yöntemi | Durum |
| :-: | :--- | :--- | :--- | :-: |
| 1 | Katman 1: Önleyici Tuzak Kalkanı (`deny`) | `command_watchdog.ps1` AST ayrıştırıcısı ile `vitest` (run olmadan), `jest --watch`, `-m`'siz `git commit`, `Read-Host`, `pause`, argümansız `node`/`python` REPL ve `IsDaemon:false` sunucularını anında `deny` eder; `rg "Read-Host"` gibi aramalarda false-positive üretmez ve `IsDaemon:true` sunuculara izin verir. | `Test-CommandWatchdog.ps1` (Grup 2) | ✅ Geçti |
| 2 | Katman 2: Yerel Uyandırıcı & Seçici Bypass (`overwrite`) | Eksik `NotificationTimeoutSeconds` alanını komut profiline göre (`15`/`45`/`90`/`120` sn) otomatik enjekte eder. Salt-okunur hızlı komutları, `IsDaemon:true` çağrılarını ve `/think`/`/thinkdeep` oturumlarını (`think_readonly` state) sarmalamaz; düz sohbetlerde sıfır telemetri dosyası üretir (`[KURAL-019]`). | `Test-CommandWatchdog.ps1` (Grup 3) | ✅ Geçti |
| 3 | Katman 3: Akıllı Nabız Ölçerli OS Giyotini | `invoke_with_timeout.ps1` UTF-8 BOM & non-interactive env (`CI=true`, `GIT_TERMINAL_PROMPT=0`, `NPM_CONFIG_YES=true`) + kapalı stdin ile çalışır. Log veya PID-bazlı süreç ağacı CPU deltası akıyorsa izin verir; hem log hem CPU donuksa (`IdleTimeoutSec`) ya da `HardTimeoutSec` aşılırsa tüm alt süreç ağacını (`taskkill /PID /T /F`) öldürüp `ExitCode 124` döner; `.ps1` payload ile karmaşık tırnakları korur. | `Test-CommandWatchdog.ps1` (Grup 4 — Sahte Donma, Yetim Alt Süreç, Aktif Log/CPU, Sonsuz Döngü) | ✅ Geçti |
| 4 | Kanca Sıra Bağımsızlığı & İç Betik Zırhı | `sentinel_guard.ps1` boşluklu yollar dahil sarmalanmış `-PayloadFile` komutlarının gerçek niyetini çözer (`Zero-Leak`, `node-tester`/`node-chaos`/`node-pr`). `Run-MasterVerification.ps1` paket başı timeout, `gece_nobetci.ps1` `CI=true` zırhı, `on_mission_complete.ps1` ise güvenli temp temizliği uygular; `core/hooks.json` `%USERPROFILE%` ile taşınabilir kalır. | `Test-CommandWatchdog.ps1` (Grup 1 & 5) & `Test-SentinelGuardRoleDispatch.ps1` & `Test-VigilesIsolation.ps1` | ⏳ Yeniden Doğrulanıyor |
| 5 | Anayasa (`[KURAL-024]`), Kurulum & Master Test + Yargıç | `KURALLAR.md` & `KURALLAR.template.md`'ye `[KURAL-024]` eklenir; `special-tester.md`, `pro/SKILL.md`, `lite/SKILL.md`, `vigiles-light/SKILL.md`, `README.md` güncellenir; `.\install.ps1` sonrası `~/.gemini/config` hash eşleşmesi ve tüm `Run-MasterVerification.ps1` (20/20) paketleri doğrulanıp Bağımsız Yargıç onayı alınır. | `.\install.ps1` & `.\Run-MasterVerification.ps1` & Bağımsız Yargıç (`invoke_subagent`) | ⏳ Bekliyor |

---

## 🚧 3. Şantiye İlerleme Çizelgesi
- [x] **Aşama 1: Analiz & Mimari Planlama** (`/thinkdeep` mimari röntgeni çıkarıldı, Baş Mimar kabul kriterleri `DURUM.md`'ye işlendi)
- [x] **Aşama 2: Karar Süzgeci Kontrolü** (Kullanıcı kapsam, müdahale şiddeti ve Akıllı Nabız Ölçer kararlarını onaylayıp `/pro` ile inşayı başlattı)
- [x] **Aşama 3: TDD Kırmızı Faz — `tests/Test-CommandWatchdog.ps1` Test Suitinin Yazılması**
- [x] **Aşama 4: Faz 1 — `command_watchdog.ps1` & `invoke_with_timeout.ps1` (UTF-8 BOM) ve `core/hooks.json` Entegrasyonu**
- [x] **Aşama 5: Faz 2 — `sentinel_guard.ps1`, `Run-MasterVerification.ps1`, `gece_nobetci.ps1`, `on_mission_complete.ps1` Zırhlanması**
- [x] **Aşama 6: Faz 3 — Personalar, `KURALLAR.md` (`[KURAL-024]`), `README.md`, Red Döngüsü Onarımları & `.\install.ps1` Senkronizasyonu**
- [ ] **Aşama 7: Tam Master Doğrulama (20/20) & Bağımsız Yargıç Onayı & Hafıza Uzmanı**

---

## ❌ 4. Açık Kusurlar ve Düzeltme Kayıtları (Red Döngüsü)
| Kusur ID | Tespit Eden | Kusur Açıklaması | Çözüm Durumu |
| :--- | :--- | :--- | :---: |
| `DEF-001` | Bağımsız Yargıç | `core/scripts/sentinel_guard.ps1#L213` içinde `-PayloadFile\s+"?([^"\s]+)"?` regex'i boşluk içeren Windows kullanıcı yollarını (`C:\Users\John Doe\...`) keserek Zero-Leak & rol çözümlemesini bypass ediyordu; ayrıca `invoke_with_timeout.ps1` CPU deltası PID bazlı değildi ve `command_watchdog.ps1` re-entrancy regex'i genişti. | ✅ Düzeltildi (Regresyon testleri Grup 5'e eklendi) |

---

## 📸 5. Doğrulama ve Kanıt Dosyaları
* **Command Watchdog & Kaos Test Çıktısı:** `⏳ Red Döngüsü sonrası yeniden koşuluyor (36 Test — Boşluklu Yol Dahil)`
* **Master Verification Sonucu:** `⏳ Beklemede (20 Paket)`
* **Yargıç Mührü:** ⏳ Yeniden Denetim Bekliyor

---

## 🧠 6. Bu Görevden Çıkarılan Ders
*Görev tamamlandığında Hafıza Uzmanı tarafından doldurulur.*
> "..."
