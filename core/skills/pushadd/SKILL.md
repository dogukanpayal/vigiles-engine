---
name: pushadd
description: >-
  Adds previously excluded, manual editor, shared, or safe .gitignore files into the current
  session's /pushprep manifest while strictly blocking secrets (Zero-Leak) and files owned
  by other conversations. Triggered when the user types /pushadd.
---

# ➕ Vigiles Engine - Push Paketine Dosya Ekleme (/pushadd)

Bu yetenek (skill), kullanıcının **/pushadd <hedef>** komutunu vermesiyle tetiklenir. Önizleme listesinde hariç tutulan veya elle değiştirilen güvenli dosyaları bu sohbetin push paketine dahil eder.

---

## 🛡️ 1. Katı Güvenlik ve Sohbet İzolasyon Kalkanı (Aşılamaz Kurallar)

1. **Başka Sohbet Koruması (Katı Kilit):**
   - Tamamen başka bir sohbete ait (`LOCKED_OTHER_CHAT`) dosyalar `/pushadd` ile **ASLA** eklenemez (`ExitCode 1`).
   - Kullanıcıya hangi sohbete ait olduğu netçe bildirilir; o dosya yalnızca kendi sohbetinden pushlanabilir.
2. **Zero-Leak Kalkanı:**
   - `.env` (`.env.example`/`.template`/`.sample` hariç), özel anahtarlar (`.pem`, `.key`, `id_rsa`) ve API secret içeren dosyalar (`AKIA...`, `sk-...`, `sk-proj-*`, `ghp_...`) kesinlikle reddedilir.

---

## 📋 2. İzinli Ekleme Senaryoları ve İcra

- **Önceden `/pushremove` ile çıkarılmış bu sohbetin dosyası:** Pakete geri alınır.
- **Ortak dokunulan dosya (`SHARED_MULTI_CHAT`):** Kullanıcı açıkça eklediği için `approved` olarak dahil edilir.
- **Sohbet dışı / editörde elle değiştirilen dosya (`UNTRACKED_MANUAL`):** Güvenli olarak pakete dahil edilir.
- **`.gitignore` nedeniyle gizli güvenli dosya:** Kullanıcı bilgilendirilerek istisna (`git add -f`) olarak eklenir.

Çalıştırılacak komut:
```powershell
$mgr = if (Test-Path ".\core\scripts\git_push_manager.ps1") { ".\core\scripts\git_push_manager.ps1" } else { "$HOME\.gemini\config\scripts\git_push_manager.ps1" }
powershell -NoProfile -ExecutionPolicy Bypass -File $mgr -Action Add -Targets "<hedef1>","<hedef2>"
```

- İşlem tamamlandığında pakete eklenen dosyayı ve güncel önizleme listesini kullanıcıya özetle.
