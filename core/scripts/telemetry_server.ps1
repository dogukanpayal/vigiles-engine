# telemetry_server.ps1
# Antigravity Canlı Operasyon Merkezi - Hafif SSE & HTTP Telemetri Dağıtım Servisi
# Port: 9999

param(
    [int]$Port = 9999,
    [string]$ArtifactDir = "C:\Users\Dogukan\.gemini\antigravity\brain\f6dee0d7-3f60-474d-8a94-ce06e0039c63"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$prefix = "http://localhost:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "🛰️ ANTIGRAVITY MISSION CONTROL TELEMETRI SUNUCUSU BASLATILDI" -ForegroundColor Cyan
    Write-Host "   URL: http://localhost:$Port/" -ForegroundColor Yellow
    Write-Host "   SSE: http://localhost:$Port/events" -ForegroundColor Yellow
    Write-Host "   Artifact: $ArtifactDir" -ForegroundColor Gray
    Write-Host "==========================================================" -ForegroundColor Green
} catch {
    Write-Host "HATA: Port $Port acilamadi: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Aktif SSE istemcileri ve son durum
$sseClients = [System.Collections.Generic.List[System.IO.StreamWriter]]::new()
$sseLock = [object]::new()
$latestStateJson = "{}"

# Başlangıç durumunu oku
$statePath = Join-Path $ArtifactDir "live_state.json"
if (Test-Path $statePath) {
    try { $latestStateJson = Get-Content -Raw -Encoding UTF8 $statePath } catch {}
}

function Broadcast-SSE([string]$jsonData) {
    [System.Threading.Monitor]::Enter($sseLock)
    try {
        $deadClients = @()
        $msg = "data: $jsonData`n`n"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)

        foreach ($client in $sseClients) {
            try {
                $client.BaseStream.Write($bytes, 0, $bytes.Length)
                $client.BaseStream.Flush()
            } catch {
                $deadClients += $client
            }
        }

        foreach ($dead in $deadClients) {
            $sseClients.Remove($dead) | Out-Null
            try { $dead.Dispose() } catch {}
        }
    } finally {
        [System.Threading.Monitor]::Exit($sseLock)
    }
}

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $req = $context.Request
        $res = $context.Response

        # CORS Başlıkları
        $res.AddHeader("Access-Control-Allow-Origin", "*")
        $res.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        $res.AddHeader("Access-Control-Allow-Headers", "Content-Type")

        if ($req.HttpMethod -eq "OPTIONS") {
            $res.StatusCode = 200
            $res.Close()
            continue
        }

        $rawUrl = $req.Url.AbsolutePath.ToLower()

        # 1. GET /events (Server-Sent Events)
        if ($rawUrl -eq "/events") {
            $res.ContentType = "text/event-stream; charset=utf-8"
            $res.AddHeader("Cache-Control", "no-cache")
            $res.AddHeader("Connection", "keep-alive")
            $res.StatusCode = 200

            $writer = New-Object System.IO.StreamWriter($res.OutputStream, [System.Text.Encoding]::UTF8)
            $writer.AutoFlush = $true

            # İlk bağlantı sinyali ve son durumu gönder
            $initMsg = ": connected`n`n"
            $writer.Write($initMsg)
            if (-not [string]::IsNullOrWhiteSpace($latestStateJson) -and $latestStateJson -ne "{}") {
                $writer.Write("data: $latestStateJson`n`n")
            }

            [System.Threading.Monitor]::Enter($sseLock)
            try {
                $sseClients.Add($writer)
                Write-Host "[SSE] Yeni istemci baglandi. Toplam: $($sseClients.Count)" -ForegroundColor DarkCyan
            } finally {
                [System.Threading.Monitor]::Exit($sseLock)
            }
            continue
        }

        # 2. POST /notify (Hook'tan gelen telemetri bildirimi)
        if ($rawUrl -eq "/notify" -and $req.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $reader.Dispose()

            if (-not [string]::IsNullOrWhiteSpace($body)) {
                $latestStateJson = $body
                Broadcast-SSE $body
            }

            $res.ContentType = "application/json"
            $res.StatusCode = 200
            $ackBytes = [System.Text.Encoding]::UTF8.GetBytes('{"status":"broadcasted"}')
            $res.OutputStream.Write($ackBytes, 0, $ackBytes.Length)
            $res.Close()
            continue
        }

        # 3. GET /state
        if ($rawUrl -eq "/state") {
            $res.ContentType = "application/json; charset=utf-8"
            $res.StatusCode = 200
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($latestStateJson)
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
            $res.Close()
            continue
        }

        # 4. GET / veya /index.html (HTML arayüzü sun)
        if ($rawUrl -eq "/" -or $rawUrl -eq "/index.html" -or $rawUrl -eq "/live") {
            $htmlPath = Join-Path $ArtifactDir "live_mission_control.html"
            if (Test-Path $htmlPath) {
                $htmlContent = Get-Content -Raw -Encoding UTF8 $htmlPath
                $res.ContentType = "text/html; charset=utf-8"
                $res.StatusCode = 200
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($htmlContent)
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $res.StatusCode = 404
                $err = [System.Text.Encoding]::UTF8.GetBytes("live_mission_control.html bulunamadi: $htmlPath")
                $res.OutputStream.Write($err, 0, $err.Length)
            }
            $res.Close()
            continue
        }

        # 5. GET /playground
        if ($rawUrl -eq "/playground") {
            $htmlPath = Join-Path $ArtifactDir "live_playground.html"
            if (Test-Path $htmlPath) {
                $htmlContent = Get-Content -Raw -Encoding UTF8 $htmlPath
                $res.ContentType = "text/html; charset=utf-8"
                $res.StatusCode = 200
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($htmlContent)
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $res.StatusCode = 404
                $err = [System.Text.Encoding]::UTF8.GetBytes("live_playground.html bulunamadi")
                $res.OutputStream.Write($err, 0, $err.Length)
            }
            $res.Close()
            continue
        }

        # 6. GET /status (Health Check)
        if ($rawUrl -eq "/status") {
            $res.ContentType = "application/json"
            $res.StatusCode = 200
            $statusObj = @{
                status = "running"
                port = $Port
                activeSseClients = $sseClients.Count
                timestamp = (Get-Date).ToString("o")
            }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(($statusObj | ConvertTo-Json -Compress))
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
            $res.Close()
            continue
        }

        # Bilinmeyen rotalar
        $res.StatusCode = 404
        $res.Close()
    }
    catch {
        Write-Host "Istek isleme hatasi: $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}
