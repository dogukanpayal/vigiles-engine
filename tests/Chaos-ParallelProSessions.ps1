# ==============================================================================
# Chaos-ParallelProSessions.ps1
# Vigiles Engine - Eszamanli /pro Yaris Durumu, On Ek Carpismasi & Zero-Leak Kaos Testi
# ==============================================================================
param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Continue"

$ws = Split-Path -Parent $PSScriptRoot
$coreScripts = Join-Path $ws "core\scripts"
$ensureScript = Join-Path $coreScripts "ensure_live_mission_control.ps1"
$sessionMgr = Join-Path $coreScripts "vigiles_session_manager.ps1"
$mergeMgr = Join-Path $coreScripts "vigiles_merge_manager.ps1"

$global:passed = 0
$global:failed = 0

function Assert-Chaos([string]$name, [bool]$cond, [string]$detail = "") {
    if ($cond) {
        Write-Host "  [PUSKURTULDU] $name" -ForegroundColor Green
        if ($detail) { Write-Host "     -> $detail" -ForegroundColor DarkGray }
        $global:passed++
    } else {
        Write-Host "  [COKTU] $name" -ForegroundColor Red
        if ($detail) { Write-Host "     -> HATA: $detail" -ForegroundColor Yellow }
        $global:failed++
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "VIGILES KAOS: ESZAMANLI /PRO YARIS & STRES TESTI" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

$runId = [guid]::NewGuid().ToString("N").Substring(0, 8)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "vigiles_chaos_parallel_$runId"
$tempCfg = Join-Path $tempRoot "cfg"
New-Item -ItemType Directory -Path $tempRoot, $tempCfg -Force | Out-Null

$prevCfg = $env:VIGILES_CONFIG_DIR
$env:VIGILES_CONFIG_DIR = $tempCfg

try {
    # 1. Eszamanli 4 /pro firtinasi (Ayni anda Mutex yarisina sok!)
    $repo = Join-Path $tempRoot "StormRepo"
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    Push-Location $repo
    & git init -b main | Out-Null
    & git config user.email "chaos@vigiles.local"
    & git config user.name "Chaos Monkey"
    & git config core.quotepath false
    "init" | Set-Content -Encoding UTF8 "README.md"
    & git add README.md | Out-Null
    & git commit -m "chore: init" | Out-Null
    Pop-Location

    $procs = @()
    $cids = @(
        "parallel-storm-shared-prefix-001",
        "parallel-storm-shared-prefix-002",
        "parallel-storm-shared-prefix-003",
        "parallel-storm-shared-prefix-004"
    )
    $arts = @()
    foreach ($cid in $cids) {
        $art = Join-Path $tempRoot "art_$cid"
        New-Item -ItemType Directory -Path $art -Force | Out-Null
        $arts += $art
        $jsonPayload = (@{
            lastUserInput = "/pro eszamanli firtina testi"
            conversationId = $cid
            artifactDirectoryPath = $art
            workspacePaths = @($repo)
            invocationNum = 1
        } | ConvertTo-Json -Depth 5 -Compress)

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = "powershell.exe"
        $pinfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ensureScript`""
        $pinfo.RedirectStandardInput = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        $p = [System.Diagnostics.Process]::Start($pinfo)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonPayload)
        $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $p.StandardInput.Close()
        $null = $p.StandardOutput.ReadToEndAsync()
        $null = $p.StandardError.ReadToEndAsync()
        $procs += $p
    }

    foreach ($p in $procs) {
        $null = $p.WaitForExit(20000)
    }

    $mainCount = 0
    $wtCount = 0
    $wtPaths = @{}
    for ($i = 0; $i -lt $cids.Count; $i++) {
        $spPath = Join-Path $arts[$i] ".vigiles_session"
        if (Test-Path $spPath) {
            $sp = Get-Content -Raw -Encoding UTF8 $spPath | ConvertFrom-Json
            if ($sp.mode -eq "MAIN_TREE") { $mainCount++ }
            elseif ($sp.mode -eq "WORKTREE") {
                $wtCount++
                $wtPaths[$sp.worktreePath] = $true
            }
        }
    }

    Assert-Chaos "1. 4 Eszamanli /pro + Ayni On-Ekli ID'ler: Tam 1 MAIN_TREE + 3 Benzersiz WORKTREE olmali" `
        ($mainCount -eq 1 -and $wtCount -eq 3 -and $wtPaths.Count -eq 3) `
        "Main=$mainCount | Worktrees=$wtCount | UniqueWT=$($wtPaths.Count)"

    # 2. Zero-Leak engeli + Turkce dosya adi ile /merge testi
    $wt1 = ($wtPaths.Keys | Select-Object -First 1)
    $fakeSecret = ("ghp_" + ("AbCdEf123456" * 3))
    "const token = '$fakeSecret';" | Set-Content -Encoding UTF8 (Join-Path $wt1 "leak_test.js")

    $leakMergeOut = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mergeMgr -Action Merge -WorkspacePath $repo -Target (Split-Path $wt1 -Leaf) -Approved 2>&1 | Out-String)
    $leakExit = $LASTEXITCODE
    Assert-Chaos "2. Zero-Leak Kaos: Worktree'deki gizli token ana klasore birlestirilmeden ExitCode 1 ile bloke edilmeli" `
        ($leakExit -eq 1 -and -not (Test-Path (Join-Path $repo "leak_test.js"))) `
        "Exit=$leakExit | LeakExistsOnMain=$(Test-Path (Join-Path $repo 'leak_test.js'))"

    # Sizinli dosyayi temizleyip Turkce dosya adini birlestir
    Remove-Item -LiteralPath (Join-Path $wt1 "leak_test.js") -Force
    "Turkce icerik: I S G O U C" | Set-Content -Encoding UTF8 (Join-Path $wt1 "santiye_ozet_şğüöç.txt")
    $trMergeOut = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mergeMgr -Action Merge -WorkspacePath $repo -Target (Split-Path $wt1 -Leaf) -Approved 2>&1 | Out-String)
    $trExit = $LASTEXITCODE
    $trOnMain = Test-Path (Join-Path $repo "santiye_ozet_şğüöç.txt")
    Assert-Chaos "3. Turkce UTF-8 dosya adi worktree'den ana klasore kayipsiz aktarilmali" `
        ($trExit -eq 0 -and $trOnMain) `
        "Exit=$trExit | ExistsOnMain=$trOnMain"

    # 4. Unborn HEAD (sifir commit'li bos repo) guvenli fallback
    $emptyRepo = Join-Path $tempRoot "UnbornRepo"
    New-Item -ItemType Directory -Path $emptyRepo -Force | Out-Null
    Push-Location $emptyRepo
    & git init -b main | Out-Null
    Pop-Location
    $artUnborn = Join-Path $tempRoot "art_unborn"
    New-Item -ItemType Directory -Path $artUnborn -Force | Out-Null
    $unbornRes = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sessionMgr -Action Start -ConversationId "unborn-cid-1" -ArtifactDir $artUnborn -WorkspacePath $emptyRepo -ForceWorktree -Json 2>&1 | Out-String).Trim() | ConvertFrom-Json
    Assert-Chaos "4. Sifir commit'li (UNBORN HEAD) repoda cakilmadan MAIN_TREE fallback calismali" `
        ($unbornRes.isGitRepo -eq $true -and $unbornRes.mode -eq "MAIN_TREE") `
        "Mode=$($unbornRes.mode)"

} catch {
    Assert-Chaos "Beklenmeyen Kaos Istisnasi Olmamali" $false $_.Exception.Message
} finally {
    $env:VIGILES_CONFIG_DIR = $prevCfg
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
$col = if ($global:failed -eq 0) { "Green" } else { "Red" }
Write-Host "KAOS SONUCU: $global:passed Puskurtuldu | $global:failed Coktu" -ForegroundColor $col
Write-Host "==========================================================" -ForegroundColor Cyan

if ($global:failed -gt 0) { exit 1 } else { exit 0 }
