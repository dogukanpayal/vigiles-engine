# telemetry_server.ps1
# Antigravity Canli Operasyon Merkezi - Dinamik SSE & HTTP Telemetri Dagitim Servisi
# Port: 9999

param(
    [int]$Port = 9999,
    [string]$ArtifactDir = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$configDir = Join-Path $HOME ".gemini\config"
$activeMissionFile = Join-Path $configDir "active_mission.json"
$globalTemplateHtml = Join-Path $configDir "templates\live_mission_control.html"
$workspaceHtmlFallback = "C:\Users\Dogukan\Desktop\Antigravity Improvement\ui\live_mission_control.html"

# Self-healing UTF-8 / Mojibake onarici
function Repair-Utf8String([string]$str) {
    if ([string]::IsNullOrWhiteSpace($str)) { return $str }
    if ($str -match 'Ã|Å|Ä') {
        try {
            $rawBytes = [System.Text.Encoding]::GetEncoding(1252).GetBytes($str)
            $candidate = [System.Text.Encoding]::UTF8.GetString($rawBytes)
            if (-not $candidate.Contains([char]0xFFFD)) {
                $str = $candidate
            }
        } catch {}

        # Guvenli Regex Kurtarma (Kalan veya karisik bozukluklari onarir)
        $str = $str -replace 'GÃ–REV|GÃ-REV', 'GÖREV' `
                    -replace 'SÄ°Z|SÃ°Z', 'SİZ' `
                    -replace 'ÅžÄ°RKET|ÅŽÄ°RKET|ÅžİRKET|ÅŽİRKET', 'ŞİRKET' `
                    -replace 'Åžirket|ÅŽirket', 'Şirket' `
                    -replace 'TÃ¼m', 'Tüm' `
                    -replace 'iÅŸlemler', 'işlemler' `
                    -replace 'tamamlandÄ±', 'tamamlandı' `
                    -replace 'Ã§Ä±ktÄ±', 'çıktı' `
                    -replace 'kontrolÃ¼', 'kontrolü' `
                    -replace 'elemanlÄ±', 'elemanlı' `
                    -replace 'gÃ¶revini', 'görevini' `
                    -replace 'AlÄ±ndÄ±', 'Alındı' `
                    -replace 'HazÄ±r', 'Hazır' `
                    -replace 'Åž|ÅŽ', 'Ş' `
                    -replace 'ÅŸ', 'ş' `
                    -replace 'Ä°|Ã°', 'İ' `
                    -replace 'Ä±|Ã±', 'ı' `
                    -replace 'Ã–|Ã-', 'Ö' `
                    -replace 'Ã¶', 'ö' `
                    -replace 'Ãœ', 'Ü' `
                    -replace 'Ã¼', 'ü' `
                    -replace 'Ã‡', 'Ç' `
                    -replace 'Ã§', 'ç' `
                    -replace 'Äž|ÄŽ', 'Ğ' `
                    -replace 'ÄŸ', 'ğ'
    }
    return $str
}

if ([string]::IsNullOrWhiteSpace($ArtifactDir) -and (Test-Path $activeMissionFile)) {
    try {
        $act = Get-Content -Raw -Encoding UTF8 $activeMissionFile | ConvertFrom-Json
        if ($act.artifactDirectoryPath) {
            $ArtifactDir = $act.artifactDirectoryPath
        }
    } catch {}
}

$prefix = "http://localhost:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "🛰️ ANTIGRAVITY MISSION CONTROL TELEMETRI SUNUCUSU BASLATILDI" -ForegroundColor Cyan
    Write-Host "   URL: http://localhost:$Port/" -ForegroundColor Yellow
    Write-Host "   SSE: http://localhost:$Port/events" -ForegroundColor Yellow
    Write-Host "   Active Artifact: $ArtifactDir" -ForegroundColor Gray
    Write-Host "==========================================================" -ForegroundColor Green
} catch {
    Write-Host "HATA: Port $Port acilamadi: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$sseClients = [System.Collections.Generic.List[System.IO.StreamWriter]]::new()
$sseLock = [object]::new()
$latestStateJson = "{}"

if (-not [string]::IsNullOrWhiteSpace($ArtifactDir)) {
    $statePath = Join-Path $ArtifactDir "live_state.json"
    if (Test-Path $statePath) {
        try {
            $latestStateJson = [System.IO.File]::ReadAllText($statePath, [System.Text.Encoding]::UTF8)
            $latestStateJson = Repair-Utf8String $latestStateJson
        } catch {}
    }
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
    $context = $null
    $rawUrl = ""
    try {
        $context = $listener.GetContext()
        $req = $context.Request
        $res = $context.Response

        $res.AddHeader("Access-Control-Allow-Origin", "*")
        $res.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS, HEAD")
        $res.AddHeader("Access-Control-Allow-Headers", "Content-Type")

        if ($req.HttpMethod -eq "OPTIONS") {
            $res.StatusCode = 200
            $res.ContentLength64 = 0
            $res.Close()
            continue
        }

        $rawUrl = $req.Url.AbsolutePath.ToLower()
        $isHead = ($req.HttpMethod -eq "HEAD")

        # 1. GET /events (Server-Sent Events)
        if ($rawUrl -eq "/events") {
            $res.ContentType = "text/event-stream; charset=utf-8"
            $res.AddHeader("Cache-Control", "no-cache")
            $res.AddHeader("Connection", "keep-alive")
            $res.StatusCode = 200

            $writer = New-Object System.IO.StreamWriter($res.OutputStream, [System.Text.Encoding]::UTF8)
            $writer.AutoFlush = $true

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

        # 2. POST /notify
        if ($rawUrl -eq "/notify" -and $req.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $reader.Dispose()

            if (-not [string]::IsNullOrWhiteSpace($body)) {
                $body = Repair-Utf8String $body
                $latestStateJson = $body
                Broadcast-SSE $body
            }

            $res.ContentType = "application/json; charset=utf-8"
            $res.StatusCode = 200
            $ackBytes = [System.Text.Encoding]::UTF8.GetBytes('{"status":"broadcasted"}')
            $res.ContentLength64 = $ackBytes.Length
            $res.OutputStream.Write($ackBytes, 0, $ackBytes.Length)
            $res.Close()
            continue
        }

        # 3. POST /set-active
        if ($rawUrl -eq "/set-active" -and $req.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $reader.Dispose()

            try {
                $obj = $body | ConvertFrom-Json
                if ($obj.artifactDirectoryPath) {
                    $ArtifactDir = $obj.artifactDirectoryPath
                    Write-Host "[ROUTER] Aktif Gorev Dizini Guncellendi: $ArtifactDir" -ForegroundColor Cyan
                    $statePath = Join-Path $ArtifactDir "live_state.json"
                    if (Test-Path $statePath) {
                        try {
                            $latestStateJson = [System.IO.File]::ReadAllText($statePath, [System.Text.Encoding]::UTF8)
                            $latestStateJson = Repair-Utf8String $latestStateJson
                            Broadcast-SSE $latestStateJson
                        } catch {}
                    }
                }
            } catch {}

            $res.ContentType = "application/json; charset=utf-8"
            $res.StatusCode = 200
            $ackBytes = [System.Text.Encoding]::UTF8.GetBytes('{"status":"active_updated"}')
            $res.ContentLength64 = $ackBytes.Length
            $res.OutputStream.Write($ackBytes, 0, $ackBytes.Length)
            $res.Close()
            continue
        }

        # 4. GET /state
        if ($rawUrl -eq "/state") {
            $res.ContentType = "application/json; charset=utf-8"
            $res.StatusCode = 200
            $cleanState = Repair-Utf8String $latestStateJson
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($cleanState)
            $res.ContentLength64 = $bytes.Length
            if (-not $isHead) {
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            $res.Close()
            continue
        }

        # 5. GET / veya /index.html veya /live
        if ($rawUrl -eq "/" -or $rawUrl -eq "/index.html" -or $rawUrl -eq "/live") {
            $candidates = [System.Collections.Generic.List[string]]::new()
            $candidates.Add($globalTemplateHtml)
            $candidates.Add($workspaceHtmlFallback)
            if (-not [string]::IsNullOrWhiteSpace($ArtifactDir)) {
                $candidates.Add((Join-Path $ArtifactDir "live_mission_control.html"))
            }

            $foundPath = $null
            foreach ($cp in $candidates) {
                if (-not [string]::IsNullOrWhiteSpace($cp) -and (Test-Path $cp)) {
                    $foundPath = $cp
                    break
                }
            }

            if ($foundPath) {
                $htmlContent = [System.IO.File]::ReadAllText($foundPath, [System.Text.Encoding]::UTF8)
                $res.ContentType = "text/html; charset=utf-8"
                $res.StatusCode = 200
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($htmlContent)
                $res.ContentLength64 = $bytes.Length
                if (-not $isHead) {
                    $res.OutputStream.Write($bytes, 0, $bytes.Length)
                }
            } else {
                $res.StatusCode = 404
                $err = [System.Text.Encoding]::UTF8.GetBytes("live_mission_control.html bulunamadi")
                $res.ContentLength64 = $err.Length
                if (-not $isHead) {
                    $res.OutputStream.Write($err, 0, $err.Length)
                }
            }
            $res.Close()
            continue
        }

        # 6. GET /playground
        if ($rawUrl -eq "/playground") {
            $candidates = [System.Collections.Generic.List[string]]::new()
            if (-not [string]::IsNullOrWhiteSpace($ArtifactDir)) {
                $candidates.Add((Join-Path $ArtifactDir "live_playground.html"))
            }
            $candidates.Add((Join-Path $configDir "templates\live_playground.html"))
            $candidates.Add("C:\Users\Dogukan\Desktop\Antigravity Improvement\ui\live_playground.html")

            $foundPath = $null
            foreach ($cp in $candidates) {
                if (-not [string]::IsNullOrWhiteSpace($cp) -and (Test-Path $cp)) {
                    $foundPath = $cp
                    break
                }
            }

            if ($foundPath) {
                $htmlContent = [System.IO.File]::ReadAllText($foundPath, [System.Text.Encoding]::UTF8)
                $res.ContentType = "text/html; charset=utf-8"
                $res.StatusCode = 200
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($htmlContent)
                $res.ContentLength64 = $bytes.Length
                if (-not $isHead) {
                    $res.OutputStream.Write($bytes, 0, $bytes.Length)
                }
            } else {
                $res.StatusCode = 404
                $err = [System.Text.Encoding]::UTF8.GetBytes("live_playground.html bulunamadi")
                $res.ContentLength64 = $err.Length
                if (-not $isHead) {
                    $res.OutputStream.Write($err, 0, $err.Length)
                }
            }
            $res.Close()
            continue
        }

        # 7. GET /status (Health Check)
        if ($rawUrl -eq "/status") {
            $res.ContentType = "application/json; charset=utf-8"
            $res.StatusCode = 200
            $statusObj = @{
                status = "running"
                port = $Port
                activeArtifactDir = $ArtifactDir
                activeSseClients = $sseClients.Count
                timestamp = (Get-Date).ToString("o")
            }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes(($statusObj | ConvertTo-Json -Compress))
            $res.ContentLength64 = $bytes.Length
            if (-not $isHead) {
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            $res.Close()
            continue
        }

        # Bilinmeyen rotalar
        $res.StatusCode = 404
        $res.ContentLength64 = 0
        $res.Close()
    }
    catch {
        Write-Host "Istek isleme hatasi: $($_.Exception.Message)" -ForegroundColor DarkGray
        if ($context -and $context.Response -and $rawUrl -ne "/events") {
            try { $context.Response.Close() } catch {}
        }
    }
}