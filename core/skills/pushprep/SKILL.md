---
name: pushprep
description: >-
  Previews all staged, modified, untracked, deleted, and unpushed Git changes in a numbered
  manifest before pushing, allowing selective inspection prior to /pushremove, /pushadd, or /push.
  Triggered when the user types /pushprep or asks to preview what will be pushed.
---

# 🔍 Vigiles Engine - Push Önizleme & Hazırlık Protokolü (/pushprep)

Bu yetenek (skill), kullanıcı **/pushprep** (veya `/pushprep --reset`) yazdığında ya da GitHub'a göndermeden önce hangi dosya ve commitlerin gideceğini görmek istediğinde tetiklenir.

---

## 📋 1. İcra Adımları (Sıfır Mutasyonlu Önizleme)

1. **Çalışma Alanında Git Push Yöneticisini Hazırlık Modunda Çalıştır:**
   - Varsa yerel `core/scripts/git_push_manager.ps1` betiğini, yoksa küresel `$HOME\.gemini\config\scripts\git_push_manager.ps1` betiğini çalıştır:
   - Normal önizleme (`/pushprep`):
     ```powershell
     $mgr = if (Test-Path ".\core\scripts\git_push_manager.ps1") { ".\core\scripts\git_push_manager.ps1" } else { "$HOME\.gemini\config\scripts\git_push_manager.ps1" }
     powershell -NoProfile -ExecutionPolicy Bypass -File $mgr -Action Prep
     ```
   - Kullanıcı sıfırlama istediyse (`/pushprep --reset` veya *"listeyi sıfırla"*): `-Action Reset` kullan.

2. **Manifesto ve Sıfır Kirlilik İlkesi:**
   - Hazırlık durumu `.git/vigiles/pushprep.json` dosyasında tutulur; proje dizinine geçici dosya yazılmaz.
   - Önceden `/pushremove` ile çıkarılmış dosyalar normal `/pushprep` çağrısında korunur; hem **Gönderilecekler (`✅`)** hem **Hariç Tutulanlar (`🚫`)** ayrı gruplarda numaralandırılır.
   - `.env`, özel anahtar veya API secret içeren dosyalar **Zero-Leak Kalkanı** ile otomatik olarak hariç tutulur.

---

## 📊 2. Kullanıcıya Sunulacak Rapor Formatı

Çıktıyı sade, numaralı ve kolay yönetilebilir şekilde özetle:
* **Branch & Hedef:** Aktif branch ve `origin` adresi
* **Pushlanacak Dosyalar (`[1]`, `[2]`...):** Durumu (`Yeni`, `Değişti`, `Silindi`, `Taşındı`) ve göreceli dosya yolu
* **Hariç Tutulanlar (varsa):** Yerelde korunan dosyalar ve çıkarma nedeni
* **Bekleyen Yerel Commitler (varsa):** Henüz GitHub'a gönderilmemiş commit özeti
* **Sonraki Adımlar:**
  - Çıkarmak için: `/pushremove <numara veya dosya>` *(kalıcı gizlemek için `--ignore`)*
  - Eklemek için: `/pushadd <numara veya dosya>`
  - Onaylayıp göndermek için: `/push`
