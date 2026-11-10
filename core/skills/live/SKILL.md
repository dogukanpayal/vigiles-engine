---
name: live
description: >-
  Manually opens, verifies, and connects the Live Operation Center (Canlı Operasyon Merkezi)
  in the Antigravity side panel and browser (Port 9999 SSE). Triggered explicitly when the
  user types /live, /mission-control, /hud, or asks to open or re-open the live operation center.
---

# Canlı Operasyon Merkezi Manuel Başlatıcı (/live)

Bu yetenek, kullanıcının sohbet içinde dilediği an **Canlı Operasyon Merkezi'ni (Live Mission Control)** bağımsız olarak açması, yan panelde görüntülemesi ve Port 9999 SSE bağlantısını tazelemesi için kullanılır.

---

## 🚀 Çalışma Prosedürü

Kullanıcı `/live` yazdığında veya canlı kontrol merkezini açmak istediğinde sistem şu adımları icra eder:

1. **Yan Panel Artifact Doğrulaması:**
   - Mevcut chat oturumunun artifact dizininde (`<artifactDirectoryPath>/live_mission_control.html`) dosyasını `write_file` ile `ArtifactMetadata (userFacing: true)` formatında teyit eder.
   - Bu sayede Antigravity IDE arayüzünün sağ yan panelinde kontrol merkezi doğrudan açılır.

2. **Telemetri Sunucusu (Port 9999) Denetimi:**
   - Arka planda `telemetry_server.ps1` çalışmıyorsa `([wmiclass]"win32_process").Create` ile bağımsız olarak ayağa kaldırır.
   - Sunucu ayaktaysa `/set-active` rotasına oturum bilgilerini bildirir.

3. **Tarayıcıda Canlı Görünüm:**
   - `Start-Process "http://localhost:9999/"` ile kullanıcı için tarayıcıda geniş ekran kontrol merkezini açar.

4. **Kullanıcıya Bildirim:**
   - Kullanıcıya panelin aktif olduğunu, hem IDE yan panelinden hem de `http://localhost:9999/` üzerinden canlı takip edilebileceğini net ve şık bir mesajla bildirir.
