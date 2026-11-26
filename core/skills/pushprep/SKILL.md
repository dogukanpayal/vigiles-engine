---
name: pushprep
description: >-
  Previews all staged, modified, untracked, deleted, and unpushed Git changes scoped to the current
  conversation in a numbered manifest before pushing, isolating other chats' changes and manual edits.
  Triggered when the user types /pushprep or asks to preview what will be pushed.
---

# 🔍 Vigiles Engine - Sohbet İzolasyonlu Push Önizleme (/pushprep)

Bu yetenek (skill), kullanıcı **/pushprep** (veya `/pushprep --reset`) yazdığında ya da GitHub'a göndermeden önce **yalnızca bu sohbete ait** hangi dosyaların pushlanacağını görmek istediğinde tetiklenir.

---

## 📋 1. İcra Adımları (Sohbete Özel Manifesto)

1. **Git Push Yöneticisini Hazırlık Modunda Çalıştır:**
   - Varsa yerel `core/scripts/git_push_manager.ps1` betiğini, yoksa küresel `$HOME\.gemini\config\scripts\git_push_manager.ps1` betiğini çalıştır:
   - *(Güvenlik Notu: `session_file_ledger.ps1` PreToolUse kancası gerçek sohbet kimliğini otomatik doğrular ve izole ortam değişkeni olarak geçirir.)*
     ```powershell
     $mgr = if (Test-Path ".\core\scripts\git_push_manager.ps1") { ".\core\scripts\git_push_manager.ps1" } else { "$HOME\.gemini\config\scripts\git_push_manager.ps1" }
     powershell -NoProfile -ExecutionPolicy Bypass -File $mgr -Action Prep
     ```
   - Kullanıcı sıfırlama istediyse (`/pushprep --reset`): `-Action Reset` kullan.

2. **4'lü Sahiplik Sınıflandırması (`.git/vigiles/pushprep_<cid>.json`):**
   - **`[A] Bu Sohbetin Dosyaları (✅ Dahil)`:** Yalnızca bu sohbet (veya alt ajanları) tarafından değiştirilen dosyalar.
   - **`[B] Ortak Dokunulan Dosyalar (⚠️ Onay Gerekli)`:** Hem bu sohbetin hem başka bir sohbetin dokunduğu dosyalar; varsayılan olarak hariç tutulur ve karar beklenir.
   - **`[C] Sohbet Dışı / Elle Değiştirilen & Çıkarılanlar (📝 Hariç)`:** Senin editörde elle değiştirdiğin veya `/pushremove` ile çıkardığın dosyalar; dilersen `/pushadd` ile ekleyebilirsin.
   - **`[D] Başka Sohbete Ait Kilitli Dosyalar (🔒 Kilitli)`:** Tamamen başka bir sohbete ait dosyalar; katı koruma gereği yalnızca kendi sohbetlerinden pushlanabilir (`/pushadd` ile bile eklenemez).
   - **Zero-Leak Kalkanı:** `.env`, özel anahtar veya API secret içeren dosyalar otomatik bloke edilir.

---

## 📊 2. Kullanıcıya Sunulacak Rapor Formatı

Çıktıyı 4 grup halinde sade, numaralı ve net şekilde sun:
* **Branch, Remote & Sohbet Kimliği**
* **Grup [A] Bu Sohbetin Pushlanacak Dosyaları**
* **Grup [B] Ortak Dosyalar (varsa — diğer sohbetin adıyla)**
* **Grup [C] Elle Değiştirilen / Çıkarılan Dosyalar (varsa)**
* **Grup [D] Başka Sohbete Kilitli Dosyalar (varsa — sahibi olan sohbetin adıyla)**
* **Grup [E] Push Bekleyen Yerel Commitler (varsa — sahip bilgisiyle)**
