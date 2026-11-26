# Test-ChatDiffViewer.ps1
# Vigiles Engine - /chatdiff Sohbet Odakli Salt-Okunur Degisiklik Goruntuleyici TDD & Kaos Testleri

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$ErrorActionPreference    = "Continue"

$repoRoot   = Split-Path -Parent $PSScriptRoot
$viewer     = Join-Path $repoRoot "core\scripts\chat_diff_viewer.ps1"
$skillPath  = Join-Path $repoRoot "core\skills\chatdiff\SKILL.md"
$ledgerHook = Join-Path $repoRoot "core\scripts\session_file_ledger.ps1"
$watchdog   = Join-Path $repoRoot "core\scripts\command_watchdog.ps1"
$wrapper    = Join-Path $repoRoot "core\scripts\invoke_with_timeout.ps1"
$sentinel   = Join-Path $repoRoot "core\scripts\sentinel_guard.ps1"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "TEST: /chatdiff Sohbet Odakli Salt-Okunur Goruntuleyici" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$passed = 0
$failed = 0

function Assert-ChatDiff([string]$name, [bool]$cond, [string]$detail = "") {
    if ($cond) {
        Write-Host "  [GECTI OK] $name" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  [BASARISIZ] $name -> $detail" -ForegroundColor Red
        $script:failed++
    }
}

function Test-HasUtf8Bom([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Invoke-HookJson([string]$scriptPath, [hashtable]$payloadObj) {
    $json = $payloadObj | ConvertTo-Json -Depth 8 -Compress
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "powershell.exe"
    $pinfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $pinfo.RedirectStandardInput = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true

    $proc = [System.Diagnostics.Process]::Start($pinfo)
    $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $proc.StandardInput.BaseStream.Write($utf8Bytes, 0, $utf8Bytes.Length)
    $proc.StandardInput.Close()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    $parsed = $null
    $trimmed = $stdout.Trim()
    if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
        try { $parsed = $trimmed | ConvertFrom-Json } catch {}
    }
    return @{ ExitCode = $proc.ExitCode; Stdout = $trimmed; Json = $parsed }
}

function Invoke-ChatDiff([string[]]$argsList) {
    if (-not (Test-Path -LiteralPath $viewer)) {
        return @{ ExitCode = 127; Output = "MISSING_VIEWER"; Json = $null }
    }
    $allArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $viewer, "-SkipTranscriptScan") + $argsList
    $out = (& powershell.exe @allArgs 2>&1 | Out-String)
    $ec = $LASTEXITCODE
    $jsonObj = $null
    if ($argsList -contains "-Json" -and -not [string]::IsNullOrWhiteSpace($out)) {
        try { $jsonObj = $out.Trim() | ConvertFrom-Json } catch {}
    }
    return @{ ExitCode = $ec; Output = $out; Json = $jsonObj }
}

function New-TestRepoPair([switch]$NoRemote) {
    $id = [System.Guid]::NewGuid().ToString().Substring(0, 8)
    $bare = Join-Path $env:TEMP ("vig_cd_bare_" + $id)
    $clone = Join-Path $env:TEMP ("vig_cd_clone_" + $id)

    if (-not $NoRemote) {
        New-Item -ItemType Directory -Path $bare -Force | Out-Null
        & git init --bare $bare | Out-Null
    }

    New-Item -ItemType Directory -Path $clone -Force | Out-Null
    Push-Location $clone
    & git init -b main | Out-Null
    & git config user.email "chatdiff@vigiles.local"
    & git config user.name "Vigiles ChatDiff Tester"
    & git config core.quotepath false
    if (-not $NoRemote) {
        & git remote add origin $bare
    }
    "base line 1`nbase line 2" | Set-Content -Encoding UTF8 "BASE.md"
    & git add BASE.md | Out-Null
    & git commit -m "chore: initial base" | Out-Null
    if (-not $NoRemote) {
        & git push -u origin main 2>&1 | Out-Null
    }
    Pop-Location

    return @{ Bare = $bare; Clone = $clone; Id = $id }
}

function Remove-TestRepoPair($pair) {
    if ($pair.Bare -and (Test-Path -LiteralPath $pair.Bare)) {
        Remove-Item -Path $pair.Bare -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($pair.Clone -and (Test-Path -LiteralPath $pair.Clone)) {
        Remove-Item -Path $pair.Clone -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$env:VIGILES_SKIP_DB = "1"
$env:VIGILES_CONVERSATION_ID = $null
$env:VIGILES_HOOK_CONVERSATION_ID = $null
$env:VIGILES_CONVERSATION_TITLE = $null

# ------------------------------------------------------------------------------
# TEST 1: Dosya Varligi, UTF-8 BOM, Skill & Global Kurulum Senkronizasyonu
# ------------------------------------------------------------------------------
$globalViewer = Join-Path $HOME ".gemini\config\scripts\chat_diff_viewer.ps1"
$globalSkill  = Join-Path $HOME ".gemini\config\skills\chatdiff\SKILL.md"
$syncViewerOk = (Test-Path -LiteralPath $globalViewer) -and ((Get-FileHash $viewer -Algorithm SHA256).Hash -eq (Get-FileHash $globalViewer -Algorithm SHA256).Hash)
$syncSkillOk  = (Test-Path -LiteralPath $globalSkill) -and ((Get-FileHash $skillPath -Algorithm SHA256).Hash -eq (Get-FileHash $globalSkill -Algorithm SHA256).Hash)

Assert-ChatDiff "Test 1: chat_diff_viewer.ps1 mevcut, UTF-8 BOM'lu, chatdiff/SKILL.md mevcut ve ~/.gemini/config senkron olmali" `
    ((Test-Path -LiteralPath $viewer) -and (Test-HasUtf8Bom $viewer) -and (Test-Path -LiteralPath $skillPath) -and $syncViewerOk -and $syncSkillOk) `
    "Viewer=$(Test-Path -LiteralPath $viewer) | BOM=$(Test-HasUtf8Bom $viewer) | Skill=$(Test-Path -LiteralPath $skillPath) | SyncV=$syncViewerOk | SyncS=$syncSkillOk"

# ------------------------------------------------------------------------------
# TEST 2 & 3 & 11 & 12: Izolasyon, SHARED, Turkce Dosya Adi, Line Stats & Zero-Mutation
# ------------------------------------------------------------------------------
$p1 = New-TestRepoPair
try {
    Push-Location $p1.Clone

    $fa1 = Join-Path $p1.Clone "alpha_only.txt"
    $fa2 = Join-Path $p1.Clone "Yeni Klasör\şğüöçİı_rapor.txt"
    $fb1 = Join-Path $p1.Clone "beta_locked.txt"
    $fShared = Join-Path $p1.Clone "shared_config.txt"
    $fManual = Join-Path $p1.Clone "manual_untracked.txt"

    New-Item -ItemType Directory -Path (Split-Path $fa2 -Parent) -Force | Out-Null
    "satir 1`nsatir 2`nsatir 3" | Set-Content -Encoding UTF8 $fa1
    "turkce icerik" | Set-Content -Encoding UTF8 $fa2
    "beta gizli calisma" | Set-Content -Encoding UTF8 $fb1
    "ortak satir A`nortak satir B" | Set-Content -Encoding UTF8 $fShared
    "elle yazilan dosya" | Set-Content -Encoding UTF8 $fManual

    Invoke-HookJson $ledgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-alpha-1111"; lastUserInput = "Alpha Ozelligi"; cwd = $p1.Clone
        toolCall = @{ id = "c1"; name = "write_file"; args = @{ Path = $fa1 } }
    } | Out-Null
    Invoke-HookJson $ledgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-alpha-1111"; lastUserInput = "Alpha Ozelligi"; cwd = $p1.Clone
        toolCall = @{ id = "c2"; name = "write_file"; args = @{ Path = $fa2 } }
    } | Out-Null
    Invoke-HookJson $ledgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-beta-2222"; lastUserInput = "Beta Modulu"; cwd = $p1.Clone
        toolCall = @{ id = "c3"; name = "write_file"; args = @{ Path = $fb1 } }
    } | Out-Null
    Invoke-HookJson $ledgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-alpha-1111"; lastUserInput = "Alpha Ozelligi"; cwd = $p1.Clone
        toolCall = @{ id = "c4"; name = "edit_file"; args = @{ Path = $fShared } }
    } | Out-Null
    Invoke-HookJson $ledgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-beta-2222"; lastUserInput = "Beta Modulu"; cwd = $p1.Clone
        toolCall = @{ id = "c5"; name = "edit_file"; args = @{ Path = $fShared } }
    } | Out-Null

    # Zero-Mutation: file_ledger.json, git working tree VE stat-dirty .git/index degismemeli
    $wtBefore = (& git --no-optional-locks -c core.quotepath=false status --porcelain=v1 -uall | Out-String)
    (Get-Item -LiteralPath (Join-Path $p1.Clone "BASE.md")).LastWriteTime = (Get-Date).AddMinutes(5)
    $indexBeforeHash = (Get-FileHash ".git\index" -Algorithm SHA256).Hash
    $ledgerBeforeHash = (Get-FileHash ".git\vigiles\file_ledger.json" -Algorithm SHA256).Hash

    $resAlpha = Invoke-ChatDiff @("-CallerConversationId", "chat-alpha-1111", "-Json")
    $resAlphaText = Invoke-ChatDiff @("-CallerConversationId", "chat-alpha-1111")

    $indexAfterHash = (Get-FileHash ".git\index" -Algorithm SHA256).Hash
    $ledgerAfterHash = (Get-FileHash ".git\vigiles\file_ledger.json" -Algorithm SHA256).Hash
    $wtAfter = (& git --no-optional-locks -c core.quotepath=false status --porcelain=v1 -uall | Out-String)

    $alphaPaths = @()
    if ($resAlpha.Json -and $resAlpha.Json.mainTreeItems) {
        $alphaPaths = @($resAlpha.Json.mainTreeItems | ForEach-Object { $_.path })
    }
    $sharedItem = if ($resAlpha.Json) { $resAlpha.Json.mainTreeItems | Where-Object { $_.path -eq "shared_config.txt" } } else { $null }
    $alphaOnlyItem = if ($resAlpha.Json) { $resAlpha.Json.mainTreeItems | Where-Object { $_.path -eq "alpha_only.txt" } } else { $null }

    Assert-ChatDiff "Test 2: Chat-A ciktisi yalnizca Chat-A ve ortak dosyayi gostermeli (Chat-B ve manuel gizli)" `
        ($resAlpha.ExitCode -eq 0 -and ($alphaPaths -contains "alpha_only.txt") -and ($alphaPaths -contains "shared_config.txt") -and ($alphaPaths -notcontains "beta_locked.txt") -and ($alphaPaths -notcontains "manual_untracked.txt") -and ($resAlphaText.Output -notmatch "beta_locked\.txt") -and ($resAlphaText.Output -notmatch "manual_untracked\.txt") -and $alphaOnlyItem.addedLines -ge 3) `
        "Paths=$($alphaPaths -join ', ') | Added=$($alphaOnlyItem.addedLines)"

    Assert-ChatDiff "Test 3: Ortak dosya SHARED_MULTI_CHAT olarak diger sohbet basligiyla isaretlenmeli" `
        ($null -ne $sharedItem -and $sharedItem.ownership -eq "SHARED_MULTI_CHAT" -and ($sharedItem.otherOwners -contains "Beta Modulu")) `
        "Ownership=$($sharedItem.ownership) | Others=$($sharedItem.otherOwners -join ',')"

    Assert-ChatDiff "Test 11: Turkce ve bosluklu dosya adlari quotepath bozulmadan listelenmeli" `
        ($alphaPaths -contains "Yeni Klasör/şğüöçİı_rapor.txt") `
        "Paths=$($alphaPaths -join ', ')"

    Assert-ChatDiff "Test 12: Zero-Mutation — stat-dirty .git/index, file_ledger.json ve git working tree degismemeli" `
        ($ledgerBeforeHash -eq $ledgerAfterHash -and $wtBefore -eq $wtAfter -and $indexBeforeHash -eq $indexAfterHash) `
        "LedgerEq=$($ledgerBeforeHash -eq $ledgerAfterHash) | WtEq=$($wtBefore -eq $wtAfter) | IndexEq=$($indexBeforeHash -eq $indexAfterHash)"

    # ------------------------------------------------------------------------------
    # TEST 8: -ListChats, -TargetChat (sira no, kisa ID, baslik) & Belirsiz Eslesme
    # ------------------------------------------------------------------------------
    $resList = Invoke-ChatDiff @("-CallerConversationId", "chat-alpha-1111", "-ListChats", "-Json")
    $listChats = @(if ($resList.Json -and $resList.Json.chats) { $resList.Json.chats })

    $resTargetBeta = Invoke-ChatDiff @("-CallerConversationId", "chat-alpha-1111", "-TargetChat", "Beta Modulu", "-Json")
    $betaPaths = @(if ($resTargetBeta.Json -and $resTargetBeta.Json.mainTreeItems) { $resTargetBeta.Json.mainTreeItems | ForEach-Object { $_.path } })

    $resAmbig = Invoke-ChatDiff @("-CallerConversationId", "chat-alpha-1111", "-TargetChat", "chat-")
    $resNotFound = Invoke-ChatDiff @("-CallerConversationId", "chat-alpha-1111", "-TargetChat", "olmayan-sohbet-xyz")

    Assert-ChatDiff "Test 8: -ListChats her iki sohbeti listelemeli, -TargetChat 'Beta Modulu' yalnizca Beta'yi suzmeli, belirsiz=2, yok=1" `
        ($resList.ExitCode -eq 0 -and $listChats.Count -eq 2 -and $resTargetBeta.ExitCode -eq 0 -and ($betaPaths -contains "beta_locked.txt") -and ($betaPaths -notcontains "alpha_only.txt") -and $resAmbig.ExitCode -eq 2 -and $resNotFound.ExitCode -eq 1) `
        "ListCount=$($listChats.Count) | BetaPaths=$($betaPaths -join ',') | AmbigEC=$($resAmbig.ExitCode) | NotFoundEC=$($resNotFound.ExitCode)"

    # ------------------------------------------------------------------------------
    # TEST 4 & 5: Push Sonrasi Kapsam Disi Kalma + Sahibe Ozel Unpushed Local Commit
    # ------------------------------------------------------------------------------
    $pushMgr = Join-Path $repoRoot "core\scripts\git_push_manager.ps1"
    $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $pushMgr -SkipTranscriptScan -Action Prep -ConversationId "chat-alpha-1111" 2>&1
    $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $pushMgr -SkipTranscriptScan -Action Push -ConversationId "chat-alpha-1111" -Approved -CommitMessage "feat: alpha pushed" 2>&1

    "alpha unpushed v2" | Set-Content -Encoding UTF8 "alpha_unpushed.txt"
    & git add "alpha_unpushed.txt" | Out-Null
    & git commit -m "feat: alpha local unpushed" | Out-Null
    $shaA = (& git rev-parse HEAD).Trim()

    "beta unpushed v2" | Set-Content -Encoding UTF8 "beta_unpushed.txt"
    & git add "beta_unpushed.txt" | Out-Null
    & git commit -m "feat: beta local unpushed" | Out-Null
    $shaB = (& git rev-parse HEAD).Trim()

    $led = Get-Content -Raw -Encoding UTF8 ".git\vigiles\file_ledger.json" | ConvertFrom-Json
    if (-not $led.commits) {
        $led | Add-Member -NotePropertyName "commits" -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    $led.commits | Add-Member -NotePropertyName $shaA -NotePropertyValue ([PSCustomObject]@{ conversationId = "chat-alpha-1111"; at = (Get-Date).ToString("o"); subject = "feat: alpha local unpushed" }) -Force
    $led.commits | Add-Member -NotePropertyName $shaB -NotePropertyValue ([PSCustomObject]@{ conversationId = "chat-beta-2222"; at = (Get-Date).ToString("o"); subject = "feat: beta local unpushed" }) -Force
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $p1.Clone ".git\vigiles\file_ledger.json"), ($led | ConvertTo-Json -Depth 10), $utf8NoBom)

    $resAfterPush = Invoke-ChatDiff @("-CallerConversationId", "chat-alpha-1111", "-Json")
    $afterPaths = @(if ($resAfterPush.Json -and $resAfterPush.Json.mainTreeItems) { $resAfterPush.Json.mainTreeItems | ForEach-Object { $_.path } })
    $afterCommits = @(if ($resAfterPush.Json -and $resAfterPush.Json.unpushedCommits) { $resAfterPush.Json.unpushedCommits })

    Assert-ChatDiff "Test 4 & 5: Pushlanan alpha_only.txt dusmeli, unpushed commitlerde yalnizca Chat-A'nin commiti gorunmeli" `
        (($afterPaths -notcontains "alpha_only.txt") -and ($afterCommits.Count -eq 1) -and ($afterCommits[0].sha -eq $shaA) -and ($resAfterPush.Json.filteredCounts.otherCommits -ge 1)) `
        "AfterPaths=$($afterPaths -join ',') | Commits=$($afterCommits.Count) | OtherCommits=$($resAfterPush.Json.filteredCounts.otherCommits)"

} finally {
    Pop-Location
    Remove-TestRepoPair $p1
}

# ------------------------------------------------------------------------------
# TEST 6 & 10: Remote Olmayan Repo + -Diff & Zero-Leak Maskeleme
# ------------------------------------------------------------------------------
$pLocal = New-TestRepoPair -NoRemote
try {
    Push-Location $pLocal.Clone
    $normFile = Join-Path $pLocal.Clone "BASE.md"
    $envFile  = Join-Path $pLocal.Clone ".env"
    $secretSrc = Join-Path $pLocal.Clone "leak_test.ts"
    $dummySecret = "sk-proj-" + "1234567890abcdefghijklmnop"

    "base line 1`nbase line 2`nyeni eklenen satir" | Set-Content -Encoding UTF8 $normFile
    "OPENAI_API_KEY=$dummySecret" | Set-Content -Encoding UTF8 $envFile
    "const k = '$dummySecret';" | Set-Content -Encoding UTF8 $secretSrc

    Invoke-HookJson $ledgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-local-99"; lastUserInput = "Yerel Gorev"; cwd = $pLocal.Clone
        toolCall = @{ id = "l1"; name = "edit_file"; args = @{ Path = $normFile } }
    } | Out-Null
    Invoke-HookJson $ledgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-local-99"; lastUserInput = "Yerel Gorev"; cwd = $pLocal.Clone
        toolCall = @{ id = "l2"; name = "write_file"; args = @{ Path = $envFile } }
    } | Out-Null
    Invoke-HookJson $ledgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-local-99"; lastUserInput = "Yerel Gorev"; cwd = $pLocal.Clone
        toolCall = @{ id = "l3"; name = "write_file"; args = @{ Path = $secretSrc } }
    } | Out-Null

    # Tracked dosyada secret silindiginde/degistiginde de diff icerigi maskelenmeli (DEF-004)
    $trackedSecret = Join-Path $pLocal.Clone "tracked_leak_old.ts"
    "const oldSecret = '$dummySecret';" | Set-Content -Encoding UTF8 $trackedSecret
    & git add "tracked_leak_old.ts" | Out-Null
    & git commit -m "chore: seed tracked secret for deletion diff test" | Out-Null
    Remove-Item -LiteralPath $trackedSecret -Force
    Invoke-HookJson $ledgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-local-99"; lastUserInput = "Yerel Gorev"; cwd = $pLocal.Clone
        toolCall = @{ id = "l4"; name = "delete_file"; args = @{ Path = $trackedSecret } }
    } | Out-Null

    $resDiff = Invoke-ChatDiff @("-CallerConversationId", "chat-local-99", "-Diff")
    $resDiffJson = Invoke-ChatDiff @("-CallerConversationId", "chat-local-99", "-Diff", "-Json")
    $delItem = @(if ($resDiffJson.Json -and $resDiffJson.Json.mainTreeItems) { $resDiffJson.Json.mainTreeItems | Where-Object { $_.path -eq "tracked_leak_old.ts" } }) | Select-Object -First 1
    $noSecretLeaked = ($resDiff.Output -notmatch '1234567890abcdefgh') -and ($resDiff.Output -notmatch 'OPENAI_API_KEY=') -and ($delItem -and $delItem.diff -match 'maskelendi')
    $hasNormalDiff = ($resDiff.Output -match 'yeni eklenen satir') -and ($resDiff.Output -match 'ZERO-LEAK|maskelendi')

    Assert-ChatDiff "Test 6 & 10: Remote olmayan yerel repoda calismali, -Diff normal farki gostermeli ama gizli anahtari (silinen dahil) maskelemeli" `
        ($resDiff.ExitCode -eq 0 -and $resDiffJson.ExitCode -eq 0 -and $noSecretLeaked -and $hasNormalDiff) `
        "EC=$($resDiff.ExitCode) | NoLeak=$noSecretLeaked | HasNorm=$hasNormalDiff | DelDiff=$($delItem.diff)"
} finally {
    Pop-Location
    Remove-TestRepoPair $pLocal
}

# ------------------------------------------------------------------------------
# TEST 7: Paralel /pro Worktree Degisikliklerinin Yakalanmasi (.worktrees/pro-<id>)
# ------------------------------------------------------------------------------
$pWt = New-TestRepoPair
$wtArtDir = Join-Path $env:TEMP ("vig_cd_art_" + $pWt.Id)
New-Item -ItemType Directory -Path $wtArtDir -Force | Out-Null
try {
    Push-Location $pWt.Clone
    $wtManager = Join-Path $repoRoot "core\scripts\vigiles_session_manager.ps1"
    $wtCid = "11223344-5566-7788-99aa-bbccddeeff00"
    $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wtManager -Action Start -ConversationId $wtCid -ArtifactDir $wtArtDir -WorkspacePath $pWt.Clone -ForceWorktree -Json 2>&1

    $wtDir = Join-Path $pWt.Clone ".worktrees\pro-11223344"
    $wtFile = Join-Path $wtDir "worktree_only_feature.ps1"
    "Write-Output 'izole santiye'" | Set-Content -Encoding UTF8 $wtFile
    $wtCommittedFile = Join-Path $wtDir "worktree_committed_feature.ps1"
    "Write-Output 'worktree commit diff kaniti'" | Set-Content -Encoding UTF8 $wtCommittedFile
    Push-Location $wtDir
    & git add "worktree_committed_feature.ps1" | Out-Null
    & git commit -m "feat: worktree local commit" | Out-Null
    Pop-Location

    $resWt = Invoke-ChatDiff @("-CallerConversationId", $wtCid, "-Diff", "-Json")
    $wtItems = @(if ($resWt.Json -and $resWt.Json.worktree -and $resWt.Json.worktree.items) { $resWt.Json.worktree.items | ForEach-Object { $_.path } })
    $wtCommItem = @(if ($resWt.Json -and $resWt.Json.worktree -and $resWt.Json.worktree.items) { $resWt.Json.worktree.items | Where-Object { $_.path -eq "worktree_committed_feature.ps1" } }) | Select-Object -First 1

    Assert-ChatDiff "Test 7: Paralel /pro worktree (commitlenmemis + commitlenmis -Diff dahil) [B] altinda eksiksiz listelenmeli" `
        ($resWt.ExitCode -eq 0 -and ($wtItems -contains "worktree_only_feature.ps1") -and ($wtItems -contains "worktree_committed_feature.ps1") -and ($resWt.Json.worktree.shortId -eq "11223344") -and $wtCommItem -and ($wtCommItem.diff -match 'worktree commit diff kaniti')) `
        "WtItems=$($wtItems -join ',') | ShortId=$($resWt.Json.worktree.shortId) | CommDiff=$($wtCommItem.diff)"
} finally {
    Pop-Location
    Remove-TestRepoPair $pWt
    Remove-Item -Path $wtArtDir -Recurse -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------------------
# TEST 9: Kanca Zinciri (session_file_ledger + command_watchdog + sentinel_guard)
# ------------------------------------------------------------------------------
$pHook = New-TestRepoPair
$artHook = Join-Path $env:TEMP ("vig_cd_hookart_" + $pHook.Id)
New-Item -ItemType Directory -Path $artHook -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $artHook ".vigiles_active"), "vigiles", [System.Text.Encoding]::UTF8)
try {
    Push-Location $pHook.Clone
    $fA = Join-Path $pHook.Clone "hook_alpha.txt"
    $fB = Join-Path $pHook.Clone "hook_beta.txt"
    "alpha" | Set-Content -Encoding UTF8 $fA
    "beta"  | Set-Content -Encoding UTF8 $fB

    Invoke-HookJson $ledgerHook @{
        hookEventName = "PostToolUse"; conversationId = "hook-alpha-cid"; lastUserInput = "Hook Alpha"; cwd = $pHook.Clone
        toolCall = @{ id = "h1"; name = "write_file"; args = @{ Path = $fA } }
    } | Out-Null
    Invoke-HookJson $ledgerHook @{
        hookEventName = "PostToolUse"; conversationId = "hook-beta-cid"; lastUserInput = "Hook Beta"; cwd = $pHook.Clone
        toolCall = @{ id = "h2"; name = "write_file"; args = @{ Path = $fB } }
    } | Out-Null

    $rawCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$viewer`" -CallerConversationId `"sahte-cid`" -SkipTranscriptScan -Json"
    $ledgerRes = Invoke-HookJson $ledgerHook @{
        hookEventName  = "PreToolUse"
        conversationId = "hook-alpha-cid"
        lastUserInput  = "Hook Alpha"
        cwd            = $pHook.Clone
        toolCall       = @{ id = "h3"; name = "run_command"; args = @{ CommandLine = $rawCmd } }
    }
    $snapLeft = Get-ChildItem (Join-Path $pHook.Clone ".git\vigiles") -Filter "cmd_snap_*.json" -ErrorAction SilentlyContinue
    $ledgerCmd = if ($ledgerRes.Json -and $ledgerRes.Json.overwrite) { [string]$ledgerRes.Json.overwrite.CommandLine } else { "" }

    $wdRes = Invoke-HookJson $watchdog @{
        conversationId        = "hook-alpha-cid"
        artifactDirectoryPath = $artHook
        cwd                   = $pHook.Clone
        toolCall              = @{ name = "run_command"; args = @{ CommandLine = $rawCmd } }
    }
    $wdCmd = if ($wdRes.Json -and $wdRes.Json.overwrite) { [string]$wdRes.Json.overwrite.CommandLine } else { "" }

    $wrappedRunOut = ""
    if ($wdCmd -match '-PayloadFile\s+"([^"]+)"') {
        $pf = $matches[1]
        $wrappedRunOut = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrapper -PayloadFile $pf 2>&1 | Out-String)
    }
    $wrappedJson = $null
    if (-not [string]::IsNullOrWhiteSpace($wrappedRunOut)) {
        try { $wrappedJson = $wrappedRunOut.Trim() | ConvertFrom-Json } catch {}
    }

    # -TargetChat parametresi watchdog sarmali altinda da korunmali
    $rawTargetCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$viewer`" -TargetChat `"Hook Beta`" -SkipTranscriptScan -Json"
    $wdTargetRes = Invoke-HookJson $watchdog @{
        conversationId        = "hook-alpha-cid"
        artifactDirectoryPath = $artHook
        cwd                   = $pHook.Clone
        toolCall              = @{ name = "run_command"; args = @{ CommandLine = $rawTargetCmd } }
    }
    $wdTargetCmd = if ($wdTargetRes.Json -and $wdTargetRes.Json.overwrite) { [string]$wdTargetRes.Json.overwrite.CommandLine } else { "" }
    $wrappedTargetOut = ""
    if ($wdTargetCmd -match '-PayloadFile\s+"([^"]+)"') {
        $pf2 = $matches[1]
        $wrappedTargetOut = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrapper -PayloadFile $pf2 2>&1 | Out-String)
    }
    $wrappedTargetJson = $null
    if (-not [string]::IsNullOrWhiteSpace($wrappedTargetOut)) {
        try { $wrappedTargetJson = $wrappedTargetOut.Trim() | ConvertFrom-Json } catch {}
    }

    # Ters Kanca Sirasi (command-watchdog -> session-file-ledger) + -Paths Test-* + sarmali git commit deny testi (DEF-002 & DEF-003)
    $rawPathTestCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$viewer`" -Paths `"tests/Test-ChatDiffViewer.ps1`" -SkipTranscriptScan -Json"
    $wdPathRes = Invoke-HookJson $watchdog @{
        conversationId        = "hook-alpha-cid"
        artifactDirectoryPath = $artHook
        cwd                   = $pHook.Clone
        toolCall              = @{ name = "run_command"; args = @{ CommandLine = $rawPathTestCmd } }
    }
    $wdPathCmd = if ($wdPathRes.Json -and $wdPathRes.Json.overwrite) { [string]$wdPathRes.Json.overwrite.CommandLine } else { "" }

    # session_file_ledger sarmalanmis komutu aldiginda cmd_snap uretmemeli ve wrapper'i bozmamali
    $revLedgerRes = Invoke-HookJson $ledgerHook @{
        hookEventName  = "PreToolUse"
        conversationId = "hook-alpha-cid"
        lastUserInput  = "Hook Alpha"
        cwd            = $pHook.Clone
        toolCall       = @{ id = "h_rev1"; name = "run_command"; args = @{ CommandLine = $wdPathCmd } }
    }
    $revSnaps = Get-ChildItem (Join-Path $pHook.Clone ".git\vigiles") -Filter "cmd_snap_*.json" -ErrorAction SilentlyContinue
    $revRunOut = ""
    if ($wdPathCmd -match '-PayloadFile\s+"([^"]+)"') {
        $pfRev = $matches[1]
        $revRunOut = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrapper -PayloadFile $pfRev 2>&1 | Out-String)
    }
    $revJson = $null
    if (-not [string]::IsNullOrWhiteSpace($revRunOut)) {
        try { $revJson = $revRunOut.Trim() | ConvertFrom-Json } catch {}
    }

    # Watchdog tarafindan sarmalanmis git commit session_file_ledger tarafindan DENY edilmeli
    $wdGitRes = Invoke-HookJson $watchdog @{
        conversationId        = "hook-alpha-cid"
        artifactDirectoryPath = $artHook
        cwd                   = $pHook.Clone
        toolCall              = @{ name = "run_command"; args = @{ CommandLine = "git commit -m 'sneaky'" } }
    }
    $wdGitCmd = if ($wdGitRes.Json -and $wdGitRes.Json.overwrite) { [string]$wdGitRes.Json.overwrite.CommandLine } else { "" }
    $revGitLedger = Invoke-HookJson $ledgerHook @{
        hookEventName  = "PreToolUse"
        conversationId = "hook-alpha-cid"
        lastUserInput  = "Hook Alpha"
        cwd            = $pHook.Clone
        toolCall       = @{ id = "h_rev2"; name = "run_command"; args = @{ CommandLine = $wdGitCmd } }
    }
    if ($wdGitCmd -match '-PayloadFile\s+"([^"]+)"') {
        Remove-Item -LiteralPath $matches[1] -Force -ErrorAction SilentlyContinue
    }

    $statePath = Join-Path $artHook "live_state.json"
    if (Test-Path $statePath) { Remove-Item $statePath -Force -ErrorAction SilentlyContinue }
    $null = Invoke-HookJson $sentinel @{
        conversationId        = "hook-alpha-cid"
        artifactDirectoryPath = $artHook
        workspacePaths        = @($pHook.Clone)
        toolCall              = @{ name = "run_command"; args = @{ CommandLine = $rawCmd } }
    }
    $stObj = if (Test-Path $statePath) { (Get-Content -Raw -Encoding UTF8 $statePath) | ConvertFrom-Json } else { $null }

    Assert-ChatDiff "Test 9: Kanca zincirinde (her iki sirada) kimlik korunmali, -Paths 'Test-*' calismali, cmd_snap=0, sarmali git commit deny ve node-architect yanmali" `
        (($null -eq $snapLeft -or $snapLeft.Count -eq 0) -and ($null -eq $revSnaps -or $revSnaps.Count -eq 0) -and ($ledgerCmd -match 'VIGILES_CONVERSATION_ID') -and ($ledgerCmd -notmatch 'sahte-cid') -and ($null -ne $wrappedJson) -and ($wrappedJson.targetConversationId -eq "hook-alpha-cid") -and ($null -ne $wrappedTargetJson) -and ($wrappedTargetJson.targetConversationId -eq "hook-beta-cid") -and ($wrappedTargetJson.callerConversationId -eq "hook-alpha-cid") -and ($null -ne $revJson) -and ($revJson.targetConversationId -eq "hook-alpha-cid") -and ($revLedgerRes.Json -and $revLedgerRes.Json.decision -eq "allow") -and ($revGitLedger.Json -and $revGitLedger.Json.decision -eq "deny") -and ($stObj -and $stObj.activeNode -eq "node-architect")) `
        "Snap=$($snapLeft.Count)/$($revSnaps.Count) | WrapCid=$($wrappedJson.targetConversationId) | TargetCid=$($wrappedTargetJson.targetConversationId) | RevPathsCid=$($revJson.targetConversationId) | RevGit=$($revGitLedger.Json.decision) | Node=$($stObj.activeNode)"
} finally {
    Pop-Location
    Remove-TestRepoPair $pHook
    Remove-Item -Path $artHook -Recurse -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------------------
# TEST 13: Alt Ajan Transcript Kurtarma (apply_patch + subagent -> rootCid)
# ------------------------------------------------------------------------------
$pTr = New-TestRepoPair
$fakeBrain = Join-Path $env:TEMP ("vig_cd_brain_" + $pTr.Id)
$subCid = "subagent-worker-777"
$rootTrCid = "root-chat-888"
New-Item -ItemType Directory -Path (Join-Path $fakeBrain "$subCid\.system_generated\logs") -Force | Out-Null
try {
    Push-Location $pTr.Clone
    $trFile = Join-Path $pTr.Clone "recovered_patch.txt"
    "recovered content" | Set-Content -Encoding UTF8 $trFile

    New-Item -ItemType Directory -Path (Join-Path $pTr.Clone ".git\vigiles") -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $pTr.Clone ".git\vigiles\subagent_map.json"), (@{ "$subCid" = $rootTrCid } | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
    $trLine = @{
        step_index = 1
        tool_calls = @(
            @{
                name = "apply_patch"
                args = @{ Patch = "*** Add File: $trFile`n+recovered content" }
            }
        )
    } | ConvertTo-Json -Depth 6 -Compress
    [System.IO.File]::WriteAllText((Join-Path $fakeBrain "$subCid\.system_generated\logs\transcript.jsonl"), "$trLine`n", (New-Object System.Text.UTF8Encoding($false)))

    $prevBrain = $env:VIGILES_BRAIN_DIR
    $env:VIGILES_BRAIN_DIR = $fakeBrain
    $resTr = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $viewer -CallerConversationId $rootTrCid -Json 2>&1 | Out-String)
    $env:VIGILES_BRAIN_DIR = $prevBrain
    $trObj = $null
    try { $trObj = $resTr.Trim() | ConvertFrom-Json } catch {}
    $trPaths = @(if ($trObj -and $trObj.mainTreeItems) { $trObj.mainTreeItems | ForEach-Object { $_.path } })

    Assert-ChatDiff "Test 13: Transcript kurtarma (alt ajan apply_patch -> kok sohbet) diske yazmadan dogru sohbete baglanmali" `
        ($LASTEXITCODE -eq 0 -and ($trPaths -contains "recovered_patch.txt")) `
        "TrPaths=$($trPaths -join ',') | Out=$resTr"

    # TEST 14: -Paths filtresi ve degisikligi olmayan temiz sohbet (ExitCode 0)
    $resEmpty = Invoke-ChatDiff @("-CallerConversationId", "hic-dokunmayan-sohbet-000", "-Json")
    $resPathMiss = Invoke-ChatDiff @("-CallerConversationId", "root-chat-888", "-Paths", "olmayan_dosya.xyz", "-Json")
    $emptyItemsCount = @(if ($resEmpty.Json -and $resEmpty.Json.mainTreeItems) { $resEmpty.Json.mainTreeItems }).Count
    $missItemsCount = @(if ($resPathMiss.Json -and $resPathMiss.Json.mainTreeItems) { $resPathMiss.Json.mainTreeItems }).Count

    Assert-ChatDiff "Test 14: Temiz sohbet ve eslesmeyen -Paths filtresi ExitCode 0 ile bos liste donmeli" `
        ($resEmpty.ExitCode -eq 0 -and $emptyItemsCount -eq 0 -and $resPathMiss.ExitCode -eq 0 -and $missItemsCount -eq 0) `
        "EmptyEC=$($resEmpty.ExitCode)/$emptyItemsCount | MissEC=$($resPathMiss.ExitCode)/$missItemsCount"
} finally {
    Pop-Location
    Remove-TestRepoPair $pTr
    Remove-Item -Path $fakeBrain -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "SONUC: $passed Gecti | $failed Basarisiz" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "==========================================================" -ForegroundColor Cyan

if ($failed -gt 0) { exit 1 } else { exit 0 }
