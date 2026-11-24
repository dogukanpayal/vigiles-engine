# TASARIM SÖZLEŞMESİ (DESIGN.md)
*Bu dosya projenin görsel anayasasıdır. Tüm UI geliştiricileri, alt ajanlar ve denetçiler stil kaymasını (Style Drift) önlemek için bu sözleşmeye uymakla yükümlüdür.*

**Proje Adı:** `[PROJE_ADI]`  
**Son Güncelleme:** `[TARİH]`  
**Hedef Kırılımlar:** `375px` (Mobil) / `768px` (Tablet) / `1280px+` (Masaüstü)

---

## 1. 📐 Estetik Kimlik & 4 Satırlık Tasarım Tezi

1. **Bağlam & Hedef Kitle:** `[Ürünün amacı, kullanıcının temel eylemi ve kullanım ortamı]`
2. **Estetik Arketip:** `[Editoryal | Teknik/Endüstriyel | Organik | Brutalist | Rafine Kurumsal | Yüksek Yoğunluklu Veri]`
3. **Tipografi Eşleşmesi:** `[Başlık Fontu (ağırlık) + Gövde Fontu (ağırlık) + Varsa Mono Font]`
4. **Tek İmza Görsel Detay:** `[Ekranı tek bakışta hatırlanır kılan özgün görsel imza]`

---

## 2. 🔤 Tipografi Ölçeği & Font Çiftleri

* **Başlık (Display/Heading):** `[Örn: Space Grotesk]` *(Önerilen ağırlık kontrastı: `700`/`800` veya `200`/`300`)*
* **Gövde (Body):** `[Örn: IBM Plex Sans]` *(Ağırlık: `400` / `500`, maks. satır genişliği: `65ch`)*
* **Veri / Kod (Monospace):** `[Örn: JetBrains Mono]` *(Sayısal sütunlarda `font-variant-numeric: tabular-nums`)*

| Rol | Boyut / Ölçek | Satır Yüksekliği | Ağırlık | Harf Aralığı | Kullanım Notu |
| :--- | :--- | :---: | :---: | :---: | :--- |
| **Display / Hero** | `[Örn: clamp(2.25rem, 4vw, 3.5rem)]` | `1.08` | `[200 veya 800]` | `-0.03em` | Sayfa başına tek ana vurgu |
| **H1 / Ekran Başlığı** | `[Örn: 1.75rem (28px)]` | `1.15` | `[700]` | `-0.02em` | Ana görünüm başlığı |
| **H2 / Bölüm Başlığı** | `[Örn: 1.25rem (20px)]` | `1.25` | `[600]` | `-0.01em` | Alt bölüm başlıkları |
| **Body / Gövde** | `[Örn: 1rem (16px)]` | `1.55` | `400` | `0` | Ana okuma ve form metinleri |
| **Caption / Etiket** | `[Örn: 0.75rem (12px)]` | `1.4` | `500` | `0.02em` | Mikro etiketler, durum rozetleri |

---

## 3. 🎨 Semantik Renk & Yüzey Tokenları (60-30-10 & WCAG AA)

* **60-30-10 Bütçesi:** `%60 --bg` (Dominant zemin) · `%30 --surface` (Yapısal paneller) · `%10 --accent` (Birincil aksiyon)
* **WCAG AA Kontrast Notu:** `--text` / `--bg` ve `--accent-fg` / `--accent` kontrastı en az **`4.5:1`** (büyük metin/UI sınırlar en az **`3:1`**) olarak doğrulanmalıdır.

| Token | Light Mode (`OKLCH` / `HEX`) | Dark Mode (`OKLCH` / `HEX`) | Rol & Kontrast Notu |
| :--- | :--- | :--- | :--- |
| `--bg` | `[oklch(...)]` | `[oklch(...)]` | %60 Dominant arka plan |
| `--surface` | `[oklch(...)]` | `[oklch(...)]` | %30 İkincil panel / yüzey |
| `--border` | `[oklch(...)]` | `[oklch(...)]` | `1px` yapısal ayırıcı çizgi |
| `--text` | `[oklch(...)]` | `[oklch(...)]` | Ana metin (`>= 4.5:1` kontrast) |
| `--muted` | `[oklch(...)]` | `[oklch(...)]` | Yardımcı metin (`>= 4.5:1` kontrast) |
| `--accent` | `[oklch(...)]` | `[oklch(...)]` | %10 Birincil vurgu & CTA |
| `--accent-fg` | `[oklch(...)]` | `[oklch(...)]` | Vurgu üzerindeki metin (`>= 4.5:1`) |
| `--success` / `--warning` / `--danger` | `[oklch(...)]` | `[oklch(...)]` | Durum geri bildirim renkleri |

```css
:root {
  --bg: /* ... */;
  --surface: /* ... */;
  --border: /* ... */;
  --text: /* ... */;
  --muted: /* ... */;
  --accent: /* ... */;
  --accent-fg: /* ... */;
}
```

---

## 4. 📏 Boşluk, Izgara Ritmi & Erişilebilirlik (4px / 8px Grid)

* **Boşluk Skalası (4px / 8px Ritmi):** `4px`, `8px`, `12px`, `16px`, `24px`, `32px`, `48px`, `64px`, `96px`
* **Köşe Yarıçapı (`border-radius`):** `[Örn: 4px keskin / 8px dengeli / 14px organik]`
* **Yüzey Hiyerarşisi:** Kart içinde kart (nested card) yasaktır; hiyerarşi boşluk, tipografi ve `1px` çizgilerle kurulur.
* **Erişilebilirlik & Mobil Taban:**
  - Tüm etkileşimli elemanlarda görünür `:focus-visible` odak halkası bulunur.
  - Animasyonlar `@media (prefers-reduced-motion: reduce)` ile sınırlandırılır.
  - `375px` mobil genişlikte yatay taşma (`overflow-x`) oluşmaz; dokunma hedefleri en az `44×44px` hedeflenir.

---

## 5. 🖥️ 4 Zorunlu Ekran Durumu (Screen States)

Her veri veya etkileşim ekranı şu 4 durumu eksiksiz tanımlar:

| Durum | Görsel & Davranış Tanımı |
| :--- | :--- |
| **`loading`** | `[İskelet/shimmer veya sabit yükseklikli yükleme göstergesi — CLS sıfır]` |
| **`empty`** | `[Veri yokken gösterilecek yönlendirici mesaj + tek net birincil eylem]` |
| **`error`** | `[Hata nedeni açıklaması + kullanıcı dostu yeniden dene / kurtarma yolu]` |
| **`populated`** | `[Gerçek veri görünümü + çok uzun metin / sıfır / uç değer taşma koruması]` |

---

## 6. 🚫 Projeye Özel Yasaklar (Anti-Slop Guardrails)

* **Evrensel Yasaklar:** Açıkça istenmedikçe `Inter`/`Roboto`/`Arial` kullanımı; sebepsiz mor-mavi gradient ve neon glow; pill-badge'li klişe SaaS hero + 3'lü/4'lü kart dizilimi; kart içinde kart; UI ikonu yerine emoji (`🚀`, `✨`, `🔥`); her butona `→` oku eklemek yasaktır.
* **Projeye Özel Kısıtlar:** `[Bu projede ayrıca yasaklanan görsel/metin/bileşen alışkanlıkları]`

---

## 7. ✅ Takas Testi (Swap Test) Onayı

- [ ] **Sektör Özgünlüğü:** Logo ve metinler çıkarılıp bambaşka bir sektöre uygulandığında tasarım jenerik kalmıyor.
- [ ] **İmza Detay:** Tasarım Tezi'ndeki imza görsel detay gerçek bileşenlerde tutarlı şekilde uygulanıyor.
- [ ] **Klişe Temizliği:** Klişe kara listesindeki hiçbir yasaklı kalıp projede yer almıyor.
- [ ] **Kalite Tabanı:** `WCAG AA` kontrast, `:focus-visible`, `prefers-reduced-motion`, `375px` mobil uyum ve 4 ekran durumu (`loading`/`empty`/`error`/`populated`) doğrulandı.
