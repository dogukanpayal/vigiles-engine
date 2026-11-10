# telemetry_server.ps1
# Antigravity Canli Operasyon Merkezi - Coklu Oturum (Multi-Session) SSE & HTTP Telemetri Dagitim Servisi
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

# Insan-Okur Sohbet Basligi Cozucusu (%100 Antigravity Aynasi)
function Get-ConversationDisplayName([string]$cid, [string]$wsName, [string]$fallbackTitle) {
    if ([string]::IsNullOrWhiteSpace($cid)) { return "Antigravity Sohbet" }

    if ($cid -match '^test-') { return "🧪 [Test] $cid" }
    if ($cid -match '^chaos-') { return "🐒 [Kaos] $cid" }

    $artDir = Join-Path $HOME ".gemini\antigravity\brain\$cid"

    # 1. Once Transcript'ten kullanicinin klavyeden girdigi ilk istemi oku (%100 Antigravity Aynasi)
    $tPath = Join-Path $artDir ".system_generated\logs\transcript.jsonl"
    $rawUserText = ""
    if (Test-Path $tPath) {
        try {
            $file = [System.IO.File]::Open($tPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $reader = New-Object System.IO.StreamReader($file, [System.Text.Encoding]::UTF8)
            $lCount = 0
            while (-not $reader.EndOfStream -and $lCount -lt 10) {
                $line = $reader.ReadLine()
                $lCount++
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    try {
                        $obj = $line | ConvertFrom-Json
                        if ($obj.content -match '<USER_REQUEST>\s*([\s\S]*?)\s*</USER_REQUEST>') {
                            $rawUserText = $matches[1].Trim()
                            break
                        }
                    } catch {}
                }
            }
            $reader.Dispose()
            $file.Dispose()
        } catch {}
    }

    if (-not [string]::IsNullOrWhiteSpace($rawUserText)) {
        $clean = ($rawUserText -replace '[\r\n]+', ' ').Trim()
        $clean = ($clean -replace '^(\\+n)+', '').Trim()
        if ($clean -match '^@\[.*?([^\\/]+)\]\s*(.*)') {
            $f = $matches[1]
            $r = $matches[2].Trim()
            $clean = if ($r) { $f + ": " + $r } else { $f }
        }
        $clean = ($clean -replace '^\s*/[a-zA-Z0-9\-_]+\s*', '').Trim()

        if ($clean.Length -gt 36) {
            return $clean.Substring(0, 33) + "..."
        }
        if (-not [string]::IsNullOrWhiteSpace($clean)) {
            return $clean
        }
    }

    # 2. transcript yoksa DURUM.md gorev adina bak
    $artDurum = Join-Path $artDir "DURUM.md"
    if (Test-Path $artDurum) {
        try {
            $lines = Get-Content $artDurum -TotalCount 20
            foreach ($line in $lines) {
                if ($line -match '\*\*Görev Adı:\*\*\s*(.+)') {
                    $gName = $matches[1].Trim()
                    if ($gName -match '—\s*(.+)') { $gName = $matches[1].Trim() }
                    elseif ($gName -match ':\s*(.+)') { $gName = $matches[1].Trim() }
                    if ($gName.Length -gt 36) { $gName = $gName.Substring(0, 33) + "..." }
                    if (-not [string]::IsNullOrWhiteSpace($gName)) {
                        return $gName
                    }
                }
            }
        } catch {}
    }

    if (-not [string]::IsNullOrWhiteSpace($fallbackTitle) -and 
        $fallbackTitle -notmatch '^(Canli|CANLI|OTURUM|GÖREV TAMAMLANDI)') {
        if ($fallbackTitle.Length -gt 36) { return $fallbackTitle.Substring(0, 33) + "..." }
        return $fallbackTitle
    }

    $short = if ($cid.Length -gt 8) { $cid.Substring(0, 8) } else { $cid }
    return "Sohbet ($short)"
}

# --- ANTIGRAVITY BRAIN AUTO-DISCOVERY & CACHE (TÜM SOHBETLERİ KEŞFETME) ---
$discoveredArchiveCache = [System.Collections.Generic.List[hashtable]]::new()
$lastDiscoveryTime = [datetime]::MinValue
$discoveryCacheExpirySec = 15

function Get-DiscoveredArchiveSessions([System.Collections.Concurrent.ConcurrentDictionary[string, hashtable]]$activeSessionsMap) {
    $now = Get-Date
    if (($now - $script:lastDiscoveryTime).TotalSeconds -lt $script:discoveryCacheExpirySec -and $script:discoveredArchiveCache.Count -gt 0) {
        $cachedFresh = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($item in $script:discoveredArchiveCache) {
            if (-not $activeSessionsMap.ContainsKey($item.conversationId)) {
                $cachedFresh.Add($item)
            }
        }
        return $cachedFresh
    }

    $brainBaseDir = Join-Path $HOME ".gemini\antigravity\brain"
    if (-not (Test-Path $brainBaseDir)) { return @() }

    $dirs = @(Get-ChildItem -Path $brainBaseDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^[a-f0-9\-]{36}$' })
    if ($dirs.Count -eq 0) { return @() }

    # Son dokunulma tarihine göre azalan sırala (en güncel en üstte)
    $dirs = @($dirs | Sort-Object LastWriteTime -Descending)

    $newList = [System.Collections.Generic.List[hashtable]]::new()
    $returnList = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($d in $dirs) {
        $cid = $d.Name

        # SADECE GERÇEK KULLANICI SOHBETLERİNİ AL (Alt işçi / Subagent görevlerini filtrele)
        $tPath = Join-Path $d.FullName '.system_generated\logs\transcript.jsonl'
        $durumPath = Join-Path $d.FullName 'DURUM.md'
        $isUserChat = $false

        if (Test-Path $durumPath) {
            $isUserChat = $true
        }

        if (-not $isUserChat -and (Test-Path $tPath)) {
            try {
                $file = [System.IO.File]::Open($tPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $reader = New-Object System.IO.StreamReader($file, [System.Text.Encoding]::UTF8)
                $lCount = 0
                while (-not $reader.EndOfStream -and $lCount -lt 10) {
                    $line = $reader.ReadLine()
                    $lCount++
                    if (-not [string]::IsNullOrWhiteSpace($line) -and $line -match '<USER_REQUEST>') {
                        $isUserChat = $true
                        break
                    }
                }
                $reader.Dispose()
                $file.Dispose()
            } catch {}
        }

        # Eğer kullanıcı komutu veya DURUM.md yoksa bu bir arka plan alt işçisidir (subagent); menüye ekleme!
        if (-not $isUserChat) {
            continue
        }

        $lastWrite = $d.LastWriteTime
        $timeStr = $lastWrite.ToString("HH:mm")
        $dateStr = $lastWrite.ToString("dd.MM")

        $cTitle = Get-ConversationDisplayName -cid $cid -wsName "Antigravity Workspace" -fallbackTitle ""
        if ([string]::IsNullOrWhiteSpace($cTitle) -or $cTitle -eq "Geçmiş Sohbet") {
            $shortCid = if ($cid.Length -gt 8) { $cid.Substring(0, 8) + "..." } else { $cid }
            $cTitle = "Sohbet ($shortCid)"
        }
        $shortCid = if ($cid.Length -gt 8) { $cid.Substring(0, 8) + "..." } else { $cid }

        $entry = @{
            conversationId = $cid
            shortId        = $shortCid
            chatTitle      = $cTitle
            workspaceName  = "Antigravity Workspace"
            title          = $cTitle
            sender         = "Antigravity"
            status         = "ARŞİV"
            step           = 0
            totalSteps     = 0
            category       = "archive"
            isArchived     = $true
            isTest         = $false
            timeStr        = "$dateStr $timeStr"
            updatedAt      = $lastWrite.ToString("o")
            createdAt      = $d.CreationTime.ToString("o")
            sessionNumber  = "Arşiv"
        }
        $newList.Add($entry)

        if (-not $activeSessionsMap.ContainsKey($cid)) {
            $returnList.Add($entry)
        }
    }

    $script:discoveredArchiveCache = $newList
    $script:lastDiscoveryTime = $now
    return $returnList
}

# --- COKLU OTURUM BELLEK HAVUZU (MULTI-SESSION REPOSITORY) ---
$sessions = [System.Collections.Concurrent.ConcurrentDictionary[string, hashtable]]::new()
$activeConversationId = ""

if ([string]::IsNullOrWhiteSpace($ArtifactDir) -and (Test-Path $activeMissionFile)) {
    try {
        $act = Get-Content -Raw -Encoding UTF8 $activeMissionFile | ConvertFrom-Json
        if ($act.artifactDirectoryPath) {
            $ArtifactDir = $act.artifactDirectoryPath
        }
        if ($act.conversationId) {
            $activeConversationId = $act.conversationId
        }
    } catch {}
}

$prefix = "http://localhost:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
    Write-Host "==========================================================" -ForegroundColor Green
    Write-Host "🛰️ ANTIGRAVITY MISSION CONTROL TELEMETRI SUNUCUSU (MULTI-SESSION)" -ForegroundColor Cyan
    Write-Host "   URL: http://localhost:$Port/" -ForegroundColor Yellow
    Write-Host "   SSE: http://localhost:$Port/events" -ForegroundColor Yellow
    Write-Host "   Sessions: http://localhost:$Port/sessions" -ForegroundColor Yellow
    Write-Host "   Active Artifact: $ArtifactDir" -ForegroundColor Gray
    Write-Host "==========================================================" -ForegroundColor Green
} catch {
    Write-Host "HATA: Port $Port acilamadi: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$sseClients = [System.Collections.Generic.List[hashtable]]::new()
$sseLock = [object]::new()
$latestStateJson = "{}"

if (-not [string]::IsNullOrWhiteSpace($ArtifactDir)) {
    $statePath = Join-Path $ArtifactDir "live_state.json"
    if (Test-Path $statePath) {
        try {
            $latestStateJson = [System.IO.File]::ReadAllText($statePath, [System.Text.Encoding]::UTF8)
            $latestStateJson = Repair-Utf8String $latestStateJson
            if (-not [string]::IsNullOrWhiteSpace($activeConversationId)) {
                $initObj = $latestStateJson | ConvertFrom-Json
                $sessions[$activeConversationId] = @{
                    conversationId = $activeConversationId
                    workspaceName  = "Antigravity Workspace"
                    title          = if ($initObj.title) { $initObj.title } else { "Canli Operasyon" }
                    sender         = if ($initObj.sender) { $initObj.sender } else { "Antigravity" }
                    status         = if ($initObj.status) { $initObj.status } else { "HAZIR" }
                    step           = if ($initObj.step) { $initObj.step } else { 1 }
                    totalSteps     = if ($initObj.totalSteps) { $initObj.totalSteps } else { 15 }
                    createdAt      = (Get-Date).ToString("o")
                    sessionIndex   = 1
                    updatedAt      = (Get-Date).ToString("o")
                    state          = $initObj
                }
            }
        } catch {}
    }
}

# Hedefli veya Genel SSE Yayini (Cross-Talk Engeli)
function Broadcast-SSE([string]$jsonData, [string]$targetCid = $null, [bool]$broadcastToUnfiltered = $true) {
    [System.Threading.Monitor]::Enter($sseLock)
    try {
        $deadClients = @()
        $msg = "data: $jsonData`n`n"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)

        foreach ($client in $sseClients) {
            $shouldSend = $false
            if ([string]::IsNullOrWhiteSpace($targetCid)) {
                $shouldSend = $true
            } elseif ([string]::IsNullOrWhiteSpace($client.FilterCid) -or $client.FilterCid -eq "all") {
                $shouldSend = $broadcastToUnfiltered
            } elseif ($client.FilterCid -eq $targetCid) {
                $shouldSend = $true
            }

            if ($shouldSend) {
                try {
                    $client.Writer.BaseStream.Write($bytes, 0, $bytes.Length)
                    $client.Writer.BaseStream.Flush()
                } catch {
                    $deadClients += $client
                }
            }
        }

        foreach ($dead in $deadClients) {
            $sseClients.Remove($dead) | Out-Null
            try { $dead.Writer.Dispose() } catch {}
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
        $res.AddHeader("Access-Control-Allow-Headers", "Content-Type, X-Conversation-Id")

        if ($req.HttpMethod -eq "OPTIONS") {
            $res.StatusCode = 200
            $res.ContentLength64 = 0
            $res.Close()
            continue
        }

        $rawUrl = $req.Url.AbsolutePath.ToLower()
        $isHead = ($req.HttpMethod -eq "HEAD")

        # 1. GET /events (Server-Sent Events - Oturum Filtreli veya Genel)
        if ($rawUrl -eq "/events") {
            $res.ContentType = "text/event-stream; charset=utf-8"
            $res.AddHeader("Cache-Control", "no-cache")
            $res.AddHeader("Connection", "keep-alive")
            $res.StatusCode = 200

            $writer = New-Object System.IO.StreamWriter($res.OutputStream, [System.Text.Encoding]::UTF8)
            $writer.AutoFlush = $true

            $filterCid = $null
            if ($req.Url.Query -and $req.Url.Query -match 'cid=([a-zA-Z0-9\-_]+)') {
                $filterCid = $matches[1]
            }

            $initMsg = ": connected`n`n"
            $writer.Write($initMsg)

            # Hedef oturumun o anki durumunu ilet (Varsa)
            if (-not [string]::IsNullOrWhiteSpace($filterCid)) {
                if ($sessions.ContainsKey($filterCid) -and $sessions[$filterCid].state) {
                    $initialState = ($sessions[$filterCid].state | ConvertTo-Json -Depth 6 -Compress)
                    $initialState = Repair-Utf8String $initialState
                    $writer.Write("data: $initialState`n`n")
                }
            } elseif (-not [string]::IsNullOrWhiteSpace($latestStateJson) -and $latestStateJson -ne "{}") {
                # Filtresiz genel baglantiysa son durumu gonder
                $initialState = Repair-Utf8String $latestStateJson
                $writer.Write("data: $initialState`n`n")
            }

            $clientRecord = @{
                Writer      = $writer
                FilterCid   = $filterCid
                ConnectedAt = (Get-Date)
            }

            [System.Threading.Monitor]::Enter($sseLock)
            try {
                $sseClients.Add($clientRecord)
                $cidNote = if ($filterCid) { " (Filtre: $filterCid)" } else { " (Global)" }
                Write-Host "[SSE] Yeni istemci baglandi$cidNote. Toplam: $($sseClients.Count)" -ForegroundColor DarkCyan
            } finally {
                [System.Threading.Monitor]::Exit($sseLock)
            }
            continue
        }

        # 2. POST /notify (Coklu Oturum Bildirim Yonlendiricisi)
        if ($rawUrl -eq "/notify" -and $req.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $reader.Dispose()

            if (-not [string]::IsNullOrWhiteSpace($body)) {
                $body = Repair-Utf8String $body
                $latestStateJson = $body

                $cid = ""
                $wsName = "Antigravity Workspace"
                try {
                    $parsed = $body | ConvertFrom-Json
                    $cid = if ($parsed.conversationId) { [string]$parsed.conversationId }
                           elseif ($parsed.cid) { [string]$parsed.cid }
                           elseif ($req.Headers["X-Conversation-Id"]) { [string]$req.Headers["X-Conversation-Id"] }
                           else { $activeConversationId }

                    if ([string]::IsNullOrWhiteSpace($cid)) { $cid = "default" }
                    if ($parsed.workspaceName) { $wsName = [string]$parsed.workspaceName }

                    $cTitle = if ($parsed.chatTitle) { [string]$parsed.chatTitle }
                              else { Get-ConversationDisplayName -cid $cid -wsName $wsName -fallbackTitle $parsed.title }

                    $existing = $null
                    $firstSeen = (Get-Date).ToString("o")
                    $fixedIndex = 0
                    if ($sessions.TryGetValue($cid, [ref]$existing)) {
                        if ($existing.createdAt) { $firstSeen = $existing.createdAt }
                        if ($existing.sessionIndex) { $fixedIndex = [int]$existing.sessionIndex }
                    }
                    if ($fixedIndex -eq 0 -and $cid -notmatch '^(test-|chaos-)') {
                        $userSessions = @($sessions.Values | Where-Object { $_.conversationId -notmatch '^(test-|chaos-)' })
                        $fixedIndex = $userSessions.Count + 1
                    }

                    $sessionEntry = @{
                        conversationId = $cid
                        shortId        = if ($cid.Length -gt 8) { $cid.Substring(0, 8) + "..." } else { $cid }
                        chatTitle      = $cTitle
                        workspaceName  = $wsName
                        title          = if ($parsed.title) { [string]$parsed.title } else { "Canli Operasyon" }
                        sender         = if ($parsed.sender) { [string]$parsed.sender } else { "Antigravity" }
                        status         = if ($parsed.status) { [string]$parsed.status } else { "CALISIYOR" }
                        step           = if ($parsed.step) { [int]$parsed.step } else { 1 }
                        totalSteps     = if ($parsed.totalSteps) { [int]$parsed.totalSteps } else { 15 }
                        createdAt      = $firstSeen
                        sessionIndex   = $fixedIndex
                        updatedAt      = (Get-Date).ToString("o")
                        state          = $parsed
                    }
                    $sessions[$cid] = $sessionEntry
                    $activeConversationId = $cid
                } catch {}

                # Yalnizca ilgili sohbetin istemcilerine veya filtre belirtmeyenlere yay
                Broadcast-SSE -jsonData $body -targetCid $cid
            }

            $res.ContentType = "application/json; charset=utf-8"
            $res.StatusCode = 200
            $ackBytes = [System.Text.Encoding]::UTF8.GetBytes('{"status":"broadcasted"}')
            $res.ContentLength64 = $ackBytes.Length
            $res.OutputStream.Write($ackBytes, 0, $ackBytes.Length)
            $res.Close()
            continue
        }

        # 3.1 POST /delete-session veya DELETE /sessions (Manuel Oturum Kapatma)
        if ($rawUrl -like "/delete-session*" -or ($rawUrl -like "/sessions*" -and $req.HttpMethod -eq "DELETE")) {
            $delCid = ""
            if ($rawUrl -match 'cid=([a-zA-Z0-9\-_]+)') {
                $delCid = $matches[1]
            } else {
                try {
                    $reader = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
                    $body = $reader.ReadToEnd()
                    $reader.Dispose()
                    $delObj = $body | ConvertFrom-Json
                    if ($delObj.conversationId) { $delCid = $delObj.conversationId }
                    elseif ($delObj.cid) { $delCid = $delObj.cid }
                } catch {}
            }

            if (-not [string]::IsNullOrWhiteSpace($delCid) -and $sessions.ContainsKey($delCid)) {
                $discard = $null
                $sessions.TryRemove($delCid, [ref]$discard) | Out-Null
            }

            $res.ContentType = "application/json; charset=utf-8"
            $res.StatusCode = 200
            $ackBytes = [System.Text.Encoding]::UTF8.GetBytes('{"status":"deleted"}')
            $res.ContentLength64 = $ackBytes.Length
            $res.OutputStream.Write($ackBytes, 0, $ackBytes.Length)
            $res.Close()
            continue
        }

        # 3. GET /sessions (Aktif Oturum Listesi - Akilli Baslik ve Siralama)
        if ($rawUrl -like "/sessions*") {
            $res.ContentType = "application/json; charset=utf-8"
            $res.StatusCode = 200

            # Otomatik Çöp Toplayıcı (Garbage Collection):
            # Diskte brain/<cid> klasörü bulunmayan veya silinmiş oturumları bellekten temizle
            # İstisna: Test oturumları (test- / chaos-) korunur.
            $brainBaseDir = Join-Path $HOME ".gemini\antigravity\brain"
            $toRemove = [System.Collections.Generic.List[string]]::new()
            
            foreach ($k in $sessions.Keys) {
                if ($k -notmatch '^(test-|chaos-)') {
                    $dir = Join-Path $brainBaseDir $k
                    if (-not [System.IO.Directory]::Exists($dir)) {
                        $toRemove.Add($k)
                    }
                }
            }
            foreach ($delId in $toRemove) {
                $discard = $null
                $sessions.TryRemove($delId, [ref]$discard) | Out-Null
            }

            $sessList = [System.Collections.Generic.List[hashtable]]::new()
            
            $rawList = @($sessions.Values)
            $sortedList = $rawList | Sort-Object { 
                if ($_.sessionIndex -and [int]$_.sessionIndex -gt 0) { [int]$_.sessionIndex } else { 9999 } 
            }, { 
                if ($_.createdAt) { try { [datetime]$_.createdAt } catch { [datetime]::MaxValue } } else { [datetime]::MaxValue } 
            }

            $userIndex = 1
            foreach ($s in $sortedList) {
                $cTitle = if ($s.chatTitle) { $s.chatTitle } else { Get-ConversationDisplayName -cid $s.conversationId -wsName $s.workspaceName -fallbackTitle $s.title }
                $shortCid = if ($s.conversationId.Length -gt 8) { $s.conversationId.Substring(0, 8) + "..." } else { $s.conversationId }
                $isTest = ($s.conversationId -match '^(test-|chaos-)')
                
                $sessionNum = if (-not $isTest) {
                    "Sohbet #$userIndex"
                } else {
                    "Test"
                }
                if (-not $isTest) {
                    $s.sessionIndex = $userIndex
                    $userIndex++
                }

                $timeStr = ""
                try {
                    $dt = [datetime]$s.updatedAt
                    $timeStr = $dt.ToString("HH:mm")
                } catch {}

                $sessList.Add(@{
                    conversationId = $s.conversationId
                    shortId        = $shortCid
                    sessionNumber  = $sessionNum
                    chatTitle      = $cTitle
                    workspaceName  = $s.workspaceName
                    title          = $s.title
                    sender         = $s.sender
                    status         = $s.status
                    step           = $s.step
                    totalSteps     = $s.totalSteps
                    updatedAt      = $s.updatedAt
                    timeStr        = $timeStr
                    isTest         = $isTest
                    isArchived     = $false
                    category       = if ($isTest) { "test" } else { "active" }
                    isActive       = ($s.conversationId -eq $activeConversationId)
                })
            }

            # Diskten Antigravity Arşiv Sohbetlerini Keşfet ve Ekle (Auto-Discovery)
            try {
                $archiveList = Get-DiscoveredArchiveSessions -activeSessionsMap $sessions
                foreach ($arch in $archiveList) {
                    $sessList.Add($arch)
                }
            } catch {}

            $cleanSessJson = Repair-Utf8String ($sessList | ConvertTo-Json -Depth 5)
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($cleanSessJson)
            $res.ContentLength64 = $bytes.Length
            if (-not $isHead) {
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            $res.Close()
            continue
        }

        # 4. GET /state (Oturum Filtreli veya Son Durum)
        if ($rawUrl -eq "/state") {
            $res.ContentType = "application/json; charset=utf-8"
            $res.StatusCode = 200

            $reqCid = ""
            if ($req.Url.Query -and $req.Url.Query -match 'cid=([a-zA-Z0-9\-_]+)') {
                $reqCid = $matches[1]
            }

            $cleanState = "{}"
            if (-not [string]::IsNullOrWhiteSpace($reqCid)) {
                if ($sessions.ContainsKey($reqCid) -and $sessions[$reqCid].state) {
                    $cleanState = ($sessions[$reqCid].state | ConvertTo-Json -Depth 6 -Compress)
                } else {
                    # Disk üzerinde live_state.json veya arşiv durumu kontrolü
                    $diskDir = Join-Path (Join-Path $HOME ".gemini\antigravity\brain") $reqCid
                    $diskState = Join-Path $diskDir "live_state.json"
                    if (Test-Path $diskState) {
                        try {
                            $cleanState = [System.IO.File]::ReadAllText($diskState, [System.Text.Encoding]::UTF8)
                        } catch {}
                    } else {
                        $cTitle = Get-ConversationDisplayName -cid $reqCid -wsName "Antigravity Workspace" -fallbackTitle "Sohbet"
                        $archivedObj = @{
                            conversationId = $reqCid
                            title          = $cTitle
                            chatTitle      = $cTitle
                            sender         = "Antigravity"
                            status         = "ARŞİV"
                            isArchived     = $true
                            step           = 0
                            totalSteps     = 0
                            activeNode     = "none"
                            phase          = "ARŞİV SOHBET"
                            message        = "Bu sohbet geçmiş bir Antigravity oturumudur (Canlı telemetri yayını bulunmamaktadır)."
                            updatedAt      = (Get-Date).ToString("o")
                        }
                        $cleanState = ($archivedObj | ConvertTo-Json -Depth 5 -Compress)
                    }
                }
            } else {
                $cleanState = $latestStateJson
            }

            $cleanState = Repair-Utf8String $cleanState
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($cleanState)
            $res.ContentLength64 = $bytes.Length
            if (-not $isHead) {
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            }
            $res.Close()
            continue
        }

        # 5. POST /set-active (Aktif Oturumu Degistir)
        if ($rawUrl -eq "/set-active" -and $req.HttpMethod -eq "POST") {
            $reader = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $reader.Dispose()

            try {
                $obj = $body | ConvertFrom-Json
                if ($obj.conversationId) {
                    $activeConversationId = $obj.conversationId
                }
                if ($obj.artifactDirectoryPath) {
                    $ArtifactDir = $obj.artifactDirectoryPath
                    Write-Host "[ROUTER] Aktif Gorev Dizini Guncellendi: $ArtifactDir (CID: $activeConversationId)" -ForegroundColor Cyan
                    $statePath = Join-Path $ArtifactDir "live_state.json"
                    if (Test-Path $statePath) {
                        try {
                            $latestStateJson = [System.IO.File]::ReadAllText($statePath, [System.Text.Encoding]::UTF8)
                            $latestStateJson = Repair-Utf8String $latestStateJson
                            Broadcast-SSE -jsonData $latestStateJson -targetCid $activeConversationId
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

        # 6. GET / veya /index.html veya /live
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

        # 7. GET /playground
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

        # 8. GET /status (Health Check)
        if ($rawUrl -eq "/status") {
            $res.ContentType = "application/json; charset=utf-8"
            $res.StatusCode = 200
            $statusObj = @{
                status               = "running"
                port                 = $Port
                activeArtifactDir    = $ArtifactDir
                activeConversationId = $activeConversationId
                totalActiveSessions  = $sessions.Count
                activeSseClients     = $sseClients.Count
                timestamp            = (Get-Date).ToString("o")
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
