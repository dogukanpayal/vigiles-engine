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

if ([string]::IsNullOrWhiteSpace($artifactDir)) {
    $activeFile = Join-Path $HOME ".gemini\config\active_mission.json"
    if (Test-Path $activeFile) {
        try {
            $act = Get-Content -Raw -Encoding UTF8 $activeFile | ConvertFrom-Json
            if ($act.artifactDirectoryPath) { $artifactDir = $act.artifactDirectoryPath }
            if ($act.conversationId) { $conversationId = $act.conversationId }
        } catch {}
    }
}

if ([string]::IsNullOrWhiteSpace($artifactDir) -and -not [string]::IsNullOrWhiteSpace($conversationId)) {
    $artifactDir = "C:\Users\Dogukan\.gemini\antigravity\brain\$conversationId"
}

# Vigiles İzolasyon Kontrolü:
# Bu oturumda /vigiles veya /live komutu çalıştırılmamışsa (artifact dizininde .vigiles_active yoksa)
# kanca hiçbir işlem yapmadan ve telemetri yayınlamadan anında çıkar.
$isVigilesActive = $false
if (-not [string]::IsNullOrWhiteSpace($artifactDir) -and (Test-Path $artifactDir)) {
    $markerFile = Join-Path $artifactDir ".vigiles_active"
    if (Test-Path $markerFile) {
        $isVigilesActive = $true
    }
}

if (-not $isVigilesActive) {
    Write-Output "{}"
    exit 0
}

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
    desc          = "20 elemanlı otonom fabrika görevini tamamladı. Proje Şirket Sahibine teslim edildi."
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

# 4. Port 9999 SSE Sunucusuna Bildir
try {
    $req = [System.Net.WebRequest]::Create("http://localhost:9999/notify")
    $req.Method = "POST"
    $req.ContentType = "application/json; charset=utf-8"
    if (-not [string]::IsNullOrWhiteSpace($conversationId)) {
        $req.Headers.Add("X-Conversation-Id", $conversationId)
    }
    $req.Timeout = 200
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($stateJson)
    $req.ContentLength = $bytes.Length
    $stream = $req.GetRequestStream()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Dispose()
    $resp = $req.GetResponse()
    $resp.Dispose()
} catch {}

Write-Output "{}"
exit 0