# core/scripts/vigiles_session_manager.ps1
# Vigiles Engine - Hibrit Adaptif Coklu Oturum ve Worktree Yoneticisi (ADR-025 / Secenek C)
# Tek aktif /pro oturumunda MAIN_TREE; ayni repoda eszamanli 2.+ /pro oturumunda otomatik .worktrees/pro-<id> acar.

param(
    [ValidateSet("Start", "Heartbeat", "Complete", "Status", "Cleanup")]
    [string]$Action = "Status",
    [string]$ConversationId = "",
    [string]$ArtifactDir = "",
    [string]$WorkspacePath = "",
    [int]$TtlMinutes = 15,
    [switch]$ForceWorktree = $false,
    [switch]$Json = $false
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Format-ProcArg([string]$arg) {
    if ($null -eq $arg) { return '""' }
    if ($arg -eq "") { return '""' }
    if ($arg -notmatch '[\s"]') { return $arg }
    $escaped = [regex]::Replace($arg, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Invoke-GitRaw {
    param(
        [string]$WorkingDir,
        [string[]]$GitArgs
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "git"
    $psi.Arguments = (($GitArgs | ForEach-Object { Format-ProcArg $_ }) -join " ")
    if (-not [string]::IsNullOrWhiteSpace($WorkingDir) -and (Test-Path -LiteralPath $WorkingDir)) {
        $psi.WorkingDirectory = $WorkingDir
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()

    return @{
        ExitCode = $proc.ExitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}

function Normalize-WinPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return "" }
    try {
        return [System.IO.Path]::GetFullPath($p.Trim().Replace('/', '\')).TrimEnd('\')
    } catch {
        return $p.Trim().Replace('/', '\').TrimEnd('\')
    }
}

function Get-SafeKey([string]$cid, [string]$fallbackSeed = "") {
    $raw = if (-not [string]::IsNullOrWhiteSpace($cid)) { $cid } else { $fallbackSeed }
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return "session_" + [guid]::NewGuid().ToString("N").Substring(0, 12)
    }
    $clean = ($raw -replace '[^a-zA-Z0-9\-_]', '_')
    if ($clean.Length -gt 64) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($raw))
            $hex = ([BitConverter]::ToString($h) -replace '-', '').ToLowerInvariant().Substring(0, 16)
        } finally { $sha.Dispose() }
        return $clean.Substring(0, 32) + "_" + $hex
    }
    return $clean
}

function Get-ShortSessionId([string]$cid, [string]$fallbackSeed = "") {
    $seed = if (-not [string]::IsNullOrWhiteSpace($cid)) { $cid } elseif (-not [string]::IsNullOrWhiteSpace($fallbackSeed)) { $fallbackSeed } else { [guid]::NewGuid().ToString("N") }
    $clean = ($seed -replace '[^a-zA-Z0-9\-_]', '_')
    if ($clean -match '^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$') {
        return $clean.Substring(0, 8).ToLowerInvariant()
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($seed))
        $hex = ([BitConverter]::ToString($h) -replace '-', '').ToLowerInvariant().Substring(0, 4)
    } finally { $sha.Dispose() }
    $prefix = if ($clean.Length -gt 12) { $clean.Substring(0, 12).TrimEnd('-', '_') } else { $clean }
    if ([string]::IsNullOrWhiteSpace($prefix)) { $prefix = "pro" }
    return "$prefix-$hex"
}

function Get-RepoCommonContext([string]$wsPath) {
    if ([string]::IsNullOrWhiteSpace($wsPath) -or -not (Test-Path -LiteralPath $wsPath)) {
        return @{ IsGitRepo = $false }
    }
    $wsNorm = Normalize-WinPath $wsPath
    $insideRes = Invoke-GitRaw -WorkingDir $wsNorm -GitArgs @("rev-parse", "--is-inside-work-tree")
    if ($insideRes.ExitCode -ne 0 -or $insideRes.StdOut.Trim() -ne "true") {
        return @{ IsGitRepo = $false }
    }

    $topRes = Invoke-GitRaw -WorkingDir $wsNorm -GitArgs @("rev-parse", "--show-toplevel")
    $topLevel = Normalize-WinPath $topRes.StdOut.Trim()

    $commonRes = Invoke-GitRaw -WorkingDir $wsNorm -GitArgs @("rev-parse", "--git-common-dir")
    $commonRaw = $commonRes.StdOut.Trim().Replace('/', '\')
    if (-not [System.IO.Path]::IsPathRooted($commonRaw)) {
        $commonGitDir = Normalize-WinPath (Join-Path $wsNorm $commonRaw)
    } else {
        $commonGitDir = Normalize-WinPath $commonRaw
    }

    $mainRepoRoot = if ((Split-Path -Leaf $commonGitDir) -ieq ".git") {
        Normalize-WinPath (Split-Path -Parent $commonGitDir)
    } else {
        $topLevel
    }

    $headRes = Invoke-GitRaw -WorkingDir $mainRepoRoot -GitArgs @("rev-parse", "HEAD")
    $headSha = if ($headRes.ExitCode -eq 0) { $headRes.StdOut.Trim() } else { "UNBORN" }

    $sessionsDir = Join-Path $commonGitDir "vigiles\sessions"

    return @{
        IsGitRepo     = $true
        WorkspacePath = $wsNorm
        TopLevel      = $topLevel
        CommonGitDir  = $commonGitDir
        MainRepoRoot  = $mainRepoRoot
        HeadSha       = $headSha
        SessionsDir   = $sessionsDir
    }
}

function Acquire-RepoMutex([string]$commonGitDir) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($commonGitDir.ToLowerInvariant()))
        $hex = ([BitConverter]::ToString($h) -replace '-', '').ToLowerInvariant().Substring(0, 16)
    } finally { $sha.Dispose() }

    $mutexName = "Local\VigilesSession_$hex"
    $mtx = New-Object System.Threading.Mutex($false, $mutexName)
    $acquired = $false
    try {
        $acquired = $mtx.WaitOne(10000)
    } catch [System.Threading.AbandonedMutexException] {
        $acquired = $true
    }
    return @{ Mutex = $mtx; Acquired = $acquired }
}

function Release-RepoMutex($lockObj) {
    if ($null -eq $lockObj) { return }
    try {
        if ($lockObj.Acquired -and $lockObj.Mutex) {
            $lockObj.Mutex.ReleaseMutex()
        }
    } catch {}
    try {
        if ($lockObj.Mutex) { $lockObj.Mutex.Dispose() }
    } catch {}
}

function Ensure-GitInfoExclude([string]$commonGitDir, [string[]]$patterns) {
    $infoDir = Join-Path $commonGitDir "info"
    $excludeFile = Join-Path $infoDir "exclude"
    if (-not (Test-Path -LiteralPath $infoDir)) {
        New-Item -ItemType Directory -Path $infoDir -Force | Out-Null
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    $existing = @{}
    if (Test-Path -LiteralPath $excludeFile) {
        $raw = [System.IO.File]::ReadAllText($excludeFile, [System.Text.Encoding]::UTF8)
        if (-not [string]::IsNullOrEmpty($raw)) {
            foreach ($l in ($raw -split "`r?`n")) {
                $lines.Add($l)
                $t = $l.Trim()
                if (-not [string]::IsNullOrEmpty($t)) { $existing[$t] = $true }
            }
        }
    }
    $changed = $false
    foreach ($pat in $patterns) {
        if (-not $existing.ContainsKey($pat)) {
            if ($lines.Count -gt 0 -and [string]::IsNullOrEmpty($lines[$lines.Count - 1])) {
                $lines[$lines.Count - 1] = $pat
            } else {
                $lines.Add($pat)
            }
            $existing[$pat] = $true
            $changed = $true
        }
    }
    if ($changed -or -not (Test-Path -LiteralPath $excludeFile)) {
        $content = ($lines.ToArray() -join "`n").TrimEnd("`n") + "`n"
        [System.IO.File]::WriteAllText($excludeFile, $content, $Utf8NoBom)
    }
}

function Read-JsonObject([string]$path) {
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8).Trim().Trim([char]65279)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Write-JsonObject([string]$path, $obj) {
    $parent = Split-Path -Parent $path
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $json = $obj | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($path, $json, $Utf8NoBom)
}

function Test-SessionHeartbeatFresh($sessionObj, [int]$ttlMin) {
    if (-not $sessionObj -or $sessionObj.status -ne "ACTIVE") { return $false }
    $hbStr = if ($sessionObj.lastHeartbeatAt) { [string]$sessionObj.lastHeartbeatAt } else { [string]$sessionObj.startedAt }
    if ([string]::IsNullOrWhiteSpace($hbStr)) { return $false }
    try {
        $hbTime = [datetimeoffset]::Parse($hbStr)
        $ageMin = ([datetimeoffset]::UtcNow - $hbTime.ToUniversalTime()).TotalMinutes
        return ($ageMin -le $ttlMin)
    } catch {
        return $false
    }
}

function Unlink-WorktreeJunctions([string]$worktreePath) {
    if ([string]::IsNullOrWhiteSpace($worktreePath) -or -not (Test-Path -LiteralPath $worktreePath)) { return }
    $depFolders = @("node_modules", ".venv", "venv", "vendor")
    foreach ($dep in $depFolders) {
        $candidate = Join-Path $worktreePath $dep
        if (Test-Path -LiteralPath $candidate) {
            try {
                $item = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
                if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                    # Yalnizca junction bagini kaldirir; hedef klasore ve icerigine ASLA dokunmaz
                    [System.IO.Directory]::Delete($candidate)
                }
            } catch {}
        }
    }
}

function Remove-WorktreeSafely([string]$mainRepoRoot, [string]$worktreePath, [string]$branchName) {
    if (-not [string]::IsNullOrWhiteSpace($worktreePath) -and (Test-Path -LiteralPath $worktreePath)) {
        Unlink-WorktreeJunctions -worktreePath $worktreePath
        # Kopyalanmis gecici .env* dosyalarini temizle (takip edilmeyenler)
        Get-ChildItem -Path $worktreePath -Filter ".env*" -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '^\.env\.(example|template|sample)$' } |
            ForEach-Object {
                $rel = $_.Name
                $chk = Invoke-GitRaw -WorkingDir $mainRepoRoot -GitArgs @("ls-files", "--error-unmatch", $rel)
                if ($chk.ExitCode -ne 0) {
                    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                }
            }
        $rmRes = Invoke-GitRaw -WorkingDir $mainRepoRoot -GitArgs @("worktree", "remove", "--force", $worktreePath)
        if ($rmRes.ExitCode -ne 0 -and (Test-Path -LiteralPath $worktreePath)) {
            Unlink-WorktreeJunctions -worktreePath $worktreePath
            Remove-Item -LiteralPath $worktreePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $null = Invoke-GitRaw -WorkingDir $mainRepoRoot -GitArgs @("worktree", "prune")
    if (-not [string]::IsNullOrWhiteSpace($branchName)) {
        $null = Invoke-GitRaw -WorkingDir $mainRepoRoot -GitArgs @("branch", "-D", $branchName)
    }
}

function Initialize-WorktreeDependencies([string]$mainRepoRoot, [string]$commonGitDir, [string]$worktreePath) {
    $linked = [System.Collections.Generic.List[string]]::new()
    $copiedEnv = [System.Collections.Generic.List[string]]::new()

    $depFolders = @("node_modules", ".venv", "venv", "vendor")
    foreach ($dep in $depFolders) {
        $srcDep = Join-Path $mainRepoRoot $dep
        $dstDep = Join-Path $worktreePath $dep
        if ((Test-Path -LiteralPath $srcDep -PathType Container) -and -not (Test-Path -LiteralPath $dstDep)) {
            # Eger gitignore'da degilse .git/info/exclude'a ekle ki diff/status kirlenmesin
            $ignChk = Invoke-GitRaw -WorkingDir $mainRepoRoot -GitArgs @("check-ignore", "-q", "$dep/")
            if ($ignChk.ExitCode -ne 0) {
                Ensure-GitInfoExclude -commonGitDir $commonGitDir -patterns @("$dep/")
            }
            $cmdOut = & cmd.exe /c "mklink /J `"$dstDep`" `"$srcDep`"" 2>&1
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $dstDep)) {
                $linked.Add($dep)
            }
        }
    }

    # .env* dosyalarini kopyala (.env.example/.template/.sample haric)
    Get-ChildItem -Path $mainRepoRoot -Filter ".env*" -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '^\.env\.(example|template|sample)$' } |
        ForEach-Object {
            $dstEnv = Join-Path $worktreePath $_.Name
            if (-not (Test-Path -LiteralPath $dstEnv)) {
                $ignChk = Invoke-GitRaw -WorkingDir $mainRepoRoot -GitArgs @("check-ignore", "-q", $_.Name)
                if ($ignChk.ExitCode -ne 0) {
                    Ensure-GitInfoExclude -commonGitDir $commonGitDir -patterns @($_.Name)
                }
                Copy-Item -LiteralPath $_.FullName -Destination $dstEnv -Force -ErrorAction SilentlyContinue
                if (Test-Path -LiteralPath $dstEnv) {
                    $copiedEnv.Add($_.Name)
                }
            }
        }

    return @{
        Junctions = @($linked.ToArray())
        EnvFiles  = @($copiedEnv.ToArray())
    }
}

function Get-DirtyEntriesExcludingWorktrees([string]$repoRoot) {
    $res = Invoke-GitRaw -WorkingDir $repoRoot -GitArgs @("-c", "core.quotepath=false", "status", "--porcelain=v1", "-uall", "-z")
    $list = [System.Collections.Generic.List[string]]::new()
    if ($res.ExitCode -ne 0 -or [string]::IsNullOrEmpty($res.StdOut)) { return @() }
    $parts = $res.StdOut.Split([char]0)
    $i = 0
    while ($i -lt $parts.Length) {
        $tok = $parts[$i]
        if ([string]::IsNullOrEmpty($tok) -or $tok.Length -lt 4) { $i++; continue }
        $xy = $tok.Substring(0, 2)
        $p = $tok.Substring(3).Replace('\', '/')
        if ($xy[0] -in @('R', 'C') -or $xy[1] -in @('R', 'C')) { $i += 2 } else { $i += 1 }
        if ($p -notmatch '^\.worktrees(/|$)') {
            $list.Add($p)
        }
    }
    return @($list.ToArray())
}

function Write-ArtifactMarkers([string]$artDir, $sessionObj, [string]$sessionFilePath) {
    if ([string]::IsNullOrWhiteSpace($artDir)) { return }
    if (-not (Test-Path -LiteralPath $artDir)) {
        try { New-Item -ItemType Directory -Path $artDir -Force | Out-Null } catch { return }
    }

    $sessionPointer = @{
        conversationId   = $sessionObj.conversationId
        shortId          = $sessionObj.shortId
        mode             = $sessionObj.mode
        repoRoot         = $sessionObj.repoRoot
        commonGitDir     = $sessionObj.commonGitDir
        effectiveWorkDir = $sessionObj.effectiveWorkDir
        worktreePath     = $sessionObj.worktreePath
        sessionFile      = $sessionFilePath
    }
    Write-JsonObject -path (Join-Path $artDir ".vigiles_session") -obj $sessionPointer

    $wtMarker = Join-Path $artDir ".vigiles_worktree"
    if ($sessionObj.mode -eq "WORKTREE" -and -not [string]::IsNullOrWhiteSpace($sessionObj.worktreePath)) {
        Write-JsonObject -path $wtMarker -obj $sessionPointer
    } else {
        if (Test-Path -LiteralPath $wtMarker) {
            Remove-Item -LiteralPath $wtMarker -Force -ErrorAction SilentlyContinue
        }
    }
}

function Emit-Output($obj) {
    if ($Json) {
        Write-Output ($obj | ConvertTo-Json -Depth 6 -Compress)
    } else {
        Write-Output ($obj | ConvertTo-Json -Depth 6)
    }
}

# --- ANA AKIS ---
$ctx = Get-RepoCommonContext -wsPath $WorkspacePath

if (-not $ctx.IsGitRepo) {
    $noGitOut = @{
        isGitRepo        = $false
        mode             = "NO_GIT"
        effectiveWorkDir = if (-not [string]::IsNullOrWhiteSpace($WorkspacePath)) { Normalize-WinPath $WorkspacePath } else { "" }
        worktreePath     = ""
        branchName       = ""
        preExistingDirty = @()
        activeOthers     = @()
    }
    Emit-Output $noGitOut
    exit 0
}

$safeKey = Get-SafeKey -cid $ConversationId -fallbackSeed $ArtifactDir
$shortId = Get-ShortSessionId -cid $ConversationId -fallbackSeed $ArtifactDir
$sessionFile = Join-Path $ctx.SessionsDir "$safeKey.json"

$lock = Acquire-RepoMutex -commonGitDir $ctx.CommonGitDir
try {
    if (-not (Test-Path -LiteralPath $ctx.SessionsDir)) {
        New-Item -ItemType Directory -Path $ctx.SessionsDir -Force | Out-Null
    }

    # Mevcut oturumlari tara ve bayat (stale) kilitleri dusur
    $allFiles = @(Get-ChildItem -Path $ctx.SessionsDir -Filter "*.json" -File -ErrorAction SilentlyContinue)
    $activeMainOwner = $null
    $otherActive = [System.Collections.Generic.List[object]]::new()
    $allRecords = [System.Collections.Generic.List[object]]::new()

    foreach ($f in $allFiles) {
        $rec = Read-JsonObject -path $f.FullName
        if (-not $rec) { continue }

        if ($rec.status -eq "ACTIVE" -and -not (Test-SessionHeartbeatFresh -sessionObj $rec -ttlMin $TtlMinutes)) {
            $rec | Add-Member -NotePropertyName "status" -NotePropertyValue "STALE" -Force
            $rec | Add-Member -NotePropertyName "staleDetectedAt" -NotePropertyValue ([datetimeoffset]::Now.ToString("o")) -Force
            Write-JsonObject -path $f.FullName -obj $rec
        }

        $allRecords.Add($rec)

        if ($rec.conversationId -ne $ConversationId -and $rec.status -eq "ACTIVE") {
            $otherActive.Add($rec)
            if ($rec.mode -eq "MAIN_TREE") {
                $activeMainOwner = $rec
            }
        }
    }

    if ($Action -eq "Status") {
        $pendingWt = @($allRecords | Where-Object { $_.mode -eq "WORKTREE" -and $_.status -in @("ACTIVE", "READY_TO_MERGE", "STALE", "COMPLETED") -and $_.worktreePath -and (Test-Path -LiteralPath $_.worktreePath) })
        $out = @{
            isGitRepo         = $true
            repoRoot          = $ctx.MainRepoRoot
            commonGitDir      = $ctx.CommonGitDir
            activeMainOwner   = if ($activeMainOwner) { $activeMainOwner.conversationId } else { "" }
            activeCount       = @($allRecords | Where-Object { $_.status -eq "ACTIVE" }).Count
            pendingWorktrees  = @($pendingWt | ForEach-Object { @{ shortId = $_.shortId; conversationId = $_.conversationId; status = $_.status; worktreePath = $_.worktreePath; branchName = $_.branchName } })
        }
        Emit-Output $out
        exit 0
    }

    if ($Action -eq "Heartbeat") {
        $cur = Read-JsonObject -path $sessionFile
        if ($cur) {
            $cur | Add-Member -NotePropertyName "lastHeartbeatAt" -NotePropertyValue ([datetimeoffset]::Now.ToString("o")) -Force
            if ($cur.status -in @("STALE", "READY_TO_MERGE", "COMPLETED")) {
                $cur | Add-Member -NotePropertyName "status" -NotePropertyValue "ACTIVE" -Force
            }
            Write-JsonObject -path $sessionFile -obj $cur
        }
        Emit-Output @{ updated = ($null -ne $cur) }
        exit 0
    }

    if ($Action -eq "Complete") {
        $cur = Read-JsonObject -path $sessionFile
        if ($cur) {
            $nowIso = [datetimeoffset]::Now.ToString("o")
            $cur | Add-Member -NotePropertyName "completedAt" -NotePropertyValue $nowIso -Force
            if ($cur.mode -eq "WORKTREE" -and $cur.worktreePath -and (Test-Path -LiteralPath $cur.worktreePath)) {
                $dirtyWt = Get-DirtyEntriesExcludingWorktrees -repoRoot $cur.worktreePath
                $aheadRes = if ($cur.baseHeadSha -and $cur.baseHeadSha -ne "UNBORN") {
                    Invoke-GitRaw -WorkingDir $cur.worktreePath -GitArgs @("rev-list", "--count", "$($cur.baseHeadSha)..HEAD")
                } else { @{ ExitCode = 1; StdOut = "0" } }
                $aheadCount = 0
                try { $aheadCount = [int]$aheadRes.StdOut.Trim() } catch {}
                $nextStatus = if ($dirtyWt.Count -gt 0 -or $aheadCount -gt 0) { "READY_TO_MERGE" } else { "COMPLETED" }
                $cur | Add-Member -NotePropertyName "status" -NotePropertyValue $nextStatus -Force
            } else {
                $cur | Add-Member -NotePropertyName "status" -NotePropertyValue "COMPLETED" -Force
            }
            Write-JsonObject -path $sessionFile -obj $cur
        }
        Emit-Output @{ completed = ($null -ne $cur); status = if ($cur) { $cur.status } else { "" } }
        exit 0
    }

    if ($Action -eq "Cleanup") {
        $cur = Read-JsonObject -path $sessionFile
        if ($cur -and $cur.mode -eq "WORKTREE") {
            Remove-WorktreeSafely -mainRepoRoot $ctx.MainRepoRoot -worktreePath $cur.worktreePath -branchName $cur.branchName
            $cur | Add-Member -NotePropertyName "status" -NotePropertyValue "ABORTED" -Force
            Write-JsonObject -path $sessionFile -obj $cur
        }
        if (-not [string]::IsNullOrWhiteSpace($ArtifactDir)) {
            $wtm = Join-Path $ArtifactDir ".vigiles_worktree"
            if (Test-Path -LiteralPath $wtm) { Remove-Item -LiteralPath $wtm -Force -ErrorAction SilentlyContinue }
        }
        Emit-Output @{ cleaned = $true }
        exit 0
    }

    # Action -eq "Start"
    $nowIso = [datetimeoffset]::Now.ToString("o")
    $existingSelf = Read-JsonObject -path $sessionFile

    # 1. Ayni sohbet zaten aktif/hazir bir WORKTREE'ye sahipse onu yeniden kullan
    if ($existingSelf -and $existingSelf.mode -eq "WORKTREE" -and
        $existingSelf.status -in @("ACTIVE", "READY_TO_MERGE", "STALE", "COMPLETED") -and
        -not [string]::IsNullOrWhiteSpace($existingSelf.worktreePath) -and
        (Test-Path -LiteralPath $existingSelf.worktreePath)) {

        $existingSelf | Add-Member -NotePropertyName "status" -NotePropertyValue "ACTIVE" -Force
        $existingSelf | Add-Member -NotePropertyName "lastHeartbeatAt" -NotePropertyValue $nowIso -Force
        if (-not [string]::IsNullOrWhiteSpace($ArtifactDir)) {
            $existingSelf | Add-Member -NotePropertyName "artifactDir" -NotePropertyValue $ArtifactDir -Force
        }
        Write-JsonObject -path $sessionFile -obj $existingSelf
        Write-ArtifactMarkers -artDir $ArtifactDir -sessionObj $existingSelf -sessionFilePath $sessionFile

        $outReuse = @{
            isGitRepo        = $true
            mode             = "WORKTREE"
            reused           = $true
            shortId          = $existingSelf.shortId
            repoRoot         = $ctx.MainRepoRoot
            commonGitDir     = $ctx.CommonGitDir
            effectiveWorkDir = $existingSelf.worktreePath
            worktreePath     = $existingSelf.worktreePath
            branchName       = $existingSelf.branchName
            baseHeadSha      = $existingSelf.baseHeadSha
            sessionFile      = $sessionFile
            preExistingDirty = @()
            activeOthers     = @($otherActive | ForEach-Object { $_.shortId })
            junctions        = @()
            envFiles         = @()
        }
        Emit-Output $outReuse
        exit 0
    }

    # 2. Paralel cakisma var mi veya zorunlu worktree istendi mi?
    $needWorktree = ($ForceWorktree -or ($null -ne $activeMainOwner)) -and ($ctx.HeadSha -ne "UNBORN")

    if ($needWorktree) {
        Ensure-GitInfoExclude -commonGitDir $ctx.CommonGitDir -patterns @(".worktrees/", ".worktrees")

        $worktreesRoot = Join-Path $ctx.MainRepoRoot ".worktrees"
        if (-not (Test-Path -LiteralPath $worktreesRoot)) {
            New-Item -ItemType Directory -Path $worktreesRoot -Force | Out-Null
        }

        $worktreePath = Normalize-WinPath (Join-Path $worktreesRoot "pro-$shortId")
        $branchName = "vigiles/pro-$shortId"

        # Eger farkli bir yetim klasor kalmissa guvenle temizle
        if (Test-Path -LiteralPath $worktreePath) {
            Remove-WorktreeSafely -mainRepoRoot $ctx.MainRepoRoot -worktreePath $worktreePath -branchName $branchName
        }

        $wtAddRes = Invoke-GitRaw -WorkingDir $ctx.MainRepoRoot -GitArgs @("worktree", "add", "-B", $branchName, $worktreePath, "HEAD")
        if ($wtAddRes.ExitCode -ne 0) {
            # Son care fallback: MAIN_TREE ama bilgi ver
            $dirtyFallback = Get-DirtyEntriesExcludingWorktrees -repoRoot $ctx.MainRepoRoot
            $fallbackSess = @{
                version               = 1
                conversationId        = $ConversationId
                shortId               = $shortId
                mode                  = "MAIN_TREE"
                status                = "ACTIVE"
                repoRoot              = $ctx.MainRepoRoot
                commonGitDir          = $ctx.CommonGitDir
                effectiveWorkDir      = $ctx.MainRepoRoot
                worktreePath          = ""
                branchName            = ""
                baseHeadSha           = $ctx.HeadSha
                artifactDir           = $ArtifactDir
                startedAt             = $nowIso
                lastHeartbeatAt       = $nowIso
                preExistingDirtyFiles = @($dirtyFallback | Select-Object -First 50)
                worktreeError         = $wtAddRes.StdErr.Trim()
            }
            Write-JsonObject -path $sessionFile -obj $fallbackSess
            Write-ArtifactMarkers -artDir $ArtifactDir -sessionObj $fallbackSess -sessionFilePath $sessionFile
            Emit-Output @{
                isGitRepo        = $true
                mode             = "MAIN_TREE"
                worktreeError    = $wtAddRes.StdErr.Trim()
                effectiveWorkDir = $ctx.MainRepoRoot
                repoRoot         = $ctx.MainRepoRoot
                sessionFile      = $sessionFile
                preExistingDirty = @($dirtyFallback | Select-Object -First 50)
                activeOthers     = @($otherActive | ForEach-Object { $_.shortId })
            }
            exit 0
        }

        $deps = Initialize-WorktreeDependencies -mainRepoRoot $ctx.MainRepoRoot -commonGitDir $ctx.CommonGitDir -worktreePath $worktreePath

        $wtSess = @{
            version               = 1
            conversationId        = $ConversationId
            shortId               = $shortId
            mode                  = "WORKTREE"
            status                = "ACTIVE"
            repoRoot              = $ctx.MainRepoRoot
            commonGitDir          = $ctx.CommonGitDir
            effectiveWorkDir      = $worktreePath
            worktreePath          = $worktreePath
            branchName            = $branchName
            baseHeadSha           = $ctx.HeadSha
            artifactDir           = $ArtifactDir
            startedAt             = $nowIso
            lastHeartbeatAt       = $nowIso
            preExistingDirtyFiles = @()
            junctions             = @($deps.Junctions)
            envFiles              = @($deps.EnvFiles)
        }
        Write-JsonObject -path $sessionFile -obj $wtSess
        Write-ArtifactMarkers -artDir $ArtifactDir -sessionObj $wtSess -sessionFilePath $sessionFile

        Emit-Output @{
            isGitRepo        = $true
            mode             = "WORKTREE"
            reused           = $false
            shortId          = $shortId
            repoRoot         = $ctx.MainRepoRoot
            commonGitDir     = $ctx.CommonGitDir
            effectiveWorkDir = $worktreePath
            worktreePath     = $worktreePath
            branchName       = $branchName
            baseHeadSha      = $ctx.HeadSha
            sessionFile      = $sessionFile
            preExistingDirty = @()
            activeOthers     = @($otherActive | ForEach-Object { $_.shortId })
            junctions        = @($deps.Junctions)
            envFiles         = @($deps.EnvFiles)
        }
        exit 0
    }

    # 3. MAIN_TREE Modu (Tek aktif /pro veya ana klasor bos)
    $dirtyFiles = Get-DirtyEntriesExcludingWorktrees -repoRoot $ctx.MainRepoRoot
    $mainSess = @{
        version               = 1
        conversationId        = $ConversationId
        shortId               = $shortId
        mode                  = "MAIN_TREE"
        status                = "ACTIVE"
        repoRoot              = $ctx.MainRepoRoot
        commonGitDir          = $ctx.CommonGitDir
        effectiveWorkDir      = $ctx.MainRepoRoot
        worktreePath          = ""
        branchName            = ""
        baseHeadSha           = $ctx.HeadSha
        artifactDir           = $ArtifactDir
        startedAt             = $nowIso
        lastHeartbeatAt       = $nowIso
        preExistingDirtyFiles = @($dirtyFiles | Select-Object -First 50)
    }
    Write-JsonObject -path $sessionFile -obj $mainSess
    Write-ArtifactMarkers -artDir $ArtifactDir -sessionObj $mainSess -sessionFilePath $sessionFile

    Emit-Output @{
        isGitRepo        = $true
        mode             = "MAIN_TREE"
        reused           = $false
        shortId          = $shortId
        repoRoot         = $ctx.MainRepoRoot
        commonGitDir     = $ctx.CommonGitDir
        effectiveWorkDir = $ctx.MainRepoRoot
        worktreePath     = ""
        branchName       = ""
        baseHeadSha      = $ctx.HeadSha
        sessionFile      = $sessionFile
        preExistingDirty = @($dirtyFiles | Select-Object -First 50)
        activeOthers     = @($otherActive | ForEach-Object { $_.shortId })
    }
    exit 0

} finally {
    Release-RepoMutex -lockObj $lock
}
