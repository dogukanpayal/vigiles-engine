# ==============================================================================
# Test-MultiSessionWorktree.ps1
# Vigiles Engine - ADR-025 Hibrit Adaptif Coklu Oturum, Worktree Yol Kalkani & /merge TDD Testi
# ==============================================================================
param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

$ws = Split-Path -Parent $PSScriptRoot
$coreScripts = Join-Path $ws "core\scripts"
$ensureScript = Join-Path $coreScripts "ensure_live_mission_control.ps1"
$sentinelScript = Join-Path $coreScripts "sentinel_guard.ps1"
$stopScript = Join-Path $coreScripts "on_mission_complete.ps1"
$sessionMgr = Join-Path $coreScripts "vigiles_session_manager.ps1"
$mergeMgr = Join-Path $coreScripts "vigiles_merge_manager.ps1"
$pushMgr = Join-Path $coreScripts "git_push_manager.ps1"

$global:passedCount = 0
$global:failedCount = 0

function Assert-Test([string]$testName, [bool]$condition, [string]$detail = "") {
    if ($condition) {
        Write-Host "  [GECTI] $testName" -ForegroundColor Green
        if ($detail) { Write-Host "     -> $detail" -ForegroundColor DarkGray }
        $global:passedCount++
    } else {
        Write-Host "  [BASARISIZ] $testName" -ForegroundColor Red
        if ($detail) { Write-Host "     -> HATA: $detail" -ForegroundColor Yellow }
        $global:failedCount++
    }
}

function Test-HasBom([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $b = [System.IO.File]::ReadAllBytes($path)
    return ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}

function Invoke-HookStdin([string]$scriptPath, [hashtable]$payloadObj) {
    $json = $payloadObj | ConvertTo-Json -Depth 8 -Compress
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "powershell.exe"
    $pinfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $pinfo.RedirectStandardInput = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.UseShellExecute = $false
    $pinfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $proc = [System.Diagnostics.Process]::Start($pinfo)
    $utf8 = [System.Text.Encoding]::UTF8.GetBytes($json)
    $proc.StandardInput.BaseStream.Write($utf8, 0, $utf8.Length)
    $proc.StandardInput.Close()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    return ($stdout -replace '[\r\n]+$', '').Trim()
}

function New-TestGitRepo([string]$rootDir, [string]$name) {
    $bare = Join-Path $rootDir "${name}_bare.git"
    & git init --bare $bare | Out-Null
    $repo = Join-Path $rootDir $name
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    Push-Location $repo
    & git init -b main | Out-Null
    & git config user.email "test@vigiles.local"
    & git config user.name "Vigiles Tester"
    & git config core.quotepath false
    & git remote add origin $bare | Out-Null
    "line1`nline2`nline3`nline4`nline5`nline6`nline7`nline8`nline9`nline10`nline11`nline12`nline13`nline14`nline15`nline16`nline17`nline18`nline19`nline20" | Set-Content -Encoding UTF8 "shared.txt"
    "to delete" | Set-Content -Encoding UTF8 "to_delete.txt"
    "conflict line 1`nconflict line 2" | Set-Content -Encoding UTF8 "conflict.txt"
    "# KURALLAR`n* [KURAL-024]: Watchdog kurali." | Set-Content -Encoding UTF8 "KURALLAR.md"
    "node_modules/`n.env" | Set-Content -Encoding UTF8 ".gitignore"
    New-Item -ItemType Directory -Path "node_modules\important_pkg" -Force | Out-Null
    "module.exports = 'CRITICAL';" | Set-Content -Encoding UTF8 "node_modules\important_pkg\index.js"
    "SECRET_DB=local_only" | Set-Content -Encoding UTF8 ".env"
    & git add shared.txt to_delete.txt conflict.txt KURALLAR.md .gitignore | Out-Null
    & git commit -m "chore: initial repo" | Out-Null
    & git push -u origin main 2>&1 | Out-Null
    Pop-Location
    return $repo
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "VIGILES TDD: COKLU OTURUM WORKTREE & KONTROLLU /MERGE" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$runId = [guid]::NewGuid().ToString("N").Substring(0, 8)
$tempBase = Join-Path ([System.IO.Path]::GetTempPath()) "vigiles_wt_tdd_$runId"
$tempCfg  = Join-Path $tempBase "cfg"
$art1     = Join-Path $tempBase "art_chat1"
$art2     = Join-Path $tempBase "art_chat2"
$art3     = Join-Path $tempBase "art_chat3"
$artProjB = Join-Path $tempBase "art_projB"
New-Item -ItemType Directory -Path $tempCfg, $art1, $art2, $art3, $artProjB -Force | Out-Null

$prevCfg = $env:VIGILES_CONFIG_DIR
$prevPort = $env:VIGILES_TELEMETRY_PORT
$env:VIGILES_CONFIG_DIR = $tempCfg
$env:VIGILES_TELEMETRY_PORT = "19989"

try {
    # TEST 1: UTF-8 BOM & Dosya Varligi
    $bomOk = (Test-HasBom $sessionMgr) -and (Test-HasBom $mergeMgr) -and (Test-HasBom $ensureScript) -and (Test-HasBom $sentinelScript) -and (Test-HasBom $stopScript) -and (Test-HasBom $pushMgr)
    $mergeSkillOk = Test-Path (Join-Path $ws "core\skills\merge\SKILL.md")
    $kurallarRaw = [System.IO.File]::ReadAllText((Join-Path $ws "KURALLAR.md"), [System.Text.Encoding]::UTF8)
    $k25Ok = ($kurallarRaw -match '\[KURAL-025\]')
    Assert-Test "1. Yeni/guncel .ps1 betikleri UTF-8 BOM, merge SKILL.md ve [KURAL-025] mevcut olmali" ($bomOk -and $mergeSkillOk -and $k25Ok) "BOM=$bomOk | MergeSkill=$mergeSkillOk | KURAL025=$k25Ok"

    $repoA = New-TestGitRepo -rootDir $tempBase -name "RepoA"
    $repoB = New-TestGitRepo -rootDir $tempBase -name "RepoB"

    # TEST 2 & 3: Ilk /pro oturumu -> MAIN_TREE + isolated state/missions/<cid>.json + active_mission.json temiz
    $cid1 = "chat-alpha-001"
    $out1 = Invoke-HookStdin $ensureScript @{
        lastUserInput = "/pro yeni ozellik gelistir"
        conversationId = $cid1
        artifactDirectoryPath = $art1
        workspacePaths = @($repoA)
        invocationNum = 1
    }
    $missionFile1 = Join-Path $tempCfg "state\missions\$cid1.json"
    $globalActiveExists = Test-Path (Join-Path $tempCfg "active_mission.json")
    $sessPtr1 = Get-Content -Raw -Encoding UTF8 (Join-Path $art1 ".vigiles_session") | ConvertFrom-Json
    $wtMarker1 = Test-Path (Join-Path $art1 ".vigiles_worktree")
    Assert-Test "2. Tek /pro oturumu MAIN_TREE olmali, state/missions/<cid>.json yazmali ve active_mission.json'i ezmemeli" `
        (($out1 -eq "{}") -and (Test-Path $missionFile1) -and -not $globalActiveExists -and $sessPtr1.mode -eq "MAIN_TREE" -and -not $wtMarker1) `
        "Out=$out1 | MissionFile=$(Test-Path $missionFile1) | ActiveJson=$globalActiveExists | Mode=$($sessPtr1.mode)"

    # TEST 4: Farkli repoda paralel /pro -> RepoB de MAIN_TREE almali (gereksiz worktree yok)
    $cidB = "chat-projB-001"
    $outB = Invoke-HookStdin $ensureScript @{
        lastUserInput = "/pro RepoB icin baska is yap"
        conversationId = $cidB
        artifactDirectoryPath = $artProjB
        workspacePaths = @($repoB)
        invocationNum = 1
    }
    $sessPtrB = Get-Content -Raw -Encoding UTF8 (Join-Path $artProjB ".vigiles_session") | ConvertFrom-Json
    Assert-Test "3. Farkli projede (RepoB) paralel /pro da MAIN_TREE olmali (sifir gereksiz worktree)" `
        ($sessPtrB.mode -eq "MAIN_TREE" -and -not (Test-Path (Join-Path $artProjB ".vigiles_worktree"))) `
        "RepoB Mode=$($sessPtrB.mode)"

    # TEST 5: Ayni repoda (RepoA) eszamanli 2. /pro -> Otomatik WORKTREE + Junction + .env + .git/info/exclude
    $cid2 = "chat-beta-002"
    $out2 = Invoke-HookStdin $ensureScript @{
        lastUserInput = "/pro ayni repoda paralel modul gelistir"
        conversationId = $cid2
        artifactDirectoryPath = $art2
        workspacePaths = @($repoA)
        invocationNum = 1
    }
    $wtMarker2Path = Join-Path $art2 ".vigiles_worktree"
    $wtPtr2 = if (Test-Path $wtMarker2Path) { Get-Content -Raw -Encoding UTF8 $wtMarker2Path | ConvertFrom-Json } else { $null }
    $wtDir2 = if ($wtPtr2) { $wtPtr2.worktreePath } else { "" }
    $wtPkgExists = if ($wtDir2) { Test-Path (Join-Path $wtDir2 "node_modules\important_pkg\index.js") } else { $false }
    $wtEnvExists = if ($wtDir2) { Test-Path (Join-Path $wtDir2 ".env") } else { $false }
    $excludeRaw = [System.IO.File]::ReadAllText((Join-Path $repoA ".git\info\exclude"), [System.Text.Encoding]::UTF8)
    $gitStatusMain = (& git -C $repoA status --porcelain 2>&1 | Out-String)

    Assert-Test "4. Ayni repoda 2. paralel /pro otomatik WORKTREE acmali, Junction/.env kurmali ve main git status temiz kalmali" `
        (($null -ne $wtPtr2) -and $wtPtr2.mode -eq "WORKTREE" -and (Test-Path $wtDir2) -and $wtPkgExists -and $wtEnvExists -and ($excludeRaw -match '\.worktrees') -and ($out2 -match 'WORKTREE AKTIF') -and [string]::IsNullOrWhiteSpace($gitStatusMain)) `
        "WT=$wtDir2 | JunctionPkg=$wtPkgExists | Env=$wtEnvExists | GitStatus='$gitStatusMain'"

    # TEST 6: Ayni sohbet cid2 tekrar /pro cagirirsa kendi mevcut worktree'sini yeniden kullanmali
    $out2Re = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sessionMgr -Action Start -ConversationId $cid2 -ArtifactDir $art2 -WorkspacePath $repoA -Json | Out-String).Trim() | ConvertFrom-Json
    Assert-Test "5. Ayni sohbet tekrar /pro baslattiginda kendi mevcut worktree'sini yeniden kullanmali" `
        ($out2Re.mode -eq "WORKTREE" -and $out2Re.reused -eq $true -and $out2Re.worktreePath -eq $wtDir2) `
        "Reused=$($out2Re.reused) | WT=$($out2Re.worktreePath)"

    # TEST 7: sentinel_guard Path Guard -> Ana klasore yazma DENY, worktree'ye ve art2/DURUM.md'ye ALLOW
    $denyMainRes = Invoke-HookStdin $sentinelScript @{
        conversationId = $cid2
        artifactDirectoryPath = $art2
        workspacePaths = @($repoA)
        toolCall = @{ name = "write_file"; args = @{ Path = (Join-Path $repoA "shared.txt"); Content = "bad write" } }
    }
    $allowWtRes = Invoke-HookStdin $sentinelScript @{
        conversationId = $cid2
        artifactDirectoryPath = $art2
        workspacePaths = @($repoA)
        toolCall = @{ name = "write_file"; args = @{ Path = (Join-Path $wtDir2 "new_feature.txt"); Content = "ok feature" } }
    }
    $allowDurumRes = Invoke-HookStdin $sentinelScript @{
        conversationId = $cid2
        artifactDirectoryPath = $art2
        workspacePaths = @($repoA)
        toolCall = @{ name = "write_file"; args = @{ Path = (Join-Path $art2 "DURUM.md"); Content = "# Plan" } }
    }
    Assert-Test "6. Path Guard: WORKTREE oturumu ana klasore yazamaz (deny + yonlendirme), worktree & artifact/DURUM.md yazabilir" `
        (($denyMainRes -match '"decision"\s*:\s*"deny"') -and ($denyMainRes -match 'YOL KALKANI') -and ($allowWtRes -match '"decision"\s*:\s*"allow"') -and ($allowDurumRes -match '"decision"\s*:\s*"allow"')) `
        "DenyMain=$($denyMainRes -match 'deny') | AllowWT=$($allowWtRes -match 'allow') | AllowDurum=$($allowDurumRes -match 'allow')"

    # TEST 8: sentinel_guard install.ps1 engeli (exec -> deny, Get-Content -> allow)
    $denyInstall = Invoke-HookStdin $sentinelScript @{
        conversationId = $cid2
        artifactDirectoryPath = $art2
        workspacePaths = @($repoA)
        toolCall = @{ name = "run_command"; args = @{ CommandLine = "powershell -File .\install.ps1" } }
    }
    $allowReadInstall = Invoke-HookStdin $sentinelScript @{
        conversationId = $cid2
        artifactDirectoryPath = $art2
        workspacePaths = @($repoA)
        toolCall = @{ name = "run_command"; args = @{ CommandLine = "Get-Content .\install.ps1" } }
    }
    Assert-Test "7. Izole worktree'de install.ps1 calistirmak engellenmeli, okumak serbest olmali" `
        (($denyInstall -match '"decision"\s*:\s*"deny"') -and ($allowReadInstall -match '"decision"\s*:\s*"allow"')) `
        "DenyExec=$($denyInstall -match 'deny') | AllowRead=$($allowReadInstall -match 'allow')"

    # TEST 9: Gercek eszamanli degisiklikler + git_push_manager bilgi bandi + Kontrollu /merge
    # Chat 1 (Main) degisiklikleri (uncommitted!):
    "dirty main file" | Set-Content -Encoding UTF8 (Join-Path $repoA "dirty_only_main.txt")
    "MAIN_LINE_1`nline2`nline3`nline4`nline5`nline6`nline7`nline8`nline9`nline10`nline11`nline12`nline13`nline14`nline15`nline16`nline17`nline18`nline19`nline20" | Set-Content -Encoding UTF8 (Join-Path $repoA "shared.txt")
    "# KURALLAR`n* [KURAL-024]: Watchdog kurali.`n* [KURAL-025]: Ana sohbet kurali." | Set-Content -Encoding UTF8 (Join-Path $repoA "KURALLAR.md")

    # Chat 2 (Worktree) degisiklikleri (uncommitted!):
    "new feature from parallel chat" | Set-Content -Encoding UTF8 (Join-Path $wtDir2 "new_feature.txt")
    Remove-Item -LiteralPath (Join-Path $wtDir2 "to_delete.txt") -Force
    "line1`nline2`nline3`nline4`nline5`nline6`nline7`nline8`nline9`nline10`nline11`nline12`nline13`nline14`nline15`nline16`nline17`nline18`nline19`nWORKTREE_LINE_20" | Set-Content -Encoding UTF8 (Join-Path $wtDir2 "shared.txt")
    "# KURALLAR`n* [KURAL-024]: Watchdog kurali.`n* [KURAL-025]: Paralel sohbet kurali." | Set-Content -Encoding UTF8 (Join-Path $wtDir2 "KURALLAR.md")

    # Stop hook cagir (Chat 2 -> READY_TO_MERGE)
    $null = Invoke-HookStdin $stopScript @{ conversationId = $cid2; artifactDirectoryPath = $art2 }
    $sess2AfterStop = Get-Content -Raw -Encoding UTF8 $wtPtr2.sessionFile | ConvertFrom-Json

    # PushPrep bilgi bandi ve .worktrees dislama kontrolu
    Push-Location $repoA
    $prepOut = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $pushMgr -Action Prep 2>&1 | Out-String)
    Pop-Location
    $prepHasNotice = ($prepOut -match 'PARALEL SANTIYE') -and ($prepOut -notmatch '\.worktrees/pro-')

    Assert-Test "8. Stop hook READY_TO_MERGE yapmali ve /pushprep .worktrees'i dislayip /merge bilgi bandi gostermeli" `
        ($sess2AfterStop.status -eq "READY_TO_MERGE" -and $prepHasNotice) `
        "Status=$($sess2AfterStop.status) | PrepNotice=$prepHasNotice | Out=$($prepOut.Trim())"

    # TEST 10: Zorunlu Onizleme Kapisi (-Approved olmadan /merge ExitCode 2 donmeli)
    $gateOut = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mergeMgr -Action Merge -WorkspacePath $repoA 2>&1 | Out-String)
    $gateExit = $LASTEXITCODE
    Assert-Test "9. Kontrollu /merge kapisi: -Approved olmadan ExitCode 2 donmeli ve yeni dosya henuz main'e gecmemeli" `
        ($gateExit -eq 2 -and -not (Test-Path (Join-Path $repoA "new_feature.txt"))) `
        "Exit=$gateExit | GateOut=$($gateOut.Trim())"

    # TEST 11: Onayli 3-Way /merge + KURALLAR.md renumbering + Junction hedef koruma
    $mergeOut = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mergeMgr -Action Merge -WorkspacePath $repoA -Approved 2>&1 | Out-String)
    $mergeExit = $LASTEXITCODE

    $sharedMerged = [System.IO.File]::ReadAllText((Join-Path $repoA "shared.txt"), [System.Text.Encoding]::UTF8)
    $kurallarMerged = [System.IO.File]::ReadAllText((Join-Path $repoA "KURALLAR.md"), [System.Text.Encoding]::UTF8)
    $mainPkgIntact = Test-Path (Join-Path $repoA "node_modules\important_pkg\index.js")
    $wtRemoved = -not (Test-Path $wtDir2)

    $okMerge = ($mergeExit -eq 0) -and
               (Test-Path (Join-Path $repoA "new_feature.txt")) -and
               (Test-Path (Join-Path $repoA "dirty_only_main.txt")) -and
               (-not (Test-Path (Join-Path $repoA "to_delete.txt"))) -and
               ($sharedMerged -match 'MAIN_LINE_1') -and ($sharedMerged -match 'WORKTREE_LINE_20') -and ($sharedMerged -notmatch '<<<<<<<') -and
               ($kurallarMerged -match '\[KURAL-025\]: Ana sohbet kurali\.') -and ($kurallarMerged -match '\[KURAL-026\]: Paralel sohbet kurali\.') -and
               $mainPkgIntact -and $wtRemoved

    Assert-Test "10. Onayli 3-Way /merge ortak dosyayi, KURALLAR renumbering'i (025+026), temizligi ve node_modules korumasini basarmali" `
        $okMerge `
        "Exit=$mergeExit | PkgIntact=$mainPkgIntact | WTRemoved=$wtRemoved | MergeOut=$($mergeOut.Trim())"

    # TEST 12: 15dk TTL Zombi Kilit Dusurme (Chat 1'in nabzini 20dk geriye cek -> Chat 3 MAIN_TREE almali)
    $s1Obj = Get-Content -Raw -Encoding UTF8 $sessPtr1.sessionFile | ConvertFrom-Json
    $s1Obj.lastHeartbeatAt = ([datetimeoffset]::UtcNow.AddMinutes(-20)).ToString("o")
    $s1Obj.status = "ACTIVE"
    [System.IO.File]::WriteAllText($sessPtr1.sessionFile, ($s1Obj | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

    $cid3 = "chat-gamma-003"
    $null = Invoke-HookStdin $ensureScript @{
        lastUserInput = "/pro bayat kilit sonrasi basla"
        conversationId = $cid3
        artifactDirectoryPath = $art3
        workspacePaths = @($repoA)
        invocationNum = 1
    }
    $s1After = Get-Content -Raw -Encoding UTF8 $sessPtr1.sessionFile | ConvertFrom-Json
    $s3Ptr = Get-Content -Raw -Encoding UTF8 (Join-Path $art3 ".vigiles_session") | ConvertFrom-Json
    Assert-Test "11. 15dk TTL asildiginda eski kilit STALE olmali ve yeni /pro MAIN_TREE alabilmeli" `
        ($s1After.status -eq "STALE" -and $s3Ptr.mode -eq "MAIN_TREE") `
        "Chat1Status=$($s1After.status) | Chat3Mode=$($s3Ptr.mode)"

    # TEST 13: Hard Cakisma Guvenligi (Ayni satirda cakisma -> ExitCode 3, Main bozulmaz, --abort temizler)
    $cid4 = "chat-conflict-004"
    $art4 = Join-Path $tempBase "art_chat4"
    New-Item -ItemType Directory -Path $art4 -Force | Out-Null
    $null = Invoke-HookStdin $ensureScript @{
        lastUserInput = "/pro cakisma testi"
        conversationId = $cid4
        artifactDirectoryPath = $art4
        workspacePaths = @($repoA)
        invocationNum = 1
    }
    $wt4Ptr = Get-Content -Raw -Encoding UTF8 (Join-Path $art4 ".vigiles_worktree") | ConvertFrom-Json
    "MAIN_SAME_LINE_EDIT`nconflict line 2" | Set-Content -Encoding UTF8 (Join-Path $repoA "conflict.txt")
    "WT_SAME_LINE_EDIT`nconflict line 2" | Set-Content -Encoding UTF8 (Join-Path $wt4Ptr.worktreePath "conflict.txt")

    $confOut = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mergeMgr -Action Merge -WorkspacePath $repoA -Target $wt4Ptr.shortId -Approved 2>&1 | Out-String)
    $confExit = $LASTEXITCODE
    $mainConflictText = [System.IO.File]::ReadAllText((Join-Path $repoA "conflict.txt"), [System.Text.Encoding]::UTF8)

    $abortOut = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mergeMgr -Action Abort -WorkspacePath $repoA -Target $wt4Ptr.shortId -Approved 2>&1 | Out-String)
    $abortExit = $LASTEXITCODE

    Assert-Test "12. Ayni satir cakismasinda ExitCode 3 donmeli, main bozulmamali ve /merge --abort temizlemeli" `
        ($confExit -eq 3 -and $mainConflictText -match 'MAIN_SAME_LINE_EDIT' -and $mainConflictText -notmatch '<<<<<<<' -and $abortExit -eq 0 -and -not (Test-Path $wt4Ptr.worktreePath)) `
        "ConfExit=$confExit | AbortExit=$abortExit | WtExists=$(Test-Path $wt4Ptr.worktreePath)"

} catch {
    Assert-Test "Beklenmeyen Test Hatasi Olmamali" $false $_.Exception.Message
} finally {
    $env:VIGILES_CONFIG_DIR = $prevCfg
    $env:VIGILES_TELEMETRY_PORT = $prevPort
    Remove-Item -Path $tempBase -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
$color = if ($global:failedCount -eq 0) { "Green" } else { "Red" }
Write-Host "SONUC: $global:passedCount Gecti | $global:failedCount Basarisiz" -ForegroundColor $color
Write-Host "==========================================================" -ForegroundColor Cyan

if ($global:failedCount -gt 0) { exit 1 } else { exit 0 }
