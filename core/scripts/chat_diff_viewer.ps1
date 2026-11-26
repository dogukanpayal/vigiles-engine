# core/scripts/chat_diff_viewer.ps1
# Vigiles Engine - Sohbet Odakli %100 Salt-Okunur Degisiklik Goruntuleyici (/chatdiff)
# Yalnizca hedef sohbete ait henuz GitHub'a gonderilmemis aktif dosyalari, paralel worktree degisikliklerini ve yerel commitleri listeler.

param(
    [string]$TargetChat = "",
    [switch]$ListChats = $false,
    [switch]$Diff = $false,
    [string[]]$Paths = @(),
    [int]$MaxDiffLinesPerFile = 120,
    [string]$CallerConversationId = "",
    [switch]$Json = $false,
    [switch]$SkipTranscriptScan = $false
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# Kancanin enjekte ettigi gercek kimlik her zaman CLI parametresine onceliklidir
if (-not [string]::IsNullOrWhiteSpace($env:VIGILES_CONVERSATION_ID)) {
    $CallerConversationId = $env:VIGILES_CONVERSATION_ID.Trim()
} elseif (-not [string]::IsNullOrWhiteSpace($env:VIGILES_HOOK_CONVERSATION_ID)) {
    $CallerConversationId = $env:VIGILES_HOOK_CONVERSATION_ID.Trim()
}

# --- YARDIMCI FONKSIYONLAR ---

function Normalize-RepoPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return "" }
    $n = $p.Trim().Replace('\', '/')
    while ($n.StartsWith("./")) { $n = $n.Substring(2) }
    return $n.TrimEnd('/')
}

function ConvertTo-Array($val) {
    if ($null -eq $val) { return @() }
    if ($val -is [System.Array]) { return $val }
    if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
        $list = @()
        foreach ($x in $val) { $list += $x }
        return $list
    }
    return @($val)
}

function Set-ObjProp($obj, [string]$name, $value) {
    if ($obj.PSObject.Properties[$name]) {
        $obj.$name = $value
    } else {
        $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
    }
}

function Format-ProcessArg([string]$arg) {
    if ($null -eq $arg -or $arg -eq "") { return '""' }
    if ($arg -notmatch '[\s"]') { return $arg }
    $escaped = [regex]::Replace($arg, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

$script:TempIndexMap = @{}

function Register-ReadOnlyTempIndex([string]$repoDir, [string]$gitDir) {
    if ([string]::IsNullOrWhiteSpace($repoDir) -or [string]::IsNullOrWhiteSpace($gitDir)) { return }
    try {
        $normDir = [System.IO.Path]::GetFullPath($repoDir).TrimEnd('\', '/')
        if ($script:TempIndexMap.ContainsKey($normDir)) { return }
        $tmpIdx = Join-Path ([System.IO.Path]::GetTempPath()) ("vigiles_cd_idx_" + [System.Guid]::NewGuid().ToString("N"))
        $srcIdx = Join-Path $gitDir "index"
        if (Test-Path -LiteralPath $srcIdx -PathType Leaf) {
            [System.IO.File]::Copy($srcIdx, $tmpIdx, $true)
        }
        $script:TempIndexMap[$normDir] = $tmpIdx
    } catch {}
}

function Cleanup-TempIndexes {
    foreach ($tmpPath in $script:TempIndexMap.Values) {
        if (-not [string]::IsNullOrWhiteSpace($tmpPath) -and (Test-Path -LiteralPath $tmpPath)) {
            Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue
        }
    }
    $script:TempIndexMap.Clear()
}

function Invoke-GitRaw {
    param(
        [string]$WorkingDir = "",
        [string[]]$GitArgs,
        [switch]$UseQuotepathFalse
    )

    $allArgs = [System.Collections.Generic.List[string]]::new()
    $allArgs.Add("--no-optional-locks")
    if ($UseQuotepathFalse) {
        $allArgs.Add("-c")
        $allArgs.Add("core.quotepath=false")
    }
    foreach ($a in $GitArgs) { $allArgs.Add($a) }

    $effectiveWd = if (-not [string]::IsNullOrWhiteSpace($WorkingDir) -and (Test-Path -LiteralPath $WorkingDir)) { $WorkingDir } else { (Get-Location).Path }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "git"
    $psi.Arguments = (($allArgs | ForEach-Object { Format-ProcessArg $_ }) -join " ")
    $psi.WorkingDirectory = $effectiveWd
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.EnvironmentVariables["GIT_OPTIONAL_LOCKS"] = "0"
    try {
        $normWd = [System.IO.Path]::GetFullPath($effectiveWd).TrimEnd('\', '/')
        if ($script:TempIndexMap.ContainsKey($normWd)) {
            $psi.EnvironmentVariables["GIT_INDEX_FILE"] = $script:TempIndexMap[$normWd]
        }
    } catch {}

    $proc = [System.Diagnostics.Process]::Start($psi)
    $errTask = $proc.StandardError.ReadToEndAsync()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    $stderr = $errTask.GetAwaiter().GetResult()

    return @{
        ExitCode = $proc.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
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

function Get-RepoContext {
    $insideRes = Invoke-GitRaw -GitArgs @("rev-parse", "--is-inside-work-tree")
    if ($insideRes.ExitCode -ne 0 -or $insideRes.StdOut.Trim() -ne "true") {
        Write-Host "[HATA]: Mevcut calisma dizini bir Git deposu degil!" -ForegroundColor Red
        return $null
    }

    $topRes = Invoke-GitRaw -GitArgs @("rev-parse", "--show-toplevel")
    $repoRoot = [System.IO.Path]::GetFullPath($topRes.StdOut.Trim())

    $gitDirRes = Invoke-GitRaw -GitArgs @("rev-parse", "--git-dir")
    $gitDirRaw = $gitDirRes.StdOut.Trim()
    $gitDir = if (-not [System.IO.Path]::IsPathRooted($gitDirRaw)) {
        [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $gitDirRaw))
    } else {
        [System.IO.Path]::GetFullPath($gitDirRaw)
    }

    $commonRes = Invoke-GitRaw -GitArgs @("rev-parse", "--git-common-dir")
    $commonRaw = if ($commonRes.ExitCode -eq 0) { $commonRes.StdOut.Trim() } else { "" }
    $commonGitDir = if (-not [string]::IsNullOrWhiteSpace($commonRaw)) {
        if (-not [System.IO.Path]::IsPathRooted($commonRaw)) {
            [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $commonRaw))
        } else {
            [System.IO.Path]::GetFullPath($commonRaw)
        }
    } else {
        $gitDir
    }

    $mainRepoRoot = if ((Split-Path -Leaf $commonGitDir) -ieq ".git") {
        [System.IO.Path]::GetFullPath((Split-Path -Parent $commonGitDir))
    } else {
        $repoRoot
    }

    Register-ReadOnlyTempIndex $repoRoot $gitDir
    Register-ReadOnlyTempIndex $mainRepoRoot $commonGitDir

    $brRes = Invoke-GitRaw -GitArgs @("branch", "--show-current")
    $activeBranch = $brRes.StdOut.Trim()
    if ([string]::IsNullOrWhiteSpace($activeBranch)) {
        $symRes = Invoke-GitRaw -GitArgs @("symbolic-ref", "--short", "HEAD")
        if ($symRes.ExitCode -eq 0) { $activeBranch = $symRes.StdOut.Trim() }
    }
    if ([string]::IsNullOrWhiteSpace($activeBranch)) { $activeBranch = "DETACHED" }

    $headRes = Invoke-GitRaw -GitArgs @("rev-parse", "HEAD")
    $headSha = if ($headRes.ExitCode -eq 0) { $headRes.StdOut.Trim() } else { "UNBORN" }

    $remRes = Invoke-GitRaw -GitArgs @("remote")
    $remoteName = ""
    $remoteUrl = ""
    if ($remRes.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($remRes.StdOut)) {
        $rems = @($remRes.StdOut -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
        if ($rems -contains "origin") { $remoteName = "origin" } elseif ($rems.Count -gt 0) { $remoteName = $rems[0] }
        if ($remoteName) {
            $uRes = Invoke-GitRaw -GitArgs @("remote", "get-url", $remoteName)
            if ($uRes.ExitCode -eq 0) { $remoteUrl = $uRes.StdOut.Trim() }
        }
    }

    return @{
        RepoRoot       = $repoRoot
        MainRepoRoot   = $mainRepoRoot
        GitDir         = $gitDir
        CommonGitDir   = $commonGitDir
        LedgerPath     = (Join-Path $gitDir "vigiles\file_ledger.json")
        MainLedgerPath = (Join-Path $commonGitDir "vigiles\file_ledger.json")
        SessionsDir    = (Join-Path $commonGitDir "vigiles\sessions")
        Branch         = $activeBranch
        HeadSha        = $headSha
        Remote         = $remoteName
        RemoteUrl      = $remoteUrl
    }
}

# --- KIMLIK, DB & ZIMMET OKUMA (100% SALT-OKUNUR) ---

function Get-DbChatMap([string]$gitDir) {
    $dbPath = if ($env:VIGILES_DB_PATH) { $env:VIGILES_DB_PATH } else { Join-Path $HOME ".gemini\antigravity\conversation_summaries.db" }
    $agyNode = Join-Path $env:APPDATA "Antigravity\bin\agy-node.cmd"
    if ($env:VIGILES_SKIP_DB -or -not (Test-Path -LiteralPath $dbPath) -or -not (Test-Path -LiteralPath $agyNode)) {
        # Varsa taze salt-okunur onbellegi oku
        $cachePath = Join-Path $gitDir "vigiles\db_chat_cache.json"
        if (Test-Path -LiteralPath $cachePath) {
            try { return (([System.IO.File]::ReadAllText($cachePath, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json) } catch {}
        }
        return $null
    }

    $cachePath = Join-Path $gitDir "vigiles\db_chat_cache.json"
    if (Test-Path -LiteralPath $cachePath) {
        try {
            $age = ((Get-Date) - (Get-Item -LiteralPath $cachePath).LastWriteTime).TotalSeconds
            if ($age -lt 15) {
                return (([System.IO.File]::ReadAllText($cachePath, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json)
            }
        } catch {}
    }

    try {
        $dbFwd = $dbPath.Replace('\', '/')
        $js = "const { DatabaseSync } = require('node:sqlite'); const db = new DatabaseSync('$dbFwd', { open: true, readOnly: true }); const rows = db.prepare('SELECT conversation_id, title, preview, parent_conversation_id FROM conversation_summaries').all(); const m = {}; for (const r of rows) { m[r.conversation_id] = { t: r.title || '', p: r.preview || '', parent: r.parent_conversation_id || '' }; } console.log(Buffer.from(JSON.stringify(m), 'utf8').toString('base64'));"
        $b64 = & $agyNode -e $js 2>$null
        if (-not [string]::IsNullOrWhiteSpace($b64)) {
            $jsonRaw = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(($b64 -join '').Trim()))
            return ($jsonRaw | ConvertFrom-Json)
        }
    } catch {}
    return $null
}

function Get-LocalSubagentMap([string]$gitDir, [string]$commonGitDir) {
    $merged = @{}
    foreach ($dir in @($commonGitDir, $gitDir) | Select-Object -Unique) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        $p = Join-Path $dir "vigiles\subagent_map.json"
        if (Test-Path -LiteralPath $p) {
            try {
                $obj = ([System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
                foreach ($prop in $obj.PSObject.Properties) {
                    $merged[$prop.Name] = [string]$prop.Value
                }
            } catch {}
        }
    }
    return $merged
}

function Resolve-RootIdentity([string]$cid, $localSubMap, $dbMap, [string]$fallbackTitle = "") {
    if ([string]::IsNullOrWhiteSpace($cid)) { return @{ RootCid = ""; Title = "" } }

    $rootCid = $cid.Trim()
    $visited = @{}
    while ($localSubMap -and $localSubMap.ContainsKey($rootCid) -and -not $visited.ContainsKey($rootCid)) {
        $visited[$rootCid] = $true
        $pv = [string]$localSubMap[$rootCid]
        if ([string]::IsNullOrWhiteSpace($pv)) { break }
        $rootCid = $pv
    }

    $title = $fallbackTitle
    if ($dbMap) {
        $visitedDb = @{}
        while ($dbMap.PSObject.Properties[$rootCid] -and -not $visitedDb.ContainsKey($rootCid)) {
            $visitedDb[$rootCid] = $true
            $entry = $dbMap.$rootCid
            if ($entry -and -not [string]::IsNullOrWhiteSpace($entry.parent)) {
                $rootCid = [string]$entry.parent
            } else {
                break
            }
        }
        if ($dbMap.PSObject.Properties[$rootCid]) {
            $re = $dbMap.$rootCid
            if ($re -and -not [string]::IsNullOrWhiteSpace($re.t)) {
                $title = ([string]$re.t).Trim()
            } elseif ($re -and -not [string]::IsNullOrWhiteSpace($re.p) -and $re.p -ne "ping" -and [string]::IsNullOrWhiteSpace($title)) {
                $pClean = (([string]$re.p) -replace '[\r\n]+', ' ').Trim()
                $title = if ($pClean.Length -gt 60) { $pClean.Substring(0, 57) + "..." } else { $pClean }
            }
        }
    }

    return @{
        RootCid = $rootCid
        Title   = $title
    }
}

function Read-LedgerReadOnly([string]$ledgerPath, [string]$gitDirForMutex) {
    $empty = [PSCustomObject]@{
        version = 1
        chats   = [PSCustomObject]@{}
        files   = [PSCustomObject]@{}
        commits = [PSCustomObject]@{}
    }
    if (-not (Test-Path -LiteralPath $ledgerPath)) { return $empty }

    $mutexName = "Local\VigilesFileLedger_" + (Get-RepoHash $gitDirForMutex)
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne(5000) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
        try {
            $raw = [System.IO.File]::ReadAllText($ledgerPath, [System.Text.Encoding]::UTF8)
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $parsed = $raw | ConvertFrom-Json
                if ($parsed) {
                    if (-not $parsed.chats)   { Set-ObjProp $parsed "chats"   ([PSCustomObject]@{}) }
                    if (-not $parsed.files)   { Set-ObjProp $parsed "files"   ([PSCustomObject]@{}) }
                    if (-not $parsed.commits) { Set-ObjProp $parsed "commits" ([PSCustomObject]@{}) }
                    return $parsed
                }
            }
        } catch {}
        return $empty
    } finally {
        if ($acquired) { try { $mutex.ReleaseMutex() } catch {} }
        $mutex.Dispose()
    }
}

function Merge-LedgerSnapshots($primary, $secondary) {
    if (-not $secondary) { return $primary }
    foreach ($cProp in $secondary.chats.PSObject.Properties) {
        if (-not $primary.chats.PSObject.Properties[$cProp.Name]) {
            Set-ObjProp $primary.chats $cProp.Name $cProp.Value
        }
    }
    foreach ($fProp in $secondary.files.PSObject.Properties) {
        if (-not $primary.files.PSObject.Properties[$fProp.Name]) {
            Set-ObjProp $primary.files $fProp.Name $fProp.Value
        } else {
            $dstEd = $primary.files.$($fProp.Name).editors
            $srcEd = $fProp.Value.editors
            if ($srcEd) {
                foreach ($eProp in $srcEd.PSObject.Properties) {
                    if (-not $dstEd.PSObject.Properties[$eProp.Name]) {
                        Set-ObjProp $dstEd $eProp.Name $eProp.Value
                    }
                }
            }
        }
    }
    foreach ($cmProp in $secondary.commits.PSObject.Properties) {
        if (-not $primary.commits.PSObject.Properties[$cmProp.Name]) {
            Set-ObjProp $primary.commits $cmProp.Name $cmProp.Value
        }
    }
    return $primary
}

function Add-TranscriptEditsInMemory($ctx, $ledger, $wtEntries, $localSubMap, $dbMap) {
    if ($SkipTranscriptScan -or $env:VIGILES_SKIP_TRANSCRIPT -eq "1") { return $ledger }
    if (-not $wtEntries -or $wtEntries.Count -eq 0) { return $ledger }

    $brainDir = if ($env:VIGILES_BRAIN_DIR) { $env:VIGILES_BRAIN_DIR } else { Join-Path $HOME ".gemini\antigravity\brain" }
    if (-not (Test-Path -LiteralPath $brainDir)) { return $ledger }

    $unowned = @{}
    foreach ($wt in $wtEntries) {
        $hasEd = $false
        if ($ledger.files -and $ledger.files.PSObject.Properties[$wt.path]) {
            $ed = $ledger.files.$($wt.path).editors
            if ($ed -and @($ed.PSObject.Properties).Count -gt 0) { $hasEd = $true }
        }
        if (-not $hasEd) { $unowned[$wt.path] = $true }
    }
    if ($unowned.Count -eq 0) { return $ledger }

    $normRoot = ([System.IO.Path]::GetFullPath($ctx.RepoRoot)).TrimEnd('\', '/').Replace('\', '/')
    $cutoff = (Get-Date).AddDays(-14)
    $writeToolNames = @("write_file", "edit_file", "replace_file_content", "multi_replace_file_content", "write_to_file", "delete_file", "apply_patch")

    $convDirs = Get-ChildItem -Path $brainDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $cutoff }
    foreach ($cd in $convDirs) {
        $tPath = Join-Path $cd.FullName ".system_generated\logs\transcript.jsonl"
        if (-not (Test-Path -LiteralPath $tPath)) { continue }

        $idInfo = Resolve-RootIdentity $cd.Name $localSubMap $dbMap ""
        $resolvedCid = $idInfo.RootCid
        if ([string]::IsNullOrWhiteSpace($resolvedCid)) { continue }

        try {
            $sr = New-Object System.IO.StreamReader($tPath, [System.Text.Encoding]::UTF8)
            try {
                while ($null -ne ($line = $sr.ReadLine())) {
                    if ($line -notmatch '"write_file"|"edit_file"|"replace_file_content"|"multi_replace_file_content"|"write_to_file"|"delete_file"|"apply_patch"') { continue }
                    try {
                        $step = $line | ConvertFrom-Json
                        if (-not $step.tool_calls) { continue }
                        foreach ($tc in $step.tool_calls) {
                            if ($tc.name -notin $writeToolNames) { continue }
                            $rawPaths = [System.Collections.Generic.List[string]]::new()
                            foreach ($pn in @("Path", "path", "TargetFile", "targetFile", "file_path")) {
                                if ($tc.args -and $tc.args.PSObject.Properties[$pn]) {
                                    $rawPaths.Add([string]$tc.args.$pn)
                                    break
                                }
                            }
                            if ($tc.name -eq "apply_patch" -and $tc.args) {
                                foreach ($pp in @("Patch", "patch", "Input", "input", "Content", "content")) {
                                    if ($tc.args.PSObject.Properties[$pp] -and $tc.args.$pp) {
                                        foreach ($pl in (([string]$tc.args.$pp) -split "`r?`n")) {
                                            if ($pl -match '^\*\*\*\s+(?:Update|Add|Delete)\s+File:\s*(.+)$') {
                                                $rawPaths.Add($matches[1].Trim())
                                            }
                                        }
                                        break
                                    }
                                }
                            }

                            foreach ($rawP in $rawPaths) {
                                if ([string]::IsNullOrWhiteSpace($rawP)) { continue }
                                $cleanP = $rawP.Trim().Trim('"').Replace('\', '/')
                                if ($cleanP.StartsWith($normRoot + "/", [System.StringComparison]::OrdinalIgnoreCase)) {
                                    $rel = Normalize-RepoPath ($cleanP.Substring($normRoot.Length + 1))
                                    if ($unowned.ContainsKey($rel)) {
                                        if (-not $ledger.chats.PSObject.Properties[$resolvedCid]) {
                                            $tLabel = if ($idInfo.Title) { $idInfo.Title } else { "Sohbet ($($resolvedCid.Substring(0, [Math]::Min(8, $resolvedCid.Length))))" }
                                            Set-ObjProp $ledger.chats $resolvedCid ([PSCustomObject]@{ title = $tLabel; lastSeenAt = "" })
                                        }
                                        if (-not $ledger.files.PSObject.Properties[$rel]) {
                                            Set-ObjProp $ledger.files $rel ([PSCustomObject]@{ editors = [PSCustomObject]@{} })
                                        }
                                        if (-not $ledger.files.$rel.editors.PSObject.Properties[$resolvedCid]) {
                                            Set-ObjProp $ledger.files.$rel.editors $resolvedCid ([PSCustomObject]@{ tool = "transcript_recovery" })
                                        }
                                    }
                                }
                            }
                        }
                    } catch {}
                }
            } finally { $sr.Dispose() }
        } catch {}
    }
    return $ledger
}

function Resolve-ChatDisplayTitle($ledger, $dbMap, [string]$cid) {
    if ([string]::IsNullOrWhiteSpace($cid)) { return "Bilinmeyen Sohbet" }
    if ($dbMap -and $dbMap.PSObject.Properties[$cid]) {
        $entry = $dbMap.$cid
        if ($entry -and -not [string]::IsNullOrWhiteSpace($entry.t)) { return ([string]$entry.t).Trim() }
    }
    if ($ledger -and $ledger.chats -and $ledger.chats.PSObject.Properties[$cid]) {
        $t = [string]$ledger.chats.$cid.title
        if (-not [string]::IsNullOrWhiteSpace($t)) { return $t }
    }
    $short = if ($cid.Length -ge 8) { $cid.Substring(0, 8) } else { $cid }
    return "Sohbet ($short)"
}

# --- STATUS, ZERO-LEAK & LINE STATS ---

function Get-StatusLabel([string]$xy) {
    if ($xy -eq "??") { return "Yeni (Takipsiz)" }
    if ($xy -match 'U|AA|DD') { return "Cakisma!" }
    $x = $xy[0]; $y = if ($xy.Length -ge 2) { $xy[1] } else { ' ' }
    if ($x -eq 'R' -or $y -eq 'R') { return "Tasindi/Yeniden Adlandirildi" }
    if ($x -eq 'C' -or $y -eq 'C') { return "Kopyalandi" }
    if ($x -eq 'D' -or $y -eq 'D') { return "Silindi" }
    if ($x -eq 'A') { return "Yeni (Sahneli)" }
    if ($x -eq 'M' -or $y -eq 'M') { return "Degisti" }
    return "Degisti ($xy)"
}

function Test-ContainsSecretPattern([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return @{ IsLeak = $false; Reason = "" } }
    $secretPatterns = @(
        @{ Name = "AWS Access Key"; Pattern = 'AKIA[0-9A-Z]{16}' },
        @{ Name = "OpenAI/API Secret Key"; Pattern = '(?<![a-zA-Z0-9_-])sk-(?:proj-|svcacct-|admin-)[a-zA-Z0-9_-]{20,}|(?<![a-zA-Z0-9_-])sk-[a-zA-Z0-9]{20,}' },
        @{ Name = "Stripe Secret Key"; Pattern = '(sk|rk)_(live|test)_[0-9a-zA-Z]{24,}' },
        @{ Name = "GitHub Personal Token"; Pattern = 'ghp_[0-9a-zA-Z]{36}' },
        @{ Name = "Private Key Block"; Pattern = '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' }
    )
    foreach ($sp in $secretPatterns) {
        if ($text -match $sp.Pattern) {
            return @{ IsLeak = $true; Reason = "$($sp.Name) tespit edildi" }
        }
    }
    return @{ IsLeak = $false; Reason = "" }
}

function Test-ZeroLeakFile([string]$rootDir, [string]$relPath, [string]$statusXy) {
    $norm = Normalize-RepoPath $relPath
    $leaf = [System.IO.Path]::GetFileName($norm)

    if ($leaf -match '^\.env(\..+)?$') {
        if ($leaf -notmatch '^\.env\.(example|template|sample)$') {
            return @{ IsLeak = $true; Reason = "Hassas ortam dosyasi ($leaf)" }
        }
    }
    if ($norm -match '\.(pem|key|p12|pfx)$' -or $leaf -in @('id_rsa', 'id_ed25519', 'id_dsa', 'secrets.json')) {
        return @{ IsLeak = $true; Reason = "Ozel anahtar/gizli dosya ($leaf)" }
    }
    if ($statusXy -match 'D') {
        return @{ IsLeak = $false; Reason = ""; IsBinary = $false }
    }

    $fullPath = Join-Path $rootDir ($norm.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        return @{ IsLeak = $false; Reason = ""; IsBinary = $false }
    }

    try {
        $info = Get-Item -LiteralPath $fullPath
        if ($info.Length -gt 2097152) {
            return @{ IsLeak = $false; Reason = ""; IsBinary = $false }
        }
        $bytes = [System.IO.File]::ReadAllBytes($fullPath)
        foreach ($b in $bytes) {
            if ($b -eq 0) { return @{ IsLeak = $false; Reason = ""; IsBinary = $true } }
        }
        $content = [System.Text.Encoding]::UTF8.GetString($bytes)
        $hit = Test-ContainsSecretPattern $content
        if ($hit.IsLeak) {
            return @{ IsLeak = $true; Reason = $hit.Reason; IsBinary = $false }
        }
    } catch {}
    return @{ IsLeak = $false; Reason = ""; IsBinary = $false }
}

function Get-NumstatMap([string]$rootDir, [string]$baseRef, [switch]$CachedOnly) {
    $map = @{}
    $gitArgs = if ($CachedOnly) {
        @("diff", "--cached", "--numstat", "--no-renames", "-z")
    } elseif (-not [string]::IsNullOrWhiteSpace($baseRef) -and $baseRef -ne "UNBORN") {
        @("diff", $baseRef, "--numstat", "--no-renames", "-z")
    } else {
        @("diff", "--numstat", "--no-renames", "-z")
    }
    $res = Invoke-GitRaw -WorkingDir $rootDir -GitArgs $gitArgs -UseQuotepathFalse
    if ($res.ExitCode -ne 0 -or [string]::IsNullOrEmpty($res.StdOut)) { return $map }

    foreach ($rec in $res.StdOut.Split([char]0)) {
        if ([string]::IsNullOrEmpty($rec)) { continue }
        $cols = $rec -split "`t", 3
        if ($cols.Count -lt 3) { continue }
        $p = Normalize-RepoPath $cols[2]
        $isBin = ($cols[0] -eq "-" -or $cols[1] -eq "-")
        $add = if ($cols[0] -match '^\d+$') { [int]$cols[0] } else { 0 }
        $del = if ($cols[1] -match '^\d+$') { [int]$cols[1] } else { 0 }
        $map[$p] = @{ Added = $add; Deleted = $del; IsBinary = $isBin }
    }
    return $map
}

function Get-TextFileLineCount([string]$fullPath) {
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return @{ Lines = 0; IsBinary = $false } }
    try {
        $info = Get-Item -LiteralPath $fullPath
        if ($info.Length -eq 0) { return @{ Lines = 0; IsBinary = $false } }
        $bytes = [System.IO.File]::ReadAllBytes($fullPath)
        $limit = [Math]::Min($bytes.Length, 8192)
        for ($i = 0; $i -lt $limit; $i++) {
            if ($bytes[$i] -eq 0) { return @{ Lines = 0; IsBinary = $true } }
        }
        $txt = [System.Text.Encoding]::UTF8.GetString($bytes)
        $arr = @($txt -split "`r?`n")
        $cnt = $arr.Count
        if ($cnt -gt 0 -and $arr[$cnt - 1] -eq "") { $cnt-- }
        return @{ Lines = [Math]::Max(0, $cnt); IsBinary = $false }
    } catch {
        return @{ Lines = 0; IsBinary = $false }
    }
}

function Get-WorkingTreeEntriesWithStats([string]$rootDir, [string]$baseRef, [switch]$SkipWorktreeFolder) {
    $res = Invoke-GitRaw -WorkingDir $rootDir -GitArgs @("status", "--porcelain=v1", "-uall", "-z") -UseQuotepathFalse
    $entries = [System.Collections.Generic.List[object]]::new()
    if ($res.ExitCode -ne 0 -or [string]::IsNullOrEmpty($res.StdOut)) { return ,@() }

    $numMap = if ($baseRef -eq "UNBORN") {
        Get-NumstatMap -rootDir $rootDir -baseRef "" -CachedOnly
    } else {
        Get-NumstatMap -rootDir $rootDir -baseRef $baseRef
    }

    $parts = $res.StdOut.Split([char]0)
    $i = 0
    while ($i -lt $parts.Length) {
        $tok = $parts[$i]
        if ([string]::IsNullOrEmpty($tok) -or $tok.Length -lt 4) { $i++; continue }
        $xy = $tok.Substring(0, 2)
        $normPath = Normalize-RepoPath ($tok.Substring(3))
        $origPath = $null
        if ($xy[0] -in @('R', 'C') -or $xy[1] -in @('R', 'C')) {
            if (($i + 1) -lt $parts.Length -and -not [string]::IsNullOrEmpty($parts[$i + 1])) {
                $origPath = Normalize-RepoPath $parts[$i + 1]
            }
            $i += 2
        } else {
            $i += 1
        }
        if ($SkipWorktreeFolder -and $normPath -match '^\.worktrees(/|$)') { continue }

        $leak = Test-ZeroLeakFile -rootDir $rootDir -relPath $normPath -statusXy $xy
        $add = 0; $del = 0; $isBin = [bool]$leak.IsBinary

        if ($numMap.ContainsKey($normPath)) {
            $add = $numMap[$normPath].Added
            $del = $numMap[$normPath].Deleted
            if ($numMap[$normPath].IsBinary) { $isBin = $true }
        } elseif ($xy -eq "??" -or $xy[0] -eq 'A') {
            $lc = Get-TextFileLineCount (Join-Path $rootDir ($normPath.Replace('/', '\')))
            $add = $lc.Lines
            if ($lc.IsBinary) { $isBin = $true }
        }

        $entries.Add([PSCustomObject]@{
            path         = $normPath
            origPath     = $origPath
            status       = $xy
            statusLabel  = (Get-StatusLabel $xy)
            addedLines   = $add
            deletedLines = $del
            isBinary     = $isBin
            isLeak       = [bool]$leak.IsLeak
            leakReason   = [string]$leak.Reason
        })
    }
    return ,@($entries.ToArray())
}

function Test-PathMatchesFilter([string]$relPath, [string[]]$filters) {
    if (-not $filters -or $filters.Count -eq 0) { return $true }
    $normPath = Normalize-RepoPath $relPath
    $leaf = [System.IO.Path]::GetFileName($normPath)

    foreach ($rawF in $filters) {
        if ([string]::IsNullOrWhiteSpace($rawF)) { continue }
        $f = Normalize-RepoPath $rawF
        if ($normPath -ieq $f -or $leaf -ieq $f) { return $true }
        if ($normPath.StartsWith("$f/", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($normPath.EndsWith("/$f", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($f -match '[\*\?]') {
            $wc = New-Object System.Management.Automation.WildcardPattern ($f, [System.Management.Automation.WildcardOptions]::IgnoreCase)
            if ($wc.IsMatch($normPath) -or $wc.IsMatch($leaf)) { return $true }
        }
    }
    return $false
}

function Get-SafeFileDiff([string]$rootDir, $item, [string]$baseRef, [int]$maxLines) {
    if ($item.isLeak) {
        return "[GUVENLIK: Zero-Leak nedeniyle icerik maskelendi ($($item.leakReason))]"
    }
    if ($item.isBinary) {
        return "[Ikili dosya: satir ici diff atlandi]"
    }

    $fullPath = Join-Path $rootDir ($item.path.Replace('/', '\'))
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        try {
            if ((Get-Item -LiteralPath $fullPath).Length -gt 1048576) {
                return "[Buyuk dosya (>1MB): satir ici diff atlandi]"
            }
        } catch {}
    }

    $rawDiff = ""
    if ($item.status -eq "??") {
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            try {
                $lines = [System.IO.File]::ReadAllLines($fullPath, [System.Text.Encoding]::UTF8)
                $sb = [System.Text.StringBuilder]::new()
                [void]$sb.AppendLine("--- /dev/null")
                [void]$sb.AppendLine("+++ b/$($item.path)")
                foreach ($l in $lines) { [void]$sb.AppendLine("+$l") }
                $rawDiff = $sb.ToString()
            } catch {}
        }
    } else {
        $dArgs = if ($baseRef -eq "UNBORN") {
            @("diff", "--cached", "--", $item.path)
        } else {
            @("diff", $baseRef, "--", $item.path)
        }
        $dRes = Invoke-GitRaw -WorkingDir $rootDir -GitArgs $dArgs -UseQuotepathFalse
        if ($dRes.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($dRes.StdOut)) {
            $rawDiff = $dRes.StdOut
        }
    }

    if ([string]::IsNullOrWhiteSpace($rawDiff)) { return "" }
    $diffLeak = Test-ContainsSecretPattern $rawDiff
    if ($diffLeak.IsLeak) {
        return "[GUVENLIK: Zero-Leak nedeniyle diff icerigi maskelendi ($($diffLeak.Reason))]"
    }
    $diffLines = @($rawDiff -split "`r?`n")
    if ($maxLines -gt 0 -and $diffLines.Count -gt $maxLines) {
        $kept = @($diffLines[0..($maxLines - 1)])
        $omitted = $diffLines.Count - $maxLines
        return (($kept -join "`n") + "`n... (toplam $($diffLines.Count) satir, $omitted satir kisaltildi)")
    }
    return ($diffLines -join "`n").TrimEnd("`r", "`n")
}

# --- UNPUSHED COMMITLER & WORKTREE KESFI ---

function Get-UnpushedCommitsAll($ctx, $ledger, $localSubMap, $dbMap) {
    $commits = [System.Collections.Generic.List[object]]::new()
    if ($ctx.HeadSha -eq "UNBORN") { return ,@() }

    $rangeArgs = $null
    $upRes = Invoke-GitRaw -WorkingDir $ctx.MainRepoRoot -GitArgs @("rev-parse", "--abbrev-ref", '@{u}')
    if ($upRes.ExitCode -eq 0) {
        $rangeArgs = @("log", '@{u}..HEAD', "--format=%H%x09%h%x09%s")
    } else {
        $hasRemRef = $false
        if ($ctx.Remote -and $ctx.Branch -ne "DETACHED") {
            $remRefRes = Invoke-GitRaw -WorkingDir $ctx.MainRepoRoot -GitArgs @("rev-parse", "--verify", "refs/remotes/$($ctx.Remote)/$($ctx.Branch)")
            if ($remRefRes.ExitCode -eq 0) { $hasRemRef = $true }
        }
        if ($hasRemRef) {
            $rangeArgs = @("log", "$($ctx.Remote)/$($ctx.Branch)..HEAD", "--format=%H%x09%h%x09%s")
        } else {
            # Remote veya upstream yoksa sadece henuz hicbir uzak dala gitmemis yerel commitleri tara
            $rangeArgs = @("log", "HEAD", "--not", "--remotes", "--format=%H%x09%h%x09%s")
        }
    }

    $logRes = Invoke-GitRaw -WorkingDir $ctx.MainRepoRoot -GitArgs $rangeArgs -UseQuotepathFalse
    if ($logRes.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($logRes.StdOut)) { return ,@() }

    foreach ($line in ($logRes.StdOut -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $cols = $line -split "`t", 3
        if ($cols.Count -lt 3) { continue }
        $sha = $cols[0].Trim(); $shortSha = $cols[1].Trim(); $subject = $cols[2].Trim()

        $filesRes = Invoke-GitRaw -WorkingDir $ctx.MainRepoRoot -GitArgs @("diff-tree", "--no-commit-id", "--name-status", "-r", $sha) -UseQuotepathFalse
        $cFiles = @()
        if ($filesRes.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($filesRes.StdOut)) {
            $cFiles = @($filesRes.StdOut -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
        }

        $ownerCid = ""
        if ($ledger -and $ledger.commits -and $ledger.commits.PSObject.Properties[$sha]) {
            $rawCid = [string]$ledger.commits.$sha.conversationId
            if (-not [string]::IsNullOrWhiteSpace($rawCid)) {
                $ownerCid = (Resolve-RootIdentity $rawCid $localSubMap $dbMap "").RootCid
            }
        }

        $commits.Add([PSCustomObject]@{
            sha      = $sha
            short    = $shortSha
            subject  = $subject
            files    = @($cFiles)
            ownerCid = $ownerCid
        })
    }
    return ,@($commits.ToArray())
}

function Get-RepoWorktreeSessions($ctx, $localSubMap, $dbMap) {
    $list = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-Path -LiteralPath $ctx.SessionsDir)) { return ,@() }

    foreach ($sf in (Get-ChildItem -Path $ctx.SessionsDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        try {
            $sRec = [System.IO.File]::ReadAllText($sf.FullName, [System.Text.Encoding]::UTF8).Trim().Trim([char]65279) | ConvertFrom-Json
            if (-not $sRec) { continue }
            if ($sRec.mode -ne "WORKTREE") { continue }
            if ($sRec.status -notin @("ACTIVE", "READY_TO_MERGE", "STALE", "COMPLETED")) { continue }
            if ([string]::IsNullOrWhiteSpace($sRec.worktreePath) -or -not (Test-Path -LiteralPath $sRec.worktreePath)) { continue }

            $idInfo = Resolve-RootIdentity ([string]$sRec.conversationId) $localSubMap $dbMap ""
            $baseSha = if ($sRec.baseHeadSha) { [string]$sRec.baseHeadSha } else { "HEAD" }

            $wtDotGit = Join-Path $sRec.worktreePath ".git"
            if (Test-Path -LiteralPath $wtDotGit -PathType Leaf) {
                try {
                    $gLine = (Get-Content -LiteralPath $wtDotGit -TotalCount 1 -Encoding UTF8).Trim()
                    if ($gLine -match '^gitdir:\s*(.+)$') {
                        $rawGd = $matches[1].Trim()
                        $wtGd = if ([System.IO.Path]::IsPathRooted($rawGd)) { [System.IO.Path]::GetFullPath($rawGd) } else { [System.IO.Path]::GetFullPath((Join-Path $sRec.worktreePath $rawGd)) }
                        Register-ReadOnlyTempIndex $sRec.worktreePath $wtGd
                    }
                } catch {}
            }

            # Worktree degisiklikleri (calisma agaci + varsa baseHeadSha uzerindeki worktree commitleri)
            $wtEntries = @(ConvertTo-Array (Get-WorkingTreeEntriesWithStats -rootDir $sRec.worktreePath -baseRef "HEAD"))
            $wtCommitted = @()
            $wtCommitLogs = @()

            $wtHeadRes = Invoke-GitRaw -WorkingDir $sRec.worktreePath -GitArgs @("rev-parse", "HEAD")
            $wtHeadSha = if ($wtHeadRes.ExitCode -eq 0) { $wtHeadRes.StdOut.Trim() } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($baseSha) -and $baseSha -ne "UNBORN" -and -not [string]::IsNullOrWhiteSpace($wtHeadSha) -and $wtHeadSha -ne $baseSha) {
                $diffCommitted = Invoke-GitRaw -WorkingDir $sRec.worktreePath -GitArgs @("diff", "--name-status", "--no-renames", "-z", "$baseSha..HEAD") -UseQuotepathFalse
                $numCommitted = Invoke-GitRaw -WorkingDir $sRec.worktreePath -GitArgs @("diff", "--numstat", "--no-renames", "-z", "$baseSha..HEAD") -UseQuotepathFalse
                $numMapC = @{}
                if ($numCommitted.ExitCode -eq 0 -and -not [string]::IsNullOrEmpty($numCommitted.StdOut)) {
                    foreach ($rec in $numCommitted.StdOut.Split([char]0)) {
                        if ([string]::IsNullOrEmpty($rec)) { continue }
                        $cols = $rec -split "`t", 3
                        if ($cols.Count -lt 3) { continue }
                        $numMapC[(Normalize-RepoPath $cols[2])] = @{
                            Added = if ($cols[0] -match '^\d+$') { [int]$cols[0] } else { 0 }
                            Deleted = if ($cols[1] -match '^\d+$') { [int]$cols[1] } else { 0 }
                            IsBinary = ($cols[0] -eq "-" -or $cols[1] -eq "-")
                        }
                    }
                }
                if ($diffCommitted.ExitCode -eq 0 -and -not [string]::IsNullOrEmpty($diffCommitted.StdOut)) {
                    $toks = $diffCommitted.StdOut.Split([char]0)
                    for ($k = 0; ($k + 1) -lt $toks.Length; $k += 2) {
                        if ([string]::IsNullOrEmpty($toks[$k])) { break }
                        $st = $toks[$k].Trim()
                        $rp = Normalize-RepoPath $toks[$k + 1]
                        if ([string]::IsNullOrWhiteSpace($rp)) { continue }
                        $ns = if ($numMapC.ContainsKey($rp)) { $numMapC[$rp] } else { @{ Added = 0; Deleted = 0; IsBinary = $false } }
                        $lk = Test-ZeroLeakFile -rootDir $sRec.worktreePath -relPath $rp -statusXy $st
                        $wtCommitted += [PSCustomObject]@{
                            path         = $rp
                            origPath     = $null
                            status       = $st
                            statusLabel  = (Get-StatusLabel $st)
                            addedLines   = $ns.Added
                            deletedLines = $ns.Deleted
                            isBinary     = ($ns.IsBinary -or $lk.IsBinary)
                            isLeak       = [bool]$lk.IsLeak
                            leakReason   = [string]$lk.Reason
                            fromCommit   = $true
                        }
                    }
                }

                $wtLogRes = Invoke-GitRaw -WorkingDir $sRec.worktreePath -GitArgs @("log", "$baseSha..HEAD", "--format=%H%x09%h%x09%s") -UseQuotepathFalse
                if ($wtLogRes.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($wtLogRes.StdOut)) {
                    foreach ($wl in ($wtLogRes.StdOut -split "`r?`n")) {
                        if ([string]::IsNullOrWhiteSpace($wl)) { continue }
                        $wc = $wl -split "`t", 3
                        if ($wc.Count -ge 3) {
                            $wtCommitLogs += [PSCustomObject]@{ sha = $wc[0].Trim(); short = $wc[1].Trim(); subject = $wc[2].Trim(); files = @() }
                        }
                    }
                }
            }

            # Uncommitted ve worktree-committed dosyalari tekil birlestir (uncommitted oncelikli)
            $combinedMap = [ordered]@{}
            foreach ($ce in $wtCommitted) { $combinedMap[$ce.path] = $ce }
            foreach ($we in $wtEntries)   { $combinedMap[$we.path] = $we }

            $list.Add([PSCustomObject]@{
                conversationId = $idInfo.RootCid
                shortId        = [string]$sRec.shortId
                status         = [string]$sRec.status
                worktreePath   = [string]$sRec.worktreePath
                branchName     = [string]$sRec.branchName
                baseHeadSha    = $baseSha
                items          = @($combinedMap.Values)
                commits        = @($wtCommitLogs)
            })
        } catch {}
    }
    return ,@($list.ToArray())
}

function Get-FileEditorsForEntry($ledger, [string]$relPath, [string]$origPath, $localSubMap, $dbMap) {
    $set = @{}
    foreach ($probe in @($relPath, $origPath)) {
        if ([string]::IsNullOrWhiteSpace($probe)) { continue }
        if ($ledger -and $ledger.files -and $ledger.files.PSObject.Properties[$probe]) {
            $ed = $ledger.files.$probe.editors
            if ($ed) {
                foreach ($p in $ed.PSObject.Properties) {
                    $rc = (Resolve-RootIdentity $p.Name $localSubMap $dbMap "").RootCid
                    if (-not [string]::IsNullOrWhiteSpace($rc)) { $set[$rc] = $true }
                }
            }
        }
    }
    return @($set.Keys)
}

function Build-PendingChatsCatalog($ctx, $ledger, $wtEntries, $worktrees, $unpushedCommits, $callerCid, $localSubMap, $dbMap) {
    $map = @{}
    $ensureChat = {
        param([string]$cid)
        if ([string]::IsNullOrWhiteSpace($cid)) { return }
        if (-not $map.ContainsKey($cid)) {
            $map[$cid] = @{
                conversationId       = $cid
                shortId              = if ($cid.Length -ge 8) { $cid.Substring(0, 8) } else { $cid }
                title                = (Resolve-ChatDisplayTitle $ledger $dbMap $cid)
                isCurrentChat        = ($cid -eq $callerCid)
                mainTreeFilesCount   = 0
                sharedFilesCount     = 0
                worktreeFilesCount   = 0
                unpushedCommitsCount = 0
                worktreeShortId      = ""
            }
        }
    }

    foreach ($wt in $wtEntries) {
        $eds = Get-FileEditorsForEntry $ledger $wt.path $wt.origPath $localSubMap $dbMap
        foreach ($e in $eds) {
            & $ensureChat $e
            $map[$e].mainTreeFilesCount++
            if ($eds.Count -gt 1) { $map[$e].sharedFilesCount++ }
        }
    }

    foreach ($w in $worktrees) {
        if (-not [string]::IsNullOrWhiteSpace($w.conversationId)) {
            & $ensureChat $w.conversationId
            $map[$w.conversationId].worktreeFilesCount += @($w.items).Count
            $map[$w.conversationId].worktreeShortId = $w.shortId
            $map[$w.conversationId].unpushedCommitsCount += @($w.commits).Count
        }
    }

    foreach ($c in $unpushedCommits) {
        if (-not [string]::IsNullOrWhiteSpace($c.ownerCid)) {
            & $ensureChat $c.ownerCid
            $map[$c.ownerCid].unpushedCommitsCount++
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($callerCid) -and $map.ContainsKey($callerCid)) {
        $map[$callerCid].isCurrentChat = $true
    }

    $sorted = @($map.Values | Sort-Object -Property @{ Expression = { if ($_.isCurrentChat) { 0 } else { 1 } } }, @{ Expression = { $_.title } }, @{ Expression = { $_.conversationId } })
    $idx = 1
    $res = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $sorted) {
        $item["index"] = $idx
        $res.Add([PSCustomObject]$item)
        $idx++
    }
    return ,@($res.ToArray())
}

function Resolve-TargetChatSelection([string]$targetArg, [string]$callerCid, $catalog, $ledger, $dbMap) {
    if ([string]::IsNullOrWhiteSpace($targetArg)) {
        if ([string]::IsNullOrWhiteSpace($callerCid)) {
            return @{ Status = "NO_CALLER"; Match = $null; Candidates = @() }
        }
        $hit = $catalog | Where-Object { $_.conversationId -eq $callerCid } | Select-Object -First 1
        $title = if ($hit) { $hit.title } else { (Resolve-ChatDisplayTitle $ledger $dbMap $callerCid) }
        return @{
            Status     = "OK"
            Match      = [PSCustomObject]@{ conversationId = $callerCid; title = $title; isCurrentChat = $true }
            Candidates = @()
        }
    }

    $q = $targetArg.Trim()
    if ($q -match '^\d+$') {
        $num = [int]$q
        $hit = $catalog | Where-Object { [int]$_.index -eq $num } | Select-Object -First 1
        if ($hit) { return @{ Status = "OK"; Match = $hit; Candidates = @() } }
    }

    # Tam eslesme (CID veya shortId veya pro-shortId)
    $exactHits = @($catalog | Where-Object {
        $_.conversationId -ieq $q -or
        $_.shortId -ieq $q -or
        ($_.worktreeShortId -and ($_.worktreeShortId -ieq $q -or "pro-$($_.worktreeShortId)" -ieq $q))
    })
    if ($exactHits.Count -eq 1) { return @{ Status = "OK"; Match = $exactHits[0]; Candidates = @() } }
    if ($exactHits.Count -gt 1) { return @{ Status = "AMBIGUOUS"; Match = $null; Candidates = $exactHits } }

    # Tam baslik eslesmesi
    $exactTitle = @($catalog | Where-Object { $_.title -ieq $q })
    if ($exactTitle.Count -eq 1) { return @{ Status = "OK"; Match = $exactTitle[0]; Candidates = @() } }
    if ($exactTitle.Count -gt 1) { return @{ Status = "AMBIGUOUS"; Match = $null; Candidates = $exactTitle } }

    # Kismi eslesme (ID oneki veya baslik alt metni)
    $partial = @($catalog | Where-Object {
        $_.conversationId.StartsWith($q, [System.StringComparison]::OrdinalIgnoreCase) -or
        $_.title.IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    })
    if ($partial.Count -eq 1) { return @{ Status = "OK"; Match = $partial[0]; Candidates = @() } }
    if ($partial.Count -gt 1) { return @{ Status = "AMBIGUOUS"; Match = $null; Candidates = $partial } }

    return @{ Status = "NOT_FOUND"; Match = $null; Candidates = @() }
}

# --- ANA AKIS ---

$script:ChatDiffExitCode = 0

function Invoke-ChatDiffMain {
    $ctx = Get-RepoContext
    if ($null -eq $ctx) { $script:ChatDiffExitCode = 1; return }
$dbMap = Get-DbChatMap $ctx.CommonGitDir
$localSubMap = Get-LocalSubagentMap $ctx.GitDir $ctx.CommonGitDir

$callerTitleHint = if (-not [string]::IsNullOrWhiteSpace($env:VIGILES_CONVERSATION_TITLE)) { $env:VIGILES_CONVERSATION_TITLE.Trim() } else { "" }
$callerInfo = Resolve-RootIdentity $CallerConversationId $localSubMap $dbMap $callerTitleHint
$callerCid = $callerInfo.RootCid

$ledger = Read-LedgerReadOnly $ctx.MainLedgerPath $ctx.CommonGitDir
if ($ctx.LedgerPath -ne $ctx.MainLedgerPath) {
    $wtLedger = Read-LedgerReadOnly $ctx.LedgerPath $ctx.GitDir
    $ledger = Merge-LedgerSnapshots $ledger $wtLedger
}

$wtEntriesAll = @(ConvertTo-Array (Get-WorkingTreeEntriesWithStats -rootDir $ctx.MainRepoRoot -baseRef $ctx.HeadSha -SkipWorktreeFolder))
$ledger = Add-TranscriptEditsInMemory $ctx $ledger $wtEntriesAll $localSubMap $dbMap
$worktreesAll = @(ConvertTo-Array (Get-RepoWorktreeSessions $ctx $localSubMap $dbMap))
$unpushedAll = @(ConvertTo-Array (Get-UnpushedCommitsAll $ctx $ledger $localSubMap $dbMap))

$catalog = @(ConvertTo-Array (Build-PendingChatsCatalog $ctx $ledger $wtEntriesAll $worktreesAll $unpushedAll $callerCid $localSubMap $dbMap))

# 1. --list MODU
if ($ListChats) {
    if ($Json) {
        $payloadOut = [PSCustomObject]@{
            repoRoot             = $ctx.MainRepoRoot
            branch               = $ctx.Branch
            callerConversationId = $callerCid
            chats                = @($catalog)
        }
        Write-Output ($payloadOut | ConvertTo-Json -Depth 6)
        $script:ChatDiffExitCode = 0
        return
    }

    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host ">> /chatdiff --list (BEKLEYEN DEGISIKLIGI OLAN SOHBETLER)" -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "   Proje  : $(Split-Path -Leaf $ctx.MainRepoRoot)  |  Branch: $($ctx.Branch)" -ForegroundColor Gray
    if ($catalog.Count -eq 0) {
        Write-Host "`n   (Bu projede herhangi bir sohbete zimmetli bekleyen degisiklik bulunmuyor)" -ForegroundColor DarkGray
        $script:ChatDiffExitCode = 0
        return
    }
    foreach ($c in $catalog) {
        $meTag = if ($c.isCurrentChat) { " [BU SOHBET]" } else { "" }
        $wtTag = if ($c.worktreeFilesCount -gt 0) { " | Worktree(pro-$($c.worktreeShortId)): $($c.worktreeFilesCount)" } else { "" }
        $cmTag = if ($c.unpushedCommitsCount -gt 0) { " | Yerel Commit: $($c.unpushedCommitsCount)" } else { "" }
        $shTag = if ($c.sharedFilesCount -gt 0) { " (Ortak: $($c.sharedFilesCount))" } else { "" }
        $col = if ($c.isCurrentChat) { "Green" } else { "White" }
        Write-Host ("   [{0}] {1} ({2}){3} -> Ana: {4} dosya{5}{6}{7}" -f $c.index, $c.title, $c.shortId, $meTag, $c.mainTreeFilesCount, $shTag, $wtTag, $cmTag) -ForegroundColor $col
    }
    Write-Host "`n   Ipucu: Tek sohbeti suzmek icin '/chatdiff <no|id|baslik>' kullanin." -ForegroundColor DarkGray
    $script:ChatDiffExitCode = 0
    return
}

# 2. HEDEF SOHBET COZUMLEME
$sel = Resolve-TargetChatSelection $TargetChat $callerCid $catalog $ledger $dbMap

if ($sel.Status -eq "NO_CALLER") {
    Write-Host "[HATA]: Mevcut sohbet kimligi tespit edilemedi. Lutfen '/chatdiff --list' veya '/chatdiff <sohbet>' kullanin." -ForegroundColor Red
    $script:ChatDiffExitCode = 1
    return
}

if ($sel.Status -eq "AMBIGUOUS") {
    Write-Host "`n[SECIM GEREKLI]: '$TargetChat' birden fazla sohbetle eslesti. Lutfen numara veya kisa ID belirtin:" -ForegroundColor Yellow
    foreach ($cand in $sel.Candidates) {
        $meTag = if ($cand.isCurrentChat) { " [BU SOHBET]" } else { "" }
        Write-Host ("   [{0}] {1} ({2}){3}" -f $cand.index, $cand.title, $cand.shortId, $meTag) -ForegroundColor White
    }
    $script:ChatDiffExitCode = 2
    return
}

if ($sel.Status -eq "NOT_FOUND") {
    Write-Host "[HATA]: '$TargetChat' ile eslesen bekleyen degisiklik sahibi sohbet bulunamadi." -ForegroundColor Red
    if ($catalog.Count -gt 0) {
        Write-Host "   Mevcut sohbetler icin '/chatdiff --list' calistirabilirsiniz." -ForegroundColor DarkGray
    }
    $script:ChatDiffExitCode = 1
    return
}

$targetCid = [string]$sel.Match.conversationId
$targetTitle = [string]$sel.Match.title
$isCurrent = ($targetCid -eq $callerCid)

# 3. HEDEF SOHBET ICIN FILTRELEME (YALNIZCA BEKLEYEN ISLER)
$mainItems = [System.Collections.Generic.List[object]]::new()
$otherChatsFiles = 0
$manualUntrackedFiles = 0
$idx = 1

foreach ($wt in $wtEntriesAll) {
    $eds = @(Get-FileEditorsForEntry $ledger $wt.path $wt.origPath $localSubMap $dbMap)
    if ($eds -contains $targetCid) {
        if (-not (Test-PathMatchesFilter $wt.path $Paths)) { continue }
        $otherCids = @($eds | Where-Object { $_ -ne $targetCid })
        $otherTitles = @($otherCids | ForEach-Object { Resolve-ChatDisplayTitle $ledger $dbMap $_ })
        $ownership = if ($otherCids.Count -gt 0) { "SHARED_MULTI_CHAT" } else { "OWNED_THIS_CHAT" }
        $diffTxt = if ($Diff) { Get-SafeFileDiff $ctx.MainRepoRoot $wt $ctx.HeadSha $MaxDiffLinesPerFile } else { "" }

        $mainItems.Add([PSCustomObject]@{
            id           = $idx
            path         = $wt.path
            origPath     = $wt.origPath
            status       = $wt.status
            statusLabel  = $wt.statusLabel
            ownership    = $ownership
            otherOwners  = @($otherTitles)
            addedLines   = $wt.addedLines
            deletedLines = $wt.deletedLines
            isBinary     = $wt.isBinary
            isLeak       = $wt.isLeak
            leakReason   = $wt.leakReason
            diff         = $diffTxt
        })
        $idx++
    } elseif ($eds.Count -gt 0) {
        $otherChatsFiles++
    } else {
        $manualUntrackedFiles++
    }
}

# Paralel Worktree (yalnizca hedef sohbete ait olanlar)
$targetWt = $worktreesAll | Where-Object { $_.conversationId -eq $targetCid } | Select-Object -First 1
$wtOutObj = $null
if ($targetWt) {
    $wtFilteredItems = [System.Collections.Generic.List[object]]::new()
    $wIdx = 1
    $wtDiffBase = if (-not [string]::IsNullOrWhiteSpace($targetWt.baseHeadSha) -and $targetWt.baseHeadSha -ne "UNBORN") { $targetWt.baseHeadSha } else { "HEAD" }
    foreach ($wi in $targetWt.items) {
        if (-not (Test-PathMatchesFilter $wi.path $Paths)) { continue }
        $wDiff = if ($Diff) { Get-SafeFileDiff $targetWt.worktreePath $wi $wtDiffBase $MaxDiffLinesPerFile } else { "" }
        $wtFilteredItems.Add([PSCustomObject]@{
            id           = $wIdx
            path         = $wi.path
            status       = $wi.status
            statusLabel  = $wi.statusLabel
            addedLines   = $wi.addedLines
            deletedLines = $wi.deletedLines
            isBinary     = $wi.isBinary
            isLeak       = $wi.isLeak
            leakReason   = $wi.leakReason
            diff         = $wDiff
        })
        $wIdx++
    }
    $wtOutObj = [PSCustomObject]@{
        shortId      = $targetWt.shortId
        worktreePath = $targetWt.worktreePath
        branchName   = $targetWt.branchName
        status       = $targetWt.status
        items        = @($wtFilteredItems.ToArray())
        commits      = @($targetWt.commits)
    }
}

# Pushlanmamis Yerel Commitler (yalnizca sahibi == hedef sohbet)
$targetCommits = [System.Collections.Generic.List[object]]::new()
$otherCommits = 0
foreach ($cm in $unpushedAll) {
    if ($cm.ownerCid -eq $targetCid) {
        $targetCommits.Add([PSCustomObject]@{
            sha     = $cm.sha
            short   = $cm.short
            subject = $cm.subject
            files   = @($cm.files)
        })
    } else {
        $otherCommits++
    }
}

# 4. JSON CIKTISI
if ($Json) {
    $jsonPayload = [PSCustomObject]@{
        repoRoot             = $ctx.MainRepoRoot
        branch               = $ctx.Branch
        callerConversationId = $callerCid
        targetConversationId = $targetCid
        targetTitle          = $targetTitle
        isCurrentChat        = $isCurrent
        mainTreeItems        = @($mainItems.ToArray())
        worktree             = $wtOutObj
        unpushedCommits      = @($targetCommits.ToArray())
        filteredCounts       = [PSCustomObject]@{
            otherChatsFiles      = $otherChatsFiles
            manualUntrackedFiles = $manualUntrackedFiles
            otherCommits         = $otherCommits
        }
    }
    Write-Output ($jsonPayload | ConvertTo-Json -Depth 7)
    $script:ChatDiffExitCode = 0
    return
}

# 5. TEMIZ KULLANICI RAPORU
$scopeBadge = if ($isCurrent) { "[BU SOHBET]" } else { "[SECILEN SOHBET]" }
$shortTarget = if ($targetCid.Length -ge 8) { $targetCid.Substring(0, 8) } else { $targetCid }

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host ">> /chatdiff - SOHBETE OZEL BEKLEYEN DEGISIKLIKLER" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Proje  : $(Split-Path -Leaf $ctx.MainRepoRoot)  |  Branch: $($ctx.Branch)" -ForegroundColor Gray
Write-Host "   Sohbet : $targetTitle ($shortTarget) $scopeBadge" -ForegroundColor Cyan

$totalAdd = ($mainItems | Measure-Object -Property addedLines -Sum).Sum
$totalDel = ($mainItems | Measure-Object -Property deletedLines -Sum).Sum
if ($null -eq $totalAdd) { $totalAdd = 0 }
if ($null -eq $totalDel) { $totalDel = 0 }

Write-Host "`n[A] ANA KLASORDE BEKLEYEN DOSYALAR ($($mainItems.Count) dosya | +$totalAdd / -$totalDel satir)" -ForegroundColor Green
if ($mainItems.Count -eq 0) {
    Write-Host "   (Bu sohbete ait ana klasorde bekleyen dosya yok)" -ForegroundColor DarkGray
} else {
    foreach ($it in $mainItems) {
        $statText = if ($it.isBinary) { "[Ikili]" } else { "+$($it.addedLines) / -$($it.deletedLines)" }
        $sharedNote = if ($it.ownership -eq "SHARED_MULTI_CHAT") { " [Ortak: $((ConvertTo-Array $it.otherOwners) -join ', ')]" } else { "" }
        $leakNote = if ($it.isLeak) { " [ZERO-LEAK UYARISI: $($it.leakReason)]" } else { "" }
        $col = if ($it.isLeak) { "Red" } elseif ($it.ownership -eq "SHARED_MULTI_CHAT") { "Yellow" } else { "White" }
        Write-Host ("   [{0}] [{1}] {2}  ({3} | {4}){5}{6}" -f $it.id, $it.status.Trim(), $it.path, $it.statusLabel, $statText, $sharedNote, $leakNote) -ForegroundColor $col
        if ($Diff -and -not [string]::IsNullOrWhiteSpace($it.diff)) {
            Write-Host "   --- Diff: $($it.path) ---" -ForegroundColor DarkCyan
            foreach ($dl in ($it.diff -split "`r?`n")) {
                $dCol = if ($dl.StartsWith("+") -and -not $dl.StartsWith("+++")) { "Green" } elseif ($dl.StartsWith("-") -and -not $dl.StartsWith("---")) { "Red" } elseif ($dl -match 'ZERO-LEAK|GUVENLIK') { "Yellow" } else { "DarkGray" }
                Write-Host "      $dl" -ForegroundColor $dCol
            }
        }
    }
}

if ($wtOutObj) {
    Write-Host "`n[B] PARALEL SANTIYE DEGISIKLIKLERI (pro-$($wtOutObj.shortId) | $($wtOutObj.status) | Henuz /merge edilmedi)" -ForegroundColor Cyan
    if ($wtOutObj.items.Count -eq 0 -and $wtOutObj.commits.Count -eq 0) {
        Write-Host "   (Bu paralel santiyede bekleyen dosya degisikligi yok)" -ForegroundColor DarkGray
    } else {
        foreach ($wi in $wtOutObj.items) {
            $wStat = if ($wi.isBinary) { "[Ikili]" } else { "+$($wi.addedLines) / -$($wi.deletedLines)" }
            $wLeak = if ($wi.isLeak) { " [ZERO-LEAK UYARISI: $($wi.leakReason)]" } else { "" }
            Write-Host ("   [W{0}] [{1}] {2}  ({3} | {4}){5}" -f $wi.id, $wi.status.Trim(), $wi.path, $wi.statusLabel, $wStat, $wLeak) -ForegroundColor White
            if ($Diff -and -not [string]::IsNullOrWhiteSpace($wi.diff)) {
                foreach ($dl in ($wi.diff -split "`r?`n")) {
                    Write-Host "      $dl" -ForegroundColor DarkGray
                }
            }
        }
        Write-Host "   -> Ana klasore aktarmak icin: /merge $($wtOutObj.shortId)" -ForegroundColor DarkCyan
    }
}

if ($targetCommits.Count -gt 0) {
    Write-Host "`n[C] PUSH BEKLEYEN YEREL COMMITLER ($($targetCommits.Count) adet)" -ForegroundColor Cyan
    foreach ($c in $targetCommits) {
        Write-Host ("   -> {0} {1}" -f $c.short, $c.subject) -ForegroundColor White
        foreach ($cf in (ConvertTo-Array $c.files)) {
            Write-Host ("      - {0}" -f $cf) -ForegroundColor DarkGray
        }
    }
}

$hasAny = ($mainItems.Count -gt 0) -or ($wtOutObj -and ($wtOutObj.items.Count -gt 0 -or $wtOutObj.commits.Count -gt 0)) -or ($targetCommits.Count -gt 0)
if (-not $hasAny) {
    Write-Host "`n[BILGI]: Bu sohbete ait GitHub'a gonderilmeyi bekleyen aktif bir degisiklik bulunmuyor." -ForegroundColor DarkGray
}

if ($otherChatsFiles -gt 0 -or $manualUntrackedFiles -gt 0 -or $otherCommits -gt 0) {
    Write-Host "`n----------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ("   Gizlenen gurultu: {0} diger sohbet dosyasi, {1} sohbet disi dosya, {2} diger yerel commit." -f $otherChatsFiles, $manualUntrackedFiles, $otherCommits) -ForegroundColor DarkGray
    Write-Host "   (Tumunu gormek icin '/pushprep', diger sohbetler icin '/chatdiff --list')" -ForegroundColor DarkGray
}

$script:ChatDiffExitCode = 0
return
}

try {
    Invoke-ChatDiffMain
} finally {
    Cleanup-TempIndexes
}
exit $script:ChatDiffExitCode
