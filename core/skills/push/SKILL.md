---
name: push
description: >-
  Pushes local Git commits to the remote repository (GitHub) safely upon explicit user command.
  Verifies branch, pending commits, dirty tree status, runs pre-push checks, and delivers
  clean execution feedback. Triggered when the user types /push or asks to push to GitHub.
---

# 🚀 Vigiles Engine - Git Push Protokolü (/push)

Bu yetenek (skill), kullanıcının Antigravity sohbetinde **/push** yazmasıyla veya açıkça "GitHub'a pushla" talimatı vermesiyle tetiklenir.

---

## 🛡️ 1. Sıfır Otomatik Push İlkesi (Zero Auto-Push)

1. **Otonom Push Yasağı:**
   - Vigiles Engine ve alt ajanları hiçbir şart altında **kullanıcıdan habersiz veya otonom olarak `git push` çalıştıramaz.**
   - Tüm geliştirme, TDD testleri ve Bağımsız Yargıç onayı bittiğinde sistem durur ve kullanıcıya şu bildirimi verir:
     > 🚀 **GitHub'a Pushlamaya Hazır!**  
     > Tüm değişiklikler yerel olarak doğrulandı ve commitlendi.  
     > Değişiklikleri GitHub'a göndermek için **/push** yazabilirsiniz.
2. **Kullanıcı Tetikleyicisi:**
   - Push işlemi yalnızca kullanıcı **/push** yazdığında veya onay verdiğinde yürütülür.

---

## 📋 2. İcra Adımları (Execution Flow)

Kullanıcı `/push` komutunu verdiğinde ajan şu deterministik adımları izler:

1. **Durum ve Güvenlik Denetimi:**
   - `core/scripts/git_push_manager.ps1` betiğini (veya küresel `~/.gemini/config/scripts/git_push_manager.ps1`) `-DryRun` veya doğrudan parametrelerle çalıştırır:
     ```powershell
     powershell -NoProfile -File "core/scripts/git_push_manager.ps1"
     ```
   - Betik; mevcut branch adını, uzaktaki remote (`origin`) adresini ve bekleyen commit listesini doğrular.

2. **Commitlenmemiş Dosyalar Varsa:**
   - Eğer çalışma dizininde henüz commitlenmemiş önemli değişiklikler varsa, ajanın önce bu değişiklikleri atomik ve Conventional Commit formatında commit yapması gerekir:
     ```bash
     git add .
     git commit -m "feat: <açıklama>"
     ```
   - Ardından push yöneticisi çalıştırılır.

3. **Geri Bildirim ve Raporlama (No-Noise):**
   - Push tamamlandığında kullanıcıya temiz ve net bir onay mesajı verilir:
     * **Aktarılan Branch:** `main` (veya ilgili branch)
     * **Hedef Depo:** `https://github.com/...`
     * **Pushlanan Commit'ler:** Commit özetleri
     * **Durum:** ✅ Başarıyla GitHub'a aktarıldı.

---

## ⚠️ 3. Güvenlik ve Koruma Kuralları

- **Force Push Yasağı:** `git push --force` veya `--force-with-lease` komutu ana branch'ler (`main`/`master`) üzerinde kesinlikle çalıştırılamaz.
- **Sızıntı Taraması:** Push öncesinde `.env` veya API anahtarı barındıran dosyalar depoya eklenemez.
- **Çakışma Durumu:** Eğer uzaktaki repo öndeyse, force push yapılmaz; kullanıcı bilgilendirilerek `git pull --rebase` uygulanır.
