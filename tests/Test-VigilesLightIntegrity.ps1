# ==============================================================================
# Test-VigilesLightIntegrity.ps1
# Vigiles Light (Fast-Strike) Bütünlük ve Keşif Doğrulama Testi
# ==============================================================================
param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$global:passedTests = 0
$global:failedTests = 0

function Assert-Condition {
    param(
        [string]$TestName,
        [bool]$Condition,
        [string]$ErrorMessage = ""
    )

    if ($Condition) {
        Write-Host "  [OK] $TestName" -ForegroundColor Green
        $global:passedTests++
    } else {
        Write-Host "  [FAIL] $TestName - $ErrorMessage" -ForegroundColor Red
        $global:failedTests++
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "VIGILES LIGHT BUTUNLUK VE PROTOKOL DOGRULAMA TESTI" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$configDir = "$HOME\.gemini\config"
$vigilesLightSkill = Join-Path $configDir "skills\vigiles-light\SKILL.md"
$liteSkill = Join-Path $configDir "skills\lite\SKILL.md"
$wsLightTemplate = Join-Path (Split-Path -Parent $PSScriptRoot) "core\templates\live_mission_control_light.html"
$cfgLightTemplate = Join-Path $configDir "templates\live_mission_control_light.html"
$skillsJson = Join-Path $configDir "skills.json"

# TEST 1: Skill Dosyalarının Varlığı
Write-Host "`n[Grup 1] Skill Dosyalari ve Dizin Yapisi:" -ForegroundColor Yellow
Assert-Condition "vigiles-light/SKILL.md mevcut olmali" (Test-Path $vigilesLightSkill) "Dosya bulunamadi: $vigilesLightSkill"
Assert-Condition "lite/SKILL.md mevcut olmali" (Test-Path $liteSkill) "Dosya bulunamadi: $liteSkill"

# TEST 2: YAML Frontmatter ve Tetikleyici İsimleri
Write-Host "`n[Grup 2] YAML Frontmatter ve Isimlendirme:" -ForegroundColor Yellow
$vlContent = if (Test-Path $vigilesLightSkill) { [System.IO.File]::ReadAllText($vigilesLightSkill, [System.Text.Encoding]::UTF8) } else { "" }
$liteContent = if (Test-Path $liteSkill) { [System.IO.File]::ReadAllText($liteSkill, [System.Text.Encoding]::UTF8) } else { "" }

Assert-Condition "vigiles-light frontmatter 'name: vigiles-light' icermeli" ($vlContent -match "name:\s*vigiles-light")
Assert-Condition "lite frontmatter 'name: lite' icermeli" ($liteContent -match "name:\s*lite")
Assert-Condition "Aciklamalarda /lite ve /vigiles-light tetikleyicileri yer almali" ($vlContent -match "/lite" -and $liteContent -match "/lite")

# TEST 3: Vigiles Light Çekirdek İlkeleri (0-Subagent, Mikro-Plan, Sıfır Sızıntı, /push)
Write-Host "`n[Grup 3] Cerrahi Icra Kurallari ve Guvenlik DNA'si:" -ForegroundColor Yellow
Assert-Condition "0-Subagent (Sifir Alt Ajan) kurali acikca belirtilmeli" ($vlContent -match "0-Subagent")
Assert-Condition "Mikro-Plan standardi tanimlanmali" ($vlContent -match "Mikro-Plan")
Assert-Condition "Sifir-Sizinti (Zero-Leak) guvenlik kurali korunmali" ($vlContent -match "Zero-Leak")
Assert-Condition "Sifir Otomatik Git ve /push kontrolu korunmali" ($vlContent -match "/push")
Assert-Condition "Hedefli Sanity / Tekil Birim Test kosumu yer almali" ($vlContent -match "Sanity")

# TEST 4: Fast-Strike HUD Şablonları
Write-Host "`n[Grup 4] Fast-Strike HUD Sablon Butunlugu:" -ForegroundColor Yellow
Assert-Condition "core/templates/live_mission_control_light.html mevcut ve dolu olmali" ((Test-Path $wsLightTemplate) -and ((Get-Item $wsLightTemplate).Length -gt 15000))
Assert-Condition "config/templates/live_mission_control_light.html senkronize olmali" (Test-Path $cfgLightTemplate)

$wsHash = if (Test-Path $wsLightTemplate) { (Get-FileHash $wsLightTemplate).Hash } else { "1" }
$cfgHash = if (Test-Path $cfgLightTemplate) { (Get-FileHash $cfgLightTemplate).Hash } else { "2" }
Assert-Condition "Sablon hash degerleri birebir eslesmeli" ($wsHash -eq $cfgHash) "Hash uyusmazligi var"

# TEST 5: Antigravity Keşif ve Konfigürasyon
Write-Host "`n[Grup 5] Antigravity Skill Kesif Yolu:" -ForegroundColor Yellow
Assert-Condition "skills.json mevcut olmali" (Test-Path $skillsJson)
$skillsJsonRaw = if (Test-Path $skillsJson) { [System.IO.File]::ReadAllText($skillsJson, [System.Text.Encoding]::UTF8) } else { "" }
Assert-Condition "skills.json skills dizinini gostermeli" ($skillsJsonRaw -match "config/skills")

# SONUÇ
Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "TEST SONUCU: $global:passedTests GECTI, $global:failedTests BASARISIZ" -ForegroundColor $(if ($global:failedTests -eq 0) { "Green" } else { "Red" })
Write-Host "==========================================================" -ForegroundColor Cyan

if ($global:failedTests -gt 0) {
    exit 1
} else {
    exit 0
}
