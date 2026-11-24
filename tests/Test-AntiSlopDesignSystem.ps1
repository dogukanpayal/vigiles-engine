# ==============================================================================
# Test-AntiSlopDesignSystem.ps1
# Vigiles Anti-Slop UI Tasarim Disiplini, DESIGN.md, design-critic & node-figma TDD Testi
# ==============================================================================
param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$global:passedCount = 0
$global:failedCount = 0

function Assert-Test([string]$testName, [bool]$condition, [string]$detail = "") {
    if ($condition) {
        Write-Host "  [GECTI] $testName" -ForegroundColor Green
        $global:passedCount++
    } else {
        Write-Host "  [BASARISIZ] $testName" -ForegroundColor Red
        if ($detail) { Write-Host "     -> HATA: $detail" -ForegroundColor Yellow }
        $global:failedCount++
    }
}

function Read-Utf8Text([string]$path) {
    if (-not (Test-Path $path)) { return "" }
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Invoke-HookJson([string]$scriptPath, [hashtable]$payloadObj, [string]$stateDirToClean = "") {
    if (-not [string]::IsNullOrWhiteSpace($stateDirToClean)) {
        $oldState = Join-Path $stateDirToClean "live_state.json"
        if (Test-Path $oldState) { Remove-Item $oldState -Force -ErrorAction SilentlyContinue }
    }

    $json = $payloadObj | ConvertTo-Json -Depth 6 -Compress
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "powershell.exe"
    $pinfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $pinfo.RedirectStandardInput = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $pinfo.UseShellExecute = $false

    $proc = [System.Diagnostics.Process]::Start($pinfo)
    $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $proc.StandardInput.BaseStream.Write($utf8Bytes, 0, $utf8Bytes.Length)
    $proc.StandardInput.Close()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()

    $state = $null
    if (-not [string]::IsNullOrWhiteSpace($stateDirToClean)) {
        $stateFile = Join-Path $stateDirToClean "live_state.json"
        if (Test-Path $stateFile) {
            try {
                $state = (Read-Utf8Text $stateFile) | ConvertFrom-Json
            } catch {}
        }
    }

    return @{
        ExitCode = $proc.ExitCode
        Stdout   = $stdout.Trim()
        State    = $state
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "VIGILES TDD: ANTI-SLOP TASARIM SISTEMI & NODE-FIGMA TESTI" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$ws = Split-Path -Parent $PSScriptRoot
$globalConfig = Join-Path $HOME ".gemini\config"

# ------------------------------------------------------------------------------
# GRUP 1: Dosya Varligi ve Hash Eslesmesi (Core & Global)
# ------------------------------------------------------------------------------
Write-Host "`n[Grup 1: Dosya Varligi ve Core <-> Global Hash Eslesmesi]" -ForegroundColor Yellow

$pairedArtifacts = @(
    @{ Label = "design/SKILL.md"; Core = "core\skills\design\SKILL.md"; Global = "skills\design\SKILL.md" },
    @{ Label = "design/references/anti_slop_catalog.md"; Core = "core\skills\design\references\anti_slop_catalog.md"; Global = "skills\design\references\anti_slop_catalog.md" },
    @{ Label = "DESIGN.template.md"; Core = "core\templates\DESIGN.template.md"; Global = "templates\DESIGN.template.md" },
    @{ Label = "pro/personas/design-critic.md"; Core = "core\skills\pro\personas\design-critic.md"; Global = "skills\pro\personas\design-critic.md" }
)

foreach ($item in $pairedArtifacts) {
    $corePath = Join-Path $ws $item.Core
    $globalPath = Join-Path $globalConfig $item.Global
    $coreExists = Test-Path $corePath
    $globalExists = Test-Path $globalPath

    Assert-Test "Core $($item.Label) mevcut olmali" $coreExists "Bulunamadi: $corePath"
    Assert-Test "Global $($item.Label) mevcut olmali" $globalExists "Bulunamadi: $globalPath"

    $hashMatch = $false
    if ($coreExists -and $globalExists) {
        $hCore = (Get-FileHash $corePath -Algorithm SHA256).Hash
        $hGlobal = (Get-FileHash $globalPath -Algorithm SHA256).Hash
        $hashMatch = ($hCore -eq $hGlobal)
    }
    Assert-Test "$($item.Label) Core <-> Global SHA256 eslesmeli" $hashMatch "install.ps1 senkronizasyonu eksik veya dosya icerigi farkli"
}

# ------------------------------------------------------------------------------
# GRUP 2: Design Skill Icerik ve Anti-Slop Kurallari
# ------------------------------------------------------------------------------
Write-Host "`n[Grup 2: Design Skill Icerik, Kara Liste ve Kalite Tabani]" -ForegroundColor Yellow

$designSkillPath = Join-Path $ws "core\skills\design\SKILL.md"
$catalogPath = Join-Path $ws "core\skills\design\references\anti_slop_catalog.md"
$designTplPath = Join-Path $ws "core\templates\DESIGN.template.md"

$designRaw = Read-Utf8Text $designSkillPath
$catalogRaw = Read-Utf8Text $catalogPath
$tplRaw = Read-Utf8Text $designTplPath

Assert-Test "design/SKILL.md frontmatter 'name: design' ve '/design' icermeli" `
    (($designRaw -match 'name:\s*design') -and ($designRaw -match '/design')) `
    "YAML frontmatter veya /design tetikleyicisi eksik"

Assert-Test "design/SKILL.md Backend/CLI icin 0 Kota izolasyonu tanimlamali" `
    (($designRaw -match '0 Kota') -and ($designRaw -match 'Backend.*CLI')) `
    "0 Kota / Backend-CLI devre disi kurali eksik"

Assert-Test "design/SKILL.md 4 satirlik Tasarim Tezi (Baglam/Arketip/Tipografi/Imza) icermeli" `
    (($designRaw -match 'Tasarım Tezi') -and ($designRaw -match 'Bağlam') -and ($designRaw -match 'Estetik Arketip') -and ($designRaw -match 'Tipografi') -and ($designRaw -match 'İmza Görsel Detay')) `
    "4 satirlik Tasarim Tezi alanlarindan biri eksik"

Assert-Test "Klişe Kara Listesi: Inter/Roboto varsayilan font yasagi bulunmali" `
    (($designRaw -match 'Inter') -and ($designRaw -match 'Roboto')) `
    "Inter/Roboto yasagi eksik"

Assert-Test "Klişe Kara Listesi: Mor gradient ve neon glow yasagi bulunmali" `
    (($designRaw -match 'gradient') -and ($designRaw -match 'glow')) `
    "Mor gradient veya neon glow yasagi eksik"

Assert-Test "Klişe Kara Listesi: Kart icinde kart (Nested Card Soup) ve emoji yasagi bulunmali" `
    (($designRaw -match 'Kart İçinde Kart|Nested Card Soup') -and ($designRaw -match 'Emoji|emoji')) `
    "Kart corbasi veya emoji yasagi eksik"

Assert-Test "Kalite Tabani: WCAG AA, :focus-visible, prefers-reduced-motion ve 375px mobil kurali bulunmali" `
    (($designRaw -match 'WCAG AA') -and ($designRaw -match ':focus-visible') -and ($designRaw -match 'prefers-reduced-motion') -and ($designRaw -match '375px')) `
    "Erisilebilirlik veya 375px mobil tasmasiz kural eksik"

Assert-Test "4 zorunlu ekran durumu (loading, empty, error, populated) tanimli olmali" `
    (($designRaw -match 'loading') -and ($designRaw -match 'empty') -and ($designRaw -match 'error') -and ($designRaw -match 'populated')) `
    "4 ekran durumundan biri eksik"

Assert-Test "Takas Testi (Swap Test) ve DESIGN.md / anti_slop_catalog.md referanslari bulunmali" `
    (($designRaw -match 'Takas Testi') -and ($designRaw -match 'Swap Test') -and ($designRaw -match 'DESIGN\.md') -and ($designRaw -match 'anti_slop_catalog\.md')) `
    "Takas Testi veya DESIGN.md/anti_slop_catalog.md referansi eksik"

Assert-Test "anti_slop_catalog.md 6 estetik arketip, OKLCH ve 60-30-10 rehberi icermeli" `
    (($catalogRaw -match 'Editoryal') -and ($catalogRaw -match 'Teknik') -and ($catalogRaw -match 'Organik') -and ($catalogRaw -match 'Brutalist') -and ($catalogRaw -match 'Rafine Kurumsal') -and ($catalogRaw -match 'Yüksek Yoğunluklu Veri') -and ($catalogRaw -match 'OKLCH') -and ($catalogRaw -match '60-30-10')) `
    "Arketip tablosu, OKLCH veya 60-30-10 icerigi eksik"

Assert-Test "DESIGN.template.md Tasarim Tezi, 4 ekran durumu, WCAG AA ve Takas Testi sablonunu icermeli" `
    (($tplRaw -match 'Tasarım Tezi') -and ($tplRaw -match 'WCAG AA') -and ($tplRaw -match ':focus-visible') -and ($tplRaw -match '375px') -and ($tplRaw -match 'loading') -and ($tplRaw -match 'empty') -and ($tplRaw -match 'error') -and ($tplRaw -match 'populated') -and ($tplRaw -match 'Takas Testi')) `
    "DESIGN.template.md icerigi eksik"

# ------------------------------------------------------------------------------
# GRUP 3: Persona, Lite & Anayasa Entegrasyonu
# ------------------------------------------------------------------------------
Write-Host "`n[Grup 3: Persona, /pro, /lite ve Anayasa Entegrasyonu]" -ForegroundColor Yellow

$criticRaw = Read-Utf8Text (Join-Path $ws "core\skills\pro\personas\design-critic.md")
$architectRaw = Read-Utf8Text (Join-Path $ws "core\skills\pro\personas\lead-architect.md")
$judgeRaw = Read-Utf8Text (Join-Path $ws "core\skills\pro\personas\supreme-judge.md")
$proRaw = Read-Utf8Text (Join-Path $ws "core\skills\pro\SKILL.md")
$bridgesRaw = Read-Utf8Text (Join-Path $ws "core\skills\pro\references\mcp_bridges.md")
$liteRaw = Read-Utf8Text (Join-Path $ws "core\skills\lite\SKILL.md")
$vlRaw = Read-Utf8Text (Join-Path $ws "core\skills\vigiles-light\SKILL.md")
$kurallarRaw = Read-Utf8Text (Join-Path $ws "KURALLAR.md")
$kurallarTplRaw = Read-Utf8Text (Join-Path $ws "core\templates\KURALLAR.template.md")

Assert-Test "design-critic.md .png ekran goruntusu ve read_file incelemesini zorunlu kilmali" `
    (($criticRaw -match '\.png') -and ($criticRaw -match 'read_file') -and ($criticRaw -match 'Özel Tester')) `
    "Gorsel kanit (.png / read_file / Ozel Tester) kurali eksik"

Assert-Test "design-critic.md Takas Testi, Red Dongusu ve DESIGN.md/Backend muafiyeti icermeli" `
    (($criticRaw -match 'Takas Testi') -and ($criticRaw -match 'Swap Test') -and ($criticRaw -match 'Red Döngüsü|rejection-loop\.md') -and ($criticRaw -match 'DESIGN\.md') -and ($criticRaw -match 'Backend.*CLI')) `
    "Takas Testi, Red Dongusu veya Backend/CLI muafiyeti eksik"

Assert-Test "lead-architect.md DESIGN.md ve Anti-Slop planlamasini icermeli" `
    (($architectRaw -match 'DESIGN\.md') -and ($architectRaw -match 'Anti-Slop')) `
    "lead-architect.md icinde DESIGN.md veya Anti-Slop yok"

Assert-Test "supreme-judge.md 5. Kosullu Kanat olarak design-critic.md ve DESIGN.md denetimini icermeli" `
    (($judgeRaw -match 'design-critic\.md') -and ($judgeRaw -match 'DESIGN\.md') -and ($judgeRaw -match 'Anti-Slop')) `
    "supreme-judge.md icinde design-critic.md veya DESIGN.md yok"

Assert-Test "pro/SKILL.md ve mcp_bridges.md DESIGN.md & node-figma entegrasyonunu icermeli" `
    (($proRaw -match 'DESIGN\.md') -and ($proRaw -match 'Anti-Slop') -and ($proRaw -match 'node-figma') -and ($bridgesRaw -match 'DESIGN\.md') -and ($bridgesRaw -match 'design-critic\.md') -and ($bridgesRaw -match 'node-figma')) `
    "pro/SKILL.md veya mcp_bridges.md entegrasyonu eksik"

Assert-Test "lite/SKILL.md ve vigiles-light/SKILL.md Anti-Slop & DESIGN.md hijyeni icermeli" `
    (($liteRaw -match 'DESIGN\.md') -and ($liteRaw -match 'Anti-Slop') -and ($vlRaw -match 'DESIGN\.md') -and ($vlRaw -match 'Anti-Slop')) `
    "lite veya vigiles-light icinde Anti-Slop/DESIGN.md yok"

Assert-Test "KURALLAR.md [KURAL-022] korunmali ve [KURAL-023] Anti-Slop kuralini icermeli" `
    (($kurallarRaw -match '\[KURAL-022\]') -and ($kurallarRaw -match '\[KURAL-023\]') -and ($kurallarRaw -match 'Anti-Slop') -and ($kurallarRaw -match 'DESIGN\.md') -and ($kurallarRaw -match 'node-figma') -and ($kurallarRaw -match 'design-critic\.md')) `
    "KURALLAR.md icinde [KURAL-022] veya [KURAL-023] eksik"

Assert-Test "KURALLAR.template.md [KURAL-022] korunmali ve [KURAL-023] Anti-Slop kuralini icermeli" `
    (($kurallarTplRaw -match '\[KURAL-022\]') -and ($kurallarTplRaw -match '\[KURAL-023\]') -and ($kurallarTplRaw -match 'Anti-Slop') -and ($kurallarTplRaw -match 'DESIGN\.md') -and ($kurallarTplRaw -match 'node-figma') -and ($kurallarTplRaw -match 'design-critic\.md')) `
    "KURALLAR.template.md icinde [KURAL-022] veya [KURAL-023] eksik"

# ------------------------------------------------------------------------------
# GRUP 4: sentinel_guard.ps1 node-figma Telemetri, UTF-8 BOM & Izolasyon
# ------------------------------------------------------------------------------
Write-Host "`n[Grup 4: sentinel_guard.ps1 node-figma Telemetri, BOM & Izolasyon]" -ForegroundColor Yellow

$sentinelPath = Join-Path $ws "core\scripts\sentinel_guard.ps1"
$ensurePath = Join-Path $ws "core\scripts\ensure_live_mission_control.ps1"
$hudHtmlPath = Join-Path $ws "core\templates\live_mission_control.html"

$sentinelBytes = if (Test-Path $sentinelPath) { [System.IO.File]::ReadAllBytes($sentinelPath) } else { @() }
$sentinelHasBom = ($sentinelBytes.Length -ge 3 -and $sentinelBytes[0] -eq 0xEF -and $sentinelBytes[1] -eq 0xBB -and $sentinelBytes[2] -eq 0xBF)
Assert-Test "core/scripts/sentinel_guard.ps1 UTF-8 BOM (EF BB BF) ile kaydedilmis olmali" `
    $sentinelHasBom "Ilk 3 byte EF BB BF degil!"

$hudHtmlRaw = Read-Utf8Text $hudHtmlPath
Assert-Test "live_mission_control.html id='node-figma', id='badge-figma', DESIGN.md ve Anti-Slop icermeli" `
    (($hudHtmlRaw -match 'id="node-figma"') -and ($hudHtmlRaw -match 'id="badge-figma"') -and ($hudHtmlRaw -match 'DESIGN\.md') -and ($hudHtmlRaw -match 'Anti-Slop')) `
    "HUD HTML icinde node-figma / badge-figma veya DESIGN.md / Anti-Slop aciklamasi eksik"

$runId = [System.Guid]::NewGuid().ToString("N").Substring(0, 8)
$tempBase = Join-Path ([System.IO.Path]::GetTempPath()) "vigiles_antislop_test_$runId"
$activeDir = Join-Path $tempBase "active_session"
$inactiveDir = Join-Path $tempBase "inactive_session"
$designCmdDir = Join-Path $tempBase "design_slash_session"

New-Item -ItemType Directory -Path $activeDir -Force | Out-Null
New-Item -ItemType Directory -Path $inactiveDir -Force | Out-Null
New-Item -ItemType Directory -Path $designCmdDir -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $activeDir ".vigiles_active"), "vigiles", [System.Text.Encoding]::UTF8)

try {
    # a) .vigiles_active VAR + write_file DESIGN.md -> node-figma & badge-figma
    $resA = Invoke-HookJson -scriptPath $sentinelPath -stateDirToClean $activeDir -payloadObj @{
        conversationId        = "antislop-a-$runId"
        artifactDirectoryPath = $activeDir
        workspacePaths        = @("C:\TestProj")
        toolCall              = @{
            name = "write_file"
            args = @{ Path = "C:\TestProj\DESIGN.md"; Content = "# TASARIM SOZLESMESI" }
        }
    }
    $nodeA = if ($resA.State) { $resA.State.activeNode } else { "null" }
    $badgeA = if ($resA.State -and $resA.State.badge) { $resA.State.badge.id } else { "null" }
    Assert-Test "Simulasyon (a): .vigiles_active VAR + write_file DESIGN.md -> node-figma & badge-figma" `
        (($resA.Stdout -match '"decision"\s*:\s*"allow"') -and ($nodeA -eq "node-figma") -and ($badgeA -eq "badge-figma")) `
        "activeNode=$nodeA | badge.id=$badgeA"

    # b) .vigiles_active VAR + edit_file nested DESIGN.md -> node-figma
    $resB = Invoke-HookJson -scriptPath $sentinelPath -stateDirToClean $activeDir -payloadObj @{
        conversationId        = "antislop-b-$runId"
        artifactDirectoryPath = $activeDir
        workspacePaths        = @("C:\TestProj")
        toolCall              = @{
            name = "edit_file"
            args = @{ Path = "C:\TestProj\src\styles\DESIGN.md"; Target = "old"; Replacement = "new" }
        }
    }
    $nodeB = if ($resB.State) { $resB.State.activeNode } else { "null" }
    Assert-Test "Simulasyon (b): .vigiles_active VAR + edit_file C:\TestProj\src\styles\DESIGN.md -> node-figma" `
        (($resB.Stdout -match '"decision"\s*:\s*"allow"') -and ($nodeB -eq "node-figma")) `
        "activeNode=$nodeB"

    # c) .vigiles_active VAR + read_file DESIGN.md -> node-architect (regresyon yok)
    $resC = Invoke-HookJson -scriptPath $sentinelPath -stateDirToClean $activeDir -payloadObj @{
        conversationId        = "antislop-c-$runId"
        artifactDirectoryPath = $activeDir
        workspacePaths        = @("C:\TestProj")
        toolCall              = @{
            name = "read_file"
            args = @{ Path = "C:\TestProj\DESIGN.md" }
        }
    }
    $nodeC = if ($resC.State) { $resC.State.activeNode } else { "null" }
    Assert-Test "Simulasyon (c): .vigiles_active VAR + read_file DESIGN.md -> node-architect (regresyon yok)" `
        (($resC.Stdout -match '"decision"\s*:\s*"allow"') -and ($nodeC -eq "node-architect")) `
        "activeNode=$nodeC"

    # d) .vigiles_active YOK + write_file DESIGN.md -> allow & live_state.json yok ([KURAL-019])
    $resD = Invoke-HookJson -scriptPath $sentinelPath -payloadObj @{
        conversationId        = "antislop-d-$runId"
        artifactDirectoryPath = $inactiveDir
        workspacePaths        = @("C:\TestProj")
        toolCall              = @{
            name = "write_file"
            args = @{ Path = "C:\TestProj\DESIGN.md"; Content = "# TASARIM SOZLESMESI" }
        }
    }
    $stateDExists = Test-Path (Join-Path $inactiveDir "live_state.json")
    Assert-Test "Simulasyon (d): .vigiles_active YOK + write_file DESIGN.md -> allow & telemetri yok (KURAL-019)" `
        (($resD.Stdout -match '"decision"\s*:\s*"allow"') -and (-not $stateDExists)) `
        "Stdout=$($resD.Stdout) | live_state.json=$stateDExists"

    # e) ensure_live_mission_control.ps1 + /design bir sayfa tasarla -> {} & .vigiles_active yok ([KURAL-019])
    $resE = Invoke-HookJson -scriptPath $ensurePath -payloadObj @{
        lastUserInput         = "/design bir sayfa tasarla"
        conversationId        = "antislop-e-$runId"
        artifactDirectoryPath = $designCmdDir
        workspacePaths        = @("C:\TestProj")
        invocationNum         = 1
    }
    $markerEExists = Test-Path (Join-Path $designCmdDir ".vigiles_active")
    Assert-Test "Simulasyon (e): ensure_live_mission_control + /design -> {} & .vigiles_active olusmaz (KURAL-019)" `
        (($resE.Stdout -eq "{}") -and (-not $markerEExists)) `
        "Stdout=$($resE.Stdout) | .vigiles_active=$markerEExists"

} finally {
    if (Test-Path $tempBase) {
        Remove-Item -Path $tempBase -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
$color = if ($global:failedCount -eq 0) { "Green" } else { "Red" }
Write-Host "TEST SONUCLARI: $global:passedCount Gecti | $global:failedCount Basarisiz" -ForegroundColor $color
Write-Host "==========================================================" -ForegroundColor Cyan

if ($global:failedCount -gt 0) {
    exit 1
} else {
    exit 0
}
