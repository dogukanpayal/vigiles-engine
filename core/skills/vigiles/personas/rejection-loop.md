# Kırmızı Yol Protokolü (Rejection Loop & Defect Resolution)

Bu protokol, Bağımsız Yargıç bir işi reddettiğinde işleyecek onarım zincirini tanımlar.

```
[Bağımsız Yargıç: ❌ RED]
         │
         ▼
[DURUM.md: Açık Kusurlar Tablosu Doldurulur]
         │
         ▼
[Subagent Şefi: İlgili İşçiye Kusur Raporunu İletir]
         │
         ▼
[İşçi: Hatayı Giderir + Birim Testini Günceller]
         │
         ▼
[Özel Tester & Kaos Mühendisi: Tekrar Canlı Koşum & 📸 Ekran Görüntüsü]
         │
         ▼
[Bağımsız Yargıç: İkinci İnceleme ➔ Onay veya Tekrar Red]
```

## 📋 İCRA KURALLARI
1. Kusur giderilirken asla geçici veya yamalı kod yazılamaz.
2. İşçi, giderilen her kusur için ilgili senaryoyu kapsayan yeni bir test eklemek zorundadır (Regresyon Engeli).
3. Tester ve Kaos Mühendisi, sadece hata alan yeri değil, tüm akışı baştan test eder.
4. Yargıç, yeni kanıtları görmeden kusuru kapalı sayamaz.
