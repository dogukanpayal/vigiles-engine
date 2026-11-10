# MCP Köprüleri: Figma ve Sentry Entegrasyonu

Bu rehber, Baş Mimar ve Canlı Hata Dedektifi'nin kullandığı iki harici köprüyü açıklar.

---

## 1. 🎨 Figma Tasarım Köprüsü (Pixel-Perfect UI)
Figma köprüsü aktif olduğunda:
* Baş Mimar, Figma proje linkinden (`https://figma.com/file/...`) renk paletini, font ailesini ve padding değerlerini otomatik okur.
* UI İşçileri doğrudan bu tokenları Tailwind veya CSS sınıflarına dönüştürür.
* **Nasıl Aktif Edilir?**
  1. Figma'dan bir Personal Access Token alın.
  2. `~/.gemini/config/templates/mcp_bridges.json` dosyasındaki `figma-design-bridge` bloğunu `~/.gemini/config/mcp_config.json` içine kopyalayın ve token'ınızı yapıştırın.

---

## 2. 🩺 Canlı Hata Dedektifi (Sentry Telemetri Can Simidi)
Sentry köprüsü aktif olduğunda:
* Canlı ortama düşen bir JavaScript / Python hatası veya Unhandled Rejection anında yakalanır.
* Hatanın satır numarası ve stack trace'i çekilerek otomatik bir fail eden test (TDD) yazılır.
* **Nasıl Aktif Edilir?**
  1. Sentry panosundan Auth Token oluşturun.
  2. `~/.gemini/config/templates/mcp_bridges.json` dosyasındaki `sentry-error-hunter` bloğunu `~/.gemini/config/mcp_config.json` içine kopyalayın ve token'ınızı yapıştırın.
