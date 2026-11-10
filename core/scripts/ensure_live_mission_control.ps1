param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8

$rawInput = [Console]::In.ReadToEnd()

if ([string]::IsNullOrWhiteSpace($rawInput)) {
    Write-Output "{}"
    exit 0
}

try {
    $payload = $rawInput | ConvertFrom-Json
} catch {
    Write-Output "{}"
    exit 0
}

# 1. Multi-turn icinde gereksiz tekrar calismayi engelle (Yalnizca kullanici komutunun ilk adiminda calis)
if ($payload.invocationNum -and [int]$payload.invocationNum -gt 1) {
    Write-Output "{}"
    exit 0
}

$userInput = if ($payload.lastUserInput) { $payload.lastUserInput.Trim() } else { "" }

# Yalnizca '/' ile baslayan komutlarda tetiklen (Orn: /live, /vigiles, /push vs.)
if (-not ($userInput -match '^\s*/')) {
    Write-Output "{}"
    exit 0
}

# Oturum ve dizin bilgilerini cikar
$conversationId = $payload.conversationId
$artifactDir = $payload.artifactDirectoryPath

if ([string]::IsNullOrWhiteSpace($artifactDir) -and -not [string]::IsNullOrWhiteSpace($conversationId)) {
    $artifactDir = "C:\Users\Dogukan\.gemini\antigravity\brain\$conversationId"
}

$configDir = Join-Path $HOME ".gemini\config"
$templatesDir = Join-Path $configDir "templates"
$scriptsDir = Join-Path $configDir "scripts"
$activeMissionFile = Join-Path $configDir "active_mission.json"

# 2. Aktif Gorev Kutugunu Guncelle (active_mission.json)
$missionInfo = @{
    conversationId        = $conversationId
    artifactDirectoryPath = $artifactDir
    workspacePaths        = $payload.workspacePaths
    lastCommand           = $userInput
    updatedAt             = (Get-Date).ToString("o")
}

try {
    $missionInfo | ConvertTo-Json -Depth 4 | Set-Content -Path $activeMissionFile -Encoding UTF8 -Force
} catch {}

# 3. Canli Dosyalari ve Artifact Dosyalarini Hazirla
if (-not [string]::IsNullOrWhiteSpace($artifactDir)) {
    if (-not (Test-Path $artifactDir)) {
        try { New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null } catch {}
    }

    # live_mission_control.html kopyala
    $destHtml = Join-Path $artifactDir "live_mission_control.html"
    $templateHtml = Join-Path $templatesDir "live_mission_control.html"
    $wsFallbackHtml = "C:\Users\Dogukan\Desktop\Antigravity Improvement\ui\live_mission_control.html"

    if (-not (Test-Path $destHtml)) {
        if (Test-Path $templateHtml) {
            Copy-Item $templateHtml $destHtml -Force
        } elseif (Test-Path $wsFallbackHtml) {
            Copy-Item $wsFallbackHtml $destHtml -Force
        }
    }

    # metadata.json (IDE yan paneli icin)
    $destMeta = Join-Path $artifactDir "live_mission_control.html.metadata.json"
    if (-not (Test-Path $destMeta)) {
        $metaObj = @{
            summary     = "Antigravity Canli Operasyon Merkezi (Live Mission Control)"
            updatedAt   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
            userFacing  = $true
        }
        try {
            $metaObj | ConvertTo-Json -Compress | Set-Content -Path $destMeta -Encoding UTF8 -Force
        } catch {}
    }

    # live_state.json ve live_state.js (Eger yoksa)
    $destJson = Join-Path $artifactDir "live_state.json"
    $destJs = Join-Path $artifactDir "live_state.js"
    if (-not (Test-Path $destJson)) {
        $cleanCmd = $userInput.Replace('"', '\"')
        $initState = @{
            step          = 1
            totalSteps    = 15
            activeNode    = "node-user"
            animClass     = "node-active-default"
            status        = "HAZIR"
            title         = "CANLI OPERASYON MERKEZI DEVREDE"
            sender        = "[1. SIZ (Sirket Sahibi)]"
            message       = "Canli Operasyon Merkezi baglandi: $cleanCmd"
            desc          = "Port 9999 SSE yayini ve Antigravity yan paneli aktif."
            timestamp     = (Get-Date).ToString("HH:mm:ss")
            badge         = @{ id = "badge-user"; text = "Hazir"; class = "bg-emerald-500/20 text-emerald-400 border-emerald-500/40 font-bold" }
            highlightPath = $null
            stats         = @{
                testsPassed    = 0
                testsFailed    = 0
                defectsOpen    = 0
                secretsBlocked = 0
                bloatBlocked   = 0
            }
        }
        $initStateJson = $initState | ConvertTo-Json -Depth 5 -Compress
        try {
            Set-Content -Path $destJson -Value $initStateJson -Encoding UTF8 -Force
            $jsWrap = "// Antigravity Canli Telemetri Kancasi`nwindow.__ANTIGRAVITY_STATE__ = $initStateJson;`nif (typeof window.onAntigravityStateUpdate === 'function') { window.onAntigravityStateUpdate(window.__ANTIGRAVITY_STATE__); }"
            Set-Content -Path $destJs -Value $jsWrap -Encoding UTF8 -Force
        } catch {}
    }
}

# 4. Telemetri Sunucusunu (Port 9999) Kontrol Et ve Baslat
$serverRunning = $false
try {
    $conn = Get-NetTCPConnection -LocalPort 9999 -State Listen -ErrorAction SilentlyContinue
    if ($conn) { $serverRunning = $true }
} catch {}

if (-not $serverRunning) {
    $serverScript = Join-Path $scriptsDir "telemetry_server.ps1"
    if (-not (Test-Path $serverScript)) {
        $serverScript = "C:\Users\Dogukan\Desktop\Antigravity Improvement\core\scripts\telemetry_server.ps1"
    }

    if (Test-Path $serverScript) {
        try {
            $cmdLine = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File `"$serverScript`""
            ([wmiclass]"win32_process").Create($cmdLine) | Out-Null
            Start-Sleep -Milliseconds 300
        } catch {
            Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File `"$serverScript`"" -WindowStyle Hidden
            Start-Sleep -Milliseconds 300
        }
    }
} else {
    try {
        $req = [System.Net.WebRequest]::Create("http://localhost:9999/set-active")
        $req.Method = "POST"
        $req.ContentType = "application/json; charset=utf-8"
        $req.Timeout = 200
        $activeJson = ($missionInfo | ConvertTo-Json -Compress)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($activeJson)
        $req.ContentLength = $bytes.Length
        $st = $req.GetRequestStream()
        $st.Write($bytes, 0, $bytes.Length)
        $st.Dispose()
        $res = $req.GetResponse()
        $res.Dispose()
    } catch {}
}

# 5. Tarayicida Canli Operasyon Merkezini Ac (Oturumda yalnizca bir kez)
if (-not [string]::IsNullOrWhiteSpace($artifactDir)) {
    $launchMarker = Join-Path $artifactDir ".live_mission_launched"
    if (-not (Test-Path $launchMarker)) {
        try {
            New-Item -ItemType File -Path $launchMarker -Force | Out-Null
            Start-Process "http://localhost:9999/"
        } catch {}
    }
}

# 6. Modeli Bilgilendir (Net ve sifir gecikmeli direktif)
$response = @{
    injectSteps = @(
        @{
            systemMessage = @{
                systemMessage = "[CANLI OPERASYON MERKEZI DEVREDE]: Canli Operasyon Merkezi Port 9999 ve tarayicida aninda baslatildi. live_mission_control.html hazirlandi. Herhangi bir dosya aramasi veya dogrulama yapmaniza gerek YOKTUR; dogrudan sonuca odaklanin ve yanit verin."
            }
        }
    )
}

Write-Output ($response | ConvertTo-Json -Depth 5 -Compress)
exit 0
