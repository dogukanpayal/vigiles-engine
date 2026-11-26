param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

function Decode-JsonUnicode([string]$text) {
    if ([string]::IsNullOrEmpty($text)) { return $text }
    return [regex]::Replace($text, '\\u([0-9a-fA-F]{4})', {
        param($m)
        [char][Convert]::ToInt32($m.Groups[1].Value, 16)
    })
}

function Write-Allow($overwriteHash = $null) {
    if ($overwriteHash -and $overwriteHash.Count -gt 0) {
        $resp = @{
            decision  = "allow"
            overwrite = $overwriteHash
        }
        $json = Decode-JsonUnicode ($resp | ConvertTo-Json -Depth 6 -Compress)
        Write-Output $json
    } else {
        Write-Output '{"decision":"allow"}'
    }
    exit 0
}

function Write-Deny([string]$reasonText) {
    $resp = @{
        decision = "deny"
        reason   = $reasonText
    }
    $json = Decode-JsonUnicode ($resp | ConvertTo-Json -Depth 4 -Compress)
    Write-Output $json
    exit 0
}

function Test-IsThinkModeActive($payload) {
    $userInput = if ($payload.lastUserInput) { [string]$payload.lastUserInput } else { "" }
    if ($userInput -match '^\s*/(thinkdeep|think|mind|sor)(\s|$)') {
        return $true
    }
    if ($userInput -match '^\s*/([a-zA-Z0-9_-]+)(\s|$)') {
        $slashName = $matches[1].ToLowerInvariant()
        if ($slashName -ne "compact") {
            return $false
        }
    }

    $stateDir = Join-Path $HOME ".gemini\config\state\think_readonly"
    $key = ""
    if ($payload.conversationId) {
        $key = ($payload.conversationId -replace '[^a-zA-Z0-9\-_]', '_')
    } elseif ($payload.artifactDirectoryPath) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$payload.artifactDirectoryPath)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hash = $sha.ComputeHash($bytes)
            $key = ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant().Substring(0, 24)
        } finally {
            $sha.Dispose()
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($key)) {
        $modeFile = Join-Path $stateDir "$key.mode"
        if (Test-Path $modeFile) {
            try {
                $val = ([System.IO.File]::ReadAllText($modeFile, [System.Text.Encoding]::UTF8)).Trim()
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    return $true
                }
            } catch {}
        }
    }
    return $false
}

function Get-CmdArgs($cmdAst) {
    $list = [System.Collections.Generic.List[string]]::new()
    $elems = $cmdAst.CommandElements
    for ($i = 1; $i -lt $elems.Count; $i++) {
        $el = $elems[$i]
        $typeName = $el.GetType().Name
        if ($typeName -eq "StringConstantExpressionAst" -or $typeName -eq "ConstantExpressionAst") {
            $list.Add([string]$el.Value)
        } elseif ($typeName -eq "CommandParameterAst") {
            $list.Add([string]$el.Extent.Text)
        } elseif ($typeName -eq "ExpandableStringExpressionAst") {
            $list.Add([string]$el.Value)
        } else {
            $list.Add([string]$el.Extent.Text)
        }
    }
    return ,($list.ToArray())
}

function Get-GitSubcommandAndArgs([string[]]$gitArgs) {
    if (-not $gitArgs -or $gitArgs.Length -eq 0) {
        return @{ Subcmd = ""; Rest = @() }
    }
    $idx = 0
    while ($idx -lt $gitArgs.Length) {
        $a = $gitArgs[$idx]
        if (-not $a.StartsWith("-")) { break }
        if ($a -in @("-C", "-c", "--git-dir", "--work-tree", "--config-env", "--namespace")) {
            $idx += 2
            continue
        }
        $idx += 1
    }
    if ($idx -ge $gitArgs.Length) {
        return @{ Subcmd = ""; Rest = @() }
    }
    $sub = $gitArgs[$idx].ToLowerInvariant()
    [string[]]$rest = if ($idx + 1 -lt $gitArgs.Length) { @($gitArgs[($idx + 1)..($gitArgs.Length - 1)]) } else { @() }
    return @{ Subcmd = $sub; Rest = $rest }
}

function Test-CommandInPipeline($cmdAst, $astRoot) {
    try {
        $parent = $cmdAst.Parent
        if ($parent -and $parent.GetType().Name -eq "PipelineAst") {
            if ($parent.PipelineElements.Count -gt 1 -and $parent.PipelineElements[0] -ne $cmdAst) {
                return $true
            }
        }
    } catch {}
    return $false
}

function Get-TrapDenialReason($ast, [bool]$isDaemon) {
    if (-not $ast) { return $null }
    $cmdNodes = $ast.FindAll({ param($n) $n.GetType().Name -eq "CommandAst" }, $true)
    if (-not $cmdNodes -or $cmdNodes.Count -eq 0) { return $null }

    foreach ($cmdAst in $cmdNodes) {
        $rawName = $cmdAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($rawName)) { continue }
        $cmdName = ([System.IO.Path]::GetFileName($rawName)).ToLowerInvariant()
        $cmdArgs = Get-CmdArgs $cmdAst

        # 1. Dogrudan interaktif terminal / editor / pager komutlari
        if ($cmdName -in @("read-host", "pause", "choice", "choice.exe", "vim", "vi", "nano", "emacs", "notepad", "notepad.exe", "less", "man")) {
            return "[VIGILES WATCHDOG - INTERAKTIF ENGEL]: '$rawName' komutu kullanicidan girdi/onay bekleyerek terminali sonsuza kadar kilitler. Non-interactive alternatif kullanin."
        }

        if ($cmdName -in @("cmd", "cmd.exe")) {
            $joined = ($cmdArgs -join " ").ToLowerInvariant()
            if ($joined -match '(^|\s|&|/c\s+)pause(\s|$|&)') {
                return "[VIGILES WATCHDOG - INTERAKTIF ENGEL]: 'cmd pause' tus basimi bekleyerek terminali kilitler."
            }
        }

        # 2. Argumansiz REPL baslaticilar (pipe icinde degilse)
        if ($cmdName -in @("node", "node.exe", "python", "python.exe", "python3", "py", "irb", "psql", "mysql", "sqlite3")) {
            if ($cmdArgs.Length -eq 0 -and -not (Test-CommandInPipeline $cmdAst $ast)) {
                return "[VIGILES WATCHDOG - REPL ENGELI]: Argumansiz '$rawName' interaktif REPL acar ve sonsuza kadar bekler. Tek seferlik komut icin '-e' / '-c' veya script dosyasi verin."
            }
            if ($cmdName -match '^python|^py$' -and ($cmdArgs -contains "-i")) {
                return "[VIGILES WATCHDOG - REPL ENGELI]: 'python -i' interaktif oturum acar ve terminali kilitler."
            }
        }

        # 3. Git interaktif tuzaklari
        if ($cmdName -in @("git", "git.exe")) {
            $gInfo = Get-GitSubcommandAndArgs $cmdArgs
            $sub = $gInfo.Subcmd
            $rest = $gInfo.Rest
            if ($sub -eq "commit") {
                $hasHelp = ($rest -contains "-h") -or ($rest -contains "--help")
                $hasMsgOrNoEdit = $false
                foreach ($r in $rest) {
                    if ($r -eq "-m" -or $r -eq "--message" -or $r -like "--message=*" -or
                        $r -eq "-F" -or $r -eq "--file" -or $r -like "--file=*" -or
                        $r -eq "-C" -or $r -eq "--reuse-message" -or $r -like "--reuse-message=*" -or
                        $r -eq "--no-edit" -or $r -cmatch '^-[a-zA-Z]*m') {
                        $hasMsgOrNoEdit = $true
                        break
                    }
                }
                if (-not $hasHelp -and -not $hasMsgOrNoEdit) {
                    return "[VIGILES WATCHDOG - GIT EDITOR ENGELI]: '-m', '-F' veya '--no-edit' olmadan 'git commit' editor acarak terminali sonsuza kadar kilitler."
                }
            } elseif ($sub -in @("rebase", "merge", "add")) {
                foreach ($r in $rest) {
                    if ($r -in @("-i", "--interactive", "-p", "--patch")) {
                        return "[VIGILES WATCHDOG - GIT INTERAKTIF ENGELI]: 'git $sub $r' interaktif mod acar ve kullanici girisi bekleyerek kilitlenir."
                    }
                }
            }
        }

        # 4. Prefix cozumlemesi (npx, pnpm, yarn, npm exec/run)
        $effectiveTool = $cmdName
        [string[]]$effectiveArgs = $cmdArgs
        if ($cmdName -in @("npx", "npx.cmd", "bunx", "pnpx")) {
            $nonFlagIdx = 0
            while ($nonFlagIdx -lt $cmdArgs.Length -and $cmdArgs[$nonFlagIdx].StartsWith("-")) {
                if ($cmdArgs[$nonFlagIdx] -in @("-p", "--package", "-c", "--call")) { $nonFlagIdx += 2 } else { $nonFlagIdx += 1 }
            }
            if ($nonFlagIdx -lt $cmdArgs.Length) {
                $effectiveTool = ([System.IO.Path]::GetFileName($cmdArgs[$nonFlagIdx])).ToLowerInvariant()
                $effectiveArgs = if ($nonFlagIdx + 1 -lt $cmdArgs.Length) { @($cmdArgs[($nonFlagIdx + 1)..($cmdArgs.Length - 1)]) } else { @() }
            }
        } elseif ($cmdName -in @("npm", "npm.cmd", "pnpm", "pnpm.cmd", "yarn", "yarn.cmd")) {
            if ($cmdArgs.Length -ge 2 -and $cmdArgs[0].ToLowerInvariant() -in @("exec", "dlx", "x")) {
                $effectiveTool = ([System.IO.Path]::GetFileName($cmdArgs[1])).ToLowerInvariant()
                $effectiveArgs = if ($cmdArgs.Length -ge 3) { @($cmdArgs[2..($cmdArgs.Length - 1)]) } else { @() }
            }
        }

        # 5. Test runner watch modlari (IsDaemon fark etmeksizin tek seferlik kosmali)
        if ($effectiveTool -eq "vitest") {
            $hasSingleRun = $false
            $hasExplicitWatch = $false
            foreach ($a in $effectiveArgs) {
                $al = $a.ToLowerInvariant()
                if ($al -in @("run", "--run", "bench", "list", "-v", "--version", "-h", "--help", "--watch=false", "--no-watch")) {
                    $hasSingleRun = $true
                }
                if ($al -in @("--watch", "-w", "watch")) {
                    $hasExplicitWatch = $true
                }
            }
            if ($hasExplicitWatch -or -not $hasSingleRun) {
                return "[VIGILES WATCHDOG - WATCH MODU ENGELI]: 'vitest' varsayilan olarak watch modunda baslar ve sonsuza kadar bekler. Lutfen 'vitest run' veya 'vitest --run' kullanin."
            }
        }

        if ($effectiveTool -eq "jest") {
            $hasWatch = $false
            $watchDisabled = $false
            foreach ($a in $effectiveArgs) {
                $al = $a.ToLowerInvariant()
                if ($al -in @("--watch", "--watchall")) { $hasWatch = $true }
                if ($al -in @("--watch=false", "--watchall=false")) { $watchDisabled = $true }
            }
            if ($hasWatch -and -not $watchDisabled) {
                return "[VIGILES WATCHDOG - WATCH MODU ENGELI]: 'jest --watch' sonlanmaz. Tek seferlik kosum icin '--watchAll=false' kullanin."
            }
        }

        if ($effectiveTool -in @("ptw", "pytest-watch", "nodemon", "cargo-watch")) {
            if (-not $isDaemon) {
                return "[VIGILES WATCHDOG - WATCH MODU ENGELI]: '$effectiveTool' surekli izleme modunda calisir. Arka plan islemi gerekiyorsa IsDaemon: true kullanin."
            }
        }

        if ($effectiveTool -in @("pytest", "pytest.exe")) {
            foreach ($a in $effectiveArgs) {
                if ($a -in @("-f", "--looponfail")) {
                    return "[VIGILES WATCHDOG - WATCH MODU ENGELI]: 'pytest $a' sonlanmayan izleme dongusu acar."
                }
            }
        }

        # 6. npm/pnpm/yarn init (-y/--yes olmadan soru sorar) ve dev/watch sunuculari (IsDaemon:false)
        if ($cmdName -in @("npm", "npm.cmd", "pnpm", "pnpm.cmd", "yarn", "yarn.cmd")) {
            if ($cmdArgs.Length -ge 1) {
                $p1 = $cmdArgs[0].ToLowerInvariant()
                if ($p1 -eq "init" -and -not (($cmdArgs -contains "-y") -or ($cmdArgs -contains "--yes"))) {
                    return "[VIGILES WATCHDOG - INTERAKTIF ENGEL]: '$cmdName init' -y/--yes olmadan kullanici sorulariyla terminali kilitler."
                }
                if ($p1 -eq "test" -and (($cmdArgs -contains "--watch") -or ($cmdArgs -contains "--watchAll")) -and -not ($cmdArgs -contains "--watchAll=false")) {
                    return "[VIGILES WATCHDOG - WATCH MODU ENGELI]: '$cmdName test --watch' sonlanmaz. '--watchAll=false' veya tek seferlik bayrak kullanin."
                }
                if (-not $isDaemon) {
                    $devScript = ""
                    if ($p1 -eq "run" -and $cmdArgs.Length -ge 2) {
                        $devScript = $cmdArgs[1].ToLowerInvariant()
                    } elseif ($p1 -in @("dev", "start", "serve", "watch")) {
                        $devScript = $p1
                    }
                    if ($devScript -in @("dev", "start", "serve", "watch")) {
                        return "[VIGILES WATCHDOG - SUNUCU ENGELI]: '$cmdName $devScript' sonlanmayan dev/watch sunucusudur. IsDaemon: true ile baslatin veya tek seferlik build/test komutu calistirin."
                    }
                }
            }
        }

        # 7. Diger IsDaemon:false dev sunuculari ve watch bayraklari
        if (-not $isDaemon) {
            if ($effectiveTool -eq "next" -and $effectiveArgs.Length -ge 1 -and $effectiveArgs[0].ToLowerInvariant() -in @("dev", "start")) {
                return "[VIGILES WATCHDOG - SUNUCU ENGELI]: 'next $($effectiveArgs[0])' sonlanmayan sunucudur. IsDaemon: true kullanin."
            }
            if ($effectiveTool -eq "vite") {
                $firstVite = if ($effectiveArgs.Length -ge 1) { $effectiveArgs[0].ToLowerInvariant() } else { "dev" }
                if ($firstVite -in @("dev", "serve", "preview") -or -not ($firstVite -in @("build", "optimize", "-v", "--version", "-h", "--help"))) {
                    return "[VIGILES WATCHDOG - SUNUCU ENGELI]: 'vite' dev sunucusu olarak baslar. IsDaemon: true kullanin veya 'vite build' calistirin."
                }
            }
            if ($effectiveTool -in @("tsc", "webpack", "esbuild", "rollup") -and (($effectiveArgs -contains "-w") -or ($effectiveArgs -contains "--watch"))) {
                return "[VIGILES WATCHDOG - WATCH MODU ENGELI]: '$effectiveTool --watch' sonlanmaz. Tek seferlik derleme yapin veya IsDaemon: true kullanin."
            }
            if ($effectiveTool -in @("python", "python.exe", "python3", "py")) {
                $pJoined = ($effectiveArgs -join " ").ToLowerInvariant()
                if ($pJoined -match '-m\s+http\.server') {
                    return "[VIGILES WATCHDOG - SUNUCU ENGELI]: 'python -m http.server' sonlanmayan HTTP sunucusudur. IsDaemon: true kullanin."
                }
            }
            if ($effectiveTool -in @("uvicorn", "gunicorn") -or ($effectiveTool -eq "flask" -and $effectiveArgs -contains "run")) {
                return "[VIGILES WATCHDOG - SUNUCU ENGELI]: '$effectiveTool' sonlanmayan web sunucusudur. IsDaemon: true kullanin."
            }
        }
    }
    return $null
}

function Test-IsFastReadOnlyCommand($ast) {
    if (-not $ast) { return $false }
    $mutatingAst = $ast.FindAll({
        param($n)
        $n.GetType().Name -in @("FileRedirectionAst", "AssignmentStatementAst", "InvokeMemberExpressionAst", "WhileStatementAst", "ForStatementAst", "DoWhileStatementAst", "DoUntilStatementAst")
    }, $true)
    if ($mutatingAst -and $mutatingAst.Count -gt 0) { return $false }

    $cmdNodes = $ast.FindAll({ param($n) $n.GetType().Name -eq "CommandAst" }, $true)
    if (-not $cmdNodes -or $cmdNodes.Count -eq 0) { return $false }

    $fastReadCmds = @(
        "get-childitem", "gci", "dir", "ls",
        "get-item", "gi", "get-itemproperty", "gp",
        "get-content", "gc", "cat", "type", "head", "tail",
        "test-path", "resolve-path", "rvpa", "split-path", "join-path",
        "get-location", "gl", "pwd",
        "select-string", "sls", "findstr", "findstr.exe",
        "rg", "rg.exe", "ripgrep", "grep", "grep.exe", "egrep", "fgrep", "ag", "ack", "fd", "fd.exe",
        "get-filehash", "compare-object", "diff", "fc", "fc.exe", "comp",
        "select-object", "select", "where-object", "where", "?",
        "sort-object", "group-object", "group", "measure-object", "measure",
        "format-table", "ft", "format-list", "fl", "format-wide", "fw",
        "out-string", "out-null", "convertto-json", "convertfrom-json",
        "write-output", "echo", "write-host",
        "get-date", "get-command", "gcm", "where.exe", "which",
        "get-help", "help", "get-member", "gm", "tree", "tree.com", "wc", "jq", "jq.exe"
    )
    $safeGitSubs = @(
        "status", "log", "show", "diff", "grep", "rev-parse", "ls-files",
        "ls-tree", "cat-file", "describe", "shortlog", "blame", "check-ignore",
        "branch", "tag", "remote", "version", "help"
    )

    foreach ($cmdAst in $cmdNodes) {
        $rawName = $cmdAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($rawName)) { return $false }
        $cmdName = ([System.IO.Path]::GetFileName($rawName)).ToLowerInvariant()

        if ($cmdName -in $fastReadCmds) { continue }
        if ($cmdName -in @("git", "git.exe")) {
            $gInfo = Get-GitSubcommandAndArgs (Get-CmdArgs $cmdAst)
            if ($gInfo.Subcmd -in $safeGitSubs) { continue }
            return $false
        }
        return $false
    }
    return $true
}

function Test-IsDirectPushOrDiffInvocation($ast, [string]$commandLine) {
    $testRunnerPattern = '^(?i)(Test-|Chaos-|Scenario-|Run-MasterVerification).*\.ps1$'
    $pushOrDiffPattern = '^(?i)(git_push_manager|chat_diff_viewer)\.ps1$'

    if ($ast) {
        $cmdNodes = $ast.FindAll({ param($n) $n.GetType().Name -eq "CommandAst" }, $true)
        $hasPushOrDiff = $false
        foreach ($cn in $cmdNodes) {
            $rawName = $cn.GetCommandName()
            if ([string]::IsNullOrWhiteSpace($rawName)) { continue }
            $leaf = [System.IO.Path]::GetFileName($rawName.Trim('"', "'")).ToLowerInvariant()
            if ($leaf -match $testRunnerPattern) { return $false }
            if ($leaf -match $pushOrDiffPattern) { $hasPushOrDiff = $true; continue }

            if ($leaf -in @("powershell", "powershell.exe", "pwsh", "pwsh.exe")) {
                $cArgs = Get-CmdArgs $cn
                for ($i = 0; $i -lt $cArgs.Length; $i++) {
                    if ($cArgs[$i] -match '^(?i)-File$' -and ($i + 1) -lt $cArgs.Length) {
                        $scriptLeaf = [System.IO.Path]::GetFileName($cArgs[$i + 1].Trim('"', "'"))
                        if ($scriptLeaf -match $testRunnerPattern) { return $false }
                        if ($scriptLeaf -match $pushOrDiffPattern) { $hasPushOrDiff = $true }
                        break
                    }
                    if ($cArgs[$i] -match '^(?i)(-Command|-c)$' -and ($i + 1) -lt $cArgs.Length) {
                        if ($cArgs[$i + 1] -match '(?i)(?:^|[;&|\s\\/"''])(?:Test-|Chaos-|Scenario-|Run-MasterVerification)[^\s;&|"'' ]*\.ps1') {
                            return $false
                        }
                    }
                }
            }
        }
        if ($hasPushOrDiff) { return $true }
        return ($commandLine -match '\b(git_push_manager|chat_diff_viewer)\.ps1\b')
    }

    $isOuterTest = ($commandLine -match '^\s*(?:powershell(?:\.exe)?\s+(?:[^;&|\r\n]*?-File\s+["'']?)?)?(?:[^;&|\r\n]*[\\/])?(?:Test-|Chaos-|Scenario-|Run-MasterVerification)[^;&|\r\n]*\.ps1(?:\s|$|["''])')
    $isDirectScript = ($commandLine -match '\b(git_push_manager|chat_diff_viewer)\.ps1\b')
    return ($isDirectScript -and -not $isOuterTest)
}

function Test-IsMasterSuiteWorkload([string]$commandLine) {
    return ($commandLine -match '(?i)Run-MasterVerification')
}

function Test-IsHeavyWorkload([string]$commandLine) {
    return ($commandLine -match '(?i)(npm\s+(install|ci|audit|test|run\s+build)|pnpm\s+(install|build|test)|yarn\s+(install|build|test)|pip\s+install|cargo\s+(build|test)|pytest|vitest|playwright|jest|tsc\b|next\s+build|vite\s+build|Run-MasterVerification|Test-|Chaos-)')
}

# --- ANA AKIS ---
if ($env:VIGILES_WATCHDOG_DISABLED -eq "1") {
    Write-Allow
}

$rawInput = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($rawInput)) {
    Write-Allow
}
$rawInput = $rawInput.Trim().Trim([char]65279)

try {
    $payload = $rawInput | ConvertFrom-Json
} catch {
    Write-Allow
}

$toolCall = $payload.toolCall
if (-not $toolCall -or ([string]$toolCall.name).ToLowerInvariant() -ne "run_command") {
    Write-Allow
}

$toolArgs = $toolCall.args
if (-not $toolArgs) {
    Write-Allow
}

$cmdLine = if ($toolArgs.CommandLine) { [string]$toolArgs.CommandLine } else { "" }
if ([string]::IsNullOrWhiteSpace($cmdLine)) {
    Write-Allow
}

$isDaemon = ($toolArgs.IsDaemon -eq $true)

# Cift sarmalamayi engelle (idempotent - yalnizca gercek wrapper cagrisini yakala)
if ($cmdLine -match 'invoke_with_timeout\.ps1[''"]?\s+-PayloadFile\b') {
    Write-Allow
}

$tokens = $null
$parseErrors = $null
$ast = $null
try {
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($cmdLine, [ref]$tokens, [ref]$parseErrors)
} catch {}

# Katman 1: Tuzak Engelleme (AST temiz ayrışabildiyse bilinen tuzaklar icin ilk kontrol)
if ($ast -and (-not $parseErrors -or $parseErrors.Count -eq 0)) {
    $denialReason = Get-TrapDenialReason -ast $ast -isDaemon $isDaemon
    if (-not [string]::IsNullOrWhiteSpace($denialReason)) {
        Write-Deny $denialReason
    }
}

# IsDaemon: true -> meşru uzun sureli arka plan sunucusu, sarmalama ve notification ekleme yapma
if ($isDaemon) {
    Write-Allow
}

$overwrite = @{}
$isThinkMode = Test-IsThinkModeActive $payload
$isFastRead = ($ast -and (-not $parseErrors -or $parseErrors.Count -eq 0) -and (Test-IsFastReadOnlyCommand $ast))
$isMasterSuite = (-not $isFastRead) -and (Test-IsMasterSuiteWorkload $cmdLine)
$isHeavy = (-not $isFastRead) -and (Test-IsHeavyWorkload $cmdLine)

# Katman 2: Eksik / Gecersiz NotificationTimeoutSeconds enjeksiyonu
$existingNotify = $null
if ($null -ne $toolArgs.NotificationTimeoutSeconds) {
    try { $existingNotify = [int]$toolArgs.NotificationTimeoutSeconds } catch {}
}

$recommendedNotify = if ($isThinkMode -or $isFastRead) { 15 } elseif ($isMasterSuite) { 120 } elseif ($isHeavy) { 90 } else { 45 }
if ($null -eq $existingNotify -or $existingNotify -le 0 -or $existingNotify -gt 600) {
    $overwrite["NotificationTimeoutSeconds"] = $recommendedNotify
}

# /think, /thinkdeep ve hizli salt-okunur komutlarda CommandLine sarmalanmaz (0ms gecikme & AST uyumu)
if ($isThinkMode -or $isFastRead) {
    Write-Allow $overwrite
}

# Katman 3: Akilli Nabiz Olcerli OS Surec Agaci Giyotini Sarmalamasi
$wrapperScript = Join-Path $PSScriptRoot "invoke_with_timeout.ps1"
if (-not (Test-Path $wrapperScript)) {
    $wrapperScript = Join-Path $HOME ".gemini\config\scripts\invoke_with_timeout.ps1"
}

if (Test-Path $wrapperScript) {
    $payloadDir = Join-Path ([System.IO.Path]::GetTempPath()) "vigiles_watchdog"
    if (-not (Test-Path $payloadDir)) {
        try { New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null } catch {}
    }

    $idleSec = if ($isMasterSuite) { 90 } elseif ($isHeavy) { 60 } else { 45 }
    $hardSec = if ($isMasterSuite) { 900 } elseif ($isHeavy) { 240 } else { 180 }

    $cid = if ($payload.conversationId) { [string]$payload.conversationId } else { "" }
    $artDir = if ($payload.artifactDirectoryPath) { [string]$payload.artifactDirectoryPath } else { "" }
    $cwd = if ($payload.cwd) { [string]$payload.cwd } elseif ($payload.workspacePaths -and $payload.workspacePaths.Count -gt 0) { [string]$payload.workspacePaths[0] } else { "" }
    $isDirectPushOrDiff = Test-IsDirectPushOrDiffInvocation -ast $ast -commandLine $cmdLine

    $payloadFile = Join-Path $payloadDir ("cmd_" + [System.Guid]::NewGuid().ToString("N") + ".json")
    $wrapObj = @{
        command               = $cmdLine
        cwd                   = $cwd
        conversationId        = $cid
        artifactDir           = $artDir
        injectConversationEnv = [bool]$isDirectPushOrDiff
        idleTimeoutSec        = $idleSec
        hardTimeoutSec        = $hardSec
        pollIntervalMs        = 1000
    }
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($payloadFile, ($wrapObj | ConvertTo-Json -Depth 4 -Compress), $utf8NoBom)
        $overwrite["CommandLine"] = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$wrapperScript`" -PayloadFile `"$payloadFile`""
    } catch {}
}

Write-Allow $overwrite
