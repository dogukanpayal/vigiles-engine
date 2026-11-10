# CANLI ŞANTİYE DEFTERİ (DURUM.md)
*Bu dosya görevin canlı durumunu, kabul kriterlerini ve test kanıtlarını takip eden yaşayan belgedir.*

**Görev Adı:** 22. Eleman: CANLI OPERASYON MERKEZİ — İşçiler (Workers) Kutusuna Bağlı Dinamik ve Sınırsız Alt İşçi Ağacı Mimarisi  
**Tarih / Saat:** 2026-11-10 22:50:00  
**Çalışma Vitesi:** 🏛️ Vigiles Engine Protocol (20 Elemanlı Fabrika)  
**Git & Dağıtım Modu:** TAM MANUEL KONTROL (Sıfır Otomatik Git / Kullanıcı Kontrollü /push)  

---

## 🎯 1. Görev Özeti ve Vizyon
*Şirket Sahibinin (Sizin) verdiği vizyon ve temel beklenti:*
> "Vigilesin içindeki canlı operasyon merkezindeki işçiler kutusunun çalışması sadece bir highlight olarak gözüküyor. Ben bunun şöyle olmasını istiyorum: Mesela işçiler aşamasına geçtik diyelim işimizde ve bu işte aynı anda çalışan 5 tane işçi var canlı operasyon merkezinde. Bunun işçiler kutusunun altında işçiler kutusuna bağlı bir durumda 5 tane küçük kutu olmasını istiyorum. Bu kutu sayısı kaç tane işçi çalışıyorsa o kadar kutu ile temsil edilmeli, sınır olmamalı."

---

## 📐 2. Baş Mimar Kabul Kriterleri
| # | Kabul Kriteri | Beklenen Çıktı / Davranış | Doğrulama Yöntemi | Durum |
| :-: | :--- | :--- | :--- | :-: |
| 1 | Hiyerarşik Ağaç Bağlantısı | 8. İŞÇİLER kutusunun hemen altında, kutudan sarkan dikey bağlantı hattı (stem) ve her alt kutuya uzanan yatay dirseklerle (branch arm) bağlı bir alt ağaç konteyneri bulunmalı. | CSS & DOM yapı denetimi | 🟡 Planlandı |
| 2 | Sınırsız Dinamik Kapasite (No Arbitrary Limit) | Kaç işçi çalışıyorsa (1, 5, 12, 50+) o kadar küçük kutu üretilmeli; kodda hiçbir hardcoded üst limit (`slice`, `max`, `cap`) olmamalı. | TDD Birim Testi | 🟡 Planlandı |
| 3 | Siber-Endüstriyel Küçük Kutu Tasarımı | Her küçük kutuda: İşçi No/Adı (`İşçi #1`), Rolü (`TDD`, `Frontend`, vb.), Anlık Görev Detayı, Canlı Nabız (`animate-pulse`) ve Durum Rozeti (`Aktif 🟢`) yer almalı. | UI Render Testi | 🟡 Planlandı |
| 4 | Ana Kutu Dinamik Sayaç Rozeti | 8. İŞÇİLER kutusu üzerindeki rozet, aktif işçi sayısını dinamik yansıtmalı (örn: `5 İşçi Aktif ⚡`). | State güncelleme testi | 🟡 Planlandı |
| 5 | Telemetri & SSE Senkronizasyonu | `state.workers` dizisi veya `state.workerCount` değeri geldiğinde arayüz gerçek zamanlı ve yumuşak geçişle güncellenmeli. | HTTP /notify & SSE testi | 🟡 Planlandı |
| 6 | İnteraktif Simülatör / Stepper | Canlı arayüz üzerinde işçi sayısını elle artırıp azaltabilen test stepper'ı (`[+]`, `[-]`) bulunmalı; Şirket Sahibi anında deneyimleyebilmeli. | UI Etkileşim Testi | 🟡 Planlandı |
| 7 | Kaos / Stres Dayanıklılığı | 50-100 işçi eşzamanlı fırlatıldığında akıcı iç kaydırma (`overflow-y-auto`) devreye girmeli; sayfa taşması veya kırılma yaşanmamalı. | `Chaos-WorkersSubNodes.ps1` | 🟡 Planlandı |
| 8 | Kurumsal Hafıza Kuralı | `[KURAL-014]` olarak `KURALLAR.md` kütüğüne işlenmesi. | Hafıza Uzmanı Kütük Kaydı | 🟡 Planlandı |

---

## 🚧 3. Şantiye İlerleme Çizelgesi
- [x] **Aşama 1: Baş Mimar Analizi & Mimari Planlama** (DURUM.md hazırlandı)
- [ ] **Aşama 2: TDD Birim Test Paketi (`Test-WorkersSubNodes.ps1`)**
- [ ] **Aşama 3: Arayüz ve Şablon Geliştirmesi (`live_mission_control.html`)**
- [ ] **Aşama 4: Telemetri Kancası Entegrasyonu (`sentinel_guard.ps1`)**
- [ ] **Aşama 5: Kaos & Stres Testi (`Chaos-WorkersSubNodes.ps1`)**
- [ ] **Aşama 6: Küresel Kurulum & Canlı Oturum Güncellemesi (`install.ps1`)**
- [ ] **Aşama 7: Büyük Konsolide Doğrulama (`Run-MasterVerification.ps1`)**
- [ ] **Aşama 8: Hafıza Uzmanı & Kural Güncellemesi (`[KURAL-014]`)**
- [ ] **Aşama 9: Şirket Sahibine Canlı Teslimat**

---

## ❌ 4. Açık Kusurlar ve Düzeltme Kayıtları
*Henüz açık kusur yok.*
