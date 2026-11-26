---
name: push
description: >-
  Executes the session-isolated, two-phase selective Git pipeline (/pushprep -> /push) safely upon
  explicit user command. Stages only the current conversation's approved files, enforces mandatory
  previews and shared-file confirmation, verifies Zero-Leak & stage parity, commits, and pushes.
  Triggered when the user types /push or asks to push to GitHub.
---

# 🚀 Vigiles Engine - Sohbet İzolasyonlu Seçici Git Dağıtım Protokolü (/push)

Bu yetenek (skill), kullanıcının Antigravity sohbetinde **/push** (veya `/push "commit mesajı"`) yazmasıyla ya da açıkça "GitHub'a pushla" talimatı vermesiyle tetiklenir.

---

## 🛡️ 1. Sıfır Otomatik Git, Sohbet İzolasyonu ve Zorunlu Kapılar

1. **Otonom Git Yasağı:**
   - Sistem veya alt ajanlar ASLA otomatik olarak `git add`, `git commit` veya `git push` yapamaz.
   - İşlem tamamlandığında kullanıcıya yalnızca şu bildirim verilir:
     > 🚀 **Çalışma Tamamlandı ve Doğrulandı!**  
     > Bu sohbetteki değişiklikleri incelemek için **`/pushprep`**, önizleyip göndermek için **`/push`** komutunu yazabilirsiniz.

2. **Sohbet İzolasyonu & Zorunlu Onay Kapıları (`ExitCode 2`):**
   - `/push` yalnızca **bu sohbetin** onaylı dosyalarını sahneler; başka sohbetlerin dosyaları yerelde güvenle ve dokunulmadan bırakılır.
   - Aşağıdaki durumlardan biri varsa sistem pushlamayı durdurup **`ExitCode 2`** döner:
     - Öncesinde `/pushprep` çalıştırılmamışsa (**Zorunlu Önizleme Kapısı**),
     - `/pushprep` sonrasında çalışma dizinine yeni bir dosya düşmüşse (**Drift Kontrolü**),
     - Başka bir sohbetle **ortak dokunulan dosya** varsa (**Ortak Dosya Onayı**),
     - Branch'te başka sohbete ait **bekleyen yerel commit** varsa (**Commit Uyarısı**).

---

## 📋 2. İcra Adımları

```powershell
$mgr = if (Test-Path ".\core\scripts\git_push_manager.ps1") { ".\core\scripts\git_push_manager.ps1" } else { "$HOME\.gemini\config\scripts\git_push_manager.ps1" }
powershell -NoProfile -ExecutionPolicy Bypass -File $mgr -Action Push -CommitMessage "<mesaj>"
```

- **Exit Code `2` Döndüğünde:**
  1. Çıktıdaki gruplandırılmış listeyi (`[A]` Bu Sohbet, `[B]` Ortak, `[C]` Elle/Hariç, `[D]` Kilitli Diğer Sohbetler) kullanıcıya net şekilde göster.
  2. `ask_question` ile sor:
     - Eğer `[B]` ortak dosya bekliyorsa: *"Ortak dokunulan dosyalar da dahil edilsin mi, yoksa yalnızca bu sohbetin dosyaları mı gönderilsin?"*
       - *"Ortakları dahil edip pushla"* -> `-Approved -IncludeShared` ile çalıştır.
       - *"Ortakları hariç tut, sadece bu sohbeti pushla"* -> `-Approved` ile çalıştır.
       - *"Düzenlemek istiyorum"* -> Dur ve `/pushremove` / `/pushadd` bekle.
     - Normal önizleme kapısı ise: *"Onaylıyorum, pushla"* -> `-Approved` ile çalıştır; *"Düzenlemek istiyorum"* -> Dur.
- **Exit Code `0` Döndüğünde:**
  - Yalnızca onaylı dosyalar pathspec ile sahnelenir, `Stage == Manifesto` ve Zero-Leak doğrulanır, commitlenir ve `origin/<branch>` üzerine aktarılır. Diğer sohbetlere ait kilitli ve çıkarılmış dosyalar yerelde korunur.

---

## 📊 3. Temiz Geri Bildirim Raporu

* **Gönderilen Dosyalar & Commit:** Yalnızca bu sohbetten giden adet, commit mesajı ve branch
* **Yerelde Korunan / Kilitli Dosyalar (varsa):** Diğer sohbetlere ait veya hariç tutulan dosya adedi
* **GitHub Aktarımı:** Hedef remote URL ve branch
* **Durum:** ✅ Sohbet İzolasyonlu Seçici Pipeline başarıyla tamamlandı.
