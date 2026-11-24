---
name: pushadd
description: >-
  Adds previously excluded, newly created, or safe .gitignore files into the /pushprep
  push manifest by index number, filename, path, or wildcard while enforcing Zero-Leak checks.
  Triggered when the user types /pushadd or asks to include a missing file in the upcoming push.
---

# ➕ Vigiles Engine - Push Paketine Dosya Ekleme (/pushadd)

Bu yetenek (skill), kullanıcının **/pushadd <hedef>** komutunu vermesiyle tetiklenir. `/pushprep` listesinde görünmeyen veya daha önce `/pushremove` ile çıkarılmış dosyaları güvenli biçimde push paketine dahil eder.

---

## 🛡️ 1. Zero-Leak Güvenlik Kalkanı (Aşılamaz Kural)

- `/pushadd` komutu bile `.env` dosyalarını, özel anahtarları (`.pem`, `.key`, `id_rsa`) veya kod içi API anahtarlarını (`AKIA...`, `sk-...`, `ghp_...`) **KESİNLİKLE** pakete ekleyemez.
- Güvenlik kalkanına takılan dosya reddedilir ve kullanıcıya net sebep bildirilir.

---

## 📋 2. Akıllı Ekleme Senaryoları ve İcra

Motor 4 durumu otomatik çözümler:
1. **Önceden `/pushremove` ile çıkarılmış dosya / numara:** Tekrar `included: true` durumuna getirir.
2. **`/pushprep` sonrası yeni oluşturulmuş dosya:** Manifestoya yeni sıra numarasıyla ekler.
3. **`.gitignore` nedeniyle listede gizli dosya:** Zero-Leak taramasından geçerse kullanıcıyı bilgilendirerek bu push için istisna (`git add -f`) olarak ekler.
4. **Zaten GitHub/HEAD ile güncel dosya:** Değişiklik olmadığını açıkça raporlar.

Çalıştırılacak komut:
```powershell
$mgr = if (Test-Path ".\core\scripts\git_push_manager.ps1") { ".\core\scripts\git_push_manager.ps1" } else { "$HOME\.gemini\config\scripts\git_push_manager.ps1" }
powershell -NoProfile -ExecutionPolicy Bypass -File $mgr -Action Add -Targets "<hedef1>","<hedef2>"
```

- İşlem tamamlandığında pakete eklenen dosyayı ve güncel push önizleme listesini kullanıcıya özetle.
