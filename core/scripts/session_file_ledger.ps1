# core/scripts/session_file_ledger.ps1
# Vigiles Engine - Tum Sohbetlerde Sessiz Dosya Zimmet & Kimlik Dogrulama Kancasi
# PreToolUse & PostToolUse olaylarinda dosya sahiplerini .git/vigiles/file_ledger.json defterine isler.

param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Allow([string]$overwriteCmd = $null) {
    if (-not [string]::IsNullOrWhiteSpace($overwriteCmd)) {
        $obj = @{
            decision  = "allow"
            overwrite = @{
                CommandLine = $overwriteCmd
            }
        }
        Write-Output ($obj | ConvertTo-Json -Depth 4 -Compress)
    } else {
        Write-Output '{"decision":"allow"}'
    }
    exit 0
}

function Write-Deny([string]$reasonText) {
    $obj = @{
        decision = "deny"
        reason   = $reasonText
    }
    Write-Output ($obj | ConvertTo-Json -Depth 4 -Compress)
    exit 0
}

function Normalize-SlashPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return "" }
    $n = $p.Trim().Trim('"').Replace('\', '/')
    while ($n.StartsWith("./")) { $n = $n.Substring(2) }
    return $n.TrimEnd('/')
}

function Find-GitContextForPath([string]$targetPath, [string]$fallbackCwd) {
    $probe = $targetPath
    if ([string]::IsNullOrWhiteSpace($probe)) { $probe = $fallbackCwd }
    if ([string]::IsNullOrWhiteSpace($probe)) { return $null }

    try {
        if (-not [System.IO.Path]::IsPathRooted($probe) -and -not [string]::IsNullOrWhiteSpace($fallbackCwd)) {
            $probe = Join-Path $fallbackCwd $probe
        }
        $probe = [System.IO.Path]::GetFullPath($probe)
    } catch {
        return $null
    }

    $dir = if (Test-Path -LiteralPath $probe -PathType Container) { $probe } else { Split-Path -Parent $probe }
    while (-not [string]::IsNullOrWhiteSpace($dir)) {
        $dotGit = Join-Path $dir ".git"
        if (Test-Path -LiteralPath $dotGit) {
            $gitDir = $null
            if (Test-Path -LiteralPath $dotGit -PathType Container) {
                $gitDir = $dotGit
            } else {
                # Git worktree .git dosyasi ("gitdir: ...")
                try {
                    $line = (Get-Content -LiteralPath $dotGit -TotalCount 1 -Encoding UTF8).Trim()
                    if ($line -match '^gitdir:\s*(.+)$') {
                        $rawGd = $matches[1].Trim()
                        if ([System.IO.Path]::IsPathRooted($rawGd)) {
                            $gitDir = [System.IO.Path]::GetFullPath($rawGd)
                        } else {
                            $gitDir = [System.IO.Path]::GetFullPath((Join-Path $dir $rawGd))
                        }
                    }
                } catch {}
            }
            if ($gitDir) {
                return @{
                    RepoRoot = [System.IO.Path]::GetFullPath($dir)
                    GitDir   = $gitDir
                }
            }
        }
        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

function Get-RelativeRepoPath([string]$repoRoot, [string]$filePath) {
    if ([string]::IsNullOrWhiteSpace($repoRoot) -or [string]::IsNullOrWhiteSpace($filePath)) { return "" }
    try {
        $fullRoot = [System.IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/')
        $fullFile = if ([System.IO.Path]::IsPathRooted($filePath)) {
            [System.IO.Path]::GetFullPath($filePath)
        } else {
            [System.IO.Path]::GetFullPath((Join-Path $fullRoot $filePath))
        }
        if ($fullFile.StartsWith($fullRoot + "\", [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = $fullFile.Substring($fullRoot.Length + 1).Replace('\', '/')
            if ($rel -notmatch '^(?:\.git|node_modules)(/|$)') {
                return $rel
            }
        }
    } catch {}
    return ""
}

function Get-RepoHash([string]$text) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text.ToLowerInvariant())
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant().Substring(0, 12)
    } finally {
        $sha.Dispose()
    }
}

function Invoke-WithLedgerLock([string]$gitDir, [scriptblock]$action) {
    $vigDir = Join-Path $gitDir "vigiles"
    if (-not (Test-Path -LiteralPath $vigDir)) {
        New-Item -ItemType Directory -Path $vigDir -Force | Out-Null
    }
    $ledgerPath = Join-Path $vigDir "file_ledger.json"
    $mutexName = "Local\VigilesFileLedger_" + (Get-RepoHash $gitDir)
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne(5000)
        } catch [System.Threading.AbandonedMutexException] {
            $acquired = $true
        }

        $ledger = $null
        if (Test-Path -LiteralPath $ledgerPath) {
            try {
                $raw = [System.IO.File]::ReadAllText($ledgerPath, [System.Text.Encoding]::UTF8)
                if (-not [string]::IsNullOrWhiteSpace($raw)) {
                    $ledger = $raw | ConvertFrom-Json
                }
            } catch {}
        }
        if (-not $ledger) {
            $ledger = [PSCustomObject]@{
                version = 1
                chats   = [PSCustomObject]@{}
                files   = [PSCustomObject]@{}
                commits = [PSCustomObject]@{}
            }
        }
        if (-not $ledger.chats)   { $ledger | Add-Member -NotePropertyName "chats"   -NotePropertyValue ([PSCustomObject]@{}) -Force }
        if (-not $ledger.files)   { $ledger | Add-Member -NotePropertyName "files"   -NotePropertyValue ([PSCustomObject]@{}) -Force }
        if (-not $ledger.commits) { $ledger | Add-Member -NotePropertyName "commits" -NotePropertyValue ([PSCustomObject]@{}) -Force }

        $modified = & $action $ledger
        if ($modified) {
            $jsonStr = $ledger | ConvertTo-Json -Depth 10
            $tmp = "$ledgerPath.tmp." + ([System.Guid]::NewGuid().ToString().Substring(0, 6))
            [System.IO.File]::WriteAllText($tmp, $jsonStr, $Utf8NoBom)
            Move-Item -LiteralPath $tmp -Destination $ledgerPath -Force
        }
    } finally {
        if ($acquired) {
            try { $mutex.ReleaseMutex() } catch {}
        }
        $mutex.Dispose()
    }
}

function Get-SubagentParentAndTitle([string]$cid, [string]$gitDir, [string]$fallbackTitle) {
    if ([string]::IsNullOrWhiteSpace($cid)) { return @{ RootCid = ""; Title = "" } }

    $rootCid = $cid
    $title = $fallbackTitle

    # 1. Test / yerel subagent esleme dosyasi (.git/vigiles/subagent_map.json)
    $localMapFile = Join-Path $gitDir "vigiles\subagent_map.json"
    if (Test-Path -LiteralPath $localMapFile) {
        try {
            $mapObj = ([System.IO.File]::ReadAllText($localMapFile, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
            $visited = @{}
            while ($mapObj.PSObject.Properties[$rootCid] -and -not $visited.ContainsKey($rootCid)) {
                $visited[$rootCid] = $true
                $parentVal = [string]$mapObj.$rootCid
                if ([string]::IsNullOrWhiteSpace($parentVal)) { break }
                $rootCid = $parentVal
            }
        } catch {}
    }

    # 2. Antigravity Resmi DB (conversation_summaries.db) uzerinden alt ajan & baslik cozumlemesi
    $dbPath = if ($env:VIGILES_DB_PATH) { $env:VIGILES_DB_PATH } else { Join-Path $HOME ".gemini\antigravity\conversation_summaries.db" }
    $agyNode = Join-Path $env:APPDATA "Antigravity\bin\agy-node.cmd"
    if (-not $env:VIGILES_SKIP_DB -and (Test-Path -LiteralPath $dbPath) -and (Test-Path -LiteralPath $agyNode)) {
        $cachePath = Join-Path $gitDir "vigiles\db_chat_cache.json"
        $cacheObj = $null
        $useCache = $false
        if (Test-Path -LiteralPath $cachePath) {
            try {
                $age = ((Get-Date) - (Get-Item -LiteralPath $cachePath).LastWriteTime).TotalSeconds
                if ($age -lt 15) {
                    $cacheObj = ([System.IO.File]::ReadAllText($cachePath, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
                    if ($cacheObj -and $cacheObj.PSObject.Properties[$rootCid]) {
                        $useCache = $true
                    }
                }
            } catch {}
        }

        if (-not $useCache) {
            try {
                $dbFwd = $dbPath.Replace('\', '/')
                $js = "const { DatabaseSync } = require('node:sqlite'); const db = new DatabaseSync('$dbFwd', { open: true, readOnly: true }); const rows = db.prepare('SELECT conversation_id, title, preview, parent_conversation_id FROM conversation_summaries').all(); const m = {}; for (const r of rows) { m[r.conversation_id] = { t: r.title || '', p: r.preview || '', parent: r.parent_conversation_id || '' }; } console.log(Buffer.from(JSON.stringify(m), 'utf8').toString('base64'));"
                $b64 = & $agyNode -e $js 2>$null
                if (-not [string]::IsNullOrWhiteSpace($b64)) {
                    $jsonRaw = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(($b64 -join '').Trim()))
                    $vigDir = Join-Path $gitDir "vigiles"
                    if (-not (Test-Path -LiteralPath $vigDir)) { New-Item -ItemType Directory -Path $vigDir -Force | Out-Null }
                    [System.IO.File]::WriteAllText($cachePath, $jsonRaw, $Utf8NoBom)
                    $cacheObj = $jsonRaw | ConvertFrom-Json
                }
            } catch {}
        }

        if ($cacheObj) {
            $visited = @{}
            while ($cacheObj.PSObject.Properties[$rootCid] -and -not $visited.ContainsKey($rootCid)) {
                $visited[$rootCid] = $true
                $entry = $cacheObj.$rootCid
                if ($entry -and -not [string]::IsNullOrWhiteSpace($entry.parent)) {
                    $rootCid = [string]$entry.parent
                } else {
                    break
                }
            }
            if ($cacheObj.PSObject.Properties[$rootCid]) {
                $rootEntry = $cacheObj.$rootCid
                if ($rootEntry -and -not [string]::IsNullOrWhiteSpace($rootEntry.t)) {
                    $title = ([string]$rootEntry.t).Trim()
                } elseif ($rootEntry -and -not [string]::IsNullOrWhiteSpace($rootEntry.p) -and $rootEntry.p -ne "ping" -and [string]::IsNullOrWhiteSpace($title)) {
                    $pClean = (([string]$rootEntry.p) -replace '[\r\n]+', ' ').Trim()
                    $title = if ($pClean.Length -gt 60) { $pClean.Substring(0, 57) + "..." } else { $pClean }
                }
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($title)) {
        $shortId = if ($rootCid.Length -ge 8) { $rootCid.Substring(0, 8) } else { $rootCid }
        $title = "Sohbet ($shortId)"
    }

    return @{
        RootCid = $rootCid
        Title   = $title
    }
}

function Set-ObjectProperty($obj, [string]$name, $value) {
    if ($obj.PSObject.Properties[$name]) {
        $obj.$name = $value
    } else {
        $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
    }
}

function Register-LedgerFiles($gitDir, $repoRoot, [string]$rootCid, [string]$chatTitle, [string[]]$relPaths, [string]$toolName) {
    $cleanPaths = @($relPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($cleanPaths.Count -eq 0) { return }

    $nowIso = (Get-Date).ToString("o")
    Invoke-WithLedgerLock $gitDir {
        param($ledger)
        # Sohbet metadata guncelle
        if ($ledger.chats.PSObject.Properties[$rootCid]) {
            if (-not [string]::IsNullOrWhiteSpace($chatTitle)) {
                Set-ObjectProperty $ledger.chats.$rootCid "title" $chatTitle
            }
            Set-ObjectProperty $ledger.chats.$rootCid "lastSeenAt" $nowIso
        } else {
            $chatMeta = [PSCustomObject]@{
                title      = $chatTitle
                lastSeenAt = $nowIso
            }
            Set-ObjectProperty $ledger.chats $rootCid $chatMeta
        }

        foreach ($rel in $cleanPaths) {
            $full = Join-Path $repoRoot ($rel.Replace('/', '\'))
            $exists = Test-Path -LiteralPath $full -PathType Leaf
            $mtimeTicks = if ($exists) { (Get-Item -LiteralPath $full).LastWriteTimeUtc.Ticks } else { 0 }

            if (-not $ledger.files.PSObject.Properties[$rel]) {
                $fileRec = [PSCustomObject]@{
                    editors               = [PSCustomObject]@{}
                    lastKnownMtimeUtcTicks = $mtimeTicks
                    lastKnownExists        = $exists
                }
                Set-ObjectProperty $ledger.files $rel $fileRec
            } else {
                Set-ObjectProperty $ledger.files.$rel "lastKnownMtimeUtcTicks" $mtimeTicks
                Set-ObjectProperty $ledger.files.$rel "lastKnownExists" $exists
                if (-not $ledger.files.$rel.editors) {
                    Set-ObjectProperty $ledger.files.$rel "editors" ([PSCustomObject]@{})
                }
            }

            $edMap = $ledger.files.$rel.editors
            if ($edMap.PSObject.Properties[$rootCid]) {
                Set-ObjectProperty $edMap.$rootCid "lastEditedAt" $nowIso
                Set-ObjectProperty $edMap.$rootCid "tool" $toolName
            } else {
                $edRec = [PSCustomObject]@{
                    firstEditedAt = $nowIso
                    lastEditedAt  = $nowIso
                    tool          = $toolName
                }
                Set-ObjectProperty $edMap $rootCid $edRec
            }
        }
        return $true
    }
}

function Get-GitWorkingTreeSnapshot([string]$repoRoot) {
    $snap = @{}
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "git"
    $psi.Arguments = "-c core.quotepath=false status --porcelain=v1 -uall -z"
    $psi.WorkingDirectory = $repoRoot
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8

    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
        if ($p.ExitCode -ne 0 -or [string]::IsNullOrEmpty($out)) { return $snap }

        $parts = $out.Split([char]0)
        $i = 0
        while ($i -lt $parts.Length) {
            $tok = $parts[$i]
            if ([string]::IsNullOrEmpty($tok) -or $tok.Length -lt 4) { $i++; continue }
            $xy = $tok.Substring(0, 2)
            $rel = Normalize-SlashPath ($tok.Substring(3))
            if ($xy[0] -in @('R', 'C') -or $xy[1] -in @('R', 'C')) { $i += 2 } else { $i += 1 }
            if ($rel -match '^(?:\.git|node_modules)(/|$)') { continue }

            $full = Join-Path $repoRoot ($rel.Replace('/', '\'))
            $ticks = if (Test-Path -LiteralPath $full -PathType Leaf) { (Get-Item -LiteralPath $full).LastWriteTimeUtc.Ticks } else { 0 }
            $snap[$rel] = "$xy|$ticks"
        }
    } catch {}
    return $snap
}

function Extract-FilePathsFromToolCall([string]$toolName, $toolArgs) {
    $paths = [System.Collections.Generic.List[string]]::new()
    if (-not $toolArgs) { return @() }

    foreach ($prop in @("Path", "path", "TargetFile", "targetFile", "file_path", "NotebookPath", "notebookPath")) {
        if ($toolArgs.PSObject.Properties[$prop]) {
            $val = [string]$toolArgs.$prop
            if (-not [string]::IsNullOrWhiteSpace($val)) { $paths.Add($val) }
        }
    }

    if ($toolName -eq "apply_patch") {
        $patchText = ""
        foreach ($pProp in @("Patch", "patch", "Input", "input", "Content", "content")) {
            if ($toolArgs.PSObject.Properties[$pProp] -and $toolArgs.$pProp) {
                $patchText = [string]$toolArgs.$pProp
                break
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($patchText)) {
            foreach ($line in ($patchText -split "`r?`n")) {
                if ($line -match '^\*\*\*\s+(?:Update|Add|Delete)\s+File:\s*(.+)$') {
                    $paths.Add($matches[1].Trim())
                }
            }
        }
    }

    return @($paths.ToArray())
}

# --- ANA AKIS ---

$rawInput = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($rawInput)) { Write-Allow }
$rawInput = $rawInput.Trim().Trim([char]65279)

try {
    $payload = $rawInput | ConvertFrom-Json
} catch {
    Write-Allow
}

$hookEventName = if ($payload.hookEventName) { [string]$payload.hookEventName } else { "" }
$toolCall = $payload.toolCall
if (-not $toolCall) { Write-Allow }

$toolName = if ($toolCall.name) { ([string]$toolCall.name).ToLowerInvariant() } else { "" }
$toolArgs = $toolCall.args
$toolCallId = if ($toolCall.id) { ($toolCall.id -replace '[^a-zA-Z0-9_-]', '_') } else { "call" }
$cid = if ($payload.conversationId) { [string]$payload.conversationId } else { "" }
$cwd = if ($payload.cwd) { [string]$payload.cwd } elseif ($payload.workspacePaths -and $payload.workspacePaths.Count -gt 0) { [string]$payload.workspacePaths[0] } else { "" }
$userText = if ($payload.lastUserInput) { ([string]$payload.lastUserInput -replace '[\r\n]+', ' ').Trim() } else { "" }
if ($userText.Length -gt 60) { $userText = $userText.Substring(0, 57) + "..." }

if ([string]::IsNullOrWhiteSpace($cid)) { Write-Allow }

function Resolve-EffectiveCommandLine([string]$rawCmd) {
    if ([string]::IsNullOrWhiteSpace($rawCmd)) { return "" }
    if ($rawCmd -match 'invoke_with_timeout\.ps1' -and $rawCmd -match '-PayloadFile\s+(?:"([^"]+)"|''([^'']+)''|([^\s]+))') {
        $pFile = if ($matches[1]) { $matches[1] } elseif ($matches[2]) { $matches[2] } else { $matches[3] }
        if ($pFile -and (Test-Path -LiteralPath $pFile)) {
            try {
                $pJson = [System.IO.File]::ReadAllText($pFile, [System.Text.Encoding]::UTF8).Trim().Trim([char]65279) | ConvertFrom-Json
                if ($pJson -and $pJson.command) {
                    return [string]$pJson.command
                }
            } catch {}
        }
    }
    return $rawCmd
}

# 1. PreToolUse ISLEMLERI
if ($hookEventName -eq "PreToolUse" -and $toolName -eq "run_command") {
    $rawCmd = if ($toolArgs -and $toolArgs.CommandLine) { [string]$toolArgs.CommandLine } else { "" }
    $cmd = Resolve-EffectiveCommandLine $rawCmd
    $isWrappedWatchdog = ($cmd -ne $rawCmd)
    $gitCtx = Find-GitContextForPath "" $cwd
    if (-not $gitCtx) { Write-Allow }

    $identity = Get-SubagentParentAndTitle $cid $gitCtx.GitDir $userText
    $rootCid = $identity.RootCid

    # A. Ajanin dogrudan git add / commit / push calistirmasini AST + komut zinciri ile engelle (test kosuculari haric)
    $parseErrs = $null
    $cmdAst = [System.Management.Automation.Language.Parser]::ParseInput($cmd, [ref]$null, [ref]$parseErrs)
    $isReadOnly = ($cmd -match '^\s*(git\s+(status|diff|log|show|branch|remote|rev-parse)|Get-ChildItem|gci|dir|ls|Get-Content|gc|cat|type|rg|Select-String|findstr|tree|Test-Path)\b')

    $isPureTestRunner = $false
    $isPushManager = $false
    $isChatDiffViewer = $false
    $testScriptRx = '^(?i)(Test-|Scenario-|Chaos-|Run-MasterVerification).*\.ps1$'
    $hasChainTokens = ($cmd -match '[;&|\r\n]')
    if ($cmdAst) {
        $allCmdNodes = @($cmdAst.FindAll({ param($n) $n.GetType().Name -eq "CommandAst" }, $true))
        if (-not $hasChainTokens -and $allCmdNodes.Count -eq 1) {
            $cn0 = $allCmdNodes[0]
            $rn0 = $cn0.GetCommandName()
            if (-not [string]::IsNullOrWhiteSpace($rn0)) {
                $lf0 = [System.IO.Path]::GetFileName($rn0.Trim('"', "'"))
                if ($lf0 -match $testScriptRx) { $isPureTestRunner = $true }
                elseif ($lf0 -match '^(?i)(powershell|pwsh)(\.exe)?$') {
                    $elems0 = $cn0.CommandElements
                    for ($ei = 1; $ei -lt $elems0.Count; $ei++) {
                        if ($elems0[$ei].Extent.Text -match '^(?i)-File$' -and ($ei + 1) -lt $elems0.Count) {
                            $sfLeaf0 = [System.IO.Path]::GetFileName($elems0[$ei + 1].Extent.Text.Trim('"', "'"))
                            if ($sfLeaf0 -match $testScriptRx) { $isPureTestRunner = $true }
                            break
                        }
                    }
                }
            }
        }
        foreach ($cn in $allCmdNodes) {
            $rn = $cn.GetCommandName()
            if ([string]::IsNullOrWhiteSpace($rn)) { continue }
            $lf = [System.IO.Path]::GetFileName($rn.Trim('"', "'"))
            if ($lf -match '^(?i)git_push_manager\.ps1$') { $isPushManager = $true }
            elseif ($lf -match '^(?i)chat_diff_viewer\.ps1$') { $isChatDiffViewer = $true }
            elseif ($lf -match '^(?i)(powershell|pwsh)(\.exe)?$') {
                $elems = $cn.CommandElements
                for ($ei = 1; $ei -lt $elems.Count; $ei++) {
                    if ($elems[$ei].Extent.Text -match '^(?i)-File$' -and ($ei + 1) -lt $elems.Count) {
                        $sfLeaf = [System.IO.Path]::GetFileName($elems[$ei + 1].Extent.Text.Trim('"', "'"))
                        if ($sfLeaf -match '^(?i)git_push_manager\.ps1$') { $isPushManager = $true }
                        elseif ($sfLeaf -match '^(?i)chat_diff_viewer\.ps1$') { $isChatDiffViewer = $true }
                        elseif ($sfLeaf.StartsWith('$')) {
                            if ($cmd -match '\bgit_push_manager\.ps1\b') { $isPushManager = $true }
                            if ($cmd -match '\bchat_diff_viewer\.ps1\b') { $isChatDiffViewer = $true }
                        }
                        break
                    }
                }
            }
        }
    } else {
        $isPureTestRunner = ($cmd -match '^\s*(?:powershell(?:\.exe)?\s+(?:[^;&|\r\n]*?-File\s+["'']?)?)?(?:[^;&|\r\n]*[\\/])?(?:Test-|Scenario-|Chaos-|Run-MasterVerification)[^;&|\r\n]*\.ps1(?:\s|$|["''])') -and ($cmd -notmatch '\b(git_push_manager|chat_diff_viewer)\.ps1\b')
        $isPushManager = (-not $isReadOnly) -and (-not $isPureTestRunner) -and ($cmd -match '\bgit_push_manager\.ps1\b')
        $isChatDiffViewer = (-not $isReadOnly) -and (-not $isPureTestRunner) -and ($cmd -match '\bchat_diff_viewer\.ps1\b')
    }

    if ($isPureTestRunner) {
        $isPushManager = $false
        $isChatDiffViewer = $false
    }

    if (-not $isPureTestRunner) {
        $hasRawGitMutation = $false
        $blockedVerb = ""
        if ($cmdAst) {
            $cmdNodes = $cmdAst.FindAll({ param($n) $n.GetType().Name -eq "CommandAst" }, $true)
            foreach ($cn in $cmdNodes) {
                $rawName = $cn.GetCommandName()
                $elems = $cn.CommandElements
                # & "git" gibi dinamik cagri durumunda ilk elemandan isim oku
                if ([string]::IsNullOrWhiteSpace($rawName) -and $elems.Count -ge 1) {
                    if ($elems[0].PSObject.Properties["Value"]) {
                        $rawName = [string]$elems[0].Value
                    }
                }
                if ([string]::IsNullOrWhiteSpace($rawName)) { continue }
                $leafCmd = [System.IO.Path]::GetFileName($rawName.Trim('"', "'")).ToLowerInvariant()

                if ($leafCmd -in @("git", "git.exe")) {
                    for ($idx = 1; $idx -lt $elems.Count; $idx++) {
                        $elTxt = $elems[$idx].Extent.Text.Trim('"', "'")
                        if ($elTxt.StartsWith("-")) {
                            if ($elTxt -in @("-c", "-C", "--git-dir", "--work-tree")) { $idx++ }
                            continue
                        }
                        if ($elTxt.ToLowerInvariant() -in @("add", "commit", "push")) {
                            $hasRawGitMutation = $true
                            $blockedVerb = $elTxt.ToLowerInvariant()
                        }
                        break
                    }
                } elseif ($leafCmd -in @("cmd", "cmd.exe")) {
                    $restTxt = $cn.Extent.Text
                    if ($restTxt -match '\bgit(?:\.exe)?\s+(?:-[cC]\s+\S+\s+)*(add|commit|push)\b') {
                        $hasRawGitMutation = $true
                        $blockedVerb = $matches[1].ToLowerInvariant()
                    }
                }
                if ($hasRawGitMutation) { break }
            }
        }
        if (-not $hasRawGitMutation -and $cmd -match '(^|[;&|\r\n]\s*)(?:&\s*)?(?:["'']?[^;&|\r\n]*[\\/])?git(?:\.exe)?["'']?\s+(?:-[cC]\s+\S+\s+)*(add|commit|push)\b') {
            $hasRawGitMutation = $true
            $blockedVerb = $matches[2].ToLowerInvariant()
        }

        if ($hasRawGitMutation) {
            Write-Deny "[SOHBET IZOLASYON & SIFIR OTOMATIK GIT ENGELI]: Sohbet izolasyonunu korumak icin ajanin dogrudan 'git $blockedVerb' calistirmasi yasaktir! Lutfen /pushprep, /pushremove, /pushadd veya /push kullanin."
        }
    }

    # B. git_push_manager.ps1 ve chat_diff_viewer.ps1 cagrilarinda gercek rootConversationId kimligini izole env + arguman overwrite ile kilitle
    if ($isPushManager -or $isChatDiffViewer) {
        if ($isWrappedWatchdog) {
            # command_watchdog zaten sarmalamis ise wrapper'i bozma (VIGILES_HOOK_CONVERSATION_ID aktif) ve cmd_snap uretme
            Write-Allow
        }
        $cleanedCmd = if ($isPushManager) {
            [regex]::Replace($cmd, '(?i)\s+[-/]Con[a-z]*(?:\s*[:=]\s*|\s+)(?:"[^"]*"|''[^'']*''|[^\s;&|\r\n]+)', '')
        } else {
            # /chatdiff icinde sahte -CallerConversationId temizlenir ancak -TargetChat korunur
            [regex]::Replace($cmd, '(?i)\s+[-/]Cal[a-z]*(?:\s*[:=]\s*|\s+)(?:"[^"]*"|''[^'']*''|[^\s;&|\r\n]+)', '')
        }
        $safeRoot = ($rootCid -replace '[^a-zA-Z0-9\-_]', '')
        $safeTitle = ($identity.Title -replace "['\u2018\u2019\u201A\u201B\r\n]", ' ')
        $rewritten = "`$env:VIGILES_CONVERSATION_ID='$safeRoot'; `$env:VIGILES_CONVERSATION_TITLE='$safeTitle'; $cleanedCmd"
        Write-Allow -overwriteCmd $rewritten
    }

    # C. Salt-okunur olmayan terminal komutlari icin oncesi/sonrasi git snapshot al (push manager, chat_diff_viewer & testler haric)
    if (-not $isReadOnly -and -not $isPushManager -and -not $isChatDiffViewer -and -not $isPureTestRunner) {
        $vigDir = Join-Path $gitCtx.GitDir "vigiles"
        if (-not (Test-Path -LiteralPath $vigDir)) { New-Item -ItemType Directory -Path $vigDir -Force | Out-Null }
        $snapPath = Join-Path $vigDir "cmd_snap_${toolCallId}.json"
        $snap = Get-GitWorkingTreeSnapshot $gitCtx.RepoRoot
        $snapObj = [PSCustomObject]@{
            repoRoot = $gitCtx.RepoRoot
            rootCid  = $rootCid
            title    = $identity.Title
            files    = $snap
        }
        [System.IO.File]::WriteAllText($snapPath, ($snapObj | ConvertTo-Json -Depth 5 -Compress), $Utf8NoBom)
    }
    Write-Allow
}

# 2. PostToolUse ISLEMLERI
if ($hookEventName -eq "PostToolUse") {
    # Arac hata ile bittiyse (or. hook tarafindan engellendiyse) zimmetleme
    if ($payload.error -and -not [string]::IsNullOrWhiteSpace([string]$payload.error)) {
        Write-Allow
    }

    $writeToolSet = @(
        "write_file", "edit_file", "write_to_file", "replace_file_content",
        "multi_replace_file_content", "delete_file", "apply_patch", "notebook_edit"
    )

    if ($toolName -in $writeToolSet) {
        $rawPaths = Extract-FilePathsFromToolCall $toolName $toolArgs
        if ($rawPaths.Count -eq 0) { Write-Allow }

        # Hedef dosyalari ilgili git reposuna gore grupla ve zimmetle
        $grouped = @{}
        foreach ($rp in $rawPaths) {
            $gCtx = Find-GitContextForPath $rp $cwd
            if (-not $gCtx) { continue }
            $rel = Get-RelativeRepoPath $gCtx.RepoRoot $rp
            if ([string]::IsNullOrWhiteSpace($rel)) { continue }
            $key = $gCtx.GitDir
            if (-not $grouped.ContainsKey($key)) {
                $grouped[$key] = @{ Ctx = $gCtx; Paths = [System.Collections.Generic.List[string]]::new() }
            }
            $grouped[$key].Paths.Add($rel)
        }

        foreach ($entry in $grouped.Values) {
            $identity = Get-SubagentParentAndTitle $cid $entry.Ctx.GitDir $userText
            Register-LedgerFiles $entry.Ctx.GitDir $entry.Ctx.RepoRoot $identity.RootCid $identity.Title ($entry.Paths.ToArray()) $toolName
        }
        Write-Allow
    }

    if ($toolName -eq "run_command") {
        $gitCtx = Find-GitContextForPath "" $cwd
        if (-not $gitCtx) { Write-Allow }
        $snapPath = Join-Path $gitCtx.GitDir "vigiles\cmd_snap_${toolCallId}.json"
        if (Test-Path -LiteralPath $snapPath) {
            try {
                $snapData = ([System.IO.File]::ReadAllText($snapPath, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
                Remove-Item -LiteralPath $snapPath -Force -ErrorAction SilentlyContinue

                $afterSnap = Get-GitWorkingTreeSnapshot $snapData.repoRoot
                $beforeFiles = $snapData.files
                $changedPaths = [System.Collections.Generic.List[string]]::new()

                foreach ($k in $afterSnap.Keys) {
                    $prevVal = if ($beforeFiles -and $beforeFiles.PSObject.Properties[$k]) { [string]$beforeFiles.$k } else { $null }
                    if ($prevVal -ne $afterSnap[$k]) {
                        $changedPaths.Add($k)
                    }
                }
                if ($beforeFiles) {
                    foreach ($prop in $beforeFiles.PSObject.Properties) {
                        if (-not $afterSnap.ContainsKey($prop.Name)) {
                            # Komutla silinmis veya git'e dusmus olabilir; disk kontrolu yap
                            $changedPaths.Add($prop.Name)
                        }
                    }
                }

                if ($changedPaths.Count -gt 0) {
                    Register-LedgerFiles $gitCtx.GitDir $snapData.repoRoot ([string]$snapData.rootCid) ([string]$snapData.title) ($changedPaths.ToArray()) "run_command"
                }
            } catch {
                Remove-Item -LiteralPath $snapPath -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Allow
    }
}

Write-Allow
