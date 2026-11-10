# CANLI ŞANTİYE DEFTERİ (DURUM.md)
*Bu dosya görevin canlı durumunu, kabul kriterlerini ve test kanıtlarını takip eden yaşayan belgedir.*

**Görev Adı:** 18. Eleman: KOTA DÜRTÜCÜSÜ (Heartbeat Sentinel) Otonom Arka Plan Entegrasyonu  
**Tarih / Saat:** 2026-11-10 21:30:00  
**Çalışma Vitesi:** 🏛️ Vigiles Engine Protocol (20 Elemanlı Fabrika)  
**Git & Dağıtım Modu:** TAM MANUEL KONTROL (Sıfır Otomatik Git / Kullanıcı Kontrollü /push)  

---

## 🎯 1. Görev Özeti ve Vizyon
*Şirket Sahibinin (Sizin) verdiği vizyon ve temel beklenti:*
> "Bu dürtme mekanizmasını Bilgisayarım Açıkken, Ben Hiçbir Şey Yapmasam Bile Kendi Kendine Dürtmesi şeklinde tamamlayalım."

---

## 📐 2. Baş Mimar Kabul Kriterleri
| # | Kabul Kriteri | Beklenen Çıktı / Davranış | Doğrulama Yöntemi | Durum |
| :-: | :--- | :--- | :--- | :-: |
| 1 | Otonom Arka Plan Betiği | `heartbeat_sentinel.ps1` oluşturulması; minimum kaynakla (1-token mikro-ping) Antigravity motoruna uyanma sinyali göndermesi. | PowerShell betik doğrulama & kuru koşum (dry-run) | ⏳ BEKLİYOR |
| 2 | Sıfır Müdahale (Zero-Touch Daemon) | Bilgisayar açık olduğu sürece kullanıcının hiçbir işlem yapmasına gerek kalmadan belirlenen periyotta otomatik tetiklenmesi. | Windows Görev Zamanlayıcısı / Arka Plan Servis Kaydı | ⏳ BEKLİYOR |
| 3 | Canlı Günlükleme (Audit Trail) | Her dürtmenin zaman damgası, model yanıtı ve durumu `heartbeat.log` dosyasına temizce işlenmesi. | Log formatı ve dosya yazım testi | ⏳ BEKLİYOR |
| 4 | Anti-Bloat & Güvenlik | Sıfır harici bağımlılık, sıfır API anahtarı sızıntısı; yalnızca mevcut yerel Antigravity istemci kimliği (`agy` / `agentapi`) ile çalışması. | `sentinel_guard.ps1` Anti-Bloat & Zero-Leak Taraması | ⏳ BEKLİYOR |
| 5 | TDD Birim & Stres Doğrulaması | `Test-Heartbeat.ps1` ile servisin başlatma, durdurma, loglama ve ping döngülerinin doğrulanması. | Pester / PowerShell TDD Test Koşumu | ⏳ BEKLİYOR |
| 6 | Canlı Operasyon Merkezi Senkronizasyonu | Kalp atışlarının Canlı Operasyon Merkezi'nde (Port 9999) `18. KOTA DÜRTÜCÜSÜ` üzerinde anlık telemetri olarak parlaması. | SSE Telemetri Olay Testi | ⏳ BEKLİYOR |
| 7 | Şirket Anayasası Kaydı | Sistemin çalışma mantığının `KURALLAR.md`'ye kalıcı kural olarak eklenmesi. | `KURALLAR.md` Hafıza Uzmanı Kaydı | ⏳ BEKLİYOR |

---

## 🚧 3. Şantiye İlerleme Çizelgesi
- [x] **Aşama 1: Baş Mimar Analizi & Mimari Planlama** (Gereksinimler netleştirildi, kabul kriterleri belirlendi)
- [ ] **Aşama 2: Karar Süzgeci** (Şirket Sahibine dürtme sıklığı onaylatılacak)
- [ ] **Aşama 3: TDD Test Paketi (`Test-Heartbeat.ps1`)** (Özel Tester kırmızı testi yazacak)
- [ ] **Aşama 4: İşçi Uygulaması (`heartbeat_sentinel.ps1`)** (Hafif ve kurşungeçirmez kalp atışı betiği kodlanacak)
- [ ] **Aşama 5: Otonom Arka Plan Kurulumu** (Windows Görev Zamanlayıcısı / Kesintisiz Daemon entegrasyonu)
- [ ] **Aşama 6: Kaos & Stres Testi** (Ağ kopması, eşzamanlı çalışma ve işlem kilitlenmesi simülasyonu)
- [ ] **Aşama 7: Bağımsız Yargıç Onayı** (Tüm testlerin yeşile döndüğünün mühürlenmesi)
- [ ] **Aşama 8: Hafıza Uzmanı & Teslimat** (Kurallar güncellenecek, `/push` için kullanıcıya devredilecek)

---

## ❌ 4. Açık Kusurlar ve Düzeltme Kayıtları (Red Döngüsü)
*Henüz açık kusur yok.*

---

## 📸 5. Doğrulama ve Kanıt Dosyaları
* **Baş Mimar Planı:** [DURUM.md](file:///c:/Users/Dogukan/Desktop/Antigravity%20Improvement/DURUM.md)
* **Kalıcı Kurallar:** [KURALLAR.md](file:///c:/Users/Dogukan/Desktop/Antigravity%20Improvement/KURALLAR.md)
