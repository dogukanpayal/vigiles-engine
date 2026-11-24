# ==============================================================================
# Test-CommandWatchdog.ps1
# Vigiles Command Watchdog & Akilli Nabiz Olcer OS Surec Giyotini TDD + Kaos Testi
# ==============================================================================
param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$global:passedCount = 0
$global:failedCount = 0

function Assert-Test([string]$testName, [bool]$condition, [string]$detail = "") {
    if ($condition) {
        Write-Host "  [GECTI] $testName" -ForegroundColor Green
        $global:passedCount++
    } else {
        Write-Host "  [BASARISIZ] $testName" -ForegroundColor Red
        if ($detail) { Write-Host "     -> HATA: $detail" -ForegroundColor Yellow }
        $global:failedCount++
    }
}

function Read-Utf8Text([string]$path) {
    if (-not (Test-Path $path)) { return "" }
    return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
}

function Test-HasUtf8Bom([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    return ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
}

function Invoke-HookJson([string]$scriptPath, [hashtable]$payloadObj) {
    if (-not (Test-Path $scriptPath)) {
        return @{ ExitCode = -1; Stdout = ""; Json = $null }
    }
    $json = $payloadObj | ConvertTo-Json -Depth 8 -Compress
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "powershell.exe"
    $pinfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $pinfo.RedirectStandardInput = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.RedirectStandardError = $true
    $pinfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $pinfo.UseShellExecute = $false

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
    return @{
        ExitCode = $proc.ExitCode
        Stdout   = $trimmed
        Json     = $parsed
    }
}

function Invoke-TimeoutWrapper(
    [string]$wrapperPath,
    [string]$commandLine,
    [int]$idleSec = 3,
    [int]$hardSec = 10,
    [string]$cwd = ""
) {
    if (-not (Test-Path $wrapperPath)) {
        return @{ ExitCode = -1; Output = "MISSING_WRAPPER"; ElapsedSec = 0 }
    }
    $payloadDir = Join-Path ([System.IO.Path]::GetTempPath()) "vigiles_watchdog_test_payloads"
    if (-not (Test-Path $payloadDir)) { New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null }
    $payloadFile = Join-Path $payloadDir ("test_" + [System.Guid]::NewGuid().ToString("N") + ".json")
    $payloadObj = @{
        command        = $commandLine
        cwd            = if ([string]::IsNullOrWhiteSpace($cwd)) { (Get-Location).Path } else { $cwd }
        idleTimeoutSec = $idleSec
        hardTimeoutSec = $hardSec
        pollIntervalMs = 300
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($payloadFile, ($payloadObj | ConvertTo-Json -Depth 4 -Compress), $utf8NoBom)

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $outLines = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrapperPath -PayloadFile $payloadFile 2>&1
    $exitCode = $LASTEXITCODE
    $sw.Stop()

    return @{
        ExitCode   = $exitCode
        Output     = ($outLines | Out-String)
        ElapsedSec = $sw.Elapsed.TotalSeconds
        PayloadExistsAfter = (Test-Path $payloadFile)
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "VIGILES TDD & KAOS: COMMAND WATCHDOG & OS GIYOTIN TESTI" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$ws = Split-Path -Parent $PSScriptRoot
$globalConfig = Join-Path $HOME ".gemini\config"
$coreWatchdog = Join-Path $ws "core\scripts\command_watchdog.ps1"
$coreWrapper = Join-Path $ws "core\scripts\invoke_with_timeout.ps1"
$globalWatchdog = Join-Path $globalConfig "scripts\command_watchdog.ps1"
$globalWrapper = Join-Path $globalConfig "scripts\invoke_with_timeout.ps1"
$coreSentinel = Join-Path $ws "core\scripts\sentinel_guard.ps1"
$coreHooks = Join-Path $ws "core\hooks.json"
$globalHooks = Join-Path $globalConfig "hooks.json"

# ------------------------------------------------------------------------------
# GRUP 1: Dosya Varligi, UTF-8 BOM, hooks.json & Core <-> Global Senkronizasyonu
# ------------------------------------------------------------------------------
Write-Host "`n[Grup 1: Dosya Varligi, UTF-8 BOM & hooks.json]" -ForegroundColor Yellow

Assert-Test "core/scripts/command_watchdog.ps1 mevcut ve UTF-8 BOM'lu olmali" `
    ((Test-Path $coreWatchdog) -and (Test-HasUtf8Bom $coreWatchdog)) `
    "Var=$(Test-Path $coreWatchdog) | BOM=$(Test-HasUtf8Bom $coreWatchdog)"

Assert-Test "core/scripts/invoke_with_timeout.ps1 mevcut ve UTF-8 BOM'lu olmali" `
    ((Test-Path $coreWrapper) -and (Test-HasUtf8Bom $coreWrapper)) `
    "Var=$(Test-Path $coreWrapper) | BOM=$(Test-HasUtf8Bom $coreWrapper)"

$coreHooksRaw = Read-Utf8Text $coreHooks
$globalHooksRaw = Read-Utf8Text $globalHooks
Assert-Test "core/hooks.json command-watchdog PreToolUse (run_command) kaydi icermeli ve tasinabilir olmali" `
    (($coreHooksRaw -match 'command-watchdog') -and ($coreHooksRaw -match 'command_watchdog\.ps1') -and ($coreHooksRaw -match '%USERPROFILE%')) `
    "core/hooks.json icinde command-watchdog veya %USERPROFILE% eksik"

$syncOk = (Test-Path $globalWatchdog) -and (Test-Path $globalWrapper) -and
          ((Get-FileHash $coreWatchdog -Algorithm SHA256).Hash -eq (Get-FileHash $globalWatchdog -Algorithm SHA256).Hash) -and
          ((Get-FileHash $coreWrapper -Algorithm SHA256).Hash -eq (Get-FileHash $globalWrapper -Algorithm SHA256).Hash) -and
          ($globalHooksRaw -match 'command-watchdog')
Assert-Test "Global ~/.gemini/config ile Core script & hooks senkronizasyonu eslesmeli" `
    $syncOk "install.ps1 calistirilmali veya hash eslesmiyor"

# ------------------------------------------------------------------------------
# GRUP 2: Katman 1 - Interaktif / Watch / REPL Tuzak Engelleme & False-Positive Testi
# ------------------------------------------------------------------------------
Write-Host "`n[Grup 2: Katman 1 - Tuzak Engelleme (deny) & False-Positive Kontrolu]" -ForegroundColor Yellow

$runId = [System.Guid]::NewGuid().ToString("N").Substring(0, 8)
$tempBase = Join-Path ([System.IO.Path]::GetTempPath()) "vigiles_watchdog_suite_$runId"
$plainArtifactDir = Join-Path $tempBase "plain_chat"
$vigilesArtifactDir = Join-Path $tempBase "vigiles_chat"
$thinkStateDir = Join-Path $globalConfig "state\think_readonly"
$testThinkCid = "test-watchdog-think-$runId"
$testThinkModeFile = Join-Path $thinkStateDir "$testThinkCid.mode"

New-Item -ItemType Directory -Path $plainArtifactDir, $vigilesArtifactDir -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $vigilesArtifactDir ".vigiles_active"), "vigiles", [System.Text.Encoding]::UTF8)

try {
    $denyCases = @(
        @{ Name = "vitest (run bayragi olmadan)"; Cmd = "npx vitest"; IsDaemon = $false },
        @{ Name = "jest --watch"; Cmd = "npx jest --watch"; IsDaemon = $false },
        @{ Name = "git commit (-m / --no-edit olmadan)"; Cmd = "git commit"; IsDaemon = $false },
        @{ Name = "git rebase -i (interaktif)"; Cmd = "git rebase -i HEAD~3"; IsDaemon = $false },
        @{ Name = "PowerShell Read-Host"; Cmd = "Read-Host 'Devam edilsin mi?'"; IsDaemon = $false },
        @{ Name = "cmd pause"; Cmd = "pause"; IsDaemon = $false },
        @{ Name = "Argumansiz node REPL"; Cmd = "node"; IsDaemon = $false },
        @{ Name = "Argumansiz python REPL"; Cmd = "python"; IsDaemon = $false },
        @{ Name = "IsDaemon:false ile npm run dev"; Cmd = "npm run dev"; IsDaemon = $false }
    )

    foreach ($tc in $denyCases) {
        $res = Invoke-HookJson $coreWatchdog @{
            conversationId        = "wd-deny-$runId"
            artifactDirectoryPath = $plainArtifactDir
            toolCall              = @{
                name = "run_command"
                args = @{ CommandLine = $tc.Cmd; IsDaemon = $tc.IsDaemon }
            }
        }
        $isDenied = ($res.Json -and $res.Json.decision -eq "deny")
        Assert-Test "Tuzak Engeli ($($tc.Name)) -> deny" $isDenied "Stdout=$($res.Stdout)"
    }

    # False-positive ve IsDaemon:true izin testleri
    $resRg = Invoke-HookJson $coreWatchdog @{
        conversationId        = "wd-fp-$runId"
        artifactDirectoryPath = $plainArtifactDir
        toolCall              = @{
            name = "run_command"
            args = @{ CommandLine = 'rg "Read-Host|vitest|pause" core/'; IsDaemon = $false }
        }
    }
    Assert-Test "False-Positive Onlemi: rg 'Read-Host|vitest|pause' -> allow ve sarmalanmamali" `
        ($resRg.Json -and $resRg.Json.decision -eq "allow" -and (-not $resRg.Json.overwrite -or -not $resRg.Json.overwrite.CommandLine) -and ($resRg.Json.overwrite.NotificationTimeoutSeconds -eq 15)) `
        "Stdout=$($resRg.Stdout)"

    $resDaemon = Invoke-HookJson $coreWatchdog @{
        conversationId        = "wd-daemon-$runId"
        artifactDirectoryPath = $plainArtifactDir
        toolCall              = @{
            name = "run_command"
            args = @{ CommandLine = "npm run dev"; IsDaemon = $true }
        }
    }
    Assert-Test "IsDaemon:true dev server -> allow ve CommandLine degistirilmemeli" `
        ($resDaemon.Json -and $resDaemon.Json.decision -eq "allow" -and (-not $resDaemon.Json.overwrite)) `
        "Stdout=$($resDaemon.Stdout)"

    $resVitestRun = Invoke-HookJson $coreWatchdog @{
        conversationId        = "wd-vrun-$runId"
        artifactDirectoryPath = $plainArtifactDir
        toolCall              = @{
            name = "run_command"
            args = @{ CommandLine = "npx vitest run"; IsDaemon = $false }
        }
    }
    Assert-Test "vitest run -> allow + NotificationTimeoutSeconds=90 + sarmalanmis olmali" `
        ($resVitestRun.Json -and $resVitestRun.Json.decision -eq "allow" -and $resVitestRun.Json.overwrite.NotificationTimeoutSeconds -eq 90 -and $resVitestRun.Json.overwrite.CommandLine -match 'invoke_with_timeout\.ps1') `
        "Stdout=$($resVitestRun.Stdout)"

    # --------------------------------------------------------------------------
    # GRUP 3: Katman 2, [KURAL-019] Duz Sohbet Izolasyonu & /thinkdeep Uyumu
    # --------------------------------------------------------------------------
    Write-Host "`n[Grup 3: Katman 2, KURAL-019 Duz Sohbet & /thinkdeep Uyumu]" -ForegroundColor Yellow

    $resPlainExec = Invoke-HookJson $coreWatchdog @{
        conversationId        = "wd-plain-exec-$runId"
        artifactDirectoryPath = $plainArtifactDir
        toolCall              = @{
            name = "run_command"
            args = @{ CommandLine = "node app.js" }
        }
    }
    $plainStateCreated = (Test-Path (Join-Path $plainArtifactDir "live_state.json")) -or (Test-Path (Join-Path $plainArtifactDir "live_events.jsonl"))
    Assert-Test "Duz sohbette koruma calismali (sarmala + 45s) AMA telemetri dosyasi olusturmamali (KURAL-019)" `
        ($resPlainExec.Json -and $resPlainExec.Json.decision -eq "allow" -and $resPlainExec.Json.overwrite.NotificationTimeoutSeconds -eq 45 -and ($resPlainExec.Json.overwrite.CommandLine -match 'invoke_with_timeout\.ps1') -and (-not $plainStateCreated)) `
        "StateCreated=$plainStateCreated | Stdout=$($resPlainExec.Stdout)"

    # Soyle olusturulmus payload dosyalarini temizle
    if ($resVitestRun.Json -and $resVitestRun.Json.overwrite.CommandLine -match '-PayloadFile\s+"([^"]+)"') {
        Remove-Item $matches[1] -Force -ErrorAction SilentlyContinue
    }
    if ($resPlainExec.Json -and $resPlainExec.Json.overwrite.CommandLine -match '-PayloadFile\s+"([^"]+)"') {
        Remove-Item $matches[1] -Force -ErrorAction SilentlyContinue
    }

    # Mevcut kullanici NotificationTimeoutSeconds korunmali
    $resPreserve = Invoke-HookJson $coreWatchdog @{
        conversationId        = "wd-preserve-$runId"
        artifactDirectoryPath = $plainArtifactDir
        toolCall              = @{
            name = "run_command"
            args = @{ CommandLine = "git status"; NotificationTimeoutSeconds = 12 }
        }
    }
    Assert-Test "git status -> hizli salt-okunur bypass + mevcut 12s timeout korunmali" `
        ($resPreserve.Json -and $resPreserve.Json.decision -eq "allow" -and (-not $resPreserve.Json.overwrite)) `
        "Stdout=$($resPreserve.Stdout)"

    # /thinkdeep modu uyumu
    if (-not (Test-Path $thinkStateDir)) { New-Item -ItemType Directory -Path $thinkStateDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($testThinkModeFile, "thinkdeep", [System.Text.Encoding]::UTF8)
    $resThink = Invoke-HookJson $coreWatchdog @{
        conversationId        = $testThinkCid
        artifactDirectoryPath = $plainArtifactDir
        lastUserInput         = "Devam edip kod tabanini analiz et"
        toolCall              = @{
            name = "run_command"
            args = @{ CommandLine = "git log -n 5 --oneline" }
        }
    }
    Assert-Test "/thinkdeep oturumunda CommandLine ASLA sarmalanmamali (think_readonly_guard uyumu)" `
        ($resThink.Json -and $resThink.Json.decision -eq "allow" -and (-not $resThink.Json.overwrite.CommandLine) -and ($resThink.Json.overwrite.NotificationTimeoutSeconds -eq 15)) `
        "Stdout=$($resThink.Stdout)"
    Remove-Item $testThinkModeFile -Force -ErrorAction SilentlyContinue

    # --------------------------------------------------------------------------
    # GRUP 4: Katman 3 - Gercek invoke_with_timeout.ps1, Nabiz Olcer & OS Giyotin Kaos Testleri
    # --------------------------------------------------------------------------
    Write-Host "`n[Grup 4: Gercek OS Surec Agaci Giyotini & Akilli Nabiz Olcer Testleri]" -ForegroundColor Yellow

    # 4a. Basarili hizli komut + Karmasik Tirnak / Turkce / Exit Code 7 korumasi
    $r4a = Invoke-TimeoutWrapper -wrapperPath $coreWrapper -commandLine 'Write-Output "Merhaba ŞİĞÜÖÇ ''tek'' ve `"cift`""; exit 7' -idleSec 4 -hardSec 10
    Assert-Test "4a. Karmasik tirnak, Turkce karakter ve ExitCode 7 kayipsiz korunmali & payload silinmeli" `
        ($r4a.ExitCode -eq 7 -and $r4a.Output -match 'Merhaba ŞİĞÜÖÇ' -and (-not $r4a.PayloadExistsAfter)) `
        "Exit=$($r4a.ExitCode) | PayloadLeft=$($r4a.PayloadExistsAfter)"

    # 4b. Kapali Stdin Zirhi (Read-Host / In.ReadLine aninda gecmeli)
    $r4b = Invoke-TimeoutWrapper -wrapperPath $coreWrapper -commandLine '$v = [Console]::In.ReadLine(); Write-Output "EOF_OK"' -idleSec 5 -hardSec 10
    Assert-Test "4b. Kapali stdin zirhi ile interaktif girdi beklemeden aninda cikmali (<4s)" `
        ($r4b.ElapsedSec -lt 4.0 -and $r4b.Output -match 'EOF_OK') `
        "Elapsed=$([math]::Round($r4b.ElapsedSec, 2))s | Exit=$($r4b.ExitCode)"

    # 4c. Aktif Log Akisi (Idle=2s iken her 0.5s'de 6 kez log basan ~3s is OLMEMELI)
    $r4c = Invoke-TimeoutWrapper -wrapperPath $coreWrapper -commandLine '1..6 | ForEach-Object { Write-Output "tick-$_"; Start-Sleep -Milliseconds 500 }; Write-Output "LOG_DONE"' -idleSec 2 -hardSec 10
    Assert-Test "4c. Aktif log akisi varsa (Idle=2s, Sure~3s) surec oldurulmemeli ve ExitCode 0 donmeli" `
        ($r4c.ExitCode -eq 0 -and $r4c.Output -match 'LOG_DONE') `
        "Exit=$($r4c.ExitCode) | Elapsed=$([math]::Round($r4c.ElapsedSec, 2))s"

    # 4d. Aktif CPU Deltasi (Log basmadan 3.2s boyunca CPU yakan is, Idle=2s iken OLMEMELI)
    $cpuCmd = '$sw=[System.Diagnostics.Stopwatch]::StartNew(); $x=0; while($sw.ElapsedMilliseconds -lt 3200){ $x = ($x + 1) % 1000003 }; Write-Output "CPU_DONE"'
    $r4d = Invoke-TimeoutWrapper -wrapperPath $coreWrapper -commandLine $cpuCmd -idleSec 2 -hardSec 10
    Assert-Test "4d. Logsuz ama aktif CPU harcayan surec (Idle=2s, Sure~3.2s) CPU nabziyla korunmali" `
        ($r4d.ExitCode -eq 0 -and $r4d.Output -match 'CPU_DONE') `
        "Exit=$($r4d.ExitCode) | Elapsed=$([math]::Round($r4d.ElapsedSec, 2))s"

    # 4e. Kaos: Tam Donma + Yetim Cocuk Surec Agaci Imhasi (Idle=2s)
    $childTag = "VIGILES_CHILD_CANARY_$runId"
    $pidFile = Join-Path $tempBase "child_pid_$runId.txt"
    $freezeCmd = "`$c = Start-Process powershell.exe -ArgumentList '-NoProfile','-Command','`$env:VIGILES_CANARY=`"$childTag`"; Start-Sleep -Seconds 30' -PassThru -WindowStyle Hidden; [System.IO.File]::WriteAllText('$pidFile', [string]`$c.Id); Start-Sleep -Seconds 30"
    $r4e = Invoke-TimeoutWrapper -wrapperPath $coreWrapper -commandLine $freezeCmd -idleSec 2 -hardSec 12
    Start-Sleep -Milliseconds 250
    $childStillAlive = $false
    if (Test-Path $pidFile) {
        $childPidText = (Get-Content -Raw $pidFile).Trim()
        if ($childPidText -match '^\d+$') {
            $childStillAlive = [bool](Get-Process -Id ([int]$childPidText) -ErrorAction SilentlyContinue)
        }
    }
    Assert-Test "4e. Tam donmada (Idle=2s) OS giyotini ExitCode 124 ile kesmeli VE cocuk surec agacini oldurmeli" `
        ($r4e.ExitCode -eq 124 -and $r4e.ElapsedSec -lt 8.0 -and (-not $childStillAlive) -and ($r4e.Output -match 'WATCHDOG TIMEOUT')) `
        "Exit=$($r4e.ExitCode) | Elapsed=$([math]::Round($r4e.ElapsedSec, 2))s | ChildAlive=$childStillAlive"

    # 4f. Kaos: Sonsuz Log/CPU Dongusu Mutlak Tavan (Hard=3s)
    $loopCmd = 'while($true){ Write-Output "spam"; Start-Sleep -Milliseconds 200 }'
    $r4f = Invoke-TimeoutWrapper -wrapperPath $coreWrapper -commandLine $loopCmd -idleSec 10 -hardSec 3
    Assert-Test "4f. Surekli log ureten sonsuz dongu HardTimeout (3s) tavaninda ExitCode 124 ile kesilmeli" `
        ($r4f.ExitCode -eq 124 -and $r4f.ElapsedSec -lt 8.0 -and ($r4f.Output -match 'WATCHDOG TIMEOUT')) `
        "Exit=$($r4f.ExitCode) | Elapsed=$([math]::Round($r4f.ElapsedSec, 2))s"

    # --------------------------------------------------------------------------
    # GRUP 5: Kanca Sira Bagimsizligi (sentinel_guard.ps1) & Ic Sistem Zirhlari
    # --------------------------------------------------------------------------
    Write-Host "`n[Grup 5: Kanca Sira Bagimsizligi & Ic Sistem Zirhlari]" -ForegroundColor Yellow

    $roleChecks = @(
        @{ Cmd = "npm test"; ExpectedNode = "node-tester"; ExpectedStep = 5 },
        @{ Cmd = "powershell -File .\Chaos-Load.ps1"; ExpectedNode = "node-chaos"; ExpectedStep = 8 },
        @{ Cmd = "git commit -m 'feat: ok'"; ExpectedNode = "node-pr"; ExpectedStep = 12 }
    )
    foreach ($rc in $roleChecks) {
        $wdOut = Invoke-HookJson $coreWatchdog @{
            conversationId        = "wd-order-$runId"
            artifactDirectoryPath = $vigilesArtifactDir
            toolCall              = @{ name = "run_command"; args = @{ CommandLine = $rc.Cmd } }
        }
        $wrappedCmd = if ($wdOut.Json -and $wdOut.Json.overwrite -and $wdOut.Json.overwrite.CommandLine) { $wdOut.Json.overwrite.CommandLine } else { "" }
        $isActuallyWrapped = ($wrappedCmd -match 'invoke_with_timeout\.ps1')

        $statePath = Join-Path $vigilesArtifactDir "live_state.json"
        if (Test-Path $statePath) { Remove-Item $statePath -Force -ErrorAction SilentlyContinue }

        $null = Invoke-HookJson $coreSentinel @{
            conversationId        = "wd-order-$runId"
            artifactDirectoryPath = $vigilesArtifactDir
            workspacePaths        = @("C:\TestProj")
            toolCall              = @{ name = "run_command"; args = @{ CommandLine = $wrappedCmd } }
        }
        $st = if (Test-Path $statePath) { (Read-Utf8Text $statePath) | ConvertFrom-Json } else { $null }
        $actualNode = if ($st) { $st.activeNode } else { "null" }
        $actualStep = if ($st) { $st.step } else { -1 }

        if ($wrappedCmd -match '-PayloadFile\s+"([^"]+)"') {
            Remove-Item $matches[1] -Force -ErrorAction SilentlyContinue
        }

        Assert-Test "Sira Bagimsiz Sentinel Dispatch ('$($rc.Cmd)' sarmali) -> $($rc.ExpectedNode) (step $($rc.ExpectedStep))" `
            ($isActuallyWrapped -and $actualNode -eq $rc.ExpectedNode -and $actualStep -eq $rc.ExpectedStep) `
            "Wrapped=$isActuallyWrapped | ActualNode=$actualNode | ActualStep=$actualStep"
    }

    # Bosluklu Kullanici/Temp Yolu Regresyon Testi (sentinel_guard.ps1 Zero-Leak & Rol Cozumlemesi)
    $spacedDir = Join-Path $tempBase "John Doe Space Path"
    New-Item -ItemType Directory -Path $spacedDir -Force | Out-Null
    $spacedPayloadEnv = Join-Path $spacedDir "cmd_env_space.json"
    $spacedPayloadTest = Join-Path $spacedDir "cmd_test_space.json"
    $utf8NoBomSpaced = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($spacedPayloadEnv, (@{ command = "git add .env" } | ConvertTo-Json -Compress), $utf8NoBomSpaced)
    [System.IO.File]::WriteAllText($spacedPayloadTest, (@{ command = "npm test" } | ConvertTo-Json -Compress), $utf8NoBomSpaced)

    $spacedWrappedEnv = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$coreWrapper`" -PayloadFile `"$spacedPayloadEnv`""
    $resSpacedEnv = Invoke-HookJson $coreSentinel @{
        conversationId        = "wd-space-env-$runId"
        artifactDirectoryPath = $vigilesArtifactDir
        workspacePaths        = @("C:\TestProj")
        toolCall              = @{ name = "run_command"; args = @{ CommandLine = $spacedWrappedEnv } }
    }
    Assert-Test "Bosluklu -PayloadFile Yolunda Zero-Leak ('git add .env' sarmali) -> deny olmali" `
        ($resSpacedEnv.Json -and $resSpacedEnv.Json.decision -eq "deny") `
        "Stdout=$($resSpacedEnv.Stdout)"

    $statePathSpaced = Join-Path $vigilesArtifactDir "live_state.json"
    if (Test-Path $statePathSpaced) { Remove-Item $statePathSpaced -Force -ErrorAction SilentlyContinue }
    $spacedWrappedTest = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$coreWrapper`" -PayloadFile `"$spacedPayloadTest`""
    $resSpacedTest = Invoke-HookJson $coreSentinel @{
        conversationId        = "wd-space-test-$runId"
        artifactDirectoryPath = $vigilesArtifactDir
        workspacePaths        = @("C:\TestProj")
        toolCall              = @{ name = "run_command"; args = @{ CommandLine = $spacedWrappedTest } }
    }
    $stSpaced = if (Test-Path $statePathSpaced) { (Read-Utf8Text $statePathSpaced) | ConvertFrom-Json } else { $null }
    Assert-Test "Bosluklu -PayloadFile Yolunda Rol Dagitimi ('npm test' sarmali) -> node-tester (step 5)" `
        ($stSpaced -and $stSpaced.activeNode -eq "node-tester" -and $stSpaced.step -eq 5) `
        "ActualNode=$(if($stSpaced){$stSpaced.activeNode}else{'null'})"

    $resArgMention = Invoke-HookJson $coreWatchdog @{
        conversationId        = "wd-reentry-$runId"
        artifactDirectoryPath = $plainArtifactDir
        toolCall              = @{ name = "run_command"; args = @{ CommandLine = "node check.js invoke_with_timeout.ps1" } }
    }
    Assert-Test "Komut argumaninda invoke_with_timeout.ps1 gecse bile gercek -PayloadFile degilse sarmalanmali" `
        ($resArgMention.Json -and $resArgMention.Json.overwrite -and $resArgMention.Json.overwrite.CommandLine -match '-PayloadFile') `
        "Stdout=$($resArgMention.Stdout)"
    if ($resArgMention.Json -and $resArgMention.Json.overwrite -and $resArgMention.Json.overwrite.CommandLine -match '-PayloadFile\s+"([^"]+)"') {
        Remove-Item $matches[1] -Force -ErrorAction SilentlyContinue
    }

    # Ic betikler & Anayasa kontrolleri
    $masterRaw = Read-Utf8Text (Join-Path $ws "Run-MasterVerification.ps1")
    $geceRaw = Read-Utf8Text (Join-Path $ws "core\scripts\gece_nobetci.ps1")
    $stopRaw = Read-Utf8Text (Join-Path $ws "core\scripts\on_mission_complete.ps1")
    $kurallarRaw = Read-Utf8Text (Join-Path $ws "KURALLAR.md")
    $kurallarTplRaw = Read-Utf8Text (Join-Path $ws "core\templates\KURALLAR.template.md")
    $testerPersonaRaw = Read-Utf8Text (Join-Path $ws "core\skills\pro\personas\special-tester.md")

    Assert-Test "Run-MasterVerification.ps1 paket bazli timeout + taskkill giyotini ve Test-CommandWatchdog icermeli" `
        (($masterRaw -match 'Test-CommandWatchdog\.ps1') -and ($masterRaw -match 'taskkill') -and ($masterRaw -match 'VIGILES_SUITE_TIMEOUT_SEC')) `
        "Run-MasterVerification.ps1 icinde timeout/taskkill veya Test-CommandWatchdog eksik"

    Assert-Test "gece_nobetci.ps1 CI=true, NPM_CONFIG_YES=true ve timeout korumasi icermeli" `
        (($geceRaw -match 'CI') -and ($geceRaw -match 'NPM_CONFIG_YES') -and ($geceRaw -match 'invoke_with_timeout|WaitForExit|taskkill')) `
        "gece_nobetci.ps1 non-interactive veya timeout zirhi eksik"

    Assert-Test "on_mission_complete.ps1 guvenli watchdog temp temizligi icermeli" `
        ($stopRaw -match 'vigiles_watchdog') `
        "on_mission_complete.ps1 icinde vigiles_watchdog temp temizligi eksik"

    Assert-Test "KURALLAR.md ve KURALLAR.template.md [KURAL-024] icermeli" `
        (($kurallarRaw -match '\[KURAL-024\]') -and ($kurallarTplRaw -match '\[KURAL-024\]')) `
        "KURALLAR.md veya KURALLAR.template.md icinde [KURAL-024] eksik"

    Assert-Test "special-tester.md IsDaemon:true sunucu kuralini icermeli" `
        ($testerPersonaRaw -match 'IsDaemon:\s*true') `
        "special-tester.md icinde IsDaemon: true kurali eksik"

} finally {
    if (Test-Path $testThinkModeFile) { Remove-Item $testThinkModeFile -Force -ErrorAction SilentlyContinue }
    if (Test-Path $tempBase) { Remove-Item -Path $tempBase -Recurse -Force -ErrorAction SilentlyContinue }
    $payloadDirCleanup = Join-Path ([System.IO.Path]::GetTempPath()) "vigiles_watchdog_test_payloads"
    if (Test-Path $payloadDirCleanup) { Remove-Item -Path $payloadDirCleanup -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
$color = if ($global:failedCount -eq 0) { "Green" } else { "Red" }
Write-Host "TEST SONUCLARI: $global:passedCount Gecti | $global:failedCount Basarisiz" -ForegroundColor $color
Write-Host "==========================================================" -ForegroundColor Cyan

if ($global:failedCount -gt 0) { exit 1 } else { exit 0 }
