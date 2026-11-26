---
name: chatdiff
description: >-
  Read-only per-chat change inspector (/chatdiff). Lists only pending (unpushed) files in the main
  working tree, unmerged parallel /pro worktree changes, and unpushed local commits belonging to
  the current chat (or a selected chat via --list / <target>) with Zero-Mutation and Zero-Leak masking.
  Triggered when the user types /chatdiff or asks to view only the changes made in this/a specific chat.
---

# 🔍 Vigiles Engine - Sohbet Odaklı Değişiklik Görüntüleyici (/chatdiff)

Bu yetenek (skill), kullanıcı **`/chatdiff`** yazdığında proje içinde **yalnızca o sohbete ait** (diğer sohbetlerin ve sohbet dışı elle düzenlemelerin gürültüsünden arındırılmış) **henüz GitHub'a gönderilmemiş** aktif değişiklikleri salt-okunur olarak listeler.

---

## 🛡️ 1. Temel Kurallar (Zero-Mutation & Zero-Leak)

1. **%100 Salt-Okunur:** `git add`, `git reset`, `pushprep` manifestosu veya `file_ledger.json` üzerinde hiçbir değişiklik yapmaz.
2. **Yalnızca Bekleyen İşler:** Zaten GitHub'a pushlanmış eski commit'ler ve dosyalar listede yer almaz; yalnızca ana klasördeki bekleyen dosyalar, henüz `/merge` edilmemiş paralel `.worktrees/pro-<id>` şantiyesi ve sahibine ait pushlanmamış yerel commit'ler gösterilir.
3. **Zero-Leak Kalkanı:** `.env`, özel anahtar veya API secret içeren dosyalarda güvenlik uyarısı verilir; `--diff` modunda bile gizli içerik ekrana basılmaz (maskelenir).
4. **Sohbet Kimliği Doğrulaması:** Mevcut sohbet kimliği `session_file_ledger.ps1` ve `command_watchdog.ps1` kancaları tarafından otomatik doğrulanır.

---

## 📋 2. İcra Adımları

Önce betik yolunu seç (`core/scripts/chat_diff_viewer.ps1` varsa yerel, yoksa küresel `$HOME\.gemini\config\scripts\chat_diff_viewer.ps1`):

```powershell
$viewer = if (Test-Path ".\core\scripts\chat_diff_viewer.ps1") { ".\core\scripts\chat_diff_viewer.ps1" } else { "$HOME\.gemini\config\scripts\chat_diff_viewer.ps1" }
```

### Kullanım Kalıpları:
1. **Mevcut Sohbetin Değişiklikleri (`/chatdiff`):**
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File $viewer
   ```
2. **Bekleyen İşi Olan Sohbetleri Listeleme (`/chatdiff --list`):**
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File $viewer -ListChats
   ```
3. **Belirli Bir Sohbeti Seçip Görüntüleme (`/chatdiff <sohbet>`):**
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File $viewer -TargetChat "<hedef>"
   ```
   * Eğer `ExitCode 2` dönerse birden fazla sohbet eşleşmiştir; kullanıcıya `ask_question` ile aday sohbetleri seçtirip net kimlik/numara ile tekrar çalıştır.
4. **Satır İçi Fark Önizleme (`/chatdiff --diff [<dosya_veya_klasör>]`):**
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File $viewer -Diff
   ```
   * Belirli bir sohbet ve dosya ile birleştirilebilir (`-TargetChat "<hedef>" -Diff -Paths "<yol>"`).

---

## 📊 3. Sunum Kuralı

* Çıktıyı kullanıcıya sade, net ve okunaklı biçimde özetle (gereksiz dev ham JSON veya dosya tekrarları yapma).
* Kullanıcı değişiklikleri dağıtmak isterse **`/pushprep`** veya **`/push`** (paralel şantiye varsa önce **`/merge`**) komutlarını kullanabileceğini hatırlat.
