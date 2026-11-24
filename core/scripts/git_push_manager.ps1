# core/scripts/git_push_manager.ps1
# Vigiles Engine - Iki Asamali Guvenli Git Pipeline Yoneticisi (PushPrep -> Remove/Add -> Push)
# Komutlar: /pushprep, /pushremove, /pushadd, /push

param(
    [ValidateSet("Push", "Prep", "Remove", "Add", "Status", "Reset")]
    [string]$Action = "Push",
    [string]$Remote = "origin",
    [string]$Branch = "",
    [string]$CommitMessage = "",
    [string[]]$Targets = @(),
    [switch]$Ignore = $false,
    [switch]$Approved = $false,
    [switch]$DryRun = $false,
    [switch]$Json = $false
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Utf8Bom   = New-Object System.Text.UTF8Encoding($true)

# --- YARDIMCI FONKSIYONLAR ---

function Normalize-RepoPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return "" }
    $n = $p.Trim().Replace('\', '/')
    while ($n.StartsWith("./")) { $n = $n.Substring(2) }
    $n = $n.TrimEnd('/')
    return $n
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

function Format-ProcessArg([string]$arg) {
    if ($null -eq $arg) { return '""' }
    if ($arg -eq "") { return '""' }
    if ($arg -notmatch '[\s"]') { return $arg }
    $escaped = [regex]::Replace($arg, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Invoke-GitRaw {
    param(
        [string[]]$GitArgs,
        [switch]$UseQuotepathFalse
    )

    $allArgs = [System.Collections.Generic.List[string]]::new()
    if ($UseQuotepathFalse) {
        $allArgs.Add("-c")
        $allArgs.Add("core.quotepath=false")
    }
    foreach ($a in $GitArgs) {
        $allArgs.Add($a)
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "git"
    $psi.Arguments = (($allArgs | ForEach-Object { Format-ProcessArg $_ }) -join " ")
    $psi.WorkingDirectory = (Get-Location).Path
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

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

function Get-RepoContext {
    $rpRes = Invoke-GitRaw -GitArgs @("rev-parse", "--is-inside-work-tree", "--show-toplevel", "--git-dir", "--git-common-dir")
    $rpLines = if ($rpRes.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($rpRes.StdOut)) {
        @($rpRes.StdOut.Trim() -split "`r?`n")
    } else {
        @()
    }
    if ($rpRes.ExitCode -ne 0 -or $rpLines.Count -lt 4 -or $rpLines[0].Trim() -ne "true") {
        Write-Host "[HATA]: Mevcut calisma dizini bir Git deposu degil!" -ForegroundColor Red
        exit 1
    }

    $repoRoot = $rpLines[1].Trim()
    $gitDirRaw = $rpLines[2].Trim()
    $commonRaw = $rpLines[3].Trim()

    if (-not [System.IO.Path]::IsPathRooted($gitDirRaw)) {
        $gitDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $gitDirRaw))
    } else {
        $gitDir = [System.IO.Path]::GetFullPath($gitDirRaw)
    }

    if (-not [string]::IsNullOrWhiteSpace($commonRaw)) {
        if (-not [System.IO.Path]::IsPathRooted($commonRaw)) {
            $commonGitDir = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $commonRaw))
        } else {
            $commonGitDir = [System.IO.Path]::GetFullPath($commonRaw)
        }
    } else {
        $commonGitDir = $gitDir
    }

    $activeBranch = $Branch
    if ([string]::IsNullOrWhiteSpace($activeBranch)) {
        $brRes = Invoke-GitRaw -GitArgs @("branch", "--show-current")
        $activeBranch = $brRes.StdOut.Trim()
        if ([string]::IsNullOrWhiteSpace($activeBranch)) {
            $symRes = Invoke-GitRaw -GitArgs @("symbolic-ref", "--short", "HEAD")
            if ($symRes.ExitCode -eq 0) {
                $activeBranch = $symRes.StdOut.Trim()
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($activeBranch)) {
        Write-Host "[HATA]: Aktif Git branch adi tespit edilemedi (Detached HEAD olabilir)." -ForegroundColor Red
        exit 1
    }

    $remRes = Invoke-GitRaw -GitArgs @("remote", "get-url", $Remote)
    $remoteUrl = $remRes.StdOut.Trim()
    if ($remRes.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($remoteUrl)) {
        Write-Host "[HATA]: '$Remote' adinda bir uzak depo (remote) bulunamadi!" -ForegroundColor Red
        exit 1
    }

    $headRes = Invoke-GitRaw -GitArgs @("rev-parse", "HEAD")
    $headSha = if ($headRes.ExitCode -eq 0) { $headRes.StdOut.Trim() } else { "UNBORN" }

    $vigilesDir = Join-Path $gitDir "vigiles"
    $manifestPath = Join-Path $vigilesDir "pushprep.json"

    return @{
        RepoRoot     = $repoRoot
        GitDir       = $gitDir
        CommonGitDir = $commonGitDir
        VigilesDir   = $vigilesDir
        ManifestPath = $manifestPath
        Branch       = $activeBranch
        Remote       = $Remote
        RemoteUrl    = $remoteUrl
        HeadSha      = $headSha
    }
}

function Get-StatusLabel([string]$xy) {
    if ($xy -eq "??") { return "Yeni (Takipsiz)" }
    if ($xy -match 'U|AA|DD') { return "Cakisma!" }
    $x = $xy[0]
    $y = $xy[1]
    if ($x -eq 'R' -or $y -eq 'R') { return "Tasindi/Yeniden Adlandirildi" }
    if ($x -eq 'C' -or $y -eq 'C') { return "Kopyalandi" }
    if ($x -eq 'D' -or $y -eq 'D') { return "Silindi" }
    if ($x -eq 'A') { return "Yeni (Sahneli)" }
    if ($x -eq 'M' -or $y -eq 'M') { return "Degisti" }
    return "Degisti ($xy)"
}

function Test-ZeroLeakFile([string]$repoRoot, [string]$relPath, [string]$statusXy) {
    $norm = Normalize-RepoPath $relPath
    $leaf = [System.IO.Path]::GetFileName($norm)

    # 1. Hassas dosya adi kontrolu (.env.example / .env.template / .env.sample istisnadir)
    if ($leaf -match '^\.env(\..+)?$') {
        if ($leaf -notmatch '^\.env\.(example|template|sample)$') {
            return @{ IsLeak = $true; Reason = "Hassas ortam dosyasi ($leaf) Git'e gonderilemez!" }
        }
    }
    if ($norm -match '\.(pem|key|p12|pfx)$' -or $leaf -in @('id_rsa', 'id_ed25519', 'id_dsa', 'secrets.json')) {
        return @{ IsLeak = $true; Reason = "Ozel anahtar/gizli dosya ($leaf) tespit edildi!" }
    }

    # Silinmis dosyalarin icerigini taramaya gerek yok
    if ($statusXy -match 'D') {
        return @{ IsLeak = $false; Reason = "" }
    }

    # 2. Icerik tabanli API/Secret taramasi
    $fullPath = Join-Path $repoRoot ($norm.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        return @{ IsLeak = $false; Reason = "" }
    }

    try {
        $info = Get-Item -LiteralPath $fullPath
        if ($info.Length -gt 2097152) {
            return @{ IsLeak = $false; Reason = "" }
        }
        $bytes = [System.IO.File]::ReadAllBytes($fullPath)
        # Binary kontrolu (NUL byte iceriyorsa atla)
        foreach ($b in $bytes) {
            if ($b -eq 0) {
                return @{ IsLeak = $false; Reason = "" }
            }
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
                return @{ IsLeak = $true; Reason = "Zero-Leak Engeli: Dosya icinde $($sp.Name) tespit edildi!" }
            }
        }
    } catch {}

    return @{ IsLeak = $false; Reason = "" }
}

function Get-WorkingTreeEntries($ctx) {
    $res = Invoke-GitRaw -GitArgs @("status", "--porcelain=v1", "-uall", "-z") -UseQuotepathFalse
    $entries = [System.Collections.Generic.List[object]]::new()
    if ($res.ExitCode -ne 0 -or [string]::IsNullOrEmpty($res.StdOut)) {
        return ,@()
    }

    $parts = $res.StdOut.Split([char]0)
    $i = 0
    while ($i -lt $parts.Length) {
        $token = $parts[$i]
        if ([string]::IsNullOrEmpty($token) -or $token.Length -lt 4) {
            $i++
            continue
        }
        $xy = $token.Substring(0, 2)
        $rawPath = $token.Substring(3)
        $normPath = Normalize-RepoPath $rawPath
        $origPath = $null

        if ($xy[0] -in @('R', 'C') -or $xy[1] -in @('R', 'C')) {
            if (($i + 1) -lt $parts.Length -and -not [string]::IsNullOrEmpty($parts[$i + 1])) {
                $origPath = Normalize-RepoPath $parts[$i + 1]
            }
            $i += 2
        } else {
            $i += 1
        }

        if ($normPath -match '^\.worktrees(/|$)') {
            continue
        }

        $leak = Test-ZeroLeakFile -repoRoot $ctx.RepoRoot -relPath $normPath -statusXy $xy
        $entries.Add([PSCustomObject]@{
            path        = $normPath
            origPath    = $origPath
            status      = $xy
            statusLabel = (Get-StatusLabel $xy)
            isLeak      = $leak.IsLeak
            leakReason  = $leak.Reason
        })
    }

    return ,@($entries.ToArray())
}

function Get-UnpushedCommits($ctx) {
    $commits = [System.Collections.Generic.List[object]]::new()
    if ($ctx.HeadSha -eq "UNBORN") {
        return ,@()
    }

    $hasUpstream = $false
    $upRes = Invoke-GitRaw -GitArgs @("rev-parse", "--abbrev-ref", '@{u}')
    if ($upRes.ExitCode -eq 0) { $hasUpstream = $true }

    $rangeArgs = $null
    if ($hasUpstream) {
        $rangeArgs = @("log", '@{u}..HEAD', "--format=%H%x09%h%x09%s")
    } else {
        $remRefRes = Invoke-GitRaw -GitArgs @("rev-parse", "--verify", "refs/remotes/$($ctx.Remote)/$($ctx.Branch)")
        if ($remRefRes.ExitCode -eq 0) {
            $rangeArgs = @("log", "$($ctx.Remote)/$($ctx.Branch)..HEAD", "--format=%H%x09%h%x09%s")
        } else {
            $rangeArgs = @("log", "HEAD", "-n", "20", "--format=%H%x09%h%x09%s")
        }
    }

    $logRes = Invoke-GitRaw -GitArgs $rangeArgs -UseQuotepathFalse
    if ($logRes.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($logRes.StdOut)) {
        return ,@()
    }

    $lines = $logRes.StdOut -split "`r?`n"
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $cols = $line -split "`t", 3
        if ($cols.Count -lt 3) { continue }
        $sha = $cols[0].Trim()
        $shortSha = $cols[1].Trim()
        $subject = $cols[2].Trim()

        $filesRes = Invoke-GitRaw -GitArgs @("diff-tree", "--no-commit-id", "--name-status", "-r", $sha) -UseQuotepathFalse
        $cFiles = @()
        if ($filesRes.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($filesRes.StdOut)) {
            foreach ($fl in ($filesRes.StdOut -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($fl)) { $cFiles += $fl.Trim() }
            }
        }

        $commits.Add([PSCustomObject]@{
            sha     = $sha
            short   = $shortSha
            subject = $subject
            files   = @($cFiles)
        })
    }

    return ,@($commits.ToArray())
}

function Read-Manifest($ctx) {
    if (-not (Test-Path -LiteralPath $ctx.ManifestPath)) { return $null }
    try {
        $raw = [System.IO.File]::ReadAllText($ctx.ManifestPath, [System.Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        $obj = $raw | ConvertFrom-Json
        if (-not $obj) { return $null }
        $items = @(ConvertTo-Array $obj.items)
        $commits = @(ConvertTo-Array $obj.unpushedCommits)
        return [PSCustomObject]@{
            version         = $obj.version
            branch          = [string]$obj.branch
            remote          = [string]$obj.remote
            headSha         = [string]$obj.headSha
            createdAt       = [string]$obj.createdAt
            updatedAt       = [string]$obj.updatedAt
            items           = $items
            unpushedCommits = $commits
        }
    } catch {
        return $null
    }
}

function Save-Manifest($ctx, $manifest, [switch]$NoSave) {
    # Id'leri 1..N yeniden sirala
    $ordered = [System.Collections.Generic.List[object]]::new()
    $idx = 1
    foreach ($it in (ConvertTo-Array $manifest.items)) {
        $ordered.Add([PSCustomObject]@{
            id            = $idx
            path          = [string]$it.path
            origPath      = $it.origPath
            status        = [string]$it.status
            statusLabel   = [string]$it.statusLabel
            included      = [bool]$it.included
            forcedIgnore  = [bool]$it.forcedIgnore
            excludeReason = [string]$it.excludeReason
        })
        $idx++
    }

    $toSave = [PSCustomObject]@{
        version         = 1
        branch          = $ctx.Branch
        remote          = $ctx.Remote
        headSha         = $ctx.HeadSha
        createdAt       = if ($manifest.createdAt) { $manifest.createdAt } else { (Get-Date).ToString("o") }
        updatedAt       = (Get-Date).ToString("o")
        items           = @($ordered.ToArray())
        unpushedCommits = @(ConvertTo-Array $manifest.unpushedCommits)
    }

    if (-not $NoSave) {
        if (-not (Test-Path -LiteralPath $ctx.VigilesDir)) {
            New-Item -ItemType Directory -Path $ctx.VigilesDir -Force | Out-Null
        }
        $jsonStr = $toSave | ConvertTo-Json -Depth 6
        [System.IO.File]::WriteAllText($ctx.ManifestPath, $jsonStr, $Utf8NoBom)
    }
    return $toSave
}

function Clear-Manifest($ctx) {
    if (Test-Path -LiteralPath $ctx.ManifestPath) {
        Remove-Item -LiteralPath $ctx.ManifestPath -Force -ErrorAction SilentlyContinue
    }
}

function Sync-Manifest($ctx, [switch]$ResetChoices, [switch]$MarkNewAsExcluded, [switch]$NoSave) {
    $existing = if (-not $ResetChoices) { Read-Manifest $ctx } else { $null }
    $existingValid = ($null -ne $existing -and $existing.branch -eq $ctx.Branch -and $existing.remote -eq $ctx.Remote)

    $prevByPath = @{}
    $forcedIgnorePrev = [System.Collections.Generic.List[object]]::new()
    if ($existingValid) {
        foreach ($old in (ConvertTo-Array $existing.items)) {
            $prevByPath[$old.path] = $old
            if ($old.forcedIgnore -and $old.included) {
                $forcedIgnorePrev.Add($old)
            }
        }
    }

    $wtEntries = @(ConvertTo-Array (Get-WorkingTreeEntries $ctx))
    $wtPathSet = @{}
    $merged = [System.Collections.Generic.List[object]]::new()
    $newlyDetected = [System.Collections.Generic.List[string]]::new()

    foreach ($wt in $wtEntries) {
        $wtPathSet[$wt.path] = $true
        $prev = if ($prevByPath.ContainsKey($wt.path)) { $prevByPath[$wt.path] } else { $null }

        $included = $true
        $excludeReason = ""
        $forcedIgnore = $false

        if ($wt.isLeak) {
            $included = $false
            $excludeReason = $wt.leakReason
        } elseif ($null -ne $prev) {
            $included = [bool]$prev.included
            $excludeReason = [string]$prev.excludeReason
            $forcedIgnore = [bool]$prev.forcedIgnore
        } elseif ($existingValid -and $MarkNewAsExcluded) {
            $included = $false
            $excludeReason = "new_since_prep"
            $newlyDetected.Add($wt.path)
        }

        $merged.Add([PSCustomObject]@{
            id            = 0
            path          = $wt.path
            origPath      = $wt.origPath
            status        = $wt.status
            statusLabel   = $wt.statusLabel
            included      = $included
            forcedIgnore  = $forcedIgnore
            excludeReason = $excludeReason
        })
    }

    # Daha once /pushadd ile zorla eklenmis (.gitignore) dosyalar diskte hala varsa koru
    foreach ($fi in $forcedIgnorePrev) {
        if (-not $wtPathSet.ContainsKey($fi.path)) {
            $fullFi = Join-Path $ctx.RepoRoot ($fi.path.Replace('/', '\'))
            if (Test-Path -LiteralPath $fullFi -PathType Leaf) {
                $leak = Test-ZeroLeakFile -repoRoot $ctx.RepoRoot -relPath $fi.path -statusXy "??"
                if (-not $leak.IsLeak) {
                    $merged.Add([PSCustomObject]@{
                        id            = 0
                        path          = $fi.path
                        origPath      = $null
                        status        = "FI"
                        statusLabel   = "Gitignore İstisnasi (/pushadd)"
                        included      = $true
                        forcedIgnore  = $true
                        excludeReason = ""
                    })
                }
            }
        }
    }

    $commits = @(ConvertTo-Array (Get-UnpushedCommits $ctx))
    $draft = [PSCustomObject]@{
        createdAt       = if ($existingValid) { $existing.createdAt } else { (Get-Date).ToString("o") }
        items           = @(ConvertTo-Array $merged)
        unpushedCommits = @(ConvertTo-Array $commits)
    }
    $saved = Save-Manifest $ctx $draft -NoSave:$NoSave

    return @{
        Manifest      = $saved
        NewlyDetected = @(ConvertTo-Array $newlyDetected)
        HadManifest   = $existingValid
    }
}

function Show-PushPrepSummary($ctx, $manifest, [string]$HeaderTitle = "PUSH ONIZLEME LISTESI (/pushprep)") {
    $items = @(ConvertTo-Array $manifest.items)
    $includedItems = @($items | Where-Object { $_.included })
    $excludedItems = @($items | Where-Object { -not $_.included })
    $commits = @(ConvertTo-Array $manifest.unpushedCommits)

    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host ">> $HeaderTitle" -ForegroundColor Yellow
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host "   Branch : $($ctx.Branch)  ->  $($ctx.Remote) ($($ctx.RemoteUrl))" -ForegroundColor Gray

    Write-Host "`n[A] PUSHLANACAK DOSYALAR (Dahil: $($includedItems.Count) adet)" -ForegroundColor Green
    if ($includedItems.Count -eq 0) {
        Write-Host "   (Push paketinde bekleyen degisiklik yok)" -ForegroundColor DarkGray
    } else {
        foreach ($it in $includedItems) {
            $renameInfo = if ($it.origPath) { " (eski: $($it.origPath))" } else { "" }
            $fiTag = if ($it.forcedIgnore) { " [.gitignore istisnasi]" } else { "" }
            Write-Host ("   [{0}] [{1}] {2}  ({3}){4}{5}" -f $it.id, $it.status.Trim(), $it.path, $it.statusLabel, $renameInfo, $fiTag) -ForegroundColor White
        }
    }

    if ($excludedItems.Count -gt 0) {
        Write-Host "`n[B] HARIC TUTULAN DOSYALAR (Gonderilmeyecek - Yerelde Korunur: $($excludedItems.Count) adet)" -ForegroundColor DarkYellow
        foreach ($it in $excludedItems) {
            $reasonText = switch ($it.excludeReason) {
                "user_removed"   { "Kullanici /pushremove ile cikardi" }
                "gitignored"     { ".gitignore'a eklendi" }
                "new_since_prep" { "/pushprep sonrasinda olustu (dahil etmek icin /pushadd)" }
                default          { if ($it.excludeReason) { $it.excludeReason } else { "Haric tutuldu" } }
            }
            $col = if ($it.excludeReason -match "Zero-Leak|Ortam|Hassas|anahtar") { "Red" } else { "DarkYellow" }
            Write-Host ("   [{0}] [{1}] {2}  -> {3}" -f $it.id, $it.status.Trim(), $it.path, $reasonText) -ForegroundColor $col
        }
    }

    if ($commits.Count -gt 0) {
        Write-Host "`n[C] ONCEDEN COMMITLENMIS & PUSH BEKLEYEN COMMITLER ($($commits.Count) adet)" -ForegroundColor Cyan
        foreach ($c in $commits) {
            Write-Host ("   -> {0} {1}" -f $c.short, $c.subject) -ForegroundColor White
            foreach ($cf in (ConvertTo-Array $c.files)) {
                Write-Host ("      - {0}" -f $cf) -ForegroundColor DarkGray
            }
        }
    }

    $sessionsDir = if ($ctx.CommonGitDir) { Join-Path $ctx.CommonGitDir "vigiles\sessions" } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($sessionsDir) -and (Test-Path -LiteralPath $sessionsDir)) {
        $pendingWorktrees = [System.Collections.Generic.List[object]]::new()
        foreach ($sf in (Get-ChildItem -Path $sessionsDir -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
            try {
                $sRec = [System.IO.File]::ReadAllText($sf.FullName, [System.Text.Encoding]::UTF8).Trim().Trim([char]65279) | ConvertFrom-Json
                if ($sRec -and $sRec.mode -eq "WORKTREE" -and $sRec.status -in @("ACTIVE", "READY_TO_MERGE", "STALE", "COMPLETED") -and $sRec.worktreePath -and (Test-Path -LiteralPath $sRec.worktreePath)) {
                    $pendingWorktrees.Add($sRec)
                }
            } catch {}
        }
        if ($pendingWorktrees.Count -gt 0) {
            Write-Host "`n[BILGI - PARALEL SANTIYE]: Bu repoda $($pendingWorktrees.Count) adet birlestirilmemis izole worktree santiyesi bulunuyor:" -ForegroundColor Cyan
            foreach ($pw in $pendingWorktrees) {
                Write-Host ("   * pro-{0} ({1}) -> {2}  [Birlestirmek icin: /merge {0}]" -f $pw.shortId, $pw.status, $pw.worktreePath) -ForegroundColor DarkCyan
            }
        }
    }

    Write-Host "`n----------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "   Komutlar: '/pushremove <no|dosya>' | '/pushadd <no|dosya>' | '/push'" -ForegroundColor Gray
}

function Expand-TargetTokens($rawTargets, $manifestItems) {
    $tokens = [System.Collections.Generic.List[string]]::new()
    $knownPaths = @{}
    foreach ($it in (ConvertTo-Array $manifestItems)) {
        $knownPaths[$it.path] = $true
    }

    foreach ($t in (ConvertTo-Array $rawTargets)) {
        if ([string]::IsNullOrWhiteSpace($t)) { continue }
        $trimmed = $t.Trim()
        $normT = Normalize-RepoPath $trimmed

        # Tam bilinen bir yol veya diskte tek basina bulunan dosya ise virgul/bosluga bolme
        if ($knownPaths.ContainsKey($normT) -or (Test-Path -LiteralPath $trimmed)) {
            $tokens.Add($trimmed)
            continue
        }

        # Virgulleri ayir
        $commaParts = $trimmed -split ','
        foreach ($cp in $commaParts) {
            $c = $cp.Trim()
            if ([string]::IsNullOrWhiteSpace($c)) { continue }
            # Eger birden fazla sayi veya aralik boslukla verilmissse ("2 3" veya "4-7")
            if ($c -match '^[\d\s\-]+$') {
                foreach ($sub in ($c -split '\s+')) {
                    if ($sub -match '^(\d+)-(\d+)$') {
                        $s = [int]$matches[1]; $e = [int]$matches[2]
                        if ($s -le $e) {
                            for ($k = $s; $k -le $e; $k++) { $tokens.Add([string]$k) }
                        }
                    } elseif ($sub -match '^\d+$') {
                        $tokens.Add($sub)
                    }
                }
            } else {
                $tokens.Add($c)
            }
        }
    }
    return @($tokens.ToArray())
}

function Resolve-ManifestTargets($tokens, $manifestItems) {
    $matched = [System.Collections.Generic.List[object]]::new()
    $unmatched = [System.Collections.Generic.List[string]]::new()
    $ambiguous = [System.Collections.Generic.List[object]]::new()
    $items = @(ConvertTo-Array $manifestItems)

    foreach ($tok in $tokens) {
        if ($tok -match '^\d+$') {
            $num = [int]$tok
            $hit = $items | Where-Object { [int]$_.id -eq $num }
            if ($hit) {
                $matched.Add($hit)
            } else {
                $unmatched.Add($tok)
            }
            continue
        }

        $normTok = Normalize-RepoPath $tok

        # 1. Tam yol eslesmesi
        $exact = @($items | Where-Object { $_.path -eq $normTok -or $_.path -ieq $normTok })
        if ($exact.Count -eq 1) {
            $matched.Add($exact[0])
            continue
        }

        # 2. Wildcard veya klasor on eki
        if ($normTok -match '[\*\?]') {
            $wc = New-Object System.Management.Automation.WildcardPattern ($normTok, [System.Management.Automation.WildcardOptions]::IgnoreCase)
            $wcHits = @($items | Where-Object { $wc.IsMatch($_.path) -or $wc.IsMatch([System.IO.Path]::GetFileName($_.path)) })
            if ($wcHits.Count -gt 0) {
                foreach ($w in $wcHits) { $matched.Add($w) }
                continue
            }
        }

        # Klasor yolu eslesmesi
        $dirHits = @($items | Where-Object { $_.path.StartsWith("$normTok/", [System.StringComparison]::OrdinalIgnoreCase) })
        if ($dirHits.Count -gt 0) {
            foreach ($d in $dirHits) { $matched.Add($d) }
            continue
        }

        # 3. Dosya adi (leaf) eslesmesi
        $leafHits = @($items | Where-Object { [System.IO.Path]::GetFileName($_.path) -ieq $normTok })
        if ($leafHits.Count -eq 1) {
            $matched.Add($leafHits[0])
            continue
        } elseif ($leafHits.Count -gt 1) {
            $ambiguous.Add([PSCustomObject]@{ Token = $tok; Candidates = $leafHits })
            continue
        }

        # 4. Kismi sonek eslesmesi (orn: "scripts/foo.ps1")
        $suffixHits = @($items | Where-Object { $_.path.EndsWith("/$normTok", [System.StringComparison]::OrdinalIgnoreCase) })
        if ($suffixHits.Count -eq 1) {
            $matched.Add($suffixHits[0])
            continue
        } elseif ($suffixHits.Count -gt 1) {
            $ambiguous.Add([PSCustomObject]@{ Token = $tok; Candidates = $suffixHits })
            continue
        }

        $unmatched.Add($tok)
    }

    # Tekrarlari ayikla (id bazinda)
    $seen = @{}
    $uniqueMatched = [System.Collections.Generic.List[object]]::new()
    foreach ($m in $matched) {
        if (-not $seen.ContainsKey($m.path)) {
            $seen[$m.path] = $true
            $uniqueMatched.Add($m)
        }
    }

    return @{
        Matched   = @($uniqueMatched.ToArray())
        Unmatched = @($unmatched.ToArray())
        Ambiguous = @($ambiguous.ToArray())
    }
}

function Unstage-RepoPaths($ctx, [string[]]$paths) {
    $valid = @($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($valid.Count -eq 0) { return }

    $tmpSpec = [System.IO.Path]::GetTempFileName()
    try {
        [System.IO.File]::WriteAllLines($tmpSpec, $valid, $Utf8NoBom)
        if ($ctx.HeadSha -eq "UNBORN") {
            Invoke-GitRaw -GitArgs @("rm", "--cached", "-q", "--ignore-unmatch", "--pathspec-from-file=$tmpSpec") | Out-Null
        } else {
            Invoke-GitRaw -GitArgs @("reset", "-q", "HEAD", "--pathspec-from-file=$tmpSpec") | Out-Null
        }
    } finally {
        Remove-Item -LiteralPath $tmpSpec -Force -ErrorAction SilentlyContinue
    }
}

function Add-PathsToGitIgnore($ctx, [string[]]$paths) {
    $giPath = Join-Path $ctx.RepoRoot ".gitignore"
    $lines = [System.Collections.Generic.List[string]]::new()
    $existingSet = @{}

    if (Test-Path -LiteralPath $giPath) {
        $raw = [System.IO.File]::ReadAllText($giPath, [System.Text.Encoding]::UTF8)
        if (-not [string]::IsNullOrEmpty($raw)) {
            foreach ($l in ($raw -split "`r?`n")) {
                $lines.Add($l)
                $trimmed = $l.Trim()
                if (-not [string]::IsNullOrEmpty($trimmed) -and -not $trimmed.StartsWith("#")) {
                    $existingSet[$trimmed.TrimStart('/')] = $true
                }
            }
        }
    }

    $addedCount = 0
    foreach ($p in $paths) {
        $norm = Normalize-RepoPath $p
        if (-not $existingSet.ContainsKey($norm)) {
            # Sondaki bos satirlari sisirmemek icin kontrol
            if ($lines.Count -gt 0 -and [string]::IsNullOrEmpty($lines[$lines.Count - 1])) {
                $lines[$lines.Count - 1] = $norm
            } else {
                $lines.Add($norm)
            }
            $existingSet[$norm] = $true
            $addedCount++
        }
    }

    if ($addedCount -gt 0 -or -not (Test-Path -LiteralPath $giPath)) {
        $finalContent = ($lines.ToArray() -join "`n").TrimEnd("`n") + "`n"
        [System.IO.File]::WriteAllText($giPath, $finalContent, $Utf8NoBom)
    }
    return $addedCount
}

function Resolve-DiskFileForAdd($ctx, [string]$tok) {
    $norm = Normalize-RepoPath $tok
    $direct = Join-Path $ctx.RepoRoot ($norm.Replace('/', '\'))
    if (Test-Path -LiteralPath $direct -PathType Leaf) {
        return @($norm)
    }

    # Wildcard veya dosya adi ile repo icinde ara (.git ve .worktrees haric)
    $allFiles = Get-ChildItem -Path $ctx.RepoRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '([\\/])(\.git|\.worktrees)([\\/]|$)' }

    $hits = [System.Collections.Generic.List[string]]::new()
    $wc = New-Object System.Management.Automation.WildcardPattern ($norm, [System.Management.Automation.WildcardOptions]::IgnoreCase)

    foreach ($f in $allFiles) {
        $rel = $f.FullName.Substring($ctx.RepoRoot.Length).TrimStart('\', '/').Replace('\', '/')
        if ($rel -ieq $norm -or $f.Name -ieq $norm -or ($norm -match '[\*\?]' -and ($wc.IsMatch($rel) -or $wc.IsMatch($f.Name))) -or $rel.EndsWith("/$norm", [System.StringComparison]::OrdinalIgnoreCase)) {
            $hits.Add($rel)
        }
    }
    return @($hits.ToArray())
}

# --- ANA AKIS ---

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ">> VIGILES ENGINE - GUVENLI GIT PIPELINE (PUSHPREP / PUSH)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$ctx = Get-RepoContext
Write-Host "[*] Aktif Branch : $($ctx.Branch)" -ForegroundColor Gray
Write-Host "[*] Hedef Remote : $($ctx.Remote) ($($ctx.RemoteUrl))" -ForegroundColor Gray

# 1. RESET veya PREP veya STATUS
if ($Action -in @("Prep", "Reset", "Status")) {
    $isReset = ($Action -eq "Reset")
    $isNoSave = ($Action -eq "Status" -or $DryRun)
    $syncRes = Sync-Manifest $ctx -ResetChoices:$isReset -NoSave:$isNoSave
    $manifest = $syncRes.Manifest

    if ($Json) {
        Write-Output ($manifest | ConvertTo-Json -Depth 6)
        exit 0
    }

    $title = if ($isReset) { "PUSH ONIZLEME SIFIRLANDI (/pushprep --reset)" } else { "PUSH ONIZLEME LISTESI (/pushprep)" }
    Show-PushPrepSummary $ctx $manifest $title
    exit 0
}

# 2. REMOVE (/pushremove)
if ($Action -eq "Remove") {
    if (-not $Targets -or $Targets.Count -eq 0) {
        Write-Host "[HATA]: Cikarilacak dosya veya sira numarasi belirtilmedi! Ornek: /pushremove 3 veya /pushremove dosya.txt" -ForegroundColor Red
        exit 1
    }

    $syncRes = Sync-Manifest $ctx
    $manifest = $syncRes.Manifest
    $items = @(ConvertTo-Array $manifest.items)

    $tokens = Expand-TargetTokens $Targets $items
    $res = Resolve-ManifestTargets $tokens $items

    if ($res.Ambiguous.Count -gt 0) {
        foreach ($amb in $res.Ambiguous) {
            Write-Host "[UYARI]: '$($amb.Token)' birden fazla dosya ile eslesti. Lutfen numara veya tam yol belirtin:" -ForegroundColor Yellow
            foreach ($cand in $amb.Candidates) {
                Write-Host "   [$($cand.id)] $($cand.path)" -ForegroundColor White
            }
        }
        exit 1
    }

    if ($res.Matched.Count -eq 0) {
        Write-Host "[HATA]: Belirtilen hedef(ler) push listesinde bulunamadi: $($res.Unmatched -join ', ')" -ForegroundColor Red
        exit 1
    }

    $removedPaths = [System.Collections.Generic.List[string]]::new()
    $matchedSet = @{}
    foreach ($m in $res.Matched) { $matchedSet[$m.path] = $true }

    foreach ($it in $items) {
        if ($matchedSet.ContainsKey($it.path)) {
            $it.included = $false
            $it.forcedIgnore = $false
            $it.excludeReason = if ($Ignore) { "gitignored" } else { "user_removed" }
            $removedPaths.Add($it.path)
        }
    }

    $manifest = Save-Manifest $ctx $manifest
    Unstage-RepoPaths $ctx ($removedPaths.ToArray())

    if ($Ignore) {
        $giAdded = Add-PathsToGitIgnore $ctx ($removedPaths.ToArray())
        Write-Host "`n[GITIGNORE]: $($removedPaths.Count) dosya .gitignore'a islendi (yeni satir: $giAdded). Yerel dosyalar korundu." -ForegroundColor Cyan
        # .gitignore dosyasini manifestoda guncel ve dahil goster
        $syncAfter = Sync-Manifest $ctx
        $manifest = $syncAfter.Manifest
    }

    Write-Host "`n[PUSHREMOVE]: Asagidaki dosya(lar) push paketinden cikarildi (YEREL DOSYALAR KORUNDU):" -ForegroundColor Yellow
    foreach ($rp in $removedPaths) {
        Write-Host "   - $rp" -ForegroundColor DarkYellow
    }

    if ($res.Unmatched.Count -gt 0) {
        Write-Host "[BILGI]: Eslesmeyen hedefler atlandi: $($res.Unmatched -join ', ')" -ForegroundColor DarkGray
    }

    Show-PushPrepSummary $ctx $manifest "GUNCELLENMIS PUSH LISTESI"
    exit 0
}

# 3. ADD (/pushadd)
if ($Action -eq "Add") {
    if (-not $Targets -or $Targets.Count -eq 0) {
        Write-Host "[HATA]: Eklenecek dosya veya sira numarasi belirtilmedi! Ornek: /pushadd 3 veya /pushadd dosya.txt" -ForegroundColor Red
        exit 1
    }

    $syncRes = Sync-Manifest $ctx
    $manifest = $syncRes.Manifest
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($x in (ConvertTo-Array $manifest.items)) { $items.Add($x) }

    $tokens = Expand-TargetTokens $Targets $items
    $res = Resolve-ManifestTargets $tokens $items

    if ($res.Ambiguous.Count -gt 0) {
        foreach ($amb in $res.Ambiguous) {
            Write-Host "[UYARI]: '$($amb.Token)' birden fazla dosya ile eslesti. Lutfen numara veya tam yol belirtin:" -ForegroundColor Yellow
            foreach ($cand in $amb.Candidates) {
                Write-Host "   [$($cand.id)] $($cand.path)" -ForegroundColor White
            }
        }
        exit 1
    }

    $addedPaths = [System.Collections.Generic.List[string]]::new()
    $blockedPaths = [System.Collections.Generic.List[string]]::new()
    $matchedSet = @{}
    foreach ($m in $res.Matched) { $matchedSet[$m.path] = $true }

    # Manifestoda zaten olanlari geri al
    foreach ($it in $items) {
        if ($matchedSet.ContainsKey($it.path)) {
            $leak = Test-ZeroLeakFile -repoRoot $ctx.RepoRoot -relPath $it.path -statusXy $it.status
            if ($leak.IsLeak) {
                Write-Host "[ZERO-LEAK ENGELI]: '$($it.path)' guvenlik ihlali nedeniyle eklenemez! ($($leak.Reason))" -ForegroundColor Red
                $blockedPaths.Add($it.path)
            } else {
                $it.included = $true
                $it.excludeReason = ""
                $addedPaths.Add($it.path)
            }
        }
    }

    # Manifestoda bulunamayanlar icin disk + gitignore kontrolu
    $stillMissing = [System.Collections.Generic.List[string]]::new()
    foreach ($uTok in $res.Unmatched) {
        if ($uTok -match '^\d+$') {
            $stillMissing.Add($uTok)
            continue
        }

        $diskHits = Resolve-DiskFileForAdd $ctx $uTok
        if ($diskHits.Count -eq 0) {
            $stillMissing.Add($uTok)
            continue
        }

        foreach ($dh in $diskHits) {
            $alreadyInManifest = $items | Where-Object { $_.path -eq $dh }
            if ($alreadyInManifest) {
                continue
            }

            $leak = Test-ZeroLeakFile -repoRoot $ctx.RepoRoot -relPath $dh -statusXy "??"
            if ($leak.IsLeak) {
                Write-Host "[ZERO-LEAK ENGELI]: '$dh' guvenlik ihlali nedeniyle eklenemez! ($($leak.Reason))" -ForegroundColor Red
                $blockedPaths.Add($dh)
                continue
            }

            $ignRes = Invoke-GitRaw -GitArgs @("check-ignore", "-q", $dh)
            if ($ignRes.ExitCode -eq 0) {
                Write-Host "[BILGI]: '$dh' .gitignore icinde olmasina ragmen guvenli oldugu icin push paketine istisna olarak eklendi." -ForegroundColor Cyan
                $items.Add([PSCustomObject]@{
                    id            = 0
                    path          = $dh
                    origPath      = $null
                    status        = "FI"
                    statusLabel   = "Gitignore Istisnasi (/pushadd)"
                    included      = $true
                    forcedIgnore  = $true
                    excludeReason = ""
                })
                $addedPaths.Add($dh)
            } else {
                $trackedRes = Invoke-GitRaw -GitArgs @("ls-files", "--error-unmatch", $dh)
                if ($trackedRes.ExitCode -eq 0) {
                    Write-Host "[BILGI]: '$dh' dosyasinda degisiklik yok (uzak/yerel son commit ile zaten guncel)." -ForegroundColor DarkGray
                } else {
                    $items.Add([PSCustomObject]@{
                        id            = 0
                        path          = $dh
                        origPath      = $null
                        status        = "??"
                        statusLabel   = "Yeni (Takipsiz)"
                        included      = $true
                        forcedIgnore  = $false
                        excludeReason = ""
                    })
                    $addedPaths.Add($dh)
                }
            }
        }
    }

    if ($blockedPaths.Count -gt 0) {
        exit 1
    }

    if ($addedPaths.Count -eq 0 -and $stillMissing.Count -gt 0) {
        Write-Host "[HATA]: Su dosya/numara(lar) bulunamadi: $($stillMissing -join ', ')" -ForegroundColor Red
        exit 1
    }

    $manifest.items = @($items.ToArray())
    $manifest = Save-Manifest $ctx $manifest

    if ($addedPaths.Count -gt 0) {
        Write-Host "`n[PUSHADD]: Push paketine eklendi ($($addedPaths.Count) adet):" -ForegroundColor Green
        foreach ($ap in $addedPaths) {
            Write-Host "   + $ap" -ForegroundColor Green
        }
    }

    Show-PushPrepSummary $ctx $manifest "GUNCELLENMIS PUSH LISTESI"
    exit 0
}

# 4. PUSH (/push) — Zorunlu Onizleme Kapisi & Secici Sahneleme
$existingManifest = Read-Manifest $ctx
$hasValidManifest = ($null -ne $existingManifest -and $existingManifest.branch -eq $ctx.Branch -and $existingManifest.remote -eq $ctx.Remote)

$syncResult = Sync-Manifest $ctx -MarkNewAsExcluded:$hasValidManifest -NoSave:$DryRun
$manifest = $syncResult.Manifest
$items = @(ConvertTo-Array $manifest.items)
$includedItems = @($items | Where-Object { $_.included })
$excludedItems = @($items | Where-Object { -not $_.included })
$commits = @(ConvertTo-Array $manifest.unpushedCommits)

# Hicbir degisiklik ve bekleyen commit yoksa temiz cik
if ($includedItems.Count -eq 0 -and $excludedItems.Count -eq 0 -and $commits.Count -eq 0) {
    if (-not $DryRun) { Clear-Manifest $ctx }
    Write-Host "`n[BILGI]: Uzak depo zaten guncel! Pushlanacak bekleyen yeni commit veya dosya bulunmuyor." -ForegroundColor Green
    exit 0
}

# ZORUNLU ONIZLEME KAPISI: Daha once /pushprep yapilmadiysa ve -Approved verilmediyse DUR!
if (-not $hasValidManifest -and -not $Approved) {
    Show-PushPrepSummary $ctx $manifest "ZORUNLU ONIZLEME (/pushprep yapilmadi)"
    if ($DryRun) {
        Write-Host "`n[DRY-RUN]: Onizleme Kapisi aktif. Gercek push yapilmadi." -ForegroundColor Yellow
        exit 0
    }
    Write-Host "`n[ONIZLEME GEREKLI]: Oncesinde '/pushprep' calistirilmadigi icin dogrudan push engellendi." -ForegroundColor Yellow
    Write-Host "   -> Listeyi duzenlemek icin '/pushremove <no|dosya>' veya '/pushadd <no|dosya>' kullanin." -ForegroundColor Gray
    Write-Host "   -> Bu paketi onaylayip gondermek icin simdi '/push' veya onay komutu verin." -ForegroundColor Gray
    exit 2
}

# DRIFT KONTROLU: /pushprep sonrasinda yeni kirli dosya turediyse ve -Approved yoksa DUR!
if ($hasValidManifest -and $syncResult.NewlyDetected.Count -gt 0 -and -not $Approved) {
    Show-PushPrepSummary $ctx $manifest "YENI DOSYA TESPITI (ONAY GEREKLI)"
    if ($DryRun) {
        Write-Host "`n[DRY-RUN]: Yeni tespit edilen dosyalar haric tutuldu. Gercek push yapilmadi." -ForegroundColor Yellow
        exit 0
    }
    Write-Host "`n[YENI DOSYA TESPITI]: /pushprep sonrasinda $($syncResult.NewlyDetected.Count) yeni dosya algilandi ve guvenlik geregi haric tutuldu:" -ForegroundColor Yellow
    foreach ($nd in $syncResult.NewlyDetected) {
        Write-Host "   ? $nd" -ForegroundColor DarkYellow
    }
    Write-Host "   -> Dahil etmek icin '/pushadd <dosya>', haric tutarak pushlamak icin onay verin." -ForegroundColor Gray
    exit 2
}

# Cakisma (merge conflict) kontrolu
$conflicts = @($includedItems | Where-Object { $_.status -match 'U|AA|DD' })
if ($conflicts.Count -gt 0) {
    Write-Host "[HATA]: Cozulmemis Git cakismalari (conflict) mevcut! Once cakismalari cozun:" -ForegroundColor Red
    foreach ($cf in $conflicts) { Write-Host "   ! $($cf.path)" -ForegroundColor Red }
    exit 1
}

# Final Zero-Leak guvenlik taramasi (dahil edilen dosyalar)
foreach ($it in $includedItems) {
    $leak = Test-ZeroLeakFile -repoRoot $ctx.RepoRoot -relPath $it.path -statusXy $it.status
    if ($leak.IsLeak) {
        Write-Host "[ZERO-LEAK ENGELI]: '$($it.path)' push oncesi taramada takildi: $($leak.Reason)" -ForegroundColor Red
        exit 1
    }
}

if ($includedItems.Count -eq 0 -and $commits.Count -eq 0) {
    Write-Host "`n[BILGI]: Push paketinde onayli dosya veya bekleyen commit bulunmuyor (tum dosyalar /pushremove ile haric tutuldu)." -ForegroundColor DarkYellow
    exit 0
}

# Dry-Run modu
if ($DryRun) {
    Show-PushPrepSummary $ctx $manifest "DRY-RUN SIMULASYONU (Gercek Push Yapilmadi)"
    Write-Host "`n[DRY-RUN]: Secici sahneleme ($($includedItems.Count) dosya) ve commit/push simule edildi." -ForegroundColor Yellow
    exit 0
}

# ADIM 1 & 2: SECICI SAHNELEME VE COMMIT
$committedNow = $false
if ($includedItems.Count -gt 0) {
    Write-Host "`n[ADIM 1 - SECICI SAHNELEME]: Yalnizca onayli $($includedItems.Count) dosya sahneye ekleniyor..." -ForegroundColor Cyan

    # Once mevcut sahneyi tamamen sifirla (disaridan kalmis veya haric tutulan dosya sizmasin)
    if ($ctx.HeadSha -eq "UNBORN") {
        $stagedRes = Invoke-GitRaw -GitArgs @("diff", "--cached", "--name-only", "-z") -UseQuotepathFalse
        if ($stagedRes.ExitCode -eq 0 -and -not [string]::IsNullOrEmpty($stagedRes.StdOut)) {
            $stagedFiles = @($stagedRes.StdOut.Split([char]0) | Where-Object { -not [string]::IsNullOrEmpty($_) })
            Unstage-RepoPaths $ctx $stagedFiles
        }
    } else {
        $rstRes = Invoke-GitRaw -GitArgs @("reset", "-q", "HEAD")
        if ($rstRes.ExitCode -ne 0) {
            Write-Host "[HATA]: Git sahne alani sifirlanamadi: $($rstRes.StdErr)" -ForegroundColor Red
            exit 1
        }
    }

    $normalStagePaths = [System.Collections.Generic.List[string]]::new()
    $forcedStagePaths = [System.Collections.Generic.List[string]]::new()
    $expectedStageSet = @{}

    foreach ($it in $includedItems) {
        $expectedStageSet[$it.path] = $true
        if ($it.origPath -and ($it.status -match 'R')) {
            # Rename islemi icin eski yolun da sahneden dusup yeniden sahnelenmesi gerekir
            $normalStagePaths.Add($it.origPath)
            $expectedStageSet[$it.origPath] = $true
        }
        if ($it.forcedIgnore) {
            $forcedStagePaths.Add($it.path)
        } else {
            $normalStagePaths.Add($it.path)
        }
        Write-Host ("   + [{0}] {1}" -f $it.id, $it.path) -ForegroundColor DarkCyan
    }

    $tmpNormal = $null
    $tmpForced = $null
    try {
        if ($normalStagePaths.Count -gt 0) {
            $tmpNormal = [System.IO.Path]::GetTempFileName()
            [System.IO.File]::WriteAllLines($tmpNormal, @($normalStagePaths.ToArray()), $Utf8NoBom)
            $addRes = Invoke-GitRaw -GitArgs @("add", "--pathspec-from-file=$tmpNormal")
            if ($addRes.ExitCode -ne 0) {
                Write-Host "[HATA]: Secici git add basarisiz oldu: $($addRes.StdErr)" -ForegroundColor Red
                exit 1
            }
        }
        if ($forcedStagePaths.Count -gt 0) {
            $tmpForced = [System.IO.Path]::GetTempFileName()
            [System.IO.File]::WriteAllLines($tmpForced, @($forcedStagePaths.ToArray()), $Utf8NoBom)
            $addFRes = Invoke-GitRaw -GitArgs @("add", "-f", "--pathspec-from-file=$tmpForced")
            if ($addFRes.ExitCode -ne 0) {
                Write-Host "[HATA]: Gitignore istisna add (-f) basarisiz oldu: $($addFRes.StdErr)" -ForegroundColor Red
                exit 1
            }
        }
    } finally {
        if ($tmpNormal) { Remove-Item -LiteralPath $tmpNormal -Force -ErrorAction SilentlyContinue }
        if ($tmpForced) { Remove-Item -LiteralPath $tmpForced -Force -ErrorAction SilentlyContinue }
    }

    # STAGE PARITY DOGRULAMASI: Gercekte sahneye giren dosyalar == Manifesto onaylilari mi?
    $cachedRes = Invoke-GitRaw -GitArgs @("diff", "--cached", "--name-only", "-z") -UseQuotepathFalse
    $actualStaged = @()
    if ($cachedRes.ExitCode -eq 0 -and -not [string]::IsNullOrEmpty($cachedRes.StdOut)) {
        $actualStaged = @($cachedRes.StdOut.Split([char]0) | Where-Object { -not [string]::IsNullOrEmpty($_) } | ForEach-Object { Normalize-RepoPath $_ })
    }

    $unexpected = @()
    foreach ($as in $actualStaged) {
        if (-not $expectedStageSet.ContainsKey($as)) {
            $unexpected += $as
        }
    }
    if ($unexpected.Count -gt 0) {
        Write-Host "[KRITIK GUVENLIK HATASI]: Manifesto disinda dosya(lar) sahneye sizdi: $($unexpected -join ', '). Islem iptal edildi!" -ForegroundColor Red
        Unstage-RepoPaths $ctx $actualStaged
        exit 1
    }

    if ($actualStaged.Count -eq 0) {
        Write-Host "`n[BILGI]: Sahneye alinan degisiklik bulunmuyor." -ForegroundColor DarkGray
    } else {
        if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
            $CommitMessage = "feat: update system improvements and verified changes"
        }

        Write-Host "`n[ADIM 2 - GIT COMMIT]: Commit olusturuluyor: '$CommitMessage'..." -ForegroundColor Cyan
        $tmpMsg = [System.IO.Path]::GetTempFileName()
        try {
            [System.IO.File]::WriteAllText($tmpMsg, $CommitMessage, $Utf8NoBom)
            $cmtRes = Invoke-GitRaw -GitArgs @("commit", "-F", $tmpMsg)
            if (-not [string]::IsNullOrWhiteSpace($cmtRes.StdOut)) { Write-Host $cmtRes.StdOut.Trim() -ForegroundColor DarkGray }
            if ($cmtRes.ExitCode -eq 0) {
                Write-Host "[OK] Commit basariyla kaydedildi." -ForegroundColor Green
                $committedNow = $true
            } else {
                Write-Host "[HATA]: Commit olusturulamadi: $($cmtRes.StdErr)" -ForegroundColor Red
                exit 1
            }
        } finally {
            Remove-Item -LiteralPath $tmpMsg -Force -ErrorAction SilentlyContinue
        }
    }
}

# ADIM 3: PUSH BEKLEYEN COMMITLER VE AKTARIM
$ctxAfter = Get-RepoContext
$finalCommits = @(ConvertTo-Array (Get-UnpushedCommits $ctxAfter))

if ($finalCommits.Count -eq 0 -and -not $committedNow) {
    Clear-Manifest $ctxAfter
    Write-Host "`n[BILGI]: Uzak depo zaten guncel! Pushlanacak bekleyen yeni commit bulunmuyor." -ForegroundColor Green
    exit 0
}

Write-Host "`n[ADIM 3 - GIT PUSH]: Pushlanacak Commitler ($($finalCommits.Count) adet):" -ForegroundColor Cyan
foreach ($c in $finalCommits) {
    Write-Host "   -> $($c.short) $($c.subject)" -ForegroundColor White
}

$hasUpstream = $false
$upCheck = Invoke-GitRaw -GitArgs @("rev-parse", "--abbrev-ref", '@{u}')
if ($upCheck.ExitCode -eq 0) { $hasUpstream = $true }

Write-Host "`n[PUSH]: GitHub'a aktariliyor ($($ctxAfter.Remote)/$($ctxAfter.Branch))..." -ForegroundColor Yellow

if (-not $hasUpstream) {
    & git push -u $ctxAfter.Remote $ctxAfter.Branch
} else {
    & git push $ctxAfter.Remote $ctxAfter.Branch
}

if ($LASTEXITCODE -eq 0) {
    Clear-Manifest $ctxAfter
    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host "[BASARILI]: Pipeline tamamlandi! (prep -> add -> commit -> push)" -ForegroundColor Green
    Write-Host "   Branch         : $($ctxAfter.Branch)" -ForegroundColor White
    Write-Host "   Hedef          : $($ctxAfter.RemoteUrl)" -ForegroundColor White
    Write-Host "   Gonderilen     : $($includedItems.Count) dosya / $($finalCommits.Count) commit" -ForegroundColor White
    if ($excludedItems.Count -gt 0) {
        Write-Host "   Haric Tutulan  : $($excludedItems.Count) dosya yerelde guvenle korundu" -ForegroundColor Yellow
    }
    Write-Host "==========================================================" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n[HATA]: Git push islemi basarisiz oldu (Exit Code: $LASTEXITCODE)!" -ForegroundColor Red
    Write-Host "   Lutfen uzaktaki degisiklikleri cekmeyi ('git pull --rebase') veya erisim izinlerinizi kontrol edin." -ForegroundColor DarkGray
    exit 1
}
