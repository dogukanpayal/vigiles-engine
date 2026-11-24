# Anti-Slop Tasarım Kataloğu & Referans Rehberi

Bu rehber, `/design` yeteneğinin (`SKILL.md`) somut karar destek ve referans kataloğudur. Her arayüz görevinde jenerik yapay zekâ klişelerinden kaçınmak ve ürüne özgü, kullanılabilirliği yüksek arayüzler inşa etmek için kullanılır.

---

## 1. 🏛️ 6 Estetik Arketip Tablosu

Tasarım Tezi'nin (Adım 1) 2. satırında projenin bağlamına en uygun arketip seçilir:

| Arketip | Ne Zaman Seçilir? | Doku, Izgara & Boşluk Karakteri | Örnek Sektörler |
| :--- | :--- | :--- | :--- |
| **1. Editoryal** *(Editorial / Print-Inspired)* | Uzun okuma, hikâye anlatımı, kürasyon, portfolyo ve marka derinliği gereken işlerde | Cömert negatif alan (`48–96px` bölüm aralıkları), ince `1px` ayırıcı çizgiler, asimetrik sütun oranları, yüksek tipografik kontrast | Medya/yayın, mimarlık & iç tasarım, hukuk/danışmanlık, kürasyonlu moda/perakende |
| **2. Teknik / Endüstriyel** *(Technical Precision)* | Mühendislik, gözlemlenebilirlik, otomasyon ve yüksek netlik isteyen araçlarda | Keskin köşeler (`0–4px` radius), görünür `1px` yapısal ızgara sınırları, monospace mikro-etiketler, `tabular-nums`, sıfır dekoratif gölge | DevTools, bulut/altyapı konsolu, siber güvenlik, CAD/mühendislik, donanım/IoT paneli |
| **3. Organik / Zanaat** *(Organic / Tactile Craft)* | İnsan sıcaklığı, güven, doğallık ve dokunsal his arayan ürünlerde | Sıcak kağıt/taş alt tonlu zeminler (`OKLCH` düşük doygunluk), dengeli yumuşak köşeler (`12–16px`), nefes alan boşluk, doğal ışık tonları | Sağlık & wellness, artizan gıda, sürdürülebilirlik, bağımsız eğitim, tasarım atölyesi |
| **4. Brutalist / Tipografik** *(Neo-Brutalist Statement)* | Güçlü tavır, yaratıcı kimlik ve ilk saniyede akılda kalıcılık gerektiğinde | Süslemesiz ham kontrast, dev başlık ölçek sıçraması, keskin kenar çizgileri, düz renk blokları *(WCAG AA korunarak)* | Yaratıcı stüdyo, kültür/sergi etkinliği, bağımsız yazılım ürünü, deneysel yayın |
| **5. Rafine Kurumsal** *(Refined Institutional / Swiss)* | Çok rollü iş akışları, tablo/form yoğunluğu ve hızlı taranabilirlik gerektiğinde | İsviçre ızgara disiplini, nötr arduvaz/kum zemin, kart yığını yerine net liste ve bölümleme, disiplinli görsel hiyerarşi | B2B SaaS, İK, CRM/ERP, uyumluluk & denetim, kurumsal tedarik zinciri |
| **6. Yüksek Yoğunluklu Veri** *(Command Cockpit / Terminal)* | Anlık izleme, karar verme ve çoklu veri karşılaştırması yapılan ekranlarda | Sıkı `4px` ritim, sabit genişlikli hizalı rakamlar, ince semantik durum çizgileri, klavye öncelikli düzen, minimum dolgu | Fintech/trading, lojistik sevk, NOC/telemetri merkezi, gerçek zamanlı analitik |

---

## 2. 🚫 Yasaklı AI Slop Klişeleri vs Özgün Alternatifler Matrisi

| Yasaklı AI Slop Klişesi | Neden Yasak? | Özgün & Kaliteli Alternatif |
| :--- | :--- | :--- |
| **`Inter` / `Roboto` / `Arial` varsayılanı** | Her AI çıktısının birebir aynı görünmesine yol açan en hızlı kimlik kaybıdır. | Bağlama uygun **karakterli bir display/sans veya serif/sans çifti** (`Bricolage Grotesque + Plus Jakarta Sans`, `Playfair Display + IBM Plex Sans` vb.) kullan. |
| **Sebepsiz mor-mavi (`indigo/purple`) gradient** | Ürünün sektörüyle bağı olmayan "jenerik AI şablonu" damgası vurur. | Ürünün gerçek alanından türeyen **tek bir anlamlı `--accent`** ve nötr zeminlerde **60-30-10** renk disiplini uygula. |
| **Karanlık zemin + neon glow kenarlıklar** | Okunabilirliği düşürür, ucuz oyun/kripto şablonu hissi verir. | Derinliği `1px` keskin semantik sınır (`--border`) veya `OKLCH` parlaklık adımı (`--bg` vs `--surface`) ile kur. |
| **Ortalanmış pill rozet (`✨ v2.0`) + 3'lü/4'lü kart hero** | Takas Testi'nden anında kalan şablon kalıbıdır; içerik hiyerarşisi üretmez. | Asimetrik editoryal hero, gerçek ürün ekran kesiti, canlı veri/etkileşim alanı veya numaralı özellik dizini kur. |
| **Kart içinde kart (`Nested Card Soup`)** | Görsel gürültüyü artırır, tarama hızını ve mobil alanı öldürür. | Tek katmanlı yüzey üzerinde boşluk (`16–32px`), tipografik ağırlık farkı ve ince `1px` ayırıcı çizgiler kullan. |
| **UI ikonu yerine rastgele emoji (`🚀`, `✨`, `🔥`)** | Platformdan platforma tutarsız render edilir, arayüz ciddiyetini bozar. | Tek bir SVG ikon kütüphanesinden (`Lucide`, `Phosphor`, `Heroicons`, `Tabler`) aynı `stroke-width` ile ikon seç. |
| **Her butonda `→` oku** | Bütün eylemleri aynı ağırlığa indirger, metin netliğini gizler. | Güçlü eylem fiili kullan (*"Raporu İndir"*, *"Değişiklikleri Kaydet"*); oku yalnızca gerçek ileri adım/harici linkte bırak. |
| **Sahte metrik & klişe kopya** (*"10x faster"*, *"99.9%"*) | Kullanıcı güvenini zedeler, tasarımı jenerikleştirir. | Ürünün gerçek kapasitesini, somut iş akışını ve gerçekçi veri örneklerini yaz. |

---

## 3. 🔤 Karakterli Font Eşleştirmeleri (Google Fonts / Açık Kaynak)

Başlık ve gövde arasında belirgin karakter ve ağırlık kontrastı (`200`/`300` vs `700`/`800`, veya `800` başlık vs `400` gövde) kurun:

| Eşleştirme Paketi | Başlık (Display / Heading) | Gövde (Body) | Veri / Kod (Mono) | En Uygun Arketip | Ağırlık & Stil İpucu |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Editoryal Zarafet** | `Playfair Display` veya `Newsreader` | `Plus Jakarta Sans` | `IBM Plex Mono` | Editoryal, Organik | Başlık `400`/`700` italik vurgulu, gövde `400`; `letter-spacing: -0.02em` |
| **Modern Zanaat** | `Fraunces` | `Plus Jakarta Sans` | `JetBrains Mono` | Organik, Editoryal | `Fraunces` yumuşak optik eksen (`300` veya `700`), gövde `400`/`500` |
| **Endüstriyel Hassasiyet** | `Space Grotesk` | `IBM Plex Sans` | `IBM Plex Mono` | Teknik/Endüstriyel, Veri | Başlık `700` sıkı tracking, gövde `400`, rakamlarda `tabular-nums` |
| **Karakterli Ürün** | `Bricolage Grotesque` | `Plus Jakarta Sans` veya `IBM Plex Sans` | `JetBrains Mono` | Brutalist, Modern SaaS | Başlık `700`/`800` güçlü ekspresif oran, gövde `400` sade |
| **İsviçre Kurumsal** | `Plus Jakarta Sans` *(800)* | `IBM Plex Sans` *(400)* | `JetBrains Mono` | Rafine Kurumsal | Başlık `800` vs etiket/alt bilgi `200`/`300` ağırlık kontrastı |
| **Yüksek Yoğunluk Cockpit** | `Space Grotesk` *(600)* | `IBM Plex Sans` *(400)* | `JetBrains Mono` | Yüksek Yoğunluklu Veri | `12–14px` net tablo okunabilirliği, `font-variant-numeric: tabular-nums` |

**Tipografi Altın Kuralları:**
* Uzun okuma metinlerini `60ch–72ch` maksimum satır genişliğinde tutun.
* Başlıklarda `line-height: 1.05–1.2`, gövdede `line-height: 1.5–1.65` kullanın.
* Tablo, fiyat, tarih ve metriklerde kaymayı önlemek için `font-variant-numeric: tabular-nums;` zorunludur.

---

## 4. 🎨 OKLCH & Semantik Token Rehberi + 60-30-10 Oranı

`OKLCH(Lightness Chroma Hue)` renk uzayı, algısal parlaklığı (`L`) doğrudan kontrol etmeyi sağlar; böylece hem **Light/Dark tema geçişleri** tutarlı olur hem de **WCAG AA** kontrastı matematiksel olarak garanti altına alınır.

### 60-30-10 Renk Bütçesi
* **%60 `--bg`:** Ana sayfa arka planı (göz yormayan taş, kırık beyaz veya derin arduvaz)
* **%30 `--surface`:** Yapısal paneller, yan çubuklar, tablo başlıkları, ikincil alanlar
* **%10 `--accent`:** Birincil CTA butonları, aktif sekme/odak göstergeleri, kritik vurgular

### Referans Semantik Token Şablonu (Örnek: Sıcak Teknik Light & Dark)

```css
:root {
  /* %60 Dominant Zemin & %30 Yüzey */
  --bg: oklch(0.985 0.004 85);       /* Kırık sıcak kağıt beyazı */
  --surface: oklch(0.955 0.006 85);  /* İkincil panel yüzeyi */
  --border: oklch(0.86 0.008 85);    /* 1px yapısal çizgi */

  /* Metin Hiyerarşisi (WCAG AA >= 4.5:1) */
  --text: oklch(0.19 0.012 250);     /* Yüksek kontrastlı mürekkep */
  --muted: oklch(0.46 0.012 250);    /* İkincil açıklama metni */

  /* %10 Tekil Vurgu & Durumlar */
  --accent: oklch(0.48 0.16 28);     /* Örnek: Kiremit / Terracotta (sektöre göre değiştir!) */
  --accent-fg: oklch(0.99 0.002 85); /* Vurgu üzeri metin */
  --success: oklch(0.48 0.14 150);
  --warning: oklch(0.58 0.15 70);
  --danger: oklch(0.50 0.18 25);

  /* 4px / 8px Boşluk Ritmi */
  --space-1: 4px;
  --space-2: 8px;
  --space-3: 12px;
  --space-4: 16px;
  --space-6: 24px;
  --space-8: 32px;
  --space-12: 48px;
  --space-16: 64px;
}

[data-theme="dark"] {
  --bg: oklch(0.15 0.010 250);
  --surface: oklch(0.20 0.012 250);
  --border: oklch(0.30 0.012 250);
  --text: oklch(0.94 0.005 85);
  --muted: oklch(0.72 0.008 250);
  --accent: oklch(0.68 0.16 28);
  --accent-fg: oklch(0.15 0.010 250);
}
```

> **Not:** Kendi projenizde `--accent` tonunu (`Hue`) mutlaka ürünün sektörüne göre seçin ve her eşleşmede `--text`/`--bg` ile `--accent-fg`/`--accent` kontrastını **>= 4.5:1** olarak doğrulayın.

---

## 5. ✅ Takas Testi (Swap Test) 5 Soruluk Kontrol Listesi

Bir arayüzü teslim etmeden önce şu 5 soruyu yanıtlayın; **herhangi biri "Hayır" veya ihlal verirse tasarımı düzeltmeden teslim etmeyin**:

1. **Sektör Özgünlüğü (Gerçek Takas Testi):** *Logo, marka adı ve metinler çıkarılıp bambaşka bir sektöre (örn. diş kliniği veya nakliye ERP'si) koyulduğunda bu tasarım yine birebir uyar mı?* → **Hayır, ürüne özgü kimlik taşıyor.**
2. **İmza Görsel Detay Kanıtı:** *Tasarım Tezi'nde belirlenen "Tek İmza Görsel Detay" ekrana ilk bakışta (3 saniye içinde) somut biçimde hissediliyor mu?* → **Evet.**
3. **Klişe Kara Listesi Temizliği:** *`Inter`/`Roboto`/`Arial` varsayılanı, sebepsiz mor-mavi gradient, neon glow, pill-badge + 3'lü/4'lü kart hero, kart içinde kart, UI ikonu yerine emoji ve her butonda `→` oku tamamen sıfırlandı mı?* → **Evet, sıfır klişe.**
4. **Hiyerarşi & Disiplin:** *60-30-10 renk oranı, `4px/8px` boşluk ritmi, semantik CSS değişkenleri ve belirgin başlık–gövde ağırlık kontrastı (`200` vs `800` gibi) kodda tutarlı biçimde uygulandı mı?* → **Evet.**
5. **Kullanılabilirlik Tabanı (Over-Correction Guard):** *`WCAG AA` kontrastı (`>=4.5:1` / `>=3:1`), `:focus-visible` klavye odağı, `prefers-reduced-motion`, `375px` taşmasız mobil düzen ve 4 zorunlu ekran durumu (`loading`, `empty`, `error`, `populated`) eksiksiz sağlandı mı?* → **Evet.**
