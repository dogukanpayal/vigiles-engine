# install.ps1
# Kurşungeçirmez 20 Elemanlı Veteran Otonom Fabrika Kurulum Betiği
# Bu betik, projenin 'core/' dizinindeki yetenekleri, kancaları ve şablonları
# bilgisayarınızdaki küresel Antigravity dizinine (~/.gemini/config/) kurar.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$targetConfig = Join-Path $HOME ".gemini\config"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceCore = Join-Path $scriptDir "core"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🚀 VIGILES ENGINE - 20 ELEMANLI OTONOM FABRIKA KURULUMU" -ForegroundColor Yellow
Write-Host "   Kaynak : $sourceCore" -ForegroundColor Gray
Write-Host "   Hedef  : $targetConfig" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

if (-not (Test-Path $sourceCore)) {
    Write-Host "HATA: 'core' dizini bulunamadi!" -ForegroundColor Red
    exit 1
}

# 1. Hedef dizinleri hazırla
$dirs = @("skills", "scripts", "templates")
foreach ($d in $dirs) {
    $p = Join-Path $targetConfig $d
    if (-not (Test-Path $p)) {
        New-Item -ItemType Directory -Path $p -Force | Out-Null
    }
}

# 2. Yetenekleri (Skills & Personas) kopyala
Write-Host "[1/4] 20 Elemanli Veteran Yetenegi kopyalaniyor..." -ForegroundColor Cyan
Copy-Item (Join-Path $sourceCore "skills\*") (Join-Path $targetConfig "skills") -Recurse -Force

# 3. Kanca ve sunucu betiklerini (Scripts) kopyala
Write-Host "[2/4] Guvenlik ve Telemetri betikleri kopyalaniyor..." -ForegroundColor Cyan
Copy-Item (Join-Path $sourceCore "scripts\*") (Join-Path $targetConfig "scripts") -Recurse -Force

# 4. Şablonları (Templates) kopyala
Write-Host "[3/4] Santiye ve Anayasa sablonlari kopyalaniyor..." -ForegroundColor Cyan
Copy-Item (Join-Path $sourceCore "templates\*") (Join-Path $targetConfig "templates") -Recurse -Force

# 5. hooks.json dosyasını güncelle
Write-Host "[4/4] hooks.json kanca yapilandirmasi kurallaniyor..." -ForegroundColor Cyan
$hooksDest = Join-Path $targetConfig "hooks.json"
Copy-Item (Join-Path $sourceCore "hooks.json") $hooksDest -Force

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "✅ KURULUM BASARIYLA TAMAMLANDI!" -ForegroundColor Green
Write-Host "   Antigravity sohbetinde artik dilediginiz projede:" -ForegroundColor Yellow
Write-Host "   '/vigiles' yazarak 20 elemanli fabrikayi baslatabilirsiniz." -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Green
