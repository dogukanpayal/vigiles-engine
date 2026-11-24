---
name: merge
description: >-
  Controlled 3-way merge manager for parallel /pro worktree sessions (.worktrees/pro-<id>).
  Previews diffs, merges non-conflicting and multi-line shared edits via git merge-file / apply,
  auto-renumbers concurrent KURALLAR.md rules, and cleans up the worktree safely on approval.
  Triggered when the user types /merge or asks to merge a parallel worktree session.
---

# 🔀 Vigiles Engine - Kontrollü Paralel Şantiye Birleştirme Protokolü (/merge)

Bu yetenek (skill), aynı repoda eşzamanlı çalıştırılan ikinci/üçüncü `/pro` oturumları için otomatik açılmış izole `.worktrees/pro-<kısa-id>` şantiyesindeki onaylı değişiklikleri **kullanıcı kontrollü 3-yollu birleştirme (`3-way merge`)** ile ana proje klasörüne aktarır.

---

## 🛡️ 1. Temel İlkeler (Kontrollü Birleştirme & Sıfır Kayıp)

1. **Önce Önizleme, Sonra Onay (Mandatory Preview Gate):**
   - Hiçbir zaman körlemesine ana klasörün üzerine yazılmaz.
   - Önce `-Action Preview` çalıştırılarak değişen/eklenen/silinen tüm dosyalar ve çakışma analizi (`[TEMIZ]`, `[OTOMATIK 3-WAY]`, `[AKILLI KURAL]`, `[CAKISMA!]`) listelenir.
   - Kullanıcıdan `ask_question` ile açık onay alınmadan `-Approved` çalıştırılmaz *(kullanıcı komutta `--yes` / `onaylı` belirtmediyse)*.
2. **Kirli Ana Klasör Dostu (Uncommitted-Safe 3-Way):**
   - Ana klasörde başka bir `/pro` oturumundan kalan commitlenmemiş dosyalar duruyor olsa bile farklı dosyalar ve aynı dosyanın farklı satırları `git merge-file` ile kayıpsız birleştirilir.
   - `KURALLAR.md` (ve `KURALLAR.template.md`) üzerinde iki paralel oturum aynı numarayı (`[KURAL-NNN]`) üretmişse ikinci kural otomatik olarak sonraki sıraya yeniden numaralandırılır.
3. **Zero-Leak & Junction Güvenliği:**
   - `.env` veya API anahtarı içeren dosyalar birleştirme öncesinde Zero-Leak kalkanı ile engellenir.
   - Temizlik sırasında `node_modules` / `.venv` Windows Junction bağları ana klasördeki hedef dizinlere dokunmadan çözülür.

---

## 📋 2. İcra Adımları

Kullanıcı `/merge` komutunu çalıştırdığında `core/scripts/vigiles_merge_manager.ps1` (veya `$HOME\.gemini\config\scripts\vigiles_merge_manager.ps1`) betiğini kullan:

```powershell
$mgr = if (Test-Path ".\core\scripts\vigiles_merge_manager.ps1") { ".\core\scripts\vigiles_merge_manager.ps1" } else { "$HOME\.gemini\config\scripts\vigiles_merge_manager.ps1" }
```

### Durum / Seçenek Akışı:
1. **Durum Listeleme (`/merge --status` veya birden fazla bekleyen şantiye varsa):**
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File $mgr -Action Status
   ```
2. **Önizleme (`/merge --preview [<id>]` veya `/merge [<id>]` ilk adımı):**
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File $mgr -Action Preview -Target "<id_varsa>"
   ```
   - `ExitCode 2` dönerse birden fazla bekleyen şantiye vardır; `ask_question` ile hangisinin birleştirileceğini sor.
   - `ExitCode 3` dönerse aynı satırda çakışan dosyalar (`[CAKISMA!]`) vardır; ana klasör **bozulmaz**, çakışan dosyaları netçe raporla.
3. **Kullanıcı Onayı ve Aktarım:**
   - Çakışma yoksa kullanıcıya `ask_question` pop-up'ı ile sor:
     - **(Tavsiye Edilen) Onaylıyorum, ana klasöre birleştir** -> `-Action Merge -Approved` çalıştır.
     - **Şantiyeyi iptal et ve sil (`--abort`)** -> `-Action Abort -Approved` çalıştır.
     - **Şimdilik beklet** -> İşlemi durdur.

   Onay alındığında:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File $mgr -Action Merge -Target "<id_varsa>" -Approved
   ```

---

## 📊 3. Teslimat Bildirimi

Birleştirme tamamlandığında kullanıcıya temiz bir özet ver:
- **Aktarılan Şantiye:** `pro-<shortId>` -> ana çalışma dizinine taşındı ve worktree temizlendi.
- **Birleştirilen / Silinen Dosya Sayısı** *(varsa akıllı KURAL yeniden numaralandırma notu)*.
- **Sonraki Adım:** Değişiklikleri inceleyip GitHub'a göndermek için **`/pushprep`** veya **`/push`** komutunu kullanabilirsiniz *(eğer `Antigravity Improvement` çekirdek dosyaları değiştiyse önce `.\install.ps1` çalıştırılması hatırlatılır)*.
