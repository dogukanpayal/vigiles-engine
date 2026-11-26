---
name: pushremove
description: >-
  Removes specified files or directories from the /pushprep push manifest by index number,
  filename, path, or wildcard without deleting local files. Optionally adds entries to .gitignore.
  Triggered when the user types /pushremove or asks to exclude files from the upcoming push.
---

# 🚫 Vigiles Engine - Push Paketinden Dosya Çıkarma (/pushremove)

Bu yetenek (skill), kullanıcının **/pushremove <hedef>** komutunu vermesiyle tetiklenir. Seçilen dosyaları yerel bilgisayardan **ASLA silmeden** yalnızca gönderilecek Git paketinden çıkarır.

---

## 🛡️ 1. Temel Güvence Kuralları

1. **Yerel Dosya Dokunulmazlığı:**
   - `/pushremove` yerel dosyayı silmez (`rm`/`Remove-Item` yok) veya yapılan değişiklikleri geri almaz (`git checkout --` yok).
   - Yalnızca bu sohbete özel `.git/vigiles/pushprep_<cid>.json` içindeki durumu `included: false` yapar ve dosya Git index'indeyse sahneden (`stage`) indirir.
2. **İsteğe Bağlı Kalıcı Gizleme (`--ignore`):**
   - Kullanıcı `--ignore` (veya *"kalıcı çıkar / gitignore'a ekle"*) belirtirse `-Ignore` parametresi ile ilgili yol `.gitignore` dosyasına da güvenli biçimde işlenir.

---

## 📋 2. Desteklenen Hedef Formatları ve İcra

Kullanıcı hedefleri tekli veya çoklu biçimde verebilir:
- **Sıra Numarası:** `/pushremove 3`, `/pushremove 2,5`, `/pushremove 4-7`
- **Dosya Adı / Kısmi Yol:** `/pushremove notlar.txt`, `/pushremove core/test.ps1`
- **Klasör veya Wildcard:** `/pushremove logs/`, `/pushremove *.tmp`

Çalıştırılacak komut:
```powershell
$mgr = if (Test-Path ".\core\scripts\git_push_manager.ps1") { ".\core\scripts\git_push_manager.ps1" } else { "$HOME\.gemini\config\scripts\git_push_manager.ps1" }
powershell -NoProfile -ExecutionPolicy Bypass -File $mgr -Action Remove -Targets "<hedef1>","<hedef2>" # --ignore varsa -Ignore ekle
```

- Eğer hedef belirtilmemişse kullanıcıya hangi numara veya dosyayı çıkarmak istediğini sor.
- Birden fazla dosya aynı isimle çakışıyorsa (`Ambiguous`) listedeki sıra numaralarını sunup netleştir.
- İşlem sonrası güncellenmiş numaralı **Sohbet Push Listesini** göster.
