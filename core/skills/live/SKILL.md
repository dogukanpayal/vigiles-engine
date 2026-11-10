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

## ⚡ ULTRA HIZLI VE SIFIR ARAÇ KURALLARI (Milisaniyelik Yanıt)

1. **Önceden Tamamlanan Altyapı:**
   - `ensure_live_mission_control.ps1` kancası, model daha ilk yanıtına başlamadan önce:
     * Port 9999 SSE telemetri sunucusunu denetlemiş ve ayaklandırmıştır,
     * Tarayıcıda `http://localhost:9999/` adresini açmıştır,
     * Mevcut chat oturumunun artifact dizinine `live_mission_control.html` dosyasını ve `userFacing: true` metadata'sını yerleştirmiştir.

2. **Kesin Yasaklar (5 Dakikalık Gecikmeyi Önleme):**
   - **ASLA** `Get-ChildItem -Recurse` ile disk taraması veya dosya araması yapmayın.
   - **ASLA** 30KB'lık HTML dosyasını parça parça veya topluca okumaya (`read_file`) veya yeniden diske yazmaya (`write_file`) çalışmayın.
   - **ASLA** arka plan görevleri (`manage_task`) veya gereksiz terminal komutları ile döngüye girmeyin.

3. **Anında Sonuç Çıktısı (Zero-Tool Response):**
   - Hiçbir araç çalıştırmadan **DOĞRUDAN VE ANINDA** aşağıdaki şık, temiz ve bağlantılı yanıtı kullanıcıya verin:
     * **IDE Yan Paneli:** Sağ taraftaki Artifact panelinde canlı ayna modunda aktif.
     * **Geniş Ekran Tarayıcı:** [http://localhost:9999/](http://localhost:9999/)
     * **Canlı Deneme Tahtası:** [http://localhost:9999/playground](http://localhost:9999/playground)
     * **Telemetri Durumu:** Port 9999 SSE hattı bağlı, tüm elemanlar gerçek zamanlı dinlemede.
