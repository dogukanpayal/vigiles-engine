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

function Write-HookAllow([string]$hookEventName) {
    if ($hookEventName -eq "PreInvocation") {
        Write-Output "{}"
    } else {
        Write-Output '{"decision":"allow"}'
    }
    exit 0
}

function Write-HookDeny([string]$reasonText) {
    $obj = @{
        decision = "deny"
        reason   = (Decode-JsonUnicode $reasonText)
    }
    Write-Output ($obj | ConvertTo-Json -Compress)
    exit 0
}

function Get-StateFilePath($payload) {
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
    if ([string]::IsNullOrWhiteSpace($key)) {
        return $null
    }
    return (Join-Path $stateDir "$key.mode")
}

function Get-CommandArgStrings($cmdAst) {
    $list = [System.Collections.Generic.List[string]]::new()
    $elems = $cmdAst.CommandElements
    for ($i = 1; $i -lt $elems.Count; $i++) {
        $el = $elems[$i]
        $typeName = $el.GetType().Name
        if ($typeName -eq "StringConstantExpressionAst") {
            $list.Add([string]$el.Value)
        } elseif ($typeName -eq "ConstantExpressionAst") {
            $list.Add([string]$el.Value)
        } elseif ($typeName -eq "CommandParameterAst") {
            $list.Add([string]$el.Extent.Text)
        } elseif ($typeName -eq "ExpandableStringExpressionAst") {
            if ($el.NestedExpressions -and $el.NestedExpressions.Count -gt 0) {
                return $null
            }
            $list.Add([string]$el.Value)
        } else {
            return $null
        }
    }
    return ,($list.ToArray())
}

function Test-GitReadOnly([string[]]$gitArgs) {
    if ($null -eq $gitArgs) {
        return $false
    }

    $idx = 0
    $sawHelpOrVersion = $false
    while ($idx -lt $gitArgs.Length) {
        $arg = $gitArgs[$idx]
        if (-not $arg.StartsWith("-")) {
            break
        }
        if ($arg -ceq "-C" -or $arg -eq "--git-dir" -or $arg -eq "--work-tree") {
            $idx += 2
            continue
        }
        if ($arg -clike "-C*" -or $arg -like "--git-dir=*" -or $arg -like "--work-tree=*") {
            $idx += 1
            continue
        }
        if ($arg -ceq "-c" -or $arg -clike "-c*" -or
            $arg -eq "--config-env" -or $arg -like "--config-env=*" -or
            $arg -eq "--exec-path" -or $arg -like "--exec-path=*" -or
            $arg -eq "--upload-pack" -or $arg -like "--upload-pack=*") {
            return $false
        }
        if ($arg -in @("--no-pager", "--paginate", "--bare", "--no-replace-objects",
                       "--literal-pathspecs", "--glob-pathspecs", "--noglob-pathspecs",
                       "--icase-pathspecs", "--no-optional-locks") -or ($arg -ceq "-p")) {
            $idx += 1
            continue
        }
        if ($arg -in @("--version", "--help", "-h") -or ($arg -ceq "-v")) {
            $sawHelpOrVersion = $true
            $idx += 1
            continue
        }
        return $false
    }

    if ($idx -ge $gitArgs.Length) {
        return $sawHelpOrVersion
    }

    $subcmd = $gitArgs[$idx].ToLowerInvariant()
    [string[]]$rest = if ($idx + 1 -lt $gitArgs.Length) { @($gitArgs[($idx + 1)..($gitArgs.Length - 1)]) } else { @() }

    foreach ($r in $rest) {
        if ($r -eq "--output" -or $r -like "--output=*" -or ($r -ceq "-o") -or $r -eq "--ext-diff") {
            return $false
        }
    }

    $alwaysSafeGitSubcmds = @(
        "status", "log", "show", "diff", "grep", "rev-parse", "ls-files",
        "ls-tree", "cat-file", "describe", "shortlog", "blame", "check-ignore",
        "count-objects", "name-rev", "show-ref", "for-each-ref", "merge-base",
        "diff-tree", "whatchanged", "version", "help"
    )
    if ($subcmd -in $alwaysSafeGitSubcmds) {
        return $true
    }

    if ($subcmd -eq "branch") {
        $valueFlags = @("--contains", "--no-contains", "--merged", "--no-merged", "--points-at", "--sort", "--format", "--abbrev")
        $allowedBranchFlags = @("-a", "--all", "-r", "--remotes", "-v", "-vv", "--verbose", "-l", "--list", "--show-current", "--color", "--no-color")
        $j = 0
        while ($j -lt $rest.Length) {
            $a = $rest[$j]
            if ($a -in $valueFlags) {
                $j += 2
                continue
            }
            if ($a -like "--contains=*" -or $a -like "--no-contains=*" -or
                $a -like "--merged=*" -or $a -like "--no-merged=*" -or
                $a -like "--points-at=*" -or $a -like "--sort=*" -or
                $a -like "--format=*" -or $a -like "--abbrev=*" -or
                $a -like "--color=*") {
                $j += 1
                continue
            }
            if ($a -ceq "-a" -or $a -ceq "-r" -or $a -ceq "-v" -or $a -ceq "-vv" -or $a -ceq "-l" -or ($a -in $allowedBranchFlags)) {
                $j += 1
                continue
            }
            return $false
        }
        return $true
    }

    if ($subcmd -eq "tag") {
        if ($rest.Length -eq 0) { return $true }
        $hasListOrQuery = $false
        foreach ($a in $rest) {
            if ($a -ceq "-a" -or $a -ceq "-s" -or $a -ceq "-u" -or $a -ceq "-d" -or
                $a -ceq "-f" -or $a -ceq "-m" -or $a -ceq "-F" -or
                $a -in @("--annotate", "--sign", "--local-user", "--delete", "--force", "--file")) {
                return $false
            }
            if (($a -ceq "-l") -or ($a -ceq "-v") -or ($a -in @("--list", "--verify", "--contains", "--no-contains", "--merged", "--no-merged"))) {
                $hasListOrQuery = $true
            }
        }
        return $hasListOrQuery
    }

    if ($subcmd -eq "remote") {
        if ($rest.Length -eq 0) { return $true }
        $first = $rest[0]
        if (($first -ceq "-v") -or ($first -in @("--verbose", "show", "get-url"))) {
            return $true
        }
        return $false
    }

    if ($subcmd -eq "config") {
        $hasReadFlag = $false
        foreach ($a in $rest) {
            if ($a -ceq "-e" -or $a -in @("--add", "--replace-all", "--unset", "--unset-all", "--remove-section", "--rename-section", "--edit")) {
                return $false
            }
            if (($a -ceq "-l") -or ($a -in @("--list", "--get", "--get-all", "--get-regexp"))) {
                $hasReadFlag = $true
            }
        }
        return $hasReadFlag
    }

    if ($subcmd -eq "reflog") {
        if ($rest.Length -eq 0) { return $true }
        return ($rest[0] -in @("show", "exists"))
    }

    return $false
}

function Test-ReadOnlyCommand([string]$commandLine) {
    if ([string]::IsNullOrWhiteSpace($commandLine)) {
        return @{ allowed = $false; reason = 'Bos terminal komutu salt-okunur modda engellendi.' }
    }

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($commandLine, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        return @{ allowed = $false; reason = 'Komut sozdizimi dogrulanamadigi icin guvenlik amaciyla engellendi.' }
    }

    $blockedAstTypes = @(
        "FileRedirectionAst",
        "AssignmentStatementAst",
        "InvokeMemberExpressionAst",
        "FunctionDefinitionAst",
        "TypeDefinitionAst",
        "ConfigurationDefinitionAst",
        "TrapStatementAst",
        "UsingStatementAst"
    )

    $allNodes = $ast.FindAll({ $true }, $true)
    foreach ($node in $allNodes) {
        $nodeType = $node.GetType().Name
        if ($nodeType -in $blockedAstTypes) {
            return @{ allowed = $false; reason = "Salt-okunur /think & /thinkdeep modunda dosya yonlendirme, atama veya metot cagrisi ($nodeType) engellendi." }
        }
    }

    $safeReadOnlyCommands = @(
        "get-childitem", "gci", "dir", "ls",
        "get-item", "gi", "get-itemproperty", "gp",
        "get-content", "gc", "cat", "type", "head", "tail", "more",
        "test-path", "resolve-path", "rvpa", "split-path", "join-path",
        "get-location", "gl", "pwd",
        "select-string", "sls",
        "get-filehash", "compare-object", "diff", "fc", "fc.exe", "comp",
        "select-object", "select",
        "sort-object",
        "group-object", "group",
        "measure-object", "measure",
        "format-table", "ft",
        "format-list", "fl",
        "format-wide", "fw",
        "out-string", "out-null",
        "convertto-json", "convertfrom-json",
        "convertfrom-csv", "convertfrom-stringdata",
        "write-output", "echo", "write-host",
        "get-date", "get-command", "gcm", "where.exe", "which",
        "get-help", "help", "get-member", "gm",
        "tree", "tree.com",
        "findstr", "findstr.exe",
        "grep", "grep.exe", "egrep", "fgrep",
        "ag", "ack",
        "jq", "jq.exe",
        "wc", "cut", "tr", "uniq"
    )

    $cmdNodes = $ast.FindAll({ param($n) $n.GetType().Name -eq "CommandAst" }, $true)
    if (-not $cmdNodes -or $cmdNodes.Count -eq 0) {
        return @{ allowed = $false; reason = 'Salt-okunur modda yalnizca bilinen okuma komutlari calistirilabilir.' }
    }

    foreach ($cmdAst in $cmdNodes) {
        if ($cmdAst.InvocationOperator -in @(
            [System.Management.Automation.Language.TokenKind]::Ampersand,
            [System.Management.Automation.Language.TokenKind]::Dot
        )) {
            return @{ allowed = $false; reason = 'Salt-okunur modda dinamik cagri (& veya .) engellendi.' }
        }

        $rawCmdName = $cmdAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($rawCmdName)) {
            return @{ allowed = $false; reason = 'Dinamik komut adi salt-okunur modda engellendi.' }
        }
        $cmdName = $rawCmdName.ToLowerInvariant()
        if ($cmdName -match '[\\/]') {
            return @{ allowed = $false; reason = "Tam dosya yolu ile calistirma ($rawCmdName) salt-okunur modda engellendi." }
        }

        if ($cmdName -in $safeReadOnlyCommands) {
            continue
        }

        if ($cmdName -in @("where-object", "where", "?")) {
            $hasScriptBlock = $false
            $elems = $cmdAst.CommandElements
            for ($i = 1; $i -lt $elems.Count; $i++) {
                $elType = $elems[$i].GetType().Name
                if ($elType -eq "ScriptBlockExpressionAst") {
                    $hasScriptBlock = $true
                } elseif ($elType -eq "CommandParameterAst" -and $elems[$i].ParameterName -eq "MemberName") {
                    return @{ allowed = $false; reason = 'Where-Object -MemberName salt-okunur modda engellendi.' }
                }
            }
            if (-not $hasScriptBlock) {
                return @{ allowed = $false; reason = 'Where-Object yalnizca { ... } script block filtresi ile kullanilabilir.' }
            }
            continue
        }

        $cmdArgs = Get-CommandArgStrings $cmdAst

        if ($cmdName -in @("sort", "sort.exe")) {
            if ($null -eq $cmdArgs) {
                return @{ allowed = $false; reason = 'sort komutunda dinamik arguman salt-okunur modda engellendi.' }
            }
            foreach ($a in $cmdArgs) {
                if ($a -eq "-o" -or $a -eq "/o" -or $a -eq "--output" -or $a -like "--output=*" -or $a -like "/o:*") {
                    return @{ allowed = $false; reason = 'sort cikti dosyasi parametresi engellendi.' }
                }
            }
            continue
        }

        if ($cmdName -in @("rg", "rg.exe", "ripgrep")) {
            if ($null -eq $cmdArgs) {
                return @{ allowed = $false; reason = 'rg komutunda dinamik arguman salt-okunur modda engellendi.' }
            }
            foreach ($a in $cmdArgs) {
                if ($a -eq "--pre" -or $a -like "--pre=*") {
                    return @{ allowed = $false; reason = 'rg --pre calistiricisi salt-okunur modda engellendi.' }
                }
            }
            continue
        }

        if ($cmdName -in @("fd", "fd.exe", "fdfind")) {
            if ($null -eq $cmdArgs) {
                return @{ allowed = $false; reason = 'fd komutunda dinamik arguman salt-okunur modda engellendi.' }
            }
            foreach ($a in $cmdArgs) {
                if (($a -ceq "-x") -or ($a -ceq "-X") -or $a -in @("--exec", "--exec-batch") -or $a -like "--exec=*" -or $a -like "--exec-batch=*") {
                    return @{ allowed = $false; reason = 'fd --exec komutu salt-okunur modda engellendi.' }
                }
            }
            continue
        }

        if ($cmdName -in @("find", "find.exe")) {
            if ($null -eq $cmdArgs) {
                return @{ allowed = $false; reason = 'find komutunda dinamik arguman salt-okunur modda engellendi.' }
            }
            foreach ($a in $cmdArgs) {
                if ($a -in @("-exec", "-execdir", "-ok", "-okdir", "-delete", "-fls", "-fprint", "-fprint0", "-fprintf")) {
                    return @{ allowed = $false; reason = "find mutasyon parametresi ($a) salt-okunur modda engellendi." }
                }
            }
            continue
        }

        if ($cmdName -in @("git", "git.exe")) {
            if (-not (Test-GitReadOnly $cmdArgs)) {
                return @{ allowed = $false; reason = 'Yalnizca salt-okunur git komutlari (status, log, show, diff, grep, branch -a vb.) izinlidir.' }
            }
            continue
        }

        if ($cmdName -in @("npm", "npm.cmd", "pnpm", "yarn")) {
            if ($null -eq $cmdArgs -or $cmdArgs.Length -eq 0) {
                return @{ allowed = $false; reason = "$rawCmdName alt komutu belirtilmelidir." }
            }
            $firstArg = $cmdArgs[0].ToLowerInvariant()
            $allowedPkgSubcmds = @("-v", "--version", "list", "ls", "view", "info", "show", "outdated", "explain", "why", "search", "audit")
            if (-not ($firstArg -in $allowedPkgSubcmds)) {
                return @{ allowed = $false; reason = "Paket yoneticisinde yalnizca salt-okunur sorgular (list/view/outdated/audit) izinlidir." }
            }
            if ($firstArg -eq "audit") {
                foreach ($a in $cmdArgs) {
                    if ($a -in @("fix", "--fix", "--force")) {
                        return @{ allowed = $false; reason = 'audit fix salt-okunur modda engellendi.' }
                    }
                }
            }
            continue
        }

        if ($cmdName -in @("pip", "pip.exe")) {
            if ($null -eq $cmdArgs -or $cmdArgs.Length -eq 0) {
                return @{ allowed = $false; reason = 'pip alt komutu belirtilmelidir.' }
            }
            $firstArg = $cmdArgs[0]
            if (-not (($firstArg -ceq "-V") -or ($firstArg.ToLowerInvariant() -in @("--version", "list", "show", "freeze", "check")))) {
                return @{ allowed = $false; reason = 'pip icinde yalnizca list/show/freeze/check/version izinlidir.' }
            }
            continue
        }

        if ($cmdName -in @("node", "node.exe", "python", "python.exe", "python3", "py", "cargo", "go", "dotnet", "rustc", "tsc")) {
            if ($null -ne $cmdArgs -and $cmdArgs.Length -eq 1 -and $cmdArgs[0] -in @("-v", "-V", "--version", "version")) {
                continue
            }
            return @{ allowed = $false; reason = "Salt-okunur modda $rawCmdName ile betik veya derleme calistirilamaz (yalnizca versiyon sorgusu izinlidir)." }
        }

        if ($cmdName -in @("gh", "gh.exe")) {
            if ($null -eq $cmdArgs -or $cmdArgs.Length -eq 0) {
                return @{ allowed = $false; reason = 'gh alt komutu belirtilmelidir.' }
            }
            $c1 = $cmdArgs[0].ToLowerInvariant()
            $c2 = if ($cmdArgs.Length -ge 2) { $cmdArgs[1].ToLowerInvariant() } else { "" }
            $okGh = (
                ($c1 -in @("--version", "status")) -or
                ($c1 -eq "auth" -and $c2 -eq "status") -or
                ($c1 -in @("repo", "pr", "issue", "run", "workflow", "release") -and $c2 -in @("list", "view", "status", "diff", "checks"))
            )
            if (-not $okGh) {
                return @{ allowed = $false; reason = 'gh CLI icinde yalnizca salt-okunur goruntuleme komutlari (list/view/status/diff) izinlidir.' }
            }
            continue
        }

        return @{ allowed = $false; reason = "Salt-okunur /think & /thinkdeep modunda bu komut ($rawCmdName) izin verilen arastirma listesinde degildir." }
    }

    return @{ allowed = $true; reason = "" }
}

$rawInput = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($rawInput)) {
    Write-Output '{"decision":"allow"}'
    exit 0
}

$rawInput = $rawInput.Trim().Trim([char]65279)

try {
    $payload = $rawInput | ConvertFrom-Json
} catch {
    Write-Output '{"decision":"allow"}'
    exit 0
}

$hookEventName = if ($payload.hookEventName) { [string]$payload.hookEventName } else { "" }

if ($hookEventName -eq "PreInvocation" -and $payload.invocationNum -and [int]$payload.invocationNum -gt 1) {
    Write-HookAllow $hookEventName
}

$userInput = if ($payload.lastUserInput) { [string]$payload.lastUserInput } else { "" }
$stateFile = Get-StateFilePath $payload
$activeMode = $null

if ($userInput -match '^\s*/(thinkdeep|think|mind|sor)(\s|$)') {
    $activeMode = $matches[1].ToLowerInvariant()
    if ($stateFile) {
        $stateDir = Split-Path $stateFile -Parent
        if (-not (Test-Path $stateDir)) {
            try { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null } catch {}
        }
        $existing = ""
        if (Test-Path $stateFile) {
            try { $existing = (Get-Content -Raw -Encoding UTF8 $stateFile).Trim() } catch {}
        }
        if ($existing -ne $activeMode) {
            try { [System.IO.File]::WriteAllText($stateFile, $activeMode, [System.Text.Encoding]::UTF8) } catch {}
        }
    }
} elseif ($userInput -match '^\s*/compact(\s|$)') {
    if ($stateFile -and (Test-Path $stateFile)) {
        try { $activeMode = (Get-Content -Raw -Encoding UTF8 $stateFile).Trim() } catch {}
    }
} elseif ($userInput -match '^\s*/([a-zA-Z0-9_-]+)(\s|$)') {
    if ($stateFile -and (Test-Path $stateFile)) {
        try { Remove-Item $stateFile -Force -ErrorAction SilentlyContinue } catch {}
    }
    $activeMode = $null
} else {
    if ($stateFile -and (Test-Path $stateFile)) {
        try { $activeMode = (Get-Content -Raw -Encoding UTF8 $stateFile).Trim() } catch {}
    }
}

if ($hookEventName -ne "PreToolUse") {
    Write-HookAllow $hookEventName
}

if ([string]::IsNullOrWhiteSpace($activeMode)) {
    Write-HookAllow $hookEventName
}

$toolCall = $payload.toolCall
if (-not $toolCall) {
    Write-HookAllow $hookEventName
}

$toolName = if ($toolCall.name) { ([string]$toolCall.name).ToLowerInvariant() } else { "" }
$toolArgs = $toolCall.args

$writeTools = @(
    "write_file",
    "edit_file",
    "write_to_file",
    "replace_file_content",
    "multi_replace_file_content",
    "delete_file",
    "apply_patch",
    "notebook_edit"
)

if ($toolName -in $writeTools) {
    Write-HookDeny '[SALT-OKUNUR KORUMA - /think & /thinkdeep]: Bu moddayken hi\u00e7bir dosya yazma, olu\u015fturma veya kod de\u011fi\u015ftirme i\u015flemi yap\u0131lamaz. T\u00fcm \u00e7\u0131kt\u0131lar\u0131 do\u011frudan sohbet i\u00e7inde sunun. Kod de\u011fi\u015fikli\u011fine ge\u00e7mek i\u00e7in /lite veya /pro komutunu kullan\u0131n.'
}

if ($toolName -eq "define_subagent") {
    Write-HookDeny '[SALT-OKUNUR KORUMA - /think & /thinkdeep]: Yeni alt ajan tan\u0131mlama (define_subagent) bu modda engellenmi\u015ftir. Ara\u015ft\u0131rma i\u00e7in yaln\u0131zca salt-okunur "research" veya "browser" alt ajan\u0131n\u0131 kullan\u0131n.'
}

if ($toolName -eq "run_workflow") {
    Write-HookDeny '[SALT-OKUNUR KORUMA - /think & /thinkdeep]: Python workflow (run_workflow) dosya yazma riski nedeniyle bu modda engellenmi\u015ftir.'
}

if ($toolName -eq "swarm") {
    Write-HookDeny '[SALT-OKUNUR KORUMA - /think & /thinkdeep]: Swarm ajanlar\u0131 kod yazabildi\u011fi i\u00e7in bu modda engellenmi\u015ftir. Ara\u015ft\u0131rma i\u00e7in "research" alt ajan\u0131n\u0131 kullan\u0131n.'
}

if ($toolName -eq "invoke_subagent") {
    $subType = if ($toolArgs -and $toolArgs.TypeName) { ([string]$toolArgs.TypeName).ToLowerInvariant() } else { "" }
    if ($subType -in @("research", "browser")) {
        Write-HookAllow $hookEventName
    }
    Write-HookDeny "[SALT-OKUNUR KORUMA - /think & /thinkdeep]: '$subType' t\u00fcr\u00fcndeki alt ajanlar yazma yetkisine sahip olabilece\u011fi i\u00e7in engellendi. Yaln\u0131zca salt-okunur 'research' veya 'browser' alt ajan\u0131na izin verilir."
}

if ($toolName -eq "run_command") {
    $cmdLine = if ($toolArgs -and $toolArgs.CommandLine) { [string]$toolArgs.CommandLine } else { "" }
    $check = Test-ReadOnlyCommand $cmdLine
    if ($check.allowed) {
        Write-HookAllow $hookEventName
    }
    $detail = $check.reason
    Write-HookDeny "[SALT-OKUNUR KORUMA - /think & /thinkdeep]: $detail Ara\u015ft\u0131rma i\u00e7in read_file, search_web veya salt-okunur komutlar\u0131 (rg, grep, Select-String, Get-ChildItem, Get-Content, git status/log/diff/show) kullan\u0131n."
}

Write-HookAllow $hookEventName
