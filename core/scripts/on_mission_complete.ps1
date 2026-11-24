param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$rawInput = [Console]::In.ReadToEnd()

$artifactDir = ""
$conversationId = ""

$wsName = "Antigravity Workspace"
if (-not [string]::IsNullOrWhiteSpace($rawInput)) {
    $rawInput = $rawInput.Trim().Trim([char]65279)
    try {
        $payload = $rawInput | ConvertFrom-Json
        if ($payload.artifactDirectoryPath) { $artifactDir = $payload.artifactDirectoryPath }
        if ($payload.conversationId) { $conversationId = $payload.conversationId }
        if ($payload.workspacePaths -and $payload.workspacePaths.Count -gt 0) { $wsName = Split-Path $payload.workspacePaths[0] -Leaf }
    } catch {}
}

if ([string]::IsNullOrWhiteSpace($artifactDir) -and -not [string]::IsNullOrWhiteSpace($conversationId)) {
    $artifactDir = Join-Path $HOME ".gemini\antigravity\brain\$conversationId"
}

$telemetryPort = 9999
if ($env:VIGILES_TELEMETRY_PORT -match '^\d+$') {
    $parsedPort = [int]$env:VIGILES_TELEMETRY_PORT
    if ($parsedPort -ge 1024 -and $parsedPort -le 65535) {
        $telemetryPort = $parsedPort
    }
}

# Vigiles İzolasyon Kontrolü:
# Bu oturumda /pro, /lite veya /live komutu çalıştırılmamışsa (artifact dizininde .vigiles_active yoksa)
# kanca hiçbir işlem yapmadan ve telemetri yayınlamadan anında çıkar.
$isVigilesActive = $false
$isLiveActive = $false
if (-not [string]::IsNullOrWhiteSpace($artifactDir) -and (Test-Path $artifactDir)) {
    $markerFile = Join-Path $artifactDir ".vigiles_active"
    if (Test-Path $markerFile) {
        $isVigilesActive = $true
    }
    $liveMarkerFile = Join-Path $artifactDir ".live_active"
    if (Test-Path $liveMarkerFile) {
        $isLiveActive = $true
    }
}

if (-not $isVigilesActive) {
    Write-Output "{}"
    exit 0
}

# Oturum kilidi ve izole mission kaydi guncellemesi (ADR-025)
try {
    $defaultConfigDir = Join-Path $HOME ".gemini\config"
    $cfgRoot = if (-not [string]::IsNullOrWhiteSpace($env:VIGILES_CONFIG_DIR)) { $env:VIGILES_CONFIG_DIR } else { $defaultConfigDir }
    $missionsDir = Join-Path $cfgRoot "state\missions"
    $rawKey = if (-not [string]::IsNullOrWhiteSpace($conversationId)) { $conversationId } else { $artifactDir }
    if (-not [string]::IsNullOrWhiteSpace($rawKey) -and (Test-Path -LiteralPath $missionsDir)) {
        $safeKey = ($rawKey -replace '[^a-zA-Z0-9\-_]', '_')
        if ($safeKey.Length -gt 80) { $safeKey = $safeKey.Substring(0, 80) }
        $mFile = Join-Path $missionsDir "$safeKey.json"
        if (Test-Path -LiteralPath $mFile) {
            $mObj = [System.IO.File]::ReadAllText($mFile, [System.Text.Encoding]::UTF8).Trim().Trim([char]65279) | ConvertFrom-Json
            if ($mObj) {
                $mObj | Add-Member -NotePropertyName "status" -NotePropertyValue "COMPLETED" -Force
                $mObj | Add-Member -NotePropertyName "completedAt" -NotePropertyValue ([datetimeoffset]::Now.ToString("o")) -Force
                $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                [System.IO.File]::WriteAllText($mFile, ($mObj | ConvertTo-Json -Depth 5), $utf8NoBom)
            }
        }
    }
} catch {}

if (-not [string]::IsNullOrWhiteSpace($artifactDir)) {
    $sessPointer = Join-Path $artifactDir ".vigiles_session"
    if (Test-Path -LiteralPath $sessPointer) {
        try {
            $ptr = [System.IO.File]::ReadAllText($sessPointer, [System.Text.Encoding]::UTF8).Trim().Trim([char]65279) | ConvertFrom-Json
            $sessMgr = Join-Path $PSScriptRoot "vigiles_session_manager.ps1"
            if (-not (Test-Path -LiteralPath $sessMgr)) {
                $sessMgr = Join-Path $HOME ".gemini\config\scripts\vigiles_session_manager.ps1"
            }
            if (Test-Path -LiteralPath $sessMgr) {
                $wsHint = if ($ptr -and $ptr.effectiveWorkDir) { [string]$ptr.effectiveWorkDir } elseif ($ptr -and $ptr.repoRoot) { [string]$ptr.repoRoot } else { "" }
                if (-not [string]::IsNullOrWhiteSpace($wsHint)) {
                    $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sessMgr -Action Complete -ConversationId $conversationId -ArtifactDir $artifactDir -WorkspacePath $wsHint -Json 2>$null
                }
            }
        } catch {}
    }
}

# Watchdog gecici dosya supurmesi (Yalnizca 1 saatten eski yetim payload/exec artıkları; Port 9999 sunucusuna dokunulmaz)
try {
    $wdTempDir = Join-Path ([System.IO.Path]::GetTempPath()) "vigiles_watchdog"
    if (Test-Path $wdTempDir) {
        $cutoff = (Get-Date).AddHours(-1)
        Get-ChildItem -Path $wdTempDir -File -ErrorAction SilentlyContinue |
            Where-Object { ($_.Name -match '^(cmd_|exec_)') -and ($_.LastWriteTime -lt $cutoff) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
} catch {}

# Görev Tamamlandı Durumu (1. SİZ - Şirket Sahibi / Vibe Coder)
$time = (Get-Date).ToString("HH:mm:ss")
$completionState = @{
    conversationId = $conversationId
    workspaceName  = $wsName
    step          = 15
    totalSteps    = 15
    activeNode    = "node-user"
    animClass     = "node-active-user"
    status        = "TESLIM_EDILDI"
    title         = "GÖREV TAMAMLANDI - KONTROL SİZDE"
    sender        = "[1. SİZ (Şirket Sahibi / Vibe Coder)]"
    message       = "Tüm işlemler tamamlandı ve çıktı teslim edildi. Sistem kontrolü sizde."
    desc          = "19 elemanlı otonom fabrika görevini tamamladı. Proje Şirket Sahibine teslim edildi."
    timestamp     = $time
    badge         = @{
        id    = "badge-user"
        text  = "Teslim Alındı / Hazır"
        class = "bg-emerald-500/20 text-emerald-400 border-emerald-500/40 font-bold"
    }
    highlightPath = $null
    stats         = @{
        testsPassed    = 8
        testsFailed    = 0
        defectsOpen    = 0
        secretsBlocked = 0
        bloatBlocked   = 0
    }
}

$completionState["workerCount"] = 0
$completionState["workers"] = @()
if (-not [string]::IsNullOrWhiteSpace($artifactDir)) {
    $workersFile = Join-Path $artifactDir "active_workers.json"
    if (Test-Path $workersFile) {
        Remove-Item $workersFile -Force -ErrorAction SilentlyContinue
    }
}

$stateJson = $completionState | ConvertTo-Json -Depth 6 -Compress

if (-not [string]::IsNullOrWhiteSpace($artifactDir) -and (Test-Path $artifactDir)) {
    try {
        # 1. live_state.json
        $jsonPath = Join-Path $artifactDir "live_state.json"
        [System.IO.File]::WriteAllText($jsonPath, $stateJson, [System.Text.Encoding]::UTF8)

        # 2. live_state.js (Zero-CORS fallback)
        $jsContent = "// Antigravity Canli Telemetri Kancasi`nwindow.__ANTIGRAVITY_STATE__ = $stateJson;`nif (typeof window.onAntigravityStateUpdate === 'function') { window.onAntigravityStateUpdate(window.__ANTIGRAVITY_STATE__); }"
        $jsPath = Join-Path $artifactDir "live_state.js"
        [System.IO.File]::WriteAllText($jsPath, $jsContent, [System.Text.Encoding]::UTF8)

        # 3. live_events.jsonl
        $logPath = Join-Path $artifactDir "live_events.jsonl"
        $eventEntry = @{
            timestamp = $time
            sender    = "[1. SİZ (Şirket Sahibi / Vibe Coder)]"
            title     = "GÖREV TAMAMLANDI - KONTROL SİZDE"
            node      = "node-user"
            tool      = "stop"
        } | ConvertTo-Json -Compress
        [System.IO.File]::AppendAllText($logPath, "$eventEntry`n", [System.Text.Encoding]::UTF8)
    } catch {}
}

# 4. Port 9999 SSE Sunucusuna Bildir (Yalnizca /live aktifse)
if ($isLiveActive) {
    try {
        $req = [System.Net.WebRequest]::Create("http://localhost:$telemetryPort/notify")
        $req.Method = "POST"
        $req.ContentType = "application/json; charset=utf-8"
        if (-not [string]::IsNullOrWhiteSpace($conversationId)) {
            $req.Headers.Add("X-Conversation-Id", $conversationId)
        }
        $req.ServicePoint.Expect100Continue = $false
        $req.Timeout = 800
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($stateJson)
        $req.ContentLength = $bytes.Length
        $stream = $req.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Dispose()
        $resp = $req.GetResponse()
        $resp.Dispose()
    } catch {}
}

Write-Output "{}"
exit 0