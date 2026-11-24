---
name: push
description: >-
  Executes the two-phase selective Git pipeline (/pushprep -> /push) safely upon explicit user command.
  Enforces mandatory preview when /pushprep has not been run, stages only manifest-approved files,
  verifies stage parity and Zero-Leak security, creates commit, and pushes to GitHub.
  Triggered when the user types /push or asks to push to GitHub.
---

# 🚀 Vigiles Engine - İki Aşamalı Güvenli Git Dağıtım Protokolü (/push)

Bu yetenek (skill), kullanıcının Antigravity sohbetinde **/push** (veya `/push "commit mesajı"`) yazmasıyla ya da açıkça "GitHub'a pushla" talimatı vermesiyle tetiklenir.

---

## 🛡️ 1. Sıfır Otomatik Git ve Zorunlu Önizleme İlkesi

1. **Otonom Git Yasağı:**
   - Vigiles Engine ve alt ajanları geliştirme esnasında **ASLA otomatik olarak `git add`, `git commit` veya `git push` yapamaz.**
   - Geliştirme bittiğinde kullanıcıya şu bildirim sunulur:
     > 🚀 **Çalışma Tamamlandı ve Doğrulandı!**  
     > Pushlanacak dosyaları incelemek için **`/pushprep`**, doğrudan önizleyip göndermek için **`/push`** komutunu yazabilirsiniz.

2. **Zorunlu Önizleme Kapısı (Preview Gate):**
   - Eğer kullanıcı öncesinde **`/pushprep`** çalıştırmadan doğrudan **`/push`** yazarsa sistem **asla körlemesine pushlamaz.**
   - Önce pushlanacak dosyalar listelenir (`ExitCode 2`), ardından kullanıcıdan `ask_question` ile açık onay istenir:
     - **Onaylıyorum, pushla:** İşlem `-Approved` bayrağıyla tamamlanır.
     - **Düzenlemek istiyorum:** Push durdurulur; kullanıcı `/pushremove` veya `/pushadd` ile listeyi günceller.

---

## 📋 2. İcra Adımları (Seçici Sahneleme & Push Pipeline)

Kullanıcı `/push` komutunu verdiğinde sistem `core/scripts/git_push_manager.ps1` (veya `~/.gemini/config/scripts/git_push_manager.ps1`) betiğini çalıştırır:

```powershell
$mgr = if (Test-Path ".\core\scripts\git_push_manager.ps1") { ".\core\scripts\git_push_manager.ps1" } else { "$HOME\.gemini\config\scripts\git_push_manager.ps1" }
powershell -NoProfile -ExecutionPolicy Bypass -File $mgr -Action Push -CommitMessage "<mesaj>"
```

- **Exit Code `2` (Önizleme / Yeni Dosya Onayı Gerekli):**
  1. Çıktıdaki numaralı dosya tablosunu kullanıcıya temiz şekilde göster.
  2. `ask_question` açarak *"Bu listeyi onaylayıp pushlayayım mı, yoksa /pushremove veya /pushadd ile düzenleyecek misiniz?"* diye sor.
  3. Kullanıcı **"Onaylıyorum, pushla"** seçeneğini seçerse aynı komutu `-Approved` parametresi ekleyerek çalıştır!
- **Exit Code `0` (Başarılı Seçici Pipeline):**
  1. **[ADIM 1] - Seçici Sahneleme:** `git add -A` ASLA kullanılmaz! Yalnızca `.git/vigiles/pushprep.json` içinde onaylı (`included: true`) dosyalar pathspec ile sahneye eklenir ve **Stage == Manifesto** eşleşmesi + **Zero-Leak** denetimi doğrulanır.
  2. **[ADIM 2] - Yerel Commit:** Kullanıcı mesaj verdiyse o mesajla, vermediyse değişikliklerin özetine göre üretilen Conventional Commit mesajıyla commit atılır.
  3. **[ADIM 3] - GitHub Aktarımı:** `origin/<branch>` üzerine pushlanır ve manifesto temizlenir; `/pushremove` ile hariç tutulan dosyalar bilgisayarda dokunulmadan korunur.

---

## 📊 3. Temiz Geri Bildirim Raporu

İşlem tamamlandığında kullanıcıya gürültüsüz (no-noise) bir özet sunulur:
* **Gönderilen Dosyalar & Commitler:** Pushlanan adet, commit mesajı ve branch
* **Hariç Tutulanlar (varsa):** Yerelde güvenle bırakılan dosya sayısı
* **GitHub Aktarımı:** Hedef remote URL ve branch
* **Durum:** ✅ Seçici Pipeline (Prep -> Selective Add -> Commit -> Push) başarıyla tamamlandı.
