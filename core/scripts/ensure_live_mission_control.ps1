param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$rawInput = [Console]::In.ReadToEnd()

if ([string]::IsNullOrWhiteSpace($rawInput)) {
    Write-Output "{}"
    exit 0
}

$rawInput = $rawInput.Trim().Trim([char]65279)

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

# Oturum ve dizin bilgilerini cikar
$conversationId = $payload.conversationId
$artifactDir = $payload.artifactDirectoryPath

if ([string]::IsNullOrWhiteSpace($artifactDir) -and -not [string]::IsNullOrWhiteSpace($conversationId)) {
    $artifactDir = Join-Path $HOME ".gemini\antigravity\brain\$conversationId"
}

# Telemetri Portu (Varsayilan: 9999; izole testler icin VIGILES_TELEMETRY_PORT desteklenir)
$telemetryPort = 9999
if ($env:VIGILES_TELEMETRY_PORT -match '^\d+$') {
    $parsedPort = [int]$env:VIGILES_TELEMETRY_PORT
    if ($parsedPort -ge 1024 -and $parsedPort -le 65535) {
        $telemetryPort = $parsedPort
    }
}

# Vigiles / Live İzolasyon Filtresi:
# /think & /thinkdeep salt-okunur modlarinda Vigiles veya Live kesinlikle tetiklenmez.
$isThinkMode = ($userInput -match '^\s*/(thinkdeep|think|mind|sor)(\s|$)')
$isLive = ($userInput -match '^\s*/(live|mission-control|hud)(\s|$)')
$isProCommand = (-not $isThinkMode) -and (
    $userInput -match '^\s*/(pro|vigiles)(\s|$)' -or
    $userInput -match '\b(pro mode|vigiles mode|vigiles engine|veteran mode|power mode|architect mode)\b'
)
$isLiteCommand = (-not $isThinkMode) -and (
    $userInput -match '^\s*/(vigiles-light|v-light|lite)(\s|$)' -or
    $userInput -match '\bvigiles light\b'
)
$isVigiles = $isProCommand -or $isLiteCommand

if (-not ($isVigiles -or $isLive)) {
    Write-Output "{}"
    exit 0
}

$defaultConfigDir = Join-Path $HOME ".gemini\config"
$configDir = if (-not [string]::IsNullOrWhiteSpace($env:VIGILES_CONFIG_DIR)) { $env:VIGILES_CONFIG_DIR } else { $defaultConfigDir }
$templatesDir = if (Test-Path (Join-Path $configDir "templates")) { Join-Path $configDir "templates" } else { Join-Path $defaultConfigDir "templates" }
$scriptsDir = if (Test-Path (Join-Path $configDir "scripts")) { Join-Path $configDir "scripts" } else { Join-Path $defaultConfigDir "scripts" }
$activeMissionFile = Join-Path $configDir "active_mission.json"
$missionsStateDir = Join-Path $configDir "state\missions"

$wsPrimaryPath = if ($payload.workspacePaths -and $payload.workspacePaths.Count -gt 0) { [string]$payload.workspacePaths[0] } elseif ($payload.cwd) { [string]$payload.cwd } else { "" }
$wsName = if (-not [string]::IsNullOrWhiteSpace($wsPrimaryPath)) { Split-Path $wsPrimaryPath -Leaf } else { "Antigravity Workspace" }
$cleanInput = ($userInput -replace '[\r\n]+', ' ').Trim()

function Write-IsolatedMissionRecord([string]$missionsDir, [string]$cid, [hashtable]$record) {
    if ([string]::IsNullOrWhiteSpace($missionsDir)) { return }
    try {
        if (-not (Test-Path -LiteralPath $missionsDir)) {
            New-Item -ItemType Directory -Path $missionsDir -Force | Out-Null
        }
        $rawKey = if (-not [string]::IsNullOrWhiteSpace($cid)) { $cid } else { [string]$record.artifactDirectoryPath }
        $safeKey = if (-not [string]::IsNullOrWhiteSpace($rawKey)) { ($rawKey -replace '[^a-zA-Z0-9\-_]', '_') } else { "session_" + [guid]::NewGuid().ToString("N").Substring(0, 8) }
        if ($safeKey.Length -gt 80) { $safeKey = $safeKey.Substring(0, 80) }
        $targetFile = Join-Path $missionsDir "$safeKey.json"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($targetFile, ($record | ConvertTo-Json -Depth 5), $utf8NoBom)
    } catch {}
}

function Get-FallbackChatTitle([string]$text, [string]$cid) {
    $fallbackClean = ($text -replace '^\s*/[a-zA-Z0-9\-_]+\s*', '').Trim()
    if (-not [string]::IsNullOrWhiteSpace($fallbackClean)) {
        if ($fallbackClean.Length -gt 60) {
            return $fallbackClean.Substring(0, 57) + "..."
        }
        return $fallbackClean
    }
    if ($text -match '^\s*/([a-zA-Z0-9\-_]+)\s*$') {
        return "⚡ Komut: /$($matches[1])"
    }
    if (-not [string]::IsNullOrWhiteSpace($text)) {
        return $text
    }
    $shortId = if ($cid -and $cid.Length -ge 8) { $cid.Substring(0, 8) } elseif ($cid) { $cid } else { "oturum" }
    return "Sohbet ($shortId)"
}

function Write-LocalStateFiles([string]$dir, [string]$stateJson) {
    if ([string]::IsNullOrWhiteSpace($dir)) { return }
    try {
        $destJson = Join-Path $dir "live_state.json"
        $destJs = Join-Path $dir "live_state.js"
        [System.IO.File]::WriteAllText($destJson, $stateJson, [System.Text.Encoding]::UTF8)
        $jsWrap = "// Antigravity Canli Telemetri Kancasi`nwindow.__ANTIGRAVITY_STATE__ = $stateJson;`nif (typeof window.onAntigravityStateUpdate === 'function') { window.onAntigravityStateUpdate(window.__ANTIGRAVITY_STATE__); }"
        [System.IO.File]::WriteAllText($destJs, $jsWrap, [System.Text.Encoding]::UTF8)
    } catch {}
}

# 2. Oturum için .vigiles_active işaretçisini yerleştir (hem /pro /lite hem /live için)
if (-not [string]::IsNullOrWhiteSpace($artifactDir)) {
    if (-not (Test-Path $artifactDir)) {
        try { New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null } catch {}
    }
    $vigilesMarker = Join-Path $artifactDir ".vigiles_active"
    try { [System.IO.File]::WriteAllText($vigilesMarker, "vigiles", [System.Text.Encoding]::UTF8) } catch {}
}

# --- YOL A: YALNIZCA /pro veya /lite (/live DEGIL) ---
# Takip sayfası (HTML), Port 9999 sunucusu ve active_mission.json ezilmesi ASLA yapilmaz.
# Oturum izolasyonu (state/missions/<cid>.json) ve /pro paralel worktree kontrolu isletilir.
if (-not $isLive) {
    $silentTitle = Get-FallbackChatTitle -text $cleanInput -cid $conversationId
    if (-not [string]::IsNullOrWhiteSpace($artifactDir)) {
        $destJson = Join-Path $artifactDir "live_state.json"
        if (-not (Test-Path $destJson)) {
            $cleanCmd = $userInput.Replace('"', '\"')
            $silentState = @{
                conversationId = $conversationId
                chatTitle      = $silentTitle
                workspaceName  = $wsName
                step           = 1
                totalSteps     = 15
                activeNode     = "node-user"
                animClass      = "node-active-default"
                status         = "HAZIR"
                title          = "VİGİLES OTURUMU HAZIR (SESSİZ KAYIT)"
                sender         = "[1. SİZ (Şirket Sahibi)]"
                message        = "Sessiz yerel takip kaydı aktif: $cleanCmd"
                desc           = "Yerel telemetri kaydı tutuluyor; /live çağrıldığında canlı panele aktarılır."
                timestamp      = (Get-Date).ToString("HH:mm:ss")
                badge          = @{ id = "badge-user"; text = "Hazır"; class = "bg-emerald-500/20 text-emerald-400 border-emerald-500/40 font-bold" }
                highlightPath  = $null
                stats          = @{
                    testsPassed    = 0
                    testsFailed    = 0
                    defectsOpen    = 0
                    secretsBlocked = 0
                    bloatBlocked   = 0
                }
            }
            $silentJson = $silentState | ConvertTo-Json -Depth 5 -Compress
            Write-LocalStateFiles -dir $artifactDir -stateJson $silentJson
        }
    }

    $isolatedMission = @{
        conversationId        = $conversationId
        chatTitle             = $silentTitle
        workspaceName         = $wsName
        artifactDirectoryPath = $artifactDir
        workspacePaths        = $payload.workspacePaths
        lastCommand           = $userInput
        mode                  = if ($isProCommand) { "PRO" } else { "LITE" }
        status                = "ACTIVE"
        updatedAt             = (Get-Date).ToString("o")
    }

    $proInjectMessage = ""
    if ($isProCommand -and -not [string]::IsNullOrWhiteSpace($wsPrimaryPath) -and (Test-Path -LiteralPath $wsPrimaryPath)) {
        $sessMgr = Join-Path $scriptsDir "vigiles_session_manager.ps1"
        if (-not (Test-Path $sessMgr)) {
            $sessMgr = Join-Path $PSScriptRoot "vigiles_session_manager.ps1"
        }
        if (Test-Path $sessMgr) {
            try {
                $forceWtArg = if ($userInput -match '(--isolated|--worktree)\b') { @("-ForceWorktree") } else { @() }
                $mgrArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $sessMgr, "-Action", "Start", "-ConversationId", $conversationId, "-ArtifactDir", $artifactDir, "-WorkspacePath", $wsPrimaryPath, "-Json") + $forceWtArg
                $mgrOut = (& powershell.exe @mgrArgs 2>$null | Out-String).Trim()
                if (-not [string]::IsNullOrWhiteSpace($mgrOut)) {
                    $sessInfo = $mgrOut | ConvertFrom-Json
                    if ($sessInfo -and $sessInfo.isGitRepo) {
                        $isolatedMission["sessionMode"] = $sessInfo.mode
                        $isolatedMission["effectiveWorkDir"] = $sessInfo.effectiveWorkDir
                        $isolatedMission["worktreePath"] = $sessInfo.worktreePath
                        $isolatedMission["branchName"] = $sessInfo.branchName
                        $durumPath = if (-not [string]::IsNullOrWhiteSpace($artifactDir)) { (Join-Path $artifactDir "DURUM.md").Replace('\', '/') } else { "<artifactDirectoryPath>/DURUM.md" }

                        if ($sessInfo.mode -eq "WORKTREE" -and -not [string]::IsNullOrWhiteSpace($sessInfo.worktreePath)) {
                            $wtForward = $sessInfo.worktreePath.Replace('\', '/')
                            $repoForward = $sessInfo.repoRoot.Replace('\', '/')
                            $proInjectMessage = "[VIGILES PARALEL SANTIYE IZOLASYONU - WORKTREE AKTIF]: Bu depoda eszamanli baska bir /pro oturumu aktif oldugu icin cakismasiz izole Git worktree santiyesi acildi (shortId: $($sessInfo.shortId), branch: $($sessInfo.branchName)). ZORUNLU CALISMA KURALLARI: (1) Tum dosya okuma, write_file, edit_file, run_command ve invoke_subagent hedeflerini YALNIZCA su izole klasor uzerinden calistirin: $wtForward . Ana klasore ($repoForward) kesinlikle yazmayin (Path Guard tarafindan reddedilir). (2) DURUM.md dosyanizi proje kokune degil YALNIZCA su artifact yoluna yazin: $durumPath . (3) Is bitip Bagimsiz Yargic onayladiginda ana klasore yazmadan veya install.ps1 / git push calistirmadan kullaniciya /merge ile ana klasore birlestirebilecegini bildirin."
                        } elseif ($sessInfo.mode -eq "MAIN_TREE" -and $sessInfo.preExistingDirty -and $sessInfo.preExistingDirty.Count -gt 0) {
                            $repoForward = $sessInfo.repoRoot.Replace('\', '/')
                            $proInjectMessage = "[VIGILES SANTIYE BILGISI - MAIN_TREE]: Ana klasorde ($repoForward) calisiyorsunuz. DURUM.md dosyanizi proje kokune degil YALNIZCA su artifact yoluna yazin: $durumPath . Bilgilendirme: Klasorde onceki gorevlerden kalan $($sessInfo.preExistingDirty.Count) adet commitlenmemis dosya mevcut; bunlar aktif paralel cakisma degildir, durup beklemeyin, onlara dokunmadan kendi gorevinize odaklanin."
                        }
                    }
                }
            } catch {}
        }
    }

    Write-IsolatedMissionRecord -missionsDir $missionsStateDir -cid $conversationId -record $isolatedMission

    if (-not [string]::IsNullOrWhiteSpace($proInjectMessage)) {
        $proResp = @{
            injectSteps = @(
                @{
                    systemMessage = @{
                        systemMessage = $proInjectMessage
                    }
                }
            )
        }
        Write-Output ($proResp | ConvertTo-Json -Depth 5 -Compress)
        exit 0
    }

    Write-Output "{}"
    exit 0
}

# --- YOL B: YALNIZCA /live (/mission-control, /hud) ---
# .live_active isaretcisi yalnizca burada olusturulur.
if (-not [string]::IsNullOrWhiteSpace($artifactDir)) {
    $liveMarker = Join-Path $artifactDir ".live_active"
    try { [System.IO.File]::WriteAllText($liveMarker, "live", [System.Text.Encoding]::UTF8) } catch {}
}

$chatTitle = ""

# 1. ÖNCE Antigravity Resmi Veritabanından (conversation_summaries.db) gerçek sohbet adını oku
$dbPath = Join-Path $HOME ".gemini\antigravity\conversation_summaries.db"
$agyNode = Join-Path $env:APPDATA "Antigravity\bin\agy-node.cmd"
if (-not [string]::IsNullOrWhiteSpace($conversationId) -and (Test-Path $dbPath) -and (Test-Path $agyNode)) {
    try {
        $dbPathForward = $dbPath.Replace('\', '/')
        $safeCid = $conversationId -replace "[^a-zA-Z0-9\-_]", ""
        $jsCode = "const { DatabaseSync } = require('node:sqlite'); const db = new DatabaseSync('$dbPathForward', { open: true, readOnly: true }); const row = db.prepare('SELECT title, preview FROM conversation_summaries WHERE conversation_id = ?').get('$safeCid'); if (row) console.log(Buffer.from(JSON.stringify(row), 'utf8').toString('base64'));"
        $b64Out = & $agyNode -e $jsCode 2>$null
        if (-not [string]::IsNullOrWhiteSpace($b64Out)) {
            $b64Clean = ($b64Out -join '').Trim()
            $jsonStr = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($b64Clean))
            $rowObj = $jsonStr | ConvertFrom-Json
            if ($rowObj -and -not [string]::IsNullOrWhiteSpace($rowObj.title)) {
                $chatTitle = $rowObj.title.Trim()
            } elseif ($rowObj -and -not [string]::IsNullOrWhiteSpace($rowObj.preview) -and $rowObj.preview -ne "ping") {
                $chatTitle = ($rowObj.preview -replace '[\r\n]+', ' ').Trim()
            }
        }
    } catch {}
}

# 2. Yedek (Fallback): Henüz DB başlığı oluşmamış yeni sohbetlerde kullanıcı istemini kullan
if ([string]::IsNullOrWhiteSpace($chatTitle)) {
    $chatTitle = Get-FallbackChatTitle -text $cleanInput -cid $conversationId
}

# 2. Aktif Görev Kütüğünü Güncelle (state/missions/<cid>.json + active_mission.json Yalnızca /live oturumunda)
$missionInfo = @{
    conversationId        = $conversationId
    chatTitle             = $chatTitle
    workspaceName         = $wsName
    artifactDirectoryPath = $artifactDir
    workspacePaths        = $payload.workspacePaths
    lastCommand           = $userInput
    mode                  = "LIVE"
    status                = "ACTIVE"
    updatedAt             = (Get-Date).ToString("o")
}
Write-IsolatedMissionRecord -missionsDir $missionsStateDir -cid $conversationId -record $missionInfo

$isTestArtifact = ($conversationId -and ($conversationId -match '^(test-|chaos-|session-)')) -or
                  ($artifactDir -and ($artifactDir -match '[\\/]Temp[\\/]'))
$allowActiveMissionWrite = (-not [string]::IsNullOrWhiteSpace($artifactDir)) -and (
    (-not [string]::IsNullOrWhiteSpace($env:VIGILES_CONFIG_DIR)) -or (-not $isTestArtifact)
)
if ($allowActiveMissionWrite) {
    try {
        $amParent = Split-Path $activeMissionFile -Parent
        if (-not (Test-Path $amParent)) {
            New-Item -ItemType Directory -Path $amParent -Force | Out-Null
        }
        $missionJson = $missionInfo | ConvertTo-Json -Depth 4
        [System.IO.File]::WriteAllText($activeMissionFile, $missionJson, [System.Text.Encoding]::UTF8)
    } catch {}
}

# 3. Canli Dosyalari ve Artifact Dosyalarini Hazirla (Yalnizca /live)
$syncStateJson = ""
if (-not [string]::IsNullOrWhiteSpace($artifactDir)) {
    if (-not (Test-Path $artifactDir)) {
        try { New-Item -ItemType Directory -Path $artifactDir -Force | Out-Null } catch {}
    }

    # live_mission_control.html kopyala
    $destHtml = Join-Path $artifactDir "live_mission_control.html"
    $templateHtml = Join-Path $templatesDir "live_mission_control.html"
    $repoRootFallback = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $wsFallbackHtml = Join-Path $repoRootFallback "core\templates\live_mission_control.html"

    $needCopy = $false
    if (-not (Test-Path $destHtml)) {
        $needCopy = $true
    } elseif (Test-Path $templateHtml) {
        if ((Get-Item $templateHtml).LastWriteTime -gt (Get-Item $destHtml).LastWriteTime) {
            $needCopy = $true
        }
    }
    if ($needCopy) {
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
            summary     = "Antigravity Canlı Operasyon Merkezi (Live Mission Control)"
            updatedAt   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffffZ")
            userFacing  = $true
        }
        try {
            $metaJson = $metaObj | ConvertTo-Json -Compress
            [System.IO.File]::WriteAllText($destMeta, $metaJson, [System.Text.Encoding]::UTF8)
        } catch {}
    }

    # live_state.json: Varsa sessizce biriken mevcut durumu koru ve senkronize et; yoksa olustur
    $destJson = Join-Path $artifactDir "live_state.json"
    if (Test-Path $destJson) {
        try {
            $existingRaw = [System.IO.File]::ReadAllText($destJson, [System.Text.Encoding]::UTF8).Trim().Trim([char]65279)
            if (-not [string]::IsNullOrWhiteSpace($existingRaw)) {
                $existingObj = $existingRaw | ConvertFrom-Json
                if ($existingObj) {
                    if (-not $existingObj.PSObject.Properties["conversationId"] -or [string]::IsNullOrWhiteSpace($existingObj.conversationId)) {
                        $existingObj | Add-Member -NotePropertyName "conversationId" -NotePropertyValue $conversationId -Force
                    }
                    if (-not $existingObj.PSObject.Properties["workspaceName"] -or [string]::IsNullOrWhiteSpace($existingObj.workspaceName)) {
                        $existingObj | Add-Member -NotePropertyName "workspaceName" -NotePropertyValue $wsName -Force
                    }
                    if (-not [string]::IsNullOrWhiteSpace($chatTitle)) {
                        $existingObj | Add-Member -NotePropertyName "chatTitle" -NotePropertyValue $chatTitle -Force
                    }
                    if ($existingObj.status -eq "HAZIR" -and $existingObj.title -eq "VİGİLES OTURUMU HAZIR (SESSİZ KAYIT)") {
                        $existingObj.title = "CANLI OPERASYON MERKEZİ DEVREDE"
                        $existingObj.desc  = "Port $telemetryPort SSE yayını ve Antigravity yan paneli aktif."
                    }
                    $syncStateJson = $existingObj | ConvertTo-Json -Depth 6 -Compress
                    Write-LocalStateFiles -dir $artifactDir -stateJson $syncStateJson
                }
            }
        } catch {}
    }

    if ([string]::IsNullOrWhiteSpace($syncStateJson)) {
        $cleanCmd = $userInput.Replace('"', '\"')
        $initState = @{
            conversationId = $conversationId
            chatTitle      = $chatTitle
            workspaceName  = $wsName
            step           = 1
            totalSteps     = 15
            activeNode     = "node-user"
            animClass      = "node-active-default"
            status         = "HAZIR"
            title          = "CANLI OPERASYON MERKEZİ DEVREDE"
            sender         = "[1. SİZ (Şirket Sahibi)]"
            message        = "Canlı Operasyon Merkezi bağlandı: $cleanCmd"
            desc           = "Port $telemetryPort SSE yayını ve Antigravity yan paneli aktif."
            timestamp      = (Get-Date).ToString("HH:mm:ss")
            badge          = @{ id = "badge-user"; text = "Hazır"; class = "bg-emerald-500/20 text-emerald-400 border-emerald-500/40 font-bold" }
            highlightPath  = $null
            stats          = @{
                testsPassed    = 0
                testsFailed    = 0
                defectsOpen    = 0
                secretsBlocked = 0
                bloatBlocked   = 0
            }
        }
        $syncStateJson = $initState | ConvertTo-Json -Depth 5 -Compress
        Write-LocalStateFiles -dir $artifactDir -stateJson $syncStateJson
    }
}

# 4. Telemetri Sunucusunu Kontrol Et ve Baslat (Yalnizca /live)
function Test-TelemetryPortListening([int]$port) {
    try {
        $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($conn) { return $true }
    } catch {}
    return $false
}

$serverRunning = Test-TelemetryPortListening -port $telemetryPort

if (-not $serverRunning) {
    $serverScript = Join-Path $scriptsDir "telemetry_server.ps1"
    if (-not (Test-Path $serverScript)) {
        $serverScript = Join-Path $PSScriptRoot "telemetry_server.ps1"
    }

    if (Test-Path $serverScript) {
        $portArg = if ($telemetryPort -ne 9999) { " -Port $telemetryPort" } else { "" }
        $artArg = if (-not [string]::IsNullOrWhiteSpace($artifactDir)) { " -ArtifactDir `"$artifactDir`"" } else { "" }
        try {
            $cmdLine = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File `"$serverScript`"$portArg$artArg"
            ([wmiclass]"win32_process").Create($cmdLine) | Out-Null
        } catch {
            $argList = @("-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-NoProfile", "-File", "`"$serverScript`"")
            if ($telemetryPort -ne 9999) { $argList += @("-Port", "$telemetryPort") }
            if (-not [string]::IsNullOrWhiteSpace($artifactDir)) { $argList += @("-ArtifactDir", "`"$artifactDir`"") }
            Start-Process powershell.exe -ArgumentList $argList -WindowStyle Hidden
        }

        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Milliseconds 100
            if (Test-TelemetryPortListening -port $telemetryPort) {
                $serverRunning = $true
                break
            }
        }
    }
}

function Invoke-TelemetryPost([string]$url, [string]$jsonBody, [string]$cidHeader = "") {
    if ([string]::IsNullOrWhiteSpace($jsonBody)) { return }
    try {
        $req = [System.Net.WebRequest]::Create($url)
        $req.Method = "POST"
        $req.ContentType = "application/json; charset=utf-8"
        if (-not [string]::IsNullOrWhiteSpace($cidHeader)) {
            $req.Headers.Add("X-Conversation-Id", $cidHeader)
        }
        $req.ServicePoint.Expect100Continue = $false
        $req.Timeout = 1500
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
        $req.ContentLength = $bytes.Length
        $st = $req.GetRequestStream()
        $st.Write($bytes, 0, $bytes.Length)
        $st.Dispose()
        $res = $req.GetResponse()
        $res.Dispose()
    } catch {}
}

if ($serverRunning) {
    $activeJson = ($missionInfo | ConvertTo-Json -Compress)
    Invoke-TelemetryPost -url "http://localhost:$telemetryPort/set-active" -jsonBody $activeJson

    # Birikmis veya yeni durumu /notify ile panele it (sohbet ortasi /live gecislerinde kaldigi yerden yakalar)
    if (-not [string]::IsNullOrWhiteSpace($syncStateJson)) {
        Invoke-TelemetryPost -url "http://localhost:$telemetryPort/notify" -jsonBody $syncStateJson -cidHeader $conversationId
    }
}

# 5. Antigravity Dahili Webview / Artifact Panelini Hazirla (Harici tarayici calistirilmaz)
if (-not [string]::IsNullOrWhiteSpace($artifactDir)) {
    $launchMarker = Join-Path $artifactDir ".live_mission_launched"
    if (-not (Test-Path $launchMarker)) {
        try {
            New-Item -ItemType File -Path $launchMarker -Force | Out-Null
        } catch {}
    }
}

# 6. Modeli Bilgilendir (Net ve sifir gecikmeli direktif - Yalnizca /live)
$destHtmlForward = if (-not [string]::IsNullOrWhiteSpace($artifactDir)) {
    (Join-Path $artifactDir "live_mission_control.html").Replace('\', '/')
} else { "" }

$sysMsgText = "[CANLI OPERASYON MERKEZI DEVREDE]: Port $telemetryPort SSE aktif. live_mission_control.html hazirlandi. Artifact dosya yolu: file:///$destHtmlForward. Harici isletim sistemi tarayicisi acilmaz. Sayfayi ASLA chat output'u icine embed etmeyin (<agent-embed> kullanmayin). Antigravity'nin side paneli uzerindeki dahili browser'da acilmasi icin dogrudan http://localhost:$telemetryPort/ baglantisini ve artifact linkini verin. Kesinlikle dosya taramasi veya okumasi yapmayin."

$response = @{
    injectSteps = @(
        @{
            systemMessage = @{
                systemMessage = $sysMsgText
            }
        }
    )
}

Write-Output ($response | ConvertTo-Json -Depth 5 -Compress)
exit 0
