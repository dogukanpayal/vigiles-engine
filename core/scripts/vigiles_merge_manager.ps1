# core/scripts/vigiles_merge_manager.ps1
# Vigiles Engine - Kontrollu 3-Way Paralel Santiye Birlestirme Yoneticisi (/merge)
# .worktrees/pro-<id> izole santiyesindeki degisiklikleri (uncommitted dahil) 3-way merge ve akilli KURALLAR numaralandirma ile ana klasore aktarir.

param(
    [ValidateSet("Status", "Preview", "Merge", "Abort")]
    [string]$Action = "Merge",
    [string]$Target = "",
    [string]$ConversationId = "",
    [string]$WorkspacePath = "",
    [switch]$Approved = $false,
    [switch]$WriteConflictMarkers = $false,
    [switch]$Json = $false
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Utf8Bom   = New-Object System.Text.UTF8Encoding($true)

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
        [string[]]$GitArgs,
        [string]$GitIndexFile = "",
        [switch]$RawBytes
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "git"
    $psi.Arguments = (($GitArgs | ForEach-Object { Format-ProcArg $_ }) -join " ")
    if (-not [string]::IsNullOrWhiteSpace($WorkingDir) -and (Test-Path -LiteralPath $WorkingDir)) {
        $psi.WorkingDirectory = $WorkingDir
    }
    if (-not [string]::IsNullOrWhiteSpace($GitIndexFile)) {
        $psi.EnvironmentVariables["GIT_INDEX_FILE"] = $GitIndexFile
    }
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    if (-not $RawBytes) {
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    }

    $proc = [System.Diagnostics.Process]::Start($psi)
    if ($RawBytes) {
        $ms = New-Object System.IO.MemoryStream
        $proc.StandardOutput.BaseStream.CopyTo($ms)
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        $bytes = $ms.ToArray()
        $ms.Dispose()
        return @{
            ExitCode = $proc.ExitCode
            Bytes    = $bytes
            StdErr   = $stderr
        }
    } else {
        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        return @{
            ExitCode = $proc.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
        }
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

function Normalize-RepoPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return "" }
    $n = $p.Trim().Replace('\', '/')
    while ($n.StartsWith("./")) { $n = $n.Substring(2) }
    return $n.TrimEnd('/')
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
    [System.IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 6), $Utf8NoBom)
}

function Get-RepoCommonContext([string]$wsPath) {
    $targetWs = if (-not [string]::IsNullOrWhiteSpace($wsPath)) { $wsPath } else { (Get-Location).Path }
    if (-not (Test-Path -LiteralPath $targetWs)) {
        return @{ IsGitRepo = $false }
    }
    $wsNorm = Normalize-WinPath $targetWs
    $insideRes = Invoke-GitRaw -WorkingDir $wsNorm -GitArgs @("rev-parse", "--is-inside-work-tree")
    if ($insideRes.ExitCode -ne 0 -or $insideRes.StdOut.Trim() -ne "true") {
        return @{ IsGitRepo = $false }
    }

    $commonRes = Invoke-GitRaw -WorkingDir $wsNorm -GitArgs @("rev-parse", "--git-common-dir")
    $commonRaw = $commonRes.StdOut.Trim().Replace('/', '\')
    if (-not [System.IO.Path]::IsPathRooted($commonRaw)) {
        $commonGitDir = Normalize-WinPath (Join-Path $wsNorm $commonRaw)
    } else {
        $commonGitDir = Normalize-WinPath $commonRaw
    }

    $topRes = Invoke-GitRaw -WorkingDir $wsNorm -GitArgs @("rev-parse", "--show-toplevel")
    $topLevel = Normalize-WinPath $topRes.StdOut.Trim()

    $mainRepoRoot = if ((Split-Path -Leaf $commonGitDir) -ieq ".git") {
        Normalize-WinPath (Split-Path -Parent $commonGitDir)
    } else {
        $topLevel
    }

    return @{
        IsGitRepo    = $true
        CommonGitDir = $commonGitDir
        MainRepoRoot = $mainRepoRoot
        SessionsDir  = (Join-Path $commonGitDir "vigiles\sessions")
    }
}

function Acquire-RepoMutex([string]$commonGitDir) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $h = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($commonGitDir.ToLowerInvariant()))
        $hex = ([BitConverter]::ToString($h) -replace '-', '').ToLowerInvariant().Substring(0, 16)
    } finally { $sha.Dispose() }

    $mtx = New-Object System.Threading.Mutex($false, "Local\VigilesSession_$hex")
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
    try { if ($lockObj.Acquired -and $lockObj.Mutex) { $lockObj.Mutex.ReleaseMutex() } } catch {}
    try { if ($lockObj.Mutex) { $lockObj.Mutex.Dispose() } } catch {}
}

function Test-ZeroLeakBytes([string]$relPath, [byte[]]$bytes, [string]$statusChar) {
    $norm = Normalize-RepoPath $relPath
    $leaf = [System.IO.Path]::GetFileName($norm)

    if ($leaf -match '^\.env(\..+)?$' -and $leaf -notmatch '^\.env\.(example|template|sample)$') {
        return @{ IsLeak = $true; Reason = "Hassas ortam dosyasi ($leaf) birlestirilemez!" }
    }
    if ($norm -match '\.(pem|key|p12|pfx)$' -or $leaf -in @('id_rsa', 'id_ed25519', 'id_dsa', 'secrets.json')) {
        return @{ IsLeak = $true; Reason = "Ozel anahtar/gizli dosya ($leaf) tespit edildi!" }
    }
    if ($statusChar -eq 'D' -or $null -eq $bytes -or $bytes.Length -eq 0 -or $bytes.Length -gt 2097152) {
        return @{ IsLeak = $false; Reason = "" }
    }
    foreach ($b in $bytes) {
        if ($b -eq 0) { return @{ IsLeak = $false; Reason = "" } }
    }
    $content = [System.Text.Encoding]::UTF8.GetString($bytes)
    $secretPatterns = @(
        @{ Name = "AWS Access Key"; Pattern = 'AKIA[0-9A-Z]{16}' },
        @{ Name = "OpenAI/API Secret Key"; Pattern = '(?<![a-zA-Z0-9_-])sk-(?:proj-|svcacct-|admin-)[a-zA-Z0-9_-]{20,}|(?<![a-zA-Z0-9_-])sk-[a-zA-Z0-9]{20,}' },
        @{ Name = "Stripe Secret Key"; Pattern = '(sk|rk)_(live|test)_[0-9a-zA-Z]{24,}' },
        @{ Name = "GitHub Personal Token"; Pattern = 'ghp_[0-9a-zA-Z]{36}' },
        @{ Name = "Private Key Block"; Pattern = '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' }
    )
    foreach ($sp in $secretPatterns) {
        if ($content -match $sp.Pattern) {
            return @{ IsLeak = $true; Reason = "Zero-Leak Engeli: $($sp.Name) tespit edildi!" }
        }
    }
    return @{ IsLeak = $false; Reason = "" }
}

function Test-BytesEqual([byte[]]$a, [byte[]]$b) {
    if ($null -eq $a -and $null -eq $b) { return $true }
    if ($null -eq $a -or $null -eq $b) { return $false }
    if ($a.Length -ne $b.Length) { return $false }
    for ($i = 0; $i -lt $a.Length; $i++) {
        if ($a[$i] -ne $b[$i]) { return $false }
    }
    return $true
}

function Test-IsBinary([byte[]]$bytes) {
    if ($null -eq $bytes -or $bytes.Length -eq 0) { return $false }
    $limit = [Math]::Min($bytes.Length, 8192)
    for ($i = 0; $i -lt $limit; $i++) {
        if ($bytes[$i] -eq 0) { return $true }
    }
    return $false
}

function ConvertTo-LfBytes([byte[]]$bytes) {
    if ($null -eq $bytes -or $bytes.Length -eq 0) { return $bytes }
    $str = [System.Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]65279)
    return $Utf8NoBom.GetBytes($str.Replace("`r`n", "`n"))
}

function Test-HasCrlf([byte[]]$bytes) {
    if ($null -eq $bytes -or $bytes.Length -lt 2) { return $false }
    for ($i = 0; $i -lt ($bytes.Length - 1); $i++) {
        if ($bytes[$i] -eq 0x0D -and $bytes[$i + 1] -eq 0x0A) { return $true }
    }
    return $false
}

function Test-IsExcludedMergePath([string]$relPath) {
    $norm = Normalize-RepoPath $relPath
    if ([string]::IsNullOrWhiteSpace($norm)) { return $true }
    if ($norm -match '^\.worktrees(/|$)') { return $true }
    if ($norm -match '^(node_modules|\.venv|venv|vendor)(/|$)') { return $true }
    $leaf = [System.IO.Path]::GetFileName($norm)
    if ($leaf -match '^\.env(\..+)?$' -and $leaf -notmatch '^\.env\.(example|template|sample)$') { return $true }
    return $false
}

function Get-GitBlobBytes([string]$repoRoot, [string]$commitSha, [string]$relPath) {
    if ([string]::IsNullOrWhiteSpace($commitSha) -or $commitSha -eq "UNBORN") {
        return @{ Exists = $false; Bytes = $null }
    }
    $norm = Normalize-RepoPath $relPath
    $res = Invoke-GitRaw -WorkingDir $repoRoot -GitArgs @("cat-file", "-p", "${commitSha}:${norm}") -RawBytes
    if ($res.ExitCode -ne 0) {
        return @{ Exists = $false; Bytes = $null }
    }
    return @{ Exists = $true; Bytes = $res.Bytes }
}

function Get-WorktreeChangeEntries([string]$worktreePath, [string]$baseHeadSha) {
    $entries = [System.Collections.Generic.List[object]]::new()
    $tempIndex = Join-Path ([System.IO.Path]::GetTempPath()) ("vig_merge_idx_" + [guid]::NewGuid().ToString("N"))
    $tmpSpec = $null

    try {
        # Worktree HEAD'ini gecici indekse yukle (gercek Git indeksine dokunmaz)
        $rdRes = Invoke-GitRaw -WorkingDir $worktreePath -GitArgs @("read-tree", "HEAD") -GitIndexFile $tempIndex
        if ($rdRes.ExitCode -ne 0) {
            return @()
        }

        # Takip edilen degisiklik ve silmeleri gecici indekse isle
        $null = Invoke-GitRaw -WorkingDir $worktreePath -GitArgs @("add", "-u") -GitIndexFile $tempIndex

        # Takipsiz yeni dosyalari topla ve gecici/junction/env klasorlerini disla
        $untrackedRes = Invoke-GitRaw -WorkingDir $worktreePath -GitArgs @("-c", "core.quotepath=false", "ls-files", "--others", "--exclude-standard", "-z") -GitIndexFile $tempIndex
        if ($untrackedRes.ExitCode -eq 0 -and -not [string]::IsNullOrEmpty($untrackedRes.StdOut)) {
            $uPaths = @($untrackedRes.StdOut.Split([char]0) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { Normalize-RepoPath $_ } | Where-Object { -not (Test-IsExcludedMergePath $_) })
            if ($uPaths.Count -gt 0) {
                $tmpSpec = [System.IO.Path]::GetTempFileName()
                [System.IO.File]::WriteAllLines($tmpSpec, $uPaths, $Utf8NoBom)
                $null = Invoke-GitRaw -WorkingDir $worktreePath -GitArgs @("add", "--pathspec-from-file=$tmpSpec") -GitIndexFile $tempIndex
            }
        }

        $diffRes = Invoke-GitRaw -WorkingDir $worktreePath -GitArgs @("-c", "core.quotepath=false", "diff", "--cached", "--name-status", "--no-renames", "-z", $baseHeadSha) -GitIndexFile $tempIndex
        if ($diffRes.ExitCode -ne 0 -or [string]::IsNullOrEmpty($diffRes.StdOut)) {
            return @()
        }

        $tokens = $diffRes.StdOut.Split([char]0)
        $i = 0
        while (($i + 1) -lt $tokens.Length) {
            $st = $tokens[$i].Trim()
            $p = Normalize-RepoPath $tokens[$i + 1]
            $i += 2
            if ([string]::IsNullOrWhiteSpace($st) -or [string]::IsNullOrWhiteSpace($p)) { continue }
            if (Test-IsExcludedMergePath $p) { continue }
            $entries.Add([PSCustomObject]@{
                Status = $st.Substring(0, 1)
                Path   = $p
            })
        }
    } finally {
        if ($tmpSpec -and (Test-Path -LiteralPath $tmpSpec)) { Remove-Item -LiteralPath $tmpSpec -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $tempIndex) { Remove-Item -LiteralPath $tempIndex -Force -ErrorAction SilentlyContinue }
    }

    return @($entries.ToArray())
}

function Invoke-GitMergeFileBytes([byte[]]$mainBytes, [byte[]]$baseBytes, [byte[]]$wtBytes, [string]$wtLabel) {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("vig_mf_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    try {
        $fMain = Join-Path $dir "main.txt"
        $fBase = Join-Path $dir "base.txt"
        $fWt   = Join-Path $dir "wt.txt"

        [System.IO.File]::WriteAllBytes($fMain, $(if ($null -ne $mainBytes) { $mainBytes } else { [byte[]]@() }))
        [System.IO.File]::WriteAllBytes($fBase, $(if ($null -ne $baseBytes) { $baseBytes } else { [byte[]]@() }))
        [System.IO.File]::WriteAllBytes($fWt,   $(if ($null -ne $wtBytes)   { $wtBytes }   else { [byte[]]@() }))

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "git"
        $psi.Arguments = ("merge-file -p -L {0} -L {1} -L {2} {3} {4} {5}" -f `
            (Format-ProcArg "Ana Klasor (Main)"), `
            (Format-ProcArg "Ortak Taban (Base)"), `
            (Format-ProcArg "Paralel Santiye ($wtLabel)"), `
            (Format-ProcArg $fMain), `
            (Format-ProcArg $fBase), `
            (Format-ProcArg $fWt))
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $ms = New-Object System.IO.MemoryStream
        $proc.StandardOutput.BaseStream.CopyTo($ms)
        $stderr = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()
        $mergedBytes = $ms.ToArray()
        $ms.Dispose()

        return @{
            ExitCode    = $proc.ExitCode
            MergedBytes = $mergedBytes
            StdErr      = $stderr
        }
    } finally {
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Parse-KurallarEntries([string]$text) {
    $map = [ordered]@{}
    $maxNum = 0
    $lastRuleLineIdx = -1
    $lines = $text -split "`r?`n"
    for ($idx = 0; $idx -lt $lines.Length; $idx++) {
        $l = $lines[$idx]
        if ($l -match '^\s*\*\s*\[KURAL-(\d+)\]\s*:\s*(.+)$') {
            $num = [int]$matches[1]
            $body = $matches[2].Trim()
            if ($num -gt $maxNum) { $maxNum = $num }
            $lastRuleLineIdx = $idx
            if (-not $map.Contains($body)) {
                $map[$body] = @{ Number = $num; Body = $body; Line = $l }
            }
        }
    }
    return @{
        Lines           = $lines
        ByBody          = $map
        MaxNum          = $maxNum
        LastRuleLineIdx = $lastRuleLineIdx
    }
}

function Merge-KurallarSmart([byte[]]$mainBytes, [byte[]]$baseBytes, [byte[]]$wtBytes) {
    $mainText = [System.Text.Encoding]::UTF8.GetString($mainBytes).TrimStart([char]65279)
    $baseText = if ($null -ne $baseBytes) { [System.Text.Encoding]::UTF8.GetString($baseBytes).TrimStart([char]65279) } else { "" }
    $wtText   = [System.Text.Encoding]::UTF8.GetString($wtBytes).TrimStart([char]65279)

    $baseInfo = Parse-KurallarEntries $baseText
    $mainInfo = Parse-KurallarEntries $mainText
    $wtInfo   = Parse-KurallarEntries $wtText

    $newFromWt = [System.Collections.Generic.List[string]]::new()
    $nextNum = $mainInfo.MaxNum

    foreach ($body in $wtInfo.ByBody.Keys) {
        if (-not $baseInfo.ByBody.Contains($body) -and -not $mainInfo.ByBody.Contains($body)) {
            $nextNum++
            $formatted = "* [KURAL-{0:D3}]: {1}" -f $nextNum, $body
            $newFromWt.Add($formatted)
        }
    }

    if ($newFromWt.Count -eq 0) {
        return @{ Success = $true; Bytes = $mainBytes; RenumberedCount = 0 }
    }

    $eol = if ($mainText -match "`r`n") { "`r`n" } else { "`n" }
    $outLines = [System.Collections.Generic.List[string]]::new()
    $insertAfter = $mainInfo.LastRuleLineIdx
    if ($insertAfter -lt 0) { $insertAfter = $mainInfo.Lines.Length - 1 }

    for ($i = 0; $i -lt $mainInfo.Lines.Length; $i++) {
        $outLines.Add($mainInfo.Lines[$i])
        if ($i -eq $insertAfter) {
            foreach ($nr in $newFromWt) {
                $outLines.Add($nr)
            }
        }
    }

    $mergedStr = ($outLines.ToArray() -join $eol)
    $hasBom = ($mainBytes.Length -ge 3 -and $mainBytes[0] -eq 0xEF -and $mainBytes[1] -eq 0xBB -and $mainBytes[2] -eq 0xBF)
    $enc = if ($hasBom) { $Utf8Bom } else { $Utf8NoBom }
    return @{
        Success         = $true
        Bytes           = $enc.GetBytes($mergedStr)
        RenumberedCount = $newFromWt.Count
    }
}

function Unlink-WorktreeJunctions([string]$worktreePath) {
    if ([string]::IsNullOrWhiteSpace($worktreePath) -or -not (Test-Path -LiteralPath $worktreePath)) { return }
    foreach ($dep in @("node_modules", ".venv", "venv", "vendor")) {
        $candidate = Join-Path $worktreePath $dep
        if (Test-Path -LiteralPath $candidate) {
            try {
                $item = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
                if ($item -and ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
                    [System.IO.Directory]::Delete($candidate)
                }
            } catch {}
        }
    }
}

function Remove-WorktreeSafely([string]$mainRepoRoot, [string]$worktreePath, [string]$branchName) {
    if (-not [string]::IsNullOrWhiteSpace($worktreePath) -and (Test-Path -LiteralPath $worktreePath)) {
        Unlink-WorktreeJunctions -worktreePath $worktreePath
        Get-ChildItem -Path $worktreePath -Filter ".env*" -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch '^\.env\.(example|template|sample)$' } |
            ForEach-Object {
                $chk = Invoke-GitRaw -WorkingDir $mainRepoRoot -GitArgs @("ls-files", "--error-unmatch", $_.Name)
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

function Resolve-TargetSession($sessionsDir, [string]$targetArg, [string]$cidArg) {
    if (-not (Test-Path -LiteralPath $sessionsDir)) { return @{ Sessions = @(); Selected = $null } }
    $pending = [System.Collections.Generic.List[object]]::new()
    foreach ($f in (Get-ChildItem -Path $sessionsDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        $rec = Read-JsonObject -path $f.FullName
        if (-not $rec) { continue }
        if ($rec.mode -eq "WORKTREE" -and $rec.status -in @("ACTIVE", "READY_TO_MERGE", "STALE", "COMPLETED") -and $rec.worktreePath -and (Test-Path -LiteralPath $rec.worktreePath)) {
            $rec | Add-Member -NotePropertyName "_sessionFile" -NotePropertyValue $f.FullName -Force
            $pending.Add($rec)
        }
    }

    $allPending = @($pending.ToArray())
    if ($allPending.Count -eq 0) { return @{ Sessions = @(); Selected = $null } }

    $lookup = if (-not [string]::IsNullOrWhiteSpace($targetArg)) { $targetArg.Trim() } elseif (-not [string]::IsNullOrWhiteSpace($cidArg)) { $cidArg.Trim() } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($lookup)) {
        $exact = @($allPending | Where-Object {
            $_.conversationId -eq $lookup -or
            $_.shortId -eq $lookup -or
            "pro-$($_.shortId)" -eq $lookup -or
            $_.branchName -eq $lookup
        })
        if ($exact.Count -eq 1) { return @{ Sessions = $allPending; Selected = $exact[0] } }
        $partial = @($allPending | Where-Object { $_.shortId -like "*$lookup*" -or $_.conversationId -like "$lookup*" })
        if ($partial.Count -eq 1) { return @{ Sessions = $allPending; Selected = $partial[0] } }
        return @{ Sessions = $allPending; Selected = $null; NotFoundLookup = $lookup }
    }

    if ($allPending.Count -eq 1) {
        return @{ Sessions = $allPending; Selected = $allPending[0] }
    }

    return @{ Sessions = $allPending; Selected = $null; Ambiguous = $true }
}

function Build-MergePlan($ctx, $session) {
    $wtPath = $session.worktreePath
    $baseSha = $session.baseHeadSha
    $shortId = $session.shortId
    $entries = @(Get-WorktreeChangeEntries -worktreePath $wtPath -baseHeadSha $baseSha)

    $planItems = [System.Collections.Generic.List[object]]::new()
    $hasConflict = $false
    $hasLeak = $false

    foreach ($e in $entries) {
        $rel = $e.Path
        $wtStatus = $e.Status
        $mainFile = Join-Path $ctx.MainRepoRoot ($rel.Replace('/', '\'))
        $wtFile   = Join-Path $wtPath ($rel.Replace('/', '\'))

        $baseBlob = Get-GitBlobBytes -repoRoot $ctx.MainRepoRoot -commitSha $baseSha -relPath $rel
        $mainExists = (Test-Path -LiteralPath $mainFile -PathType Leaf)
        $mainBytes  = if ($mainExists) { [System.IO.File]::ReadAllBytes($mainFile) } else { $null }
        $wtExists   = (Test-Path -LiteralPath $wtFile -PathType Leaf)
        $wtBytes    = if ($wtExists -and $wtStatus -ne 'D') { [System.IO.File]::ReadAllBytes($wtFile) } else { $null }

        $leak = Test-ZeroLeakBytes -relPath $rel -bytes $wtBytes -statusChar $wtStatus
        if ($leak.IsLeak) {
            $hasLeak = $true
            $planItems.Add([PSCustomObject]@{
                Path        = $rel
                WtStatus    = $wtStatus
                MergeKind   = "ZERO_LEAK"
                Label       = "ZERO-LEAK ENGELI"
                Reason      = $leak.Reason
                TargetBytes = $null
                HasConflict = $true
                IsLeak      = $true
            })
            continue
        }

        $isBinary = (Test-IsBinary $mainBytes) -or (Test-IsBinary $baseBlob.Bytes) -or (Test-IsBinary $wtBytes)
        if ($mainExists -ne $baseBlob.Exists) {
            $mainChanged = $true
        } elseif (-not $mainExists) {
            $mainChanged = $false
        } elseif ($isBinary) {
            $mainChanged = -not (Test-BytesEqual $mainBytes $baseBlob.Bytes)
        } else {
            $mainChanged = -not (Test-BytesEqual (ConvertTo-LfBytes $mainBytes) (ConvertTo-LfBytes $baseBlob.Bytes))
        }

        if (-not $mainChanged) {
            if ($wtStatus -eq 'D') {
                $planItems.Add([PSCustomObject]@{
                    Path = $rel; WtStatus = $wtStatus; MergeKind = "DELETE"; Label = "TEMIZ (Silme)"
                    Reason = ""; TargetBytes = $null; HasConflict = $false; IsLeak = $false
                })
            } else {
                $planItems.Add([PSCustomObject]@{
                    Path = $rel; WtStatus = $wtStatus; MergeKind = "WRITE"; Label = "TEMIZ"
                    Reason = ""; TargetBytes = $wtBytes; HasConflict = $false; IsLeak = $false
                })
            }
            continue
        }

        # Ana klasor de degismis!
        $sameOnBoth = ($wtStatus -eq 'D' -and -not $mainExists) -or (
            $wtStatus -ne 'D' -and $mainExists -and (
                $(if ($isBinary) { Test-BytesEqual $mainBytes $wtBytes } else { Test-BytesEqual (ConvertTo-LfBytes $mainBytes) (ConvertTo-LfBytes $wtBytes) })
            )
        )
        if ($sameOnBoth) {
            $planItems.Add([PSCustomObject]@{
                Path = $rel; WtStatus = $wtStatus; MergeKind = "NOOP"; Label = "ESIT (Atlandi)"
                Reason = "Her iki tarafta ayni sonuc"; TargetBytes = $null; HasConflict = $false; IsLeak = $false
            })
            continue
        }

        if ($wtStatus -eq 'D' -or -not $mainExists) {
            $hasConflict = $true
            $planItems.Add([PSCustomObject]@{
                Path = $rel; WtStatus = $wtStatus; MergeKind = "CONFLICT"; Label = "CAKISMA (Silme/Degisiklik)"
                Reason = "Bir tarafta silinirken diger tarafta degistirildi"; TargetBytes = $null; HasConflict = $true; IsLeak = $false
            })
            continue
        }

        # KURALLAR.md veya KURALLAR.template.md icin akilli numara birlestirme
        if ($rel -ieq "KURALLAR.md" -or $rel -ieq "core/templates/KURALLAR.template.md") {
            $kMerge = Merge-KurallarSmart -mainBytes $mainBytes -baseBytes $baseBlob.Bytes -wtBytes $wtBytes
            if ($kMerge.Success) {
                $planItems.Add([PSCustomObject]@{
                    Path = $rel; WtStatus = $wtStatus; MergeKind = "WRITE"; Label = "AKILLI KURAL (+$($kMerge.RenumberedCount))"
                    Reason = "KURAL-NNN numaralari otomatik yeniden numaralandirildi"; TargetBytes = $kMerge.Bytes; HasConflict = $false; IsLeak = $false
                })
                continue
            }
        }

        # Ikili dosya kontrolu
        if ($isBinary) {
            $hasConflict = $true
            $planItems.Add([PSCustomObject]@{
                Path = $rel; WtStatus = $wtStatus; MergeKind = "CONFLICT"; Label = "CAKISMA (Ikili Dosya)"
                Reason = "Ikili dosya her iki tarafta da degistirildi"; TargetBytes = $null; HasConflict = $true; IsLeak = $false
            })
            continue
        }

        # Metin dosyasi -> LF normalize ederek git merge-file ile gercek 3-way birlestirme
        $lfMain = ConvertTo-LfBytes $mainBytes
        $lfBase = if ($null -ne $baseBlob.Bytes) { ConvertTo-LfBytes $baseBlob.Bytes } else { [byte[]]@() }
        $lfWt   = ConvertTo-LfBytes $wtBytes
        $mf = Invoke-GitMergeFileBytes -mainBytes $lfMain -baseBytes $lfBase -wtBytes $lfWt -wtLabel $shortId
        if ($mf.ExitCode -eq 0) {
            $mergedStr = [System.Text.Encoding]::UTF8.GetString($mf.MergedBytes)
            if (Test-HasCrlf $mainBytes) {
                $mergedStr = $mergedStr.Replace("`r`n", "`n").Replace("`n", "`r`n")
            }
            $hadBom = ($mainBytes.Length -ge 3 -and $mainBytes[0] -eq 0xEF -and $mainBytes[1] -eq 0xBB -and $mainBytes[2] -eq 0xBF) -or
                      ($wtBytes.Length -ge 3 -and $wtBytes[0] -eq 0xEF -and $wtBytes[1] -eq 0xBB -and $wtBytes[2] -eq 0xBF)
            $enc = if ($hadBom -or $rel -match '\.ps1$') { $Utf8Bom } else { $Utf8NoBom }
            $finalBytes = $enc.GetBytes($mergedStr)
            $planItems.Add([PSCustomObject]@{
                Path = $rel; WtStatus = $wtStatus; MergeKind = "WRITE"; Label = "OTOMATIK 3-WAY"
                Reason = "Farkli satirlar cakismasiz birlestirildi"; TargetBytes = $finalBytes; HasConflict = $false; IsLeak = $false
            })
        } else {
            $hasConflict = $true
            $planItems.Add([PSCustomObject]@{
                Path = $rel; WtStatus = $wtStatus; MergeKind = "CONFLICT"; Label = "CAKISMA!"
                Reason = "Ayni satirlarda cakisan duzenleme ($($mf.ExitCode) bolge)"; TargetBytes = $mf.MergedBytes; HasConflict = $true; IsLeak = $false
            })
        }
    }

    return @{
        Items       = @($planItems.ToArray())
        HasConflict = $hasConflict
        HasLeak     = $hasLeak
    }
}

function Show-MergePreview($ctx, $session, $plan) {
    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host ">> VIGILES PARALEL SANTIYE ONIZLEMESI (/merge)" -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "   Oturum   : pro-$($session.shortId) (Durum: $($session.status))" -ForegroundColor Gray
    Write-Host "   Kaynak   : $($session.worktreePath)" -ForegroundColor Gray
    Write-Host "   Hedef    : $($ctx.MainRepoRoot)" -ForegroundColor Gray
    Write-Host "   Degisiklikler ($($plan.Items.Count) dosya):" -ForegroundColor White

    if ($plan.Items.Count -eq 0) {
        Write-Host "   (Birlestirilecek dosya degisikligi yok)" -ForegroundColor DarkGray
    } else {
        $idx = 1
        foreach ($it in $plan.Items) {
            $col = if ($it.IsLeak -or $it.HasConflict) { "Red" } elseif ($it.Label -match "3-WAY|AKILLI") { "Cyan" } else { "Green" }
            $note = if ($it.Reason) { " - $($it.Reason)" } else { "" }
            Write-Host ("   [{0}] [{1}] {2}  [{3}]{4}" -f $idx, $it.WtStatus, $it.Path, $it.Label, $note) -ForegroundColor $col
            $idx++
        }
    }
    Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
}

# --- ANA AKIS ---
$ctx = Get-RepoCommonContext -wsPath $WorkspacePath
if (-not $ctx.IsGitRepo) {
    Write-Host "[HATA]: Mevcut dizin bir Git deposu degil!" -ForegroundColor Red
    exit 1
}

$lock = Acquire-RepoMutex -commonGitDir $ctx.CommonGitDir
try {
    $resolved = Resolve-TargetSession -sessionsDir $ctx.SessionsDir -targetArg $Target -cidArg $ConversationId
    $allPending = @($resolved.Sessions)

    if ($Action -eq "Status") {
        if ($Json) {
            Write-Output (@{
                repoRoot = $ctx.MainRepoRoot
                count    = $allPending.Count
                sessions = @($allPending | ForEach-Object { @{ shortId = $_.shortId; conversationId = $_.conversationId; status = $_.status; worktreePath = $_.worktreePath; branchName = $_.branchName } })
            } | ConvertTo-Json -Depth 5)
            exit 0
        }
        if ($allPending.Count -eq 0) {
            Write-Host "[BILGI]: Birlestirilecek bekleyen paralel santiye bulunmuyor." -ForegroundColor Green
            exit 0
        }
        Write-Host "`n[BEKLEYEN PARALEL SANTIYELER ($($allPending.Count) adet)]:" -ForegroundColor Cyan
        $n = 1
        foreach ($s in $allPending) {
            Write-Host ("   [{0}] pro-{1} ({2}) -> {3}" -f $n, $s.shortId, $s.status, $s.worktreePath) -ForegroundColor White
            $n++
        }
        exit 0
    }

    if ($allPending.Count -eq 0) {
        Write-Host "[BILGI]: Birlestirilecek bekleyen paralel santiye (worktree) bulunmuyor." -ForegroundColor Green
        exit 0
    }

    if ($null -eq $resolved.Selected) {
        if ($resolved.NotFoundLookup) {
            Write-Host "[HATA]: '$($resolved.NotFoundLookup)' ile eslesen aktif/bekleyen paralel santiye bulunamadi." -ForegroundColor Red
            exit 1
        }
        Write-Host "`n[SECIM GEREKLI]: Birden fazla paralel santiye bekliyor. Lutfen hedef belirtin (/merge <shortId>):" -ForegroundColor Yellow
        $n = 1
        foreach ($s in $allPending) {
            Write-Host ("   [{0}] {1} ({2}) -> {3}" -f $n, $s.shortId, $s.status, $s.worktreePath) -ForegroundColor White
            $n++
        }
        exit 2
    }

    $targetSession = $resolved.Selected

    if ($Action -eq "Abort") {
        if (-not $Approved) {
            Write-Host "[ONAY GEREKLI]: 'pro-$($targetSession.shortId)' santiyesini birlestirmeden iptal edip silmek icin -Approved verin." -ForegroundColor Yellow
            exit 2
        }
        Remove-WorktreeSafely -mainRepoRoot $ctx.MainRepoRoot -worktreePath $targetSession.worktreePath -branchName $targetSession.branchName
        $targetSession | Add-Member -NotePropertyName "status" -NotePropertyValue "ABORTED" -Force
        $targetSession | Add-Member -NotePropertyName "abortedAt" -NotePropertyValue ([datetimeoffset]::Now.ToString("o")) -Force
        Write-JsonObject -path $targetSession._sessionFile -obj $targetSession
        if ($targetSession.artifactDir) {
            $wtm = Join-Path $targetSession.artifactDir ".vigiles_worktree"
            if (Test-Path -LiteralPath $wtm) { Remove-Item -LiteralPath $wtm -Force -ErrorAction SilentlyContinue }
        }
        Write-Host "[IPTAL EDILDI]: 'pro-$($targetSession.shortId)' santiyesi guvenle kaldirildi (ana klasor korundu)." -ForegroundColor Yellow
        exit 0
    }

    $plan = Build-MergePlan -ctx $ctx -session $targetSession

    if ($Json -and $Action -eq "Preview") {
        $summary = @{
            shortId     = $targetSession.shortId
            worktree    = $targetSession.worktreePath
            mainRepo    = $ctx.MainRepoRoot
            hasConflict = $plan.HasConflict
            hasLeak     = $plan.HasLeak
            items       = @($plan.Items | ForEach-Object { @{ path = $_.Path; status = $_.WtStatus; label = $_.Label; hasConflict = $_.HasConflict; isLeak = $_.IsLeak; reason = $_.Reason } })
        }
        Write-Output ($summary | ConvertTo-Json -Depth 5)
        exit 0
    }

    Show-MergePreview -ctx $ctx -session $targetSession -plan $plan

    if ($Action -eq "Preview") {
        if ($plan.HasConflict) { exit 3 }
        exit 0
    }

    # Action -eq "Merge"
    if ($plan.HasLeak) {
        Write-Host "`n[ZERO-LEAK ENGELI]: Paralel santiyede gizli veri / API anahtari tespit edildigi icin birlestirme durduruldu!" -ForegroundColor Red
        exit 1
    }

    if (-not $Approved) {
        Write-Host "`n[ONAY GEREKLI]: Ana klasore aktarmak icin kullanici onayi (-Approved) bekleniyor." -ForegroundColor Yellow
        exit 2
    }

    if ($plan.HasConflict -and -not $WriteConflictMarkers) {
        Write-Host "`n[CAKISMA ENGELI]: Yukaridaki dosyalarda ayni satirlarda cakisma tespit edildi! Ana klasorunuz guvenlik amaciyla DEGISTIRILMEDI." -ForegroundColor Red
        Write-Host "   -> Cozum icin dosyadaki cakismayi inceleyin veya Git isaretcilerini yazdirmak icin -WriteConflictMarkers kullanin." -ForegroundColor Gray
        exit 3
    }

    # Degisiklikleri ana klasore aktar
    $appliedCount = 0
    $deletedCount = 0
    $conflictFiles = [System.Collections.Generic.List[string]]::new()

    foreach ($it in $plan.Items) {
        $dstPath = Join-Path $ctx.MainRepoRoot ($it.Path.Replace('/', '\'))
        if ($it.MergeKind -eq "NOOP") { continue }

        if ($it.MergeKind -eq "DELETE") {
            if (Test-Path -LiteralPath $dstPath -PathType Leaf) {
                Remove-Item -LiteralPath $dstPath -Force
                $deletedCount++
            }
            continue
        }

        if ($it.MergeKind -eq "WRITE" -or ($it.MergeKind -eq "CONFLICT" -and $WriteConflictMarkers -and $null -ne $it.TargetBytes)) {
            $parentDir = Split-Path -Parent $dstPath
            if (-not [string]::IsNullOrWhiteSpace($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }
            [System.IO.File]::WriteAllBytes($dstPath, $it.TargetBytes)
            $appliedCount++
            if ($it.MergeKind -eq "CONFLICT") { $conflictFiles.Add($it.Path) }
        }
    }

    # Temizlik (yalnizca tam temiz/marker-yazilmis birlestirmede worktree kaldirilir)
    if ($conflictFiles.Count -eq 0) {
        Remove-WorktreeSafely -mainRepoRoot $ctx.MainRepoRoot -worktreePath $targetSession.worktreePath -branchName $targetSession.branchName
        $targetSession | Add-Member -NotePropertyName "status" -NotePropertyValue "MERGED" -Force
        $targetSession | Add-Member -NotePropertyName "mergedAt" -NotePropertyValue ([datetimeoffset]::Now.ToString("o")) -Force
        Write-JsonObject -path $targetSession._sessionFile -obj $targetSession
        if ($targetSession.artifactDir) {
            $wtm = Join-Path $targetSession.artifactDir ".vigiles_worktree"
            if (Test-Path -LiteralPath $wtm) { Remove-Item -LiteralPath $wtm -Force -ErrorAction SilentlyContinue }
        }

        Write-Host "`n[BASARILI]: Paralel santiye 'pro-$($targetSession.shortId)' ana klasore aktarildi ve temizlendi!" -ForegroundColor Green
        Write-Host "   Aktarilan Dosya : $appliedCount | Silinen Dosya : $deletedCount" -ForegroundColor White
        Write-Host "   Sonraki Adim    : '/pushprep' ile inceleyip '/push' ile GitHub'a gonderebilirsiniz." -ForegroundColor Cyan
        exit 0
    } else {
        Write-Host "`n[CAKISMA ISARETLENDI]: Cakisan dosyalar Git isaretcileriyle yazildi: $($conflictFiles -join ', ')" -ForegroundColor Yellow
        exit 3
    }

} finally {
    Release-RepoMutex -lockObj $lock
}
