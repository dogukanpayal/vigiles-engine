# CANLI ŞANTİYE DEFTERİ (DURUM.md)
*Bu dosya görevin canlı durumunu, kabul kriterlerini ve test kanıtlarını takip eden yaşayan belgedir.*

**Görev Adı:** VİGİLES İZOLASYON & KOŞULLU TETİKLEME GÜVENCESİ (/vigiles İzolasyonu)  
**Tarih / Saat:** 2026-11-10 23:16:00  
**Çalışma Vitesi:** 🏛️ Vigiles Engine Protocol (20 Elemanlı Fabrika)  
**Git & Dağıtım Modu:** TAM MANUEL KONTROL (Sıfır Otomatik Git / Kullanıcı Kontrollü /push)  

---

## 🎯 1. Görev Özeti ve Vizyon
*Şirket Sahibinin (Sizin) verdiği vizyon:*
> "/vigiles vigiles kota durtucusunu etkilemeden vigiles'in yalnızca ve yalnızca /vigiles komutu verildiğinde çalışacak şekilde ayarlayabilir miyiz ?"

---

## 📐 2. Baş Mimar Kabul Kriterleri & Doğrulama Matrisi
| # | Kriter / Odak | Beklenen Davranış | Doğrulama Yöntemi | Sonuç |
| :-: | :--- | :--- | :--- | :-: |
| 1 | Normal Sohbette Sıfır Vigiles | Normal mesajlarda `ensure_live_mission_control.ps1` `{}` dönmeli, Canlı Merkez mesajı basılmamalı. | `Test-VigilesIsolation.ps1` (Test 1) | ✅ GEÇTİ |
| 2 | Diğer Slash Komutlarında Sıfır Vigiles | `/plan`, `/push`, `/browser`, `/lite` komutlarında Vigiles telemetrisi devreye girmemeli. | `Test-VigilesIsolation.ps1` (Test 2) | ✅ GEÇTİ |
| 3 | `/vigiles` Komutunda Tam Yetki | `/vigiles` verildiğinde `.vigiles_active` oluşturulmalı ve Canlı Merkez telemetrisi çalışmalı. | `Test-VigilesIsolation.ps1` (Test 3) | ✅ GEÇTİ |
| 4 | Sentinel Guard İzolasyonu | Vigiles olmayan oturumlarda `sentinel_guard.ps1` anında allow vermeli, telemetri üretmemeli. | `Test-VigilesIsolation.ps1` (Test 4) | ✅ GEÇTİ |
| 5 | Vigiles Oturumunda 20-Eleman Telemetrisi | `.vigiles_active` olan oturumda `sentinel_guard.ps1` 20-eleman telemetrisini işletmeli. | `Test-VigilesIsolation.ps1` (Test 5) | ✅ GEÇTİ |
| 6 | Normal Oturumda Stop İzolasyonu | Normal oturum bittiğinde `on_mission_complete.ps1` `{}` dönmeli, teslimat telemetrisi basmamalı. | `Test-VigilesIsolation.ps1` (Test 6) | ✅ GEÇTİ |
| 7 | Vigiles Oturumunda Stop Teslimatı | Vigiles oturumu bittiğinde `on_mission_complete.ps1` `TESLIM_EDILDI` durumuyla teslim etmeli. | `Test-VigilesIsolation.ps1` (Test 7) | ✅ GEÇTİ |
| 8 | Kota Dürtücüsü Dokunulmazlığı | `VigilesKotaDurtucusu` Windows Görev Zamanlayıcısı görevi `Ready` kalmalı ve etkilenmemeli. | `Test-VigilesIsolation.ps1` (Test 8) | ✅ GEÇTİ |
| 9 | Konsolide Master Test Uyumu | `Run-MasterVerification.ps1` içerisinde 20/20 test paketi eksiksiz yeşil geçmeli. | Master Suite | ✅ GEÇTİ |

---

## 🚧 3. Şantiye İlerleme Çizelgesi
- [x] **Aşama 1: Kanca Analizi ve İzolasyon Mimarisinin Belirlenmesi** (`.vigiles_active` session marker deseni)
- [x] **Aşama 2: `ensure_live_mission_control.ps1` İzolasyonu** (`/vigiles` veya `/live` harici anında `exit 0`)
- [x] **Aşama 3: `sentinel_guard.ps1` İzolasyonu** (Oturumda `.vigiles_active` yoksa anında `allow`)
- [x] **Aşama 4: `on_mission_complete.ps1` İzolasyonu** (Oturumda `.vigiles_active` yoksa anında `exit 0`)
- [x] **Aşama 5: `vigiles/SKILL.md` Tanım Güçlendirmesi** (Modelin otonom tetiklenmesini engelleyen açık kısıt)
- [x] **Aşama 6: Kota Dürtücüsü Bütünlük Kontrolü** (`VigilesKotaDurtucusu` scheduled task'a dokunulmadı)
- [x] **Aşama 7: TDD Test Paketinin Yazılması (`Test-VigilesIsolation.ps1`)** (8/8 Başarılı)
- [x] **Aşama 8: Master Verification Koşumu (`Run-MasterVerification.ps1`)** (20/20 Test Paketi Başarılı)
- [x] **Aşama 9: Şirket Sahibine Detaylı Rapor ve /push Hatırlatması Sunulması**
