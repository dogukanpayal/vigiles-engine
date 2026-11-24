# install.ps1
# Kurşungeçirmez 19 Elemanlı Otonom Fabrika Kurulum Betiği
# Bu betik, projenin 'core/' dizinindeki yetenekleri, kancaları ve şablonları
# bilgisayarınızdaki küresel Antigravity dizinine (~/.gemini/config/) kurar.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$targetConfig = Join-Path $HOME ".gemini\config"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceCore = Join-Path $scriptDir "core"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "🚀 VIGILES ENGINE - 19 ELEMANLI OTONOM FABRIKA KURULUMU" -ForegroundColor Yellow
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
Write-Host "[1/4] Vigiles Yetenekleri kopyalaniyor..." -ForegroundColor Cyan
Copy-Item (Join-Path $sourceCore "skills\*") (Join-Path $targetConfig "skills") -Recurse -Force

# 3. Kanca ve sunucu betiklerini (Scripts) kopyala
Write-Host "[2/4] Guvenlik ve Telemetri betikleri kopyalaniyor..." -ForegroundColor Cyan
Copy-Item (Join-Path $sourceCore "scripts\*") (Join-Path $targetConfig "scripts") -Recurse -Force

# 4. Şablonları (Templates) kopyala
Write-Host "[3/4] Santiye ve Anayasa sablonlari kopyalaniyor..." -ForegroundColor Cyan
Copy-Item (Join-Path $sourceCore "templates\*") (Join-Path $targetConfig "templates") -Recurse -Force

# Eski tekilleştirilmiş şablon ve kaldırılan bileşen kalıntılarını temizle
$legacyPlaygroundTpl = Join-Path $targetConfig "templates\playground_template.html"
if (Test-Path $legacyPlaygroundTpl) {
    Remove-Item $legacyPlaygroundTpl -Force -ErrorAction SilentlyContinue
}

# Kaldırılan Kota Dürtücüsü (Heartbeat Sentinel) ve eski skill kalıntılarını temizle
try {
    $legacyHbTask = Get-ScheduledTask -TaskName "VigilesKotaDurtucusu" -ErrorAction SilentlyContinue
    if ($legacyHbTask) {
        if ($legacyHbTask.State -eq "Running") {
            Stop-ScheduledTask -TaskName "VigilesKotaDurtucusu" -ErrorAction SilentlyContinue
        }
        Unregister-ScheduledTask -TaskName "VigilesKotaDurtucusu" -Confirm:$false -ErrorAction SilentlyContinue
    }
} catch {}

$legacyArtifacts = @(
    (Join-Path $targetConfig "scripts\heartbeat_sentinel.ps1"),
    (Join-Path $targetConfig "scripts\manage_heartbeat.ps1"),
    (Join-Path $HOME ".gemini\heartbeat.log"),
    (Join-Path $HOME ".gemini\antigravity\heartbeat.log")
)
foreach ($legacyItem in $legacyArtifacts) {
    if (Test-Path $legacyItem) {
        Remove-Item $legacyItem -Force -ErrorAction SilentlyContinue
    }
}

$legacySkillDirs = @(
    (Join-Path $targetConfig "skills\consilium"),
    (Join-Path $targetConfig "skills\vigiles")
)
foreach ($legacySkillDir in $legacySkillDirs) {
    if (Test-Path $legacySkillDir) {
        Remove-Item $legacySkillDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 5. hooks.json dosyasını güvenli merge ederek güncelle (Mevcut kişisel kancaları korur)
Write-Host "[4/4] hooks.json kanca yapilandirmasi guvenle birlestiriliyor..." -ForegroundColor Cyan
$hooksSrc = Join-Path $sourceCore "hooks.json"
$hooksDest = Join-Path $targetConfig "hooks.json"

$rawSrcHooks = [System.IO.File]::ReadAllText($hooksSrc, [System.Text.Encoding]::UTF8)
$escapedConfigRoot = $targetConfig.Replace('\', '\\')
$resolvedSrcHooks = $rawSrcHooks.Replace('%USERPROFILE%\\.gemini\\config', $escapedConfigRoot)
$srcHooksObj = $resolvedSrcHooks | ConvertFrom-Json

$mergedHooks = [ordered]@{}
if (Test-Path $hooksDest) {
    try {
        $existingRaw = [System.IO.File]::ReadAllText($hooksDest, [System.Text.Encoding]::UTF8).Trim().Trim([char]65279)
        if (-not [string]::IsNullOrWhiteSpace($existingRaw)) {
            $existingObj = $existingRaw | ConvertFrom-Json
            foreach ($prop in $existingObj.PSObject.Properties) {
                $mergedHooks[$prop.Name] = $prop.Value
            }
        }
    } catch {
        Copy-Item $hooksDest "$hooksDest.bak" -Force -ErrorAction SilentlyContinue
    }
}

foreach ($prop in $srcHooksObj.PSObject.Properties) {
    $mergedHooks[$prop.Name] = $prop.Value
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($hooksDest, ($mergedHooks | ConvertTo-Json -Depth 10), $utf8NoBom)

Write-Host "`n==========================================================" -ForegroundColor Green
Write-Host "✅ KURULUM BASARIYLA TAMAMLANDI!" -ForegroundColor Green
Write-Host "   Antigravity sohbetinde artik dilediginiz projede:" -ForegroundColor Yellow
Write-Host "   '/pro' yazarak 19 elemanli fabrikayi baslatabilirsiniz." -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Green
