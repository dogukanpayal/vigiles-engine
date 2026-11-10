---
name: push
description: >-
  Executes the unified Git pipeline (git add + git commit + git push) safely upon explicit user command.
  Verifies branch, stages changes, creates commit, runs pre-push checks, and pushes to GitHub with clean feedback.
  Triggered when the user types /push or asks to push to GitHub.
---

# 🚀 Vigiles Engine - Birleşik Git Dağıtım Protokolü (/push)

Bu yetenek (skill), kullanıcının Antigravity sohbetinde **/push** (veya `/push "commit mesajı"`) yazmasıyla ya da açıkça "GitHub'a pushla" talimatı vermesiyle tetiklenir.

---

## 🛡️ 1. Sıfır Otomatik Git İlkesi (Tam Manuel Tetikleme)

1. **Otonom Git Yasağı:**
   - Vigiles Engine ve alt ajanları geliştirme esnasında **ASLA otomatik olarak `git add`, `git commit` veya `git push` yapamaz.**
   - Kodlar, testler ve şantiye dosyaları yerel çalışma alanında (working directory) hazır bekletilir.
   - Tüm geliştirme ve test doğrulamaları tamamlandığında sistem durur ve kullanıcıya şu bildirimi sunar:
     > 🚀 **Çalışma Tamamlandı ve Doğrulandı!**  
     > Yapılan değişiklikleri Git'e kaydedip (add + commit) GitHub'a göndermek (push) için **/push** komutunu yazabilirsiniz.

2. **Kullanıcı Tetikleyicisi:**
   - `git add`, `git commit` ve `git push` işlemleri **YALNIZCA VE YALNIZCA** kullanıcı **/push** komutunu verdiğinde topluca ve sırayla icra edilir.

---

## 📋 2. İcra Adımları (Tek Komutla 3'lü Pipeline)

Kullanıcı `/push` komutunu verdiğinde sistem `core/scripts/git_push_manager.ps1` (veya `~/.gemini/config/scripts/git_push_manager.ps1`) betiğini çalıştırır:

1. **[ADIM 1] - `git add -A` (Sahneleme):**
   - Çalışma dizinindeki tüm yeni, değiştirilmiş veya silinmiş dosyaları sahneye (staging area) ekler.
2. **[ADIM 2] - `git commit -m "<mesaj>"` (Yerel Commit):**
   - Kullanıcı bir mesaj belirttiyse onu kullanır (örn: `/push "feat: payment gateway"`).
   - Mesaj belirtilmemişse yapılan işe göre açıklayıcı bir Conventional Commit mesajı üretir.
3. **[ADIM 3] - `git push origin <branch>` (GitHub Aktarımı):**
   - Aktif branch'i ve uzaktaki GitHub reposunu (`origin`) kontrol eder, değişiklikleri uzaktaki depoya güvenle pushlar.

---

## 📊 3. Temiz Geri Bildirim Raporu

İşlem tamamlandığında kullanıcıya gürültüsüz (no-noise) bir özet sunulur:
* **Eklenen Dosyalar:** Sahnelenen dosya listesi / adedi
* **Oluşturulan Commit:** Commit hash'i ve mesajı
* **GitHub Aktarımı:** Aktarılan branch ve hedef URL
* **Durum:** ✅ Pipeline (Add -> Commit -> Push) başarıyla tamamlandı.
