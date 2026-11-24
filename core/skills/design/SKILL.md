---
name: design
description: >-
  Activates Anti-Slop UI/Frontend Design Discipline with a mandatory 4-line Design Thesis,
  hard cliché bans, DESIGN.md contract governance, WCAG AA usability floor, and Swap Test
  self-audit. Triggered by /design, /ui, /anti-slop, or new UI, screen, component, and
  frontend tasks (HTML, CSS, Tailwind, React, Next.js, Vue, Svelte). Strictly inactive
  (0 quota) for backend, CLI, PowerShell, or pure data tasks.
---

# Vigiles Anti-Slop Design Protocol (`/design`, `/ui`, `/anti-slop`)

Bu yetenek (skill), yapay zekânın ürettiği klişe, birbirinin kopyası **"AI Slop"** arayüzleri (varsayılan Inter/Roboto fontları, sebepsiz mor-mavi gradientler, kart içinde kart çorbası ve jenerik SaaS kalıpları) kökünden engellemek için tasarlanmış **önleyici UI/Frontend tasarım anayasasıdır**.

---

## 🎯 Kapsam ve Koşullu Tetikleme (0 Kota İzolasyonu)

| Görev Türü | Durum | Davranış |
| :--- | :---: | :--- |
| **UI / Frontend Görevleri** *(HTML, CSS, Tailwind, React, Next.js, Vue, Svelte, Webview, yeni ekran/sayfa/bileşen tasarımı)* | ✅ **AKTİF** | Adım 1–6 tam uygulanır. |
| **Küçük UI / CSS Rötuşları** *(Mevcut tasarımda tekil hata/hizalama düzeltmesi)* | 🩹 **HAFİF** | Yeni `DESIGN.md` yazılmaz; projedeki mevcut `DESIGN.md` tokenlarına, Adım 2 (Kara Liste) ve Adım 5 (Kalite Tabanı) kurallarına uyulur. |
| **Backend, CLI, PowerShell, API, DB veya Salt Veri Görevleri** | ⛔ **DEVRE DIŞI (0 Kota)** | Bu skill kesinlikle devreye girmez, ek adım veya token maliyeti üretmez. |

---

## 📐 Adım 1 — Zorunlu 4 Satırlık Tasarım Tezi (Koddan Önce)

**Demir Kural:** Aşağıdaki **4 satırlık Tasarım Tezi** belirlenip netleştirilmeden **tek bir satır UI kodu yazılmaz**:

```markdown
🎨 Tasarım Tezi:
1. Bağlam & Hedef Kitle: [Ürünün gerçek amacı, kullanıcının bu ekrandaki birincil eylemi ve kullanım ortamı]
2. Estetik Arketip: [Editoryal | Teknik/Endüstriyel | Organik | Brutalist | Rafine Kurumsal | Yüksek Yoğunluklu Veri]
3. Tipografi Eşleşmesi: [Başlık Fontu (ağırlık) + Gövde Fontu (ağırlık) + Varsa Monospace/Veri Fontu]
4. Tek İmza Görsel Detay: [Ekranı tek bakışta özgün ve hatırlanır kılan tekil odak unsuru]
```

> *Detaylı arketip profilleri ve font çiftleri için bkz:* [anti_slop_catalog.md](references/anti_slop_catalog.md)

---

## 🚫 Adım 2 — Klişe Kara Listesi (Hard Bans)

Kullanıcı veya projenin mevcut tasarım sistemi açıkça talep etmedikçe aşağıdaki kalıplar **kesin olarak yasaktır**:

1. **Varsayılan Slop Fontları:** `Inter`, `Roboto`, `Arial`, `Helvetica` veya çıplak `system-ui` tek başına varsayılan font olarak seçilemez.
2. **Sebepsiz Mor-Mavi Gradient & Neon Glow:** Anlamsız `indigo/purple/violet` lineer gradientler, karanlık zeminlerde klişe neon parlama (`glow`) kenarlıklar ve jenerik "AI startup" mor vurguları kullanılamaz.
3. **Klişe SaaS Hero + 3'lü/4'lü Kart Dizilimi:** Tepede ortalanmış küçük pill rozet (`✨ Introducing X`), altında büyük ortalanmış başlık ve hemen altında birbirinin aynısı 3'lü veya 4'lü ikonlu özellik kartı ızgarası kurulamaz.
4. **Kart İçinde Kart (Nested Card Soup):** Kenarlıklı veya gölgeli bir kartın içine tekrar kenarlıklı/gölgeli alt kartlar, rozet yığınları ve iç içe kutular gömülemez. Hiyerarşi boşluk, tipografi ve `1px` ayırıcılarla kurulur.
5. **UI İkonu Yerine Rastgele Emoji:** Arayüz butonlarında, menülerde, özellik listelerinde veya durum rozetlerinde profesyonel SVG ikon setleri (`Lucide`, `Phosphor`, `Heroicons`, `Tabler`) yerine rastgele emoji (`🚀`, `✨`, `🔥`, `💡`, `⚡`) kullanılamaz.
6. **Her Butona `→` Oku Konması:** Tüm CTA ve ikincil butonların sonuna alışkanlıkla `→` / `↗` oku eklenemez; ok yalnızca gerçek yönlendirme veya dış bağlantı bağlamında ölçülü kullanılır.

---

## 📜 Adım 3 — Tasarım Sözleşmesi (`DESIGN.md` & Stil Kayması Önlemi)

* **Yeni veya Çok Sayfalı Arayüz İşleri:**
  - Proje kökünde `core/templates/DESIGN.template.md` (veya `~/.gemini/config/templates/DESIGN.template.md`) şablonuna uygun **`DESIGN.md`** dosyası oluşturulur / güncellenir.
  - Tüm sayfalar, bileşenler ve alt ajanlar (`Worker`, `design-critic`) bu sözleşmedeki renk, tipografi, boşluk ve arketip kararlarına bağlanır; böylece **Stil Kayması (Style Drift)** önlenir.
* **Küçük CSS / Bileşen Rötuşları:**
  - Proje kökünde zaten `DESIGN.md` varsa sıfırdan tasarım sözleşmesi yazılmaz; mevcut `DESIGN.md` içindeki token ve kurallara harfiyen uyulur.

---

## 🎨 Adım 4 — Tipografi, Renk ve Boşluk Disiplini

1. **4px / 8px Boşluk Ritmi:**
   - Tüm `padding`, `margin`, `gap` ve yükseklikler `4px` / `8px` tabanlı tutarlı bir skaladan (`4, 8, 12, 16, 24, 32, 48, 64, 96px`) seçilir; keyfî `13px`, `19px`, `37px` gibi rastgele değerler kullanılmaz.
2. **60-30-10 Renk Oranı:**
   - **%60 Dominant Zemin (`--bg`):** Gözü yormayan ana çalışma alanı.
   - **%30 İkincil Yüzey (`--surface`):** Yapısal paneller, yan menü veya ikincil alanlar.
   - **%10 Vurgu (`--accent`):** Yalnızca birincil eylem ve kritik odak noktaları.
3. **Semantik CSS Değişkenleri:**
   - Bileşen içine ham renk kodu dağıtılmaz; en az şu semantik değişkenler tanımlanır:
     `--bg`, `--surface`, `--text`, `--muted`, `--accent` *(ek olarak `--border`, `--danger`, `--success`, `--warning` önerilir; mümkünse `OKLCH` ile kurulur)*.
4. **Belirgin Başlık–Gövde Ağırlık Kontrastı:**
   - Başlık ile gövde arasında açık bir tipografik gerilim oluşturulur (örn. `200` hafif display veya `800` ağır display karşısında `400` sade gövde; sayılarda `tabular-nums`, uzun okuma bloklarında `60ch–72ch` satır genişliği).

> *Detaylı arketip tablosu, yasaklı/özgün matris, Google Fonts eşleştirmeleri ve OKLCH token rehberi için:* [anti_slop_catalog.md](references/anti_slop_catalog.md)

---

## 🛡️ Adım 5 — Kalite Tabanı (Usability Floor & Over-Correction Guard)

Estetik özgünlük uğruna temel kullanılabilirlik ve erişilebilirlik **asla feda edilemez**:

1. **WCAG AA Kontrast Oranı:**
   - Normal metinlerde en az **`4.5:1`**, büyük metin (`>=18pt` / `14pt bold`) ve etkileşimli UI sınır/ikonlarında en az **`3:1`** kontrast zorunludur.
2. **Klavye Odağı (`:focus-visible`):**
   - Tüm tıklanabilir ve odaklanabilir elemanlarda belirgin `:focus-visible` halkası tanımlanır; yedeksiz `outline: none` yasaktır.
3. **Hareket Hassasiyeti (`prefers-reduced-motion`):**
   - Animasyon ve geçişler `@media (prefers-reduced-motion: reduce)` kuralına saygı duyar.
4. **375px Mobil Taşma Önlemi:**
   - `375px` mobil genişlikte sıfır yatay taşma (`overflow-x`), kırılmayan düzen ve yeterli dokunma alanı (`min 44×44px` hedeflenir) sağlanır.
5. **4 Zorunlu Ekran Durumu:**
   - Veri veya etkileşim içeren her ekran/bileşende şu 4 durum eksiksiz tanımlanır:
     - **`loading`:** Düzen sıçramasını (CLS) önleyen iskelet veya kararlı yükleme durumu
     - **`empty`:** Kullanıcıya ne yapacağını gösteren net boş durum ve yönlendirici eylem
     - **`error`:** Anlaşılır hata açıklaması ve yeniden deneme / kurtarma yolu
     - **`populated`:** Kısa, uzun ve uç değer verilerle taşmayan gerçek içerik durumu.

---

## 🔍 Adım 6 — Takas Testi (Swap Test) Öz-Denetimi

Teslimattan önce her ekran şu tek soruluk final filtresinden geçirilir:

> **Takas Testi:** *"Bu tasarımdaki logoyu, marka adını ve metinleri çıkarıp bambaşka bir sektöre (ör. bir diş kliniğine, nakliye ERP'sine veya müzik stüdyosuna) yapıştırsam, tek piksel değiştirmeden yine aynı jenerik uyumu verir mi?"*

* Cevap **EVET** ise tasarım klişe / jenerik kalmıştır → **REDDEDİLİR**; Adım 1'deki Arketip, Tipografi Eşleşmesi ve İmza Görsel Detay ürüne özgü biçimde yeniden kurgulanır.
* Cevap **HAYIR** ise ve [anti_slop_catalog.md](references/anti_slop_catalog.md) içindeki 5 soruluk Takas Testi kontrol listesi yeşilse tasarım teslime hazırdır.
