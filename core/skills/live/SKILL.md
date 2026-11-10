---
name: live
description: >-
  Manually opens, verifies, and connects the Live Operation Center (Canlı Operasyon Merkezi)
  in the Antigravity side panel and browser (Port 9999 SSE). Triggered explicitly when the
  user types /live, /mission-control, /hud, or asks to open or re-open the live operation center.
---

# Canlı Operasyon Merkezi Manuel Başlatıcı (/live)

Kullanıcı `/live` (veya `/mission-control`, `/hud`) komutunu çalıştırdığında sistem anında devreye girer.

---

## ⚡ ULTRA HIZLI VE ENTEGRE ÇALIŞMA PROTOKOLÜ (< 1 Saniye)

1. **Önceden Tamamlanan Altyapı:**
   - `ensure_live_mission_control.ps1` kancası, model ilk kelimesini üretmeden önce:
     * Port 9999 SSE telemetri sunucusunu denetlemiş ve ayaklandırmıştır,
     * Mevcut chat oturumunun artifact dizinine `live_mission_control.html` dosyasını yerleştirmiştir,
     * Harici OS tarayıcısını fırlatmaz; Antigravity dahili webview/artifact paneline hazırlar.

2. **Kesin Yasaklar (5 Dakikalık Gecikmeyi ve UI Kirliliğini Önleme):**
   - **ASLA** `<agent-embed>` kullanmayın; sayfa asla sohbet çıktısının ortasına gömülmemelidir.
   - **ASLA** `Get-ChildItem -Recurse` ile disk taraması veya dosya araması yapmayın.
   - **ASLA** 30KB'lık HTML dosyasını parça parça veya topluca okumaya (`read_file`) veya baştan yazmaya (`write_file`) çalışmayın.
   - **ASLA** arka plan görevleri (`manage_task`) veya gereksiz terminal komutları çalıştırmayın.
   - **ASLA** harici işletim sistemi tarayıcısını (`Start-Process`) fırlatmayın.

3. **Antigravity Dahili Yan Panelini Otomatik Tetikleme (Tek Adım / < 100ms):**
   - Antigravity IDE arayüzünün sağ taraftaki Artifact / Webview panelini otomatik olarak açması için doğrudan `edit_file` aracını şu şekilde çağırın:
     * **Path:** `<artifactDirectoryPath>\live_mission_control.html`
     * **Target:** `<title>Antigravity Canlı Operasyon Merkezi (Real-Time Mirror)</title>`
     * **Replacement:** `<title>Antigravity Canlı Operasyon Merkezi (Real-Time Mirror) 🟢</title>`
     * **ArtifactMetadata:**
       ```json
       {
         "Summary": "Antigravity Canlı Operasyon Merkezi (Live Mission Control)",
         "UserFacing": true,
         "RequestFeedback": false
       }
       ```
   - Bu tek minik çağrı (< 100ms), Antigravity UI'ına `UserFacing: true` sinyali ileterek sağ paneldeki webview'ı anında açar. (Eğer başlık zaten güncellenmişse tersine çevirin).

4. **Kullanıcıya Sunulacak Çıktı (Temiz ve Side Panel Odaklı):**
   - **ASLA** `<agent-embed>` kullanmayın.
   - Doğrudan aşağıdaki net ve şık bağlantıları sunun:
     * 🌐 **Antigravity Side Panel Browser'ı:** [http://localhost:9999/](http://localhost:9999/) *(Tıklandığında doğrudan Antigravity'nin sağ tarafındaki dahili browser sekmesinde açılır)*
     * 🪟 **Antigravity Artifact Paneli:** [🛰️ Canlı Operasyon Merkezi (Artifact)](file:///<artifactDirectoryPath>/live_mission_control.html)
     * 🧪 **Canlı Deneme Tahtası:** [http://localhost:9999/playground](http://localhost:9999/playground)
     * 📡 **Telemetri Durumu:** Port 9999 SSE hattı bağlı, tüm elemanlar gerçek zamanlı dinlemede.
