# Test-SessionPushIsolation.ps1
# Vigiles Engine - Coklu Sohbet Dosya Zimmeti, Kati Push Izolasyonu & Mutex Kaos Testi

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

$repoRoot = Split-Path -Parent $PSScriptRoot
$ledgerHook = Join-Path $repoRoot "core\scripts\session_file_ledger.ps1"
$pushMgr    = Join-Path $repoRoot "core\scripts\git_push_manager.ps1"

if (-not (Test-Path $ledgerHook) -or -not (Test-Path $pushMgr)) {
    Write-Host "HATA: Gerekli scriptler bulunamadi!" -ForegroundColor Red
    exit 1
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "TEST: Coklu Sohbet Push Izolasyonu & Zimmet Defteri (v3.0)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$passed = 0
$total = 0

function Assert-Iso([string]$name, [bool]$cond, [string]$detail = "") {
    $script:total++
    if ($cond) {
        Write-Host "  [GECTI OK] $name" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  [BASARISIZ] $name -> $detail" -ForegroundColor Red
    }
}

function Invoke-LedgerHook([hashtable]$payload) {
    $json = $payload | ConvertTo-Json -Depth 6 -Compress
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "powershell.exe"
    $pinfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ledgerHook`""
    $pinfo.RedirectStandardInput = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($pinfo)
    $p.StandardInput.Write($json)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    return $out
}

function Invoke-PushMgr([string[]]$argsList) {
    $allArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $pushMgr, "-SkipTranscriptScan") + $argsList
    $out = (& powershell @allArgs 2>&1 | Out-String)
    return @{ ExitCode = $LASTEXITCODE; Output = $out }
}

function New-IsoRepoPair {
    $id = [System.Guid]::NewGuid().ToString().Substring(0, 8)
    $bare = Join-Path $env:TEMP ("vig_iso_bare_" + $id)
    $clone = Join-Path $env:TEMP ("vig_iso_clone_" + $id)
    New-Item -ItemType Directory -Path $bare -Force | Out-Null
    & git init --bare $bare | Out-Null

    New-Item -ItemType Directory -Path $clone -Force | Out-Null
    Push-Location $clone
    & git init -b main | Out-Null
    & git config user.email "iso@vigiles.local"
    & git config user.name "Vigiles Isolation Tester"
    & git config core.quotepath false
    & git remote add origin $bare
    "base" | Set-Content -Encoding UTF8 "README_BASE.md"
    & git add README_BASE.md | Out-Null
    & git commit -m "chore: base commit" | Out-Null
    & git push -u origin main 2>&1 | Out-Null
    Pop-Location
    return @{ Bare = $bare; Clone = $clone }
}

function Remove-IsoRepoPair($pair) {
    Remove-Item -Path $pair.Bare -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $pair.Clone -Recurse -Force -ErrorAction SilentlyContinue
}

# Test ortaminda host DB sorgusunu atlamak icin
$env:VIGILES_SKIP_DB = "1"

# Test 1: Normal (komutsuz) sohbette PostToolUse zimmet kaydi & hatalida kaydetmeme
$p1 = New-IsoRepoPair
try {
    Push-Location $p1.Clone
    $f1 = Join-Path $p1.Clone "normal_chat_file.txt"
    "hello" | Set-Content -Encoding UTF8 $f1
    Invoke-LedgerHook @{
        hookEventName  = "PostToolUse"
        conversationId = "chat-normal-01"
        lastUserInput  = "normal sohbet gorevi"
        cwd            = $p1.Clone
        toolCall       = @{ id = "t1"; name = "write_file"; args = @{ Path = $f1 } }
    } | Out-Null

    $fErr = Join-Path $p1.Clone "failed_tool.txt"
    Invoke-LedgerHook @{
        hookEventName  = "PostToolUse"
        conversationId = "chat-normal-01"
        cwd            = $p1.Clone
        error          = "permission denied"
        toolCall       = @{ id = "t2"; name = "write_file"; args = @{ Path = $fErr } }
    } | Out-Null

    $ledger = Get-Content -Raw -Encoding UTF8 ".git\vigiles\file_ledger.json" | ConvertFrom-Json
    $hasNormal = $null -ne $ledger.files."normal_chat_file.txt".editors."chat-normal-01"
    $hasFailed = $null -ne $ledger.files."failed_tool.txt"

    Assert-Iso "Test 1: Normal sohbette PostToolUse zimmet kaydi (hatali arac kaydolmaz)" `
        ($hasNormal -and -not $hasFailed) "HasNormal=$hasNormal HasFailed=$hasFailed"
} finally {
    Pop-Location
    Remove-IsoRepoPair $p1
}

# Test 2 & 3: Chat-A ve Chat-B Tam Izolasyon + Baska Sohbete Kati Kilit (/pushadd reddi)
$p2 = New-IsoRepoPair
try {
    Push-Location $p2.Clone
    $fa = Join-Path $p2.Clone "chat_a_feature.txt"
    $fb = Join-Path $p2.Clone "chat_b_secret_wip.txt"
    "from A" | Set-Content -Encoding UTF8 $fa
    "from B" | Set-Content -Encoding UTF8 $fb

    Invoke-LedgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-alpha-111"; lastUserInput = "Ozellik A Gelistirme"; cwd = $p2.Clone
        toolCall = @{ id = "a1"; name = "write_file"; args = @{ Path = $fa } }
    } | Out-Null
    Invoke-LedgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-beta-222"; lastUserInput = "Ozellik B Tasarimi"; cwd = $p2.Clone
        toolCall = @{ id = "b1"; name = "edit_file"; args = @{ Path = $fb } }
    } | Out-Null

    $prepA = Invoke-PushMgr @("-Action", "Prep", "-ConversationId", "chat-alpha-111")
    $mA = Get-Content -Raw -Encoding UTF8 ".git\vigiles\pushprep_chat-alpha-111.json" | ConvertFrom-Json
    $itemA = $mA.items | Where-Object { $_.path -eq "chat_a_feature.txt" }
    $itemB = $mA.items | Where-Object { $_.path -eq "chat_b_secret_wip.txt" }

    # Katı kilit testi: Chat-A, Chat-B dosyasini /pushadd ile eklemeye calisir -> ExitCode 1
    $tryStealB = Invoke-PushMgr @("-Action", "Add", "-ConversationId", "chat-alpha-111", "-Targets", "chat_b_secret_wip.txt")

    # Chat-A push yapinca YALNIZCA chat_a_feature.txt uzak repoya gitmeli
    $pushA = Invoke-PushMgr @("-Action", "Push", "-ConversationId", "chat-alpha-111", "-CommitMessage", "feat: chat A only")

    Push-Location $p2.Bare
    $bareAfterA = (& git ls-tree -r --name-only main 2>&1 | Out-String)
    Pop-Location
    $localBExists = Test-Path $fb

    Assert-Iso "Test 2: Coklu sohbet izolasyonu (Chat-A pushunda sadece A gider, B yerelde ve kilitli kalir)" `
        ($itemA.ownership -eq "OWNED_THIS_CHAT" -and $itemA.included -and $itemB.ownership -eq "LOCKED_OTHER_CHAT" -and (-not $itemB.included) -and $pushA.ExitCode -eq 0 -and ($bareAfterA -match "chat_a_feature\.txt") -and ($bareAfterA -notmatch "chat_b_secret_wip\.txt") -and $localBExists) `
        "Bare=$bareAfterA LocalB=$localBExists"

    Assert-Iso "Test 3: Kati koruma (baska sohbet dosyasi /pushadd ile bile eklenemez -> ExitCode 1)" `
        ($tryStealB.ExitCode -eq 1 -and $tryStealB.Output -match "SOHBET IZOLASYON ENGELI") `
        "Exit=$($tryStealB.ExitCode) Out=$($tryStealB.Output)"

    # Ardindan Chat-B kendi sohbetinden pushladiginda B basariyla gitmeli
    $prepB = Invoke-PushMgr @("-Action", "Prep", "-ConversationId", "chat-beta-222")
    $pushB = Invoke-PushMgr @("-Action", "Push", "-ConversationId", "chat-beta-222", "-CommitMessage", "feat: chat B own push")
    Push-Location $p2.Bare
    $bareAfterB = (& git ls-tree -r --name-only main 2>&1 | Out-String)
    Pop-Location
    Assert-Iso "Test 3b: Chat-B kendi dosyasini kendi sohbetinden sorunsuz pushlar" `
        ($prepB.ExitCode -eq 0 -and $pushB.ExitCode -eq 0 -and ($bareAfterB -match "chat_b_secret_wip\.txt")) `
        "BareB=$bareAfterB"
} finally {
    Pop-Location
    Remove-IsoRepoPair $p2
}

# Test 4: Ortak Dokunulan Dosya (SHARED_MULTI_CHAT) Onay Kapisi & -IncludeShared vs -Approved
$p4 = New-IsoRepoPair
try {
    Push-Location $p4.Clone
    $fShared = Join-Path $p4.Clone "README_SHARED.md"
    $fOnlyA = Join-Path $p4.Clone "only_a.txt"
    "shared edit" | Set-Content -Encoding UTF8 $fShared
    "only a" | Set-Content -Encoding UTF8 $fOnlyA

    Invoke-LedgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-a"; lastUserInput = "Chat A"; cwd = $p4.Clone
        toolCall = @{ id = "sa1"; name = "edit_file"; args = @{ Path = $fShared } }
    } | Out-Null
    Invoke-LedgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-a"; lastUserInput = "Chat A"; cwd = $p4.Clone
        toolCall = @{ id = "sa2"; name = "write_file"; args = @{ Path = $fOnlyA } }
    } | Out-Null
    Invoke-LedgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-b"; lastUserInput = "Chat B Ortak"; cwd = $p4.Clone
        toolCall = @{ id = "sb1"; name = "edit_file"; args = @{ Path = $fShared } }
    } | Out-Null

    Invoke-PushMgr @("-Action", "Prep", "-ConversationId", "chat-a") | Out-Null
    $gateShared = Invoke-PushMgr @("-Action", "Push", "-ConversationId", "chat-a", "-CommitMessage", "feat: check shared gate")
    # Ortak haric tutularak push (-Approved, ama -IncludeShared YOK)
    $pushSkipShared = Invoke-PushMgr @("-Action", "Push", "-ConversationId", "chat-a", "-Approved", "-CommitMessage", "feat: push without shared")

    Push-Location $p4.Bare
    $bareSkip = (& git ls-tree -r --name-only main 2>&1 | Out-String)
    Pop-Location

    # Simdi ortak dosya dahil edilerek push (-Approved -IncludeShared)
    Invoke-PushMgr @("-Action", "Prep", "-ConversationId", "chat-a") | Out-Null
    $pushWithShared = Invoke-PushMgr @("-Action", "Push", "-ConversationId", "chat-a", "-Approved", "-IncludeShared", "-CommitMessage", "feat: push with shared")

    Push-Location $p4.Bare
    $bareWith = (& git ls-tree -r --name-only main 2>&1 | Out-String)
    Pop-Location

    Assert-Iso "Test 4: Ortak dosya (SHARED_MULTI_CHAT) ExitCode 2 onay kapisi & secimli dahil etme" `
        ($gateShared.ExitCode -eq 2 -and $gateShared.Output -match "ORTAK DOSYA ONAYI GEREKLI" -and $pushSkipShared.ExitCode -eq 0 -and ($bareSkip -match "only_a\.txt") -and ($bareSkip -notmatch "README_SHARED\.md") -and $pushWithShared.ExitCode -eq 0 -and ($bareWith -match "README_SHARED\.md")) `
        "GateExit=$($gateShared.ExitCode) BareSkip=$bareSkip BareWith=$bareWith"
} finally {
    Pop-Location
    Remove-IsoRepoPair $p4
}

# Test 5: Editorde Elle Degistirilen Dosya (UNTRACKED_MANUAL -> varsayilan haric, /pushadd izinli)
$p5 = New-IsoRepoPair
try {
    Push-Location $p5.Clone
    "elle yazildi" | Set-Content -Encoding UTF8 "manual_note.txt"
    $fChat = Join-Path $p5.Clone "chat_owned.txt"
    "chat yazdi" | Set-Content -Encoding UTF8 $fChat
    Invoke-LedgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-m1"; lastUserInput = "Chat M1"; cwd = $p5.Clone
        toolCall = @{ id = "m1"; name = "write_file"; args = @{ Path = $fChat } }
    } | Out-Null

    Invoke-PushMgr @("-Action", "Prep", "-ConversationId", "chat-m1") | Out-Null
    $m5 = Get-Content -Raw -Encoding UTF8 ".git\vigiles\pushprep_chat-m1.json" | ConvertFrom-Json
    $manItem = $m5.items | Where-Object { $_.path -eq "manual_note.txt" }
    $addMan = Invoke-PushMgr @("-Action", "Add", "-ConversationId", "chat-m1", "-Targets", "manual_note.txt")
    $pushMan = Invoke-PushMgr @("-Action", "Push", "-ConversationId", "chat-m1", "-CommitMessage", "feat: include manual edit")

    Push-Location $p5.Bare
    $bare5 = (& git ls-tree -r --name-only main 2>&1 | Out-String)
    Pop-Location

    Assert-Iso "Test 5: Elle degistirilen dosya varsayilan haric (UNTRACKED_MANUAL) & /pushadd ile eklenebilir" `
        ($manItem.ownership -eq "UNTRACKED_MANUAL" -and (-not $manItem.included) -and $addMan.ExitCode -eq 0 -and $pushMan.ExitCode -eq 0 -and ($bare5 -match "manual_note\.txt") -and ($bare5 -match "chat_owned\.txt")) `
        "ManOwn=$($manItem.ownership) ManInc=$($manItem.included) Bare=$bare5"
} finally {
    Pop-Location
    Remove-IsoRepoPair $p5
}

# Test 6: Alt Ajan (Subagent) Mirasi -> parent_conversation_id ile Ana Sohbete Baglanma
$p6 = New-IsoRepoPair
try {
    Push-Location $p6.Clone
    $vigDir6 = Join-Path $p6.Clone ".git\vigiles"
    New-Item -ItemType Directory -Path $vigDir6 -Force | Out-Null
    '{"subagent-worker-99":"root-chat-A"}' | Set-Content -Encoding UTF8 (Join-Path $vigDir6 "subagent_map.json")

    $fSub = Join-Path $p6.Clone "subagent_output.txt"
    "subagent wrote this" | Set-Content -Encoding UTF8 $fSub
    Invoke-LedgerHook @{
        hookEventName = "PostToolUse"; conversationId = "subagent-worker-99"; cwd = $p6.Clone
        toolCall = @{ id = "sub1"; name = "write_file"; args = @{ Path = $fSub } }
    } | Out-Null

    Invoke-PushMgr @("-Action", "Prep", "-ConversationId", "root-chat-A") | Out-Null
    $m6 = Get-Content -Raw -Encoding UTF8 ".git\vigiles\pushprep_root-chat-A.json" | ConvertFrom-Json
    $subItem = $m6.items | Where-Object { $_.path -eq "subagent_output.txt" }

    Assert-Iso "Test 6: Alt ajanin yazdigi dosya ana sohbet (root-chat-A) adina zimmetlenir" `
        ($subItem.ownership -eq "OWNED_THIS_CHAT" -and $subItem.included) `
        "Own=$($subItem.ownership) Inc=$($subItem.included)"
} finally {
    Pop-Location
    Remove-IsoRepoPair $p6
}

# Test 7: PreToolUse Kimlik Overwrite, Dogrudan git commit Engeli & run_command Fark Yakalama
$p7 = New-IsoRepoPair
try {
    Push-Location $p7.Clone
    $denyOut = Invoke-LedgerHook @{
        hookEventName = "PreToolUse"; conversationId = "chat-cmd-1"; cwd = $p7.Clone
        toolCall = @{ id = "c1"; name = "run_command"; args = @{ CommandLine = "git commit -m 'hack'" } }
    }
    $overwriteOut = Invoke-LedgerHook @{
        hookEventName = "PreToolUse"; conversationId = "real-chat-777"; lastUserInput = "Real Chat"; cwd = $p7.Clone
        toolCall = @{ id = "c2"; name = "run_command"; args = @{ CommandLine = "powershell -File .\core\scripts\git_push_manager.ps1 -Action Prep -ConversationId fake-id" } }
    }

    # run_command oncesi/sonrasi snapshot farki
    Invoke-LedgerHook @{
        hookEventName = "PreToolUse"; conversationId = "chat-cmd-1"; lastUserInput = "Terminal Is"; cwd = $p7.Clone
        toolCall = @{ id = "cmdsnap1"; name = "run_command"; args = @{ CommandLine = "echo hi > cmd_generated.txt" } }
    } | Out-Null
    "from terminal" | Set-Content -Encoding UTF8 (Join-Path $p7.Clone "cmd_generated.txt")
    Invoke-LedgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-cmd-1"; lastUserInput = "Terminal Is"; cwd = $p7.Clone
        toolCall = @{ id = "cmdsnap1"; name = "run_command"; args = @{ CommandLine = "echo hi > cmd_generated.txt" } }
    } | Out-Null

    $l7 = Get-Content -Raw -Encoding UTF8 ".git\vigiles\file_ledger.json" | ConvertFrom-Json
    $cmdOwned = $null -ne $l7.files."cmd_generated.txt".editors."chat-cmd-1"

    $overwriteObj = $overwriteOut | ConvertFrom-Json
    $overwriteCmd = if ($overwriteObj -and $overwriteObj.overwrite) { [string]$overwriteObj.overwrite.CommandLine } else { "" }

    Assert-Iso "Test 7: Dogrudan git commit engeli, ConversationId overwrite & run_command yan etki zimmeti" `
        (($denyOut -match '"decision"\s*:\s*"deny"') -and ($overwriteCmd -match "VIGILES_CONVERSATION_ID='real-chat-777'") -and ($overwriteCmd -notmatch "fake-id") -and $cmdOwned) `
        "Deny=$denyOut OverwriteCmd=$overwriteCmd CmdOwned=$cmdOwned"
} finally {
    Pop-Location
    Remove-IsoRepoPair $p7
}

# Test 8: Baska Sohbetin Bekleyen Yerel Commit Uyarisi (commit_ledger)
$p8 = New-IsoRepoPair
try {
    Push-Location $p8.Clone
    "b1" | Set-Content -Encoding UTF8 "b_local.txt"
    & git add b_local.txt | Out-Null
    & git commit -m "feat: commit by chat B" | Out-Null
    $bSha = (& git rev-parse HEAD).Trim()

    $vig8 = Join-Path $p8.Clone ".git\vigiles"
    New-Item -ItemType Directory -Path $vig8 -Force | Out-Null
    $l8Obj = @{
        version = 1
        chats   = @{ "chat-b-owner" = @{ title = "B Sohbeti"; lastSeenAt = (Get-Date).ToString("o") } }
        files   = @{}
        commits = @{ $bSha = @{ conversationId = "chat-b-owner"; at = (Get-Date).ToString("o"); subject = "feat: commit by chat B" } }
    } | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText((Join-Path $vig8 "file_ledger.json"), $l8Obj, (New-Object System.Text.UTF8Encoding($false)))

    $fa8 = Join-Path $p8.Clone "a_new.txt"
    "a1" | Set-Content -Encoding UTF8 $fa8
    Invoke-LedgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-a-owner"; cwd = $p8.Clone
        toolCall = @{ id = "ac1"; name = "write_file"; args = @{ Path = $fa8 } }
    } | Out-Null

    Invoke-PushMgr @("-Action", "Prep", "-ConversationId", "chat-a-owner") | Out-Null
    $warnPush = Invoke-PushMgr @("-Action", "Push", "-ConversationId", "chat-a-owner", "-CommitMessage", "feat: commit by A")

    Assert-Iso "Test 8: Branch'te baska sohbetin bekleyen commit'i varsa ExitCode 2 ile uyari verir" `
        ($warnPush.ExitCode -eq 2 -and $warnPush.Output -match "DIGER SOHBET COMMIT UYARISI") `
        "Exit=$($warnPush.ExitCode) Out=$($warnPush.Output)"
} finally {
    Pop-Location
    Remove-IsoRepoPair $p8
}

# Test 9: Kaos Testi - 10 Paralel Islem (Mutex Race-Condition Korumasi)
$p9 = New-IsoRepoPair
try {
    Push-Location $p9.Clone
    $procs = [System.Collections.Generic.List[object]]::new()
    for ($k = 1; $k -le 10; $k++) {
        $fpath = Join-Path $p9.Clone "parallel_$k.txt"
        "p$k" | Set-Content -Encoding UTF8 $fpath
        $payload = @{
            hookEventName  = "PostToolUse"
            conversationId = "parallel-chat-$k"
            lastUserInput  = "Parallel Chat $k"
            cwd            = $p9.Clone
            toolCall       = @{ id = "pj_$k"; name = "write_file"; args = @{ Path = $fpath } }
        } | ConvertTo-Json -Depth 6 -Compress

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "powershell.exe"
        $pinfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ledgerHook`""
        $pinfo.RedirectStandardInput = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        $pinfo.EnvironmentVariables["VIGILES_SKIP_DB"] = "1"
        $proc = [System.Diagnostics.Process]::Start($pinfo)
        $proc.StandardInput.Write($payload)
        $proc.StandardInput.Close()
        $procs.Add($proc)
    }
    foreach ($proc in $procs) {
        $null = $proc.WaitForExit(20000)
        $null = $proc.StandardOutput.ReadToEnd()
    }

    $l9Raw = [System.IO.File]::ReadAllText((Join-Path $p9.Clone ".git\vigiles\file_ledger.json"), [System.Text.Encoding]::UTF8)
    $l9 = $l9Raw | ConvertFrom-Json
    $okCount = 0
    for ($k = 1; $k -le 10; $k++) {
        if ($l9.files."parallel_$k.txt".editors."parallel-chat-$k") { $okCount++ }
    }
    Assert-Iso "Test 9 (Kaos): 10 eszamanli yazici Mutex altinda JSON bozulmadan 10/10 kaydedilir" `
        ($okCount -eq 10) "Kaydedilen=$okCount/10"
} finally {
    Pop-Location
    Remove-IsoRepoPair $p9
}

# Test 10: Geriye Donuk Transcript Kurtarma (Import-HistoricalTranscriptEdits)
$p10 = New-IsoRepoPair
$fakeBrain = Join-Path $env:TEMP ("vig_brain_" + [System.Guid]::NewGuid().ToString().Substring(0, 8))
try {
    Push-Location $p10.Clone
    $legacyFile = Join-Path $p10.Clone "legacy_other_chat.txt"
    "legacy" | Set-Content -Encoding UTF8 $legacyFile

    $logDir = Join-Path $fakeBrain "legacy-chat-999\.system_generated\logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $trLine = @{
        step_index = 1
        tool_calls = @(@{ name = "write_file"; args = @{ Path = $legacyFile } })
    } | ConvertTo-Json -Depth 5 -Compress
    [System.IO.File]::WriteAllText((Join-Path $logDir "transcript.jsonl"), $trLine, (New-Object System.Text.UTF8Encoding($false)))

    $env:VIGILES_BRAIN_DIR = $fakeBrain
    $prepOut10 = (& powershell -NoProfile -ExecutionPolicy Bypass -File $pushMgr -Action Prep -ConversationId "current-chat-111" 2>&1 | Out-String)
    $m10 = Get-Content -Raw -Encoding UTF8 ".git\vigiles\pushprep_current-chat-111.json" | ConvertFrom-Json
    $legItem = $m10.items | Where-Object { $_.path -eq "legacy_other_chat.txt" }

    Assert-Iso "Test 10: Geriye donuk transcript.jsonl taramasi eski baska sohbeti bulup kilitler" `
        ($LASTEXITCODE -eq 0 -and $legItem.ownership -eq "LOCKED_OTHER_CHAT" -and (-not $legItem.included)) `
        "Own=$($legItem.ownership) Out=$prepOut10"
} finally {
    Remove-Item Env:\VIGILES_BRAIN_DIR -ErrorAction SilentlyContinue
    Pop-Location
    Remove-IsoRepoPair $p10
    Remove-Item -Path $fakeBrain -Recurse -Force -ErrorAction SilentlyContinue
}

# Test 11: Yargic Sertlestirmeleri (Test- iceren pushadd kimlik kilidi, zincirli git deny, DryRun sifir ledger yazimi, Rename ledger temizligi)
$p11 = New-IsoRepoPair
$fakeBrain11 = Join-Path $env:TEMP ("vig_brain11_" + [System.Guid]::NewGuid().ToString().Substring(0, 8))
try {
    Push-Location $p11.Clone
    # 11a: Argumanda 'Test-' gecse bile kimlik overwrite calismali ve -CommitMessage korunmali
    $owTestArg = Invoke-LedgerHook @{
        hookEventName = "PreToolUse"; conversationId = "chat-real-11"; cwd = $p11.Clone
        toolCall = @{ id = "h11a"; name = "run_command"; args = @{ CommandLine = 'powershell -File .\core\scripts\git_push_manager.ps1 -Action Push -CommitMessage "ozel mesaj" -Targets tests/Test-SessionPushIsolation.ps1 -Conv:fake' } }
    }
    $owCmd11 = ($owTestArg | ConvertFrom-Json).overwrite.CommandLine

    # 11b: Zincirli '; git commit', '& "git" commit' ve 'Test-X.ps1; git commit' engellenmeli
    $chainDeny = Invoke-LedgerHook @{
        hookEventName = "PreToolUse"; conversationId = "chat-real-11"; cwd = $p11.Clone
        toolCall = @{ id = "h11b"; name = "run_command"; args = @{ CommandLine = 'powershell -File .\core\scripts\git_push_manager.ps1 -Action Prep; git commit -m "sneaky"' } }
    }
    $testChainDeny = Invoke-LedgerHook @{
        hookEventName = "PreToolUse"; conversationId = "chat-real-11"; cwd = $p11.Clone
        toolCall = @{ id = "h11b2"; name = "run_command"; args = @{ CommandLine = 'powershell -File .\tests\Test-X.ps1; git commit -m "sneak"' } }
    }
    $dynDeny = Invoke-LedgerHook @{
        hookEventName = "PreToolUse"; conversationId = "chat-real-11"; cwd = $p11.Clone
        toolCall = @{ id = "h11c"; name = "run_command"; args = @{ CommandLine = '& "git" commit -m "bypass"' } }
    }

    # 11c: DryRun sirasinda Import-HistoricalTranscriptEdits file_ledger.json yazmamali
    $leg11 = Join-Path $p11.Clone "dry_legacy.txt"
    "x" | Set-Content -Encoding UTF8 $leg11
    $logDir11 = Join-Path $fakeBrain11 "other-chat-888\.system_generated\logs"
    New-Item -ItemType Directory -Path $logDir11 -Force | Out-Null
    $trLine11 = @{ step_index = 1; tool_calls = @(@{ name = "write_file"; args = @{ Path = $leg11 } }) } | ConvertTo-Json -Depth 5 -Compress
    [System.IO.File]::WriteAllText((Join-Path $logDir11 "transcript.jsonl"), $trLine11, (New-Object System.Text.UTF8Encoding($false)))
    $env:VIGILES_BRAIN_DIR = $fakeBrain11
    & powershell -NoProfile -ExecutionPolicy Bypass -File $pushMgr -Action Push -DryRun -ConversationId "chat-real-11" | Out-Null
    $dryLedgerWritten = Test-Path (Join-Path $p11.Clone ".git\vigiles\file_ledger.json")
    Remove-Item Env:\VIGILES_BRAIN_DIR -ErrorAction SilentlyContinue

    # 11d: Rename push sonrasi eski dosya adinin zimmeti de temizlenmeli
    1..5 | ForEach-Object { "row $_" } | Set-Content -Encoding UTF8 "before_mv.txt"
    & git add before_mv.txt | Out-Null
    & git commit -m "chore: before mv" | Out-Null
    & git push origin main 2>&1 | Out-Null
    & git mv before_mv.txt after_mv.txt | Out-Null
    Invoke-LedgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-real-11"; cwd = $p11.Clone
        toolCall = @{ id = "mv1"; name = "edit_file"; args = @{ Path = (Join-Path $p11.Clone "before_mv.txt") } }
    } | Out-Null
    Invoke-LedgerHook @{
        hookEventName = "PostToolUse"; conversationId = "chat-real-11"; cwd = $p11.Clone
        toolCall = @{ id = "mv2"; name = "write_file"; args = @{ Path = (Join-Path $p11.Clone "after_mv.txt") } }
    } | Out-Null
    Invoke-PushMgr @("-Action", "Prep", "-ConversationId", "chat-real-11") | Out-Null
    $pushMv = Invoke-PushMgr @("-Action", "Push", "-ConversationId", "chat-real-11", "-CommitMessage", "refactor: mv cleanup")
    $l11After = Get-Content -Raw -Encoding UTF8 ".git\vigiles\file_ledger.json" | ConvertFrom-Json
    $hasOldMv = $null -ne $l11After.files.PSObject.Properties["before_mv.txt"]
    $hasNewMv = $null -ne $l11After.files.PSObject.Properties["after_mv.txt"]

    Assert-Iso "Test 11: Yargic sertlestirmeleri (CommitMessage & Test- overwrite, zincir deny, DryRun no-ledger, Rename cleanup)" `
        (($owCmd11 -match "VIGILES_CONVERSATION_ID='chat-real-11'") -and ($owCmd11 -match '-CommitMessage "ozel mesaj"') -and ($owCmd11 -notmatch "fake") -and ($chainDeny -match '"decision"\s*:\s*"deny"') -and ($testChainDeny -match '"decision"\s*:\s*"deny"') -and ($dynDeny -match '"decision"\s*:\s*"deny"') -and (-not $dryLedgerWritten) -and $pushMv.ExitCode -eq 0 -and (-not $hasOldMv) -and (-not $hasNewMv)) `
        "OwCmd=$owCmd11 Chain=$chainDeny TestChain=$testChainDeny Dyn=$dynDeny DryLedger=$dryLedgerWritten OldMv=$hasOldMv NewMv=$hasNewMv"
} finally {
    Remove-Item Env:\VIGILES_BRAIN_DIR -ErrorAction SilentlyContinue
    Pop-Location
    Remove-IsoRepoPair $p11
    Remove-Item -Path $fakeBrain11 -Recurse -Force -ErrorAction SilentlyContinue
}

Remove-Item Env:\VIGILES_SKIP_DB -ErrorAction SilentlyContinue

Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
Write-Host "SONUC: $passed / $total Test Basariyla Gecti." -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Red" })

if ($passed -ne $total) {
    exit 1
}
