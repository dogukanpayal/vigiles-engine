param(
    [string]$PayloadFile = "",
    [string]$Command = "",
    [string]$Cwd = "",
    [int]$IdleTimeoutSec = 45,
    [int]$HardTimeoutSec = 180,
    [int]$PollIntervalMs = 1000
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$conversationId = ""
$artifactDir = ""
$telemetryPort = 9999
if ($env:VIGILES_TELEMETRY_PORT -match '^\d+$') {
    $parsedPort = [int]$env:VIGILES_TELEMETRY_PORT
    if ($parsedPort -ge 1024 -and $parsedPort -le 65535) {
        $telemetryPort = $parsedPort
    }
}

$shouldDeletePayload = $false
if (-not [string]::IsNullOrWhiteSpace($PayloadFile) -and (Test-Path $PayloadFile)) {
    $shouldDeletePayload = $true
    try {
        $rawPayload = [System.IO.File]::ReadAllText($PayloadFile, [System.Text.Encoding]::UTF8).Trim().Trim([char]65279)
        if (-not [string]::IsNullOrWhiteSpace($rawPayload)) {
            $pObj = $rawPayload | ConvertFrom-Json
            if ($pObj.command) { $Command = [string]$pObj.command }
            if ($pObj.cwd) { $Cwd = [string]$pObj.cwd }
            if ($pObj.conversationId) { $conversationId = [string]$pObj.conversationId }
            if ($pObj.artifactDir) { $artifactDir = [string]$pObj.artifactDir }
            if ($pObj.idleTimeoutSec -and [int]$pObj.idleTimeoutSec -gt 0) { $IdleTimeoutSec = [int]$pObj.idleTimeoutSec }
            if ($pObj.hardTimeoutSec -and [int]$pObj.hardTimeoutSec -gt 0) { $HardTimeoutSec = [int]$pObj.hardTimeoutSec }
            if ($pObj.pollIntervalMs -and [int]$pObj.pollIntervalMs -ge 100) { $PollIntervalMs = [int]$pObj.pollIntervalMs }
        }
    } catch {
        Write-Error "[VIGILES WATCHDOG]: Payload okunamadi: $($_.Exception.Message)"
        if ($shouldDeletePayload) { Remove-Item $PayloadFile -Force -ErrorAction SilentlyContinue }
        exit 1
    }
}

if ($env:VIGILES_WATCHDOG_IDLE_SEC -match '^\d+$') {
    $envIdle = [int]$env:VIGILES_WATCHDOG_IDLE_SEC
    if ($envIdle -gt 0) { $IdleTimeoutSec = $envIdle }
}
if ($env:VIGILES_WATCHDOG_HARD_SEC -match '^\d+$') {
    $envHard = [int]$env:VIGILES_WATCHDOG_HARD_SEC
    if ($envHard -gt 0) { $HardTimeoutSec = $envHard }
}

if ([string]::IsNullOrWhiteSpace($Command)) {
    if ($shouldDeletePayload -and (Test-Path $PayloadFile)) {
        Remove-Item $PayloadFile -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Cwd) -or -not (Test-Path $Cwd)) {
    $Cwd = (Get-Location).Path
}

function Get-ProcessTreeIds([int]$rootPid) {
    $ids = [System.Collections.Generic.HashSet[int]]::new()
    $null = $ids.Add($rootPid)
    try {
        $allProcs = Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId -ErrorAction SilentlyContinue
        if ($allProcs) {
            $childrenMap = @{}
            foreach ($pr in $allProcs) {
                $ppid = [int]$pr.ParentProcessId
                if (-not $childrenMap.ContainsKey($ppid)) {
                    $childrenMap[$ppid] = [System.Collections.Generic.List[int]]::new()
                }
                $childrenMap[$ppid].Add([int]$pr.ProcessId)
            }
            $queue = [System.Collections.Generic.Queue[int]]::new()
            $queue.Enqueue($rootPid)
            while ($queue.Count -gt 0) {
                $curr = $queue.Dequeue()
                if ($childrenMap.ContainsKey($curr)) {
                    foreach ($childPid in $childrenMap[$curr]) {
                        if ($ids.Add($childPid)) {
                            $queue.Enqueue($childPid)
                        }
                    }
                }
            }
        }
    } catch {}
    return @($ids)
}

function Get-ProcessTreeCpuDelta([int[]]$pids, [hashtable]$prevMap) {
    if (-not $pids -or $pids.Length -eq 0) { return [long]0 }
    [long]$deltaTicks = 0
    foreach ($id in $pids) {
        try {
            $p = [System.Diagnostics.Process]::GetProcessById($id)
            if ($p -and -not $p.HasExited) {
                [long]$curr = $p.TotalProcessorTime.Ticks
                [long]$prev = if ($prevMap.ContainsKey($id)) { [long]$prevMap[$id] } else { [long]0 }
                if ($curr -gt $prev) {
                    $deltaTicks += ($curr - $prev)
                }
                $prevMap[$id] = $curr
            }
        } catch {}
    }
    return $deltaTicks
}

function Stop-ProcessTree([int]$rootPid) {
    $treeIds = Get-ProcessTreeIds -rootPid $rootPid
    try {
        $null = & cmd.exe /c "taskkill /PID $rootPid /T /F" 2>&1
    } catch {}
    foreach ($id in $treeIds) {
        try {
            $p = Get-Process -Id $id -ErrorAction SilentlyContinue
            if ($p -and -not $p.HasExited) {
                Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}

function Send-WatchdogLiveAlert([string]$artDir, [string]$cid, [string]$reasonText, [string]$cmdPreview) {
    if ([string]::IsNullOrWhiteSpace($artDir) -or -not (Test-Path $artDir)) { return }
    $hasVigiles = Test-Path (Join-Path $artDir ".vigiles_active")
    $hasLive = Test-Path (Join-Path $artDir ".live_active")
    if (-not ($hasVigiles -and $hasLive)) { return }

    try {
        $time = (Get-Date).ToString("HH:mm:ss")
        $state = @{
            conversationId = $cid
            step           = 7
            totalSteps     = 15
            activeNode     = "node-shield"
            animClass      = "node-active-red"
            status         = "KOMUT_ZAMAN_ASIMI"
            title          = "VIGILES WATCHDOG: Sıkışan Komut Kesildi"
            sender         = "[9. GÜVENLİK MUHAFIZI / WATCHDOG]"
            message        = "$reasonText | Komut: $cmdPreview"
            desc           = "OS Süreç Ağacı Giyotini donan komutu ve alt süreçlerini otomatik sonlandırdı."
            timestamp      = $time
            badge          = @{ id = "badge-shield"; text = "Komut Kesildi (124)"; class = "bg-rose-500/20 text-rose-400 border-rose-500/40 font-bold animate-pulse" }
        }
        $stateJson = $state | ConvertTo-Json -Depth 6 -Compress
        $req = [System.Net.WebRequest]::Create("http://localhost:$telemetryPort/notify")
        $req.Method = "POST"
        $req.ContentType = "application/json; charset=utf-8"
        if (-not [string]::IsNullOrWhiteSpace($cid)) {
            $req.Headers.Add("X-Conversation-Id", $cid)
        }
        $req.ServicePoint.Expect100Continue = $false
        $req.Timeout = 600
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($stateJson)
        $req.ContentLength = $bytes.Length
        $st = $req.GetRequestStream()
        $st.Write($bytes, 0, $bytes.Length)
        $st.Dispose()
        $resp = $req.GetResponse()
        $resp.Dispose()
    } catch {}
}

$tempExecDir = Join-Path ([System.IO.Path]::GetTempPath()) "vigiles_watchdog"
if (-not (Test-Path $tempExecDir)) {
    New-Item -ItemType Directory -Path $tempExecDir -Force | Out-Null
}
$execScriptPath = Join-Path $tempExecDir ("exec_" + [System.Guid]::NewGuid().ToString("N") + ".ps1")

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
$wrappedBody = @"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
`$OutputEncoding           = [System.Text.Encoding]::UTF8
$Command
if (`$LASTEXITCODE -is [int] -and `$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
"@
[System.IO.File]::WriteAllText($execScriptPath, $wrappedBody, $utf8Bom)

$proc = $null
$timedOut = $false
$timeoutReason = ""
$finalExitCode = 0

try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$execScriptPath`""
    $psi.WorkingDirectory = $Cwd
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    # Non-Interactive Ortam Zirhi
    $psi.EnvironmentVariables["GIT_TERMINAL_PROMPT"] = "0"
    $psi.EnvironmentVariables["GCM_INTERACTIVE"] = "never"
    $psi.EnvironmentVariables["NPM_CONFIG_YES"] = "true"
    $psi.EnvironmentVariables["CI"] = "true"
    $psi.EnvironmentVariables["PIP_NO_INPUT"] = "1"
    $psi.EnvironmentVariables["DEBIAN_FRONTEND"] = "noninteractive"
    $psi.EnvironmentVariables["PAGER"] = "cat"
    $psi.EnvironmentVariables["GIT_PAGER"] = "cat"
    $psi.EnvironmentVariables["VIGILES_WATCHDOG_ACTIVE"] = "1"

    $proc = [System.Diagnostics.Process]::Start($psi)
    # Stdin'i aninda kapat (interaktif input() / Read-Host / pause cagrilari EOF alip kilitlenmesin)
    try { $proc.StandardInput.Close() } catch {}

    $outStream = $proc.StandardOutput.BaseStream
    $errStream = $proc.StandardError.BaseStream
    $outBuf = New-Object byte[] 4096
    $errBuf = New-Object byte[] 4096
    $outDecoder = [System.Text.Encoding]::UTF8.GetDecoder()
    $errDecoder = [System.Text.Encoding]::UTF8.GetDecoder()

    $outTask = $outStream.ReadAsync($outBuf, 0, $outBuf.Length)
    $errTask = $errStream.ReadAsync($errBuf, 0, $errBuf.Length)
    $outDone = $false
    $errDone = $false

    $startUtc = [DateTime]::UtcNow
    $lastActivityUtc = $startUtc
    $lastPulseCheckUtc = $startUtc
    $pidCpuMap = @{}
    try { $pidCpuMap[[int]$proc.Id] = [long]$proc.TotalProcessorTime.Ticks } catch {}

    while (-not ($proc.HasExited -and $outDone -and $errDone)) {
        $nowUtc = [DateTime]::UtcNow

        if (-not $outDone -and $outTask.IsCompleted) {
            $bytesRead = 0
            try { $bytesRead = $outTask.Result } catch { $bytesRead = 0 }
            if ($bytesRead -gt 0) {
                $charBuf = New-Object char[] ($outDecoder.GetCharCount($outBuf, 0, $bytesRead) + 2)
                $charLen = $outDecoder.GetChars($outBuf, 0, $bytesRead, $charBuf, 0)
                if ($charLen -gt 0) {
                    [Console]::Out.Write($charBuf, 0, $charLen)
                }
                $lastActivityUtc = [DateTime]::UtcNow
                $outTask = $outStream.ReadAsync($outBuf, 0, $outBuf.Length)
            } else {
                $outDone = $true
            }
        }

        if (-not $errDone -and $errTask.IsCompleted) {
            $bytesRead = 0
            try { $bytesRead = $errTask.Result } catch { $bytesRead = 0 }
            if ($bytesRead -gt 0) {
                $charBuf = New-Object char[] ($errDecoder.GetCharCount($errBuf, 0, $bytesRead) + 2)
                $charLen = $errDecoder.GetChars($errBuf, 0, $bytesRead, $charBuf, 0)
                if ($charLen -gt 0) {
                    [Console]::Error.Write($charBuf, 0, $charLen)
                }
                $lastActivityUtc = [DateTime]::UtcNow
                $errTask = $errStream.ReadAsync($errBuf, 0, $errBuf.Length)
            } else {
                $errDone = $true
            }
        }

        if (-not $proc.HasExited) {
            $sincePulseMs = ($nowUtc - $lastPulseCheckUtc).TotalMilliseconds
            if ($sincePulseMs -ge $PollIntervalMs) {
                $lastPulseCheckUtc = $nowUtc
                $treeIds = Get-ProcessTreeIds -rootPid $proc.Id
                $cpuDeltaTicks = Get-ProcessTreeCpuDelta -pids $treeIds -prevMap $pidCpuMap
                if ($cpuDeltaTicks -gt 50000) {
                    $lastActivityUtc = $nowUtc
                }

                $totalElapsed = ($nowUtc - $startUtc).TotalSeconds
                $idleElapsed = ($nowUtc - $lastActivityUtc).TotalSeconds

                if ($totalElapsed -ge $HardTimeoutSec) {
                    $timedOut = $true
                    $timeoutReason = "Mutlak zaman asimi tavani ($HardTimeoutSec sn) asildi"
                    Stop-ProcessTree -rootPid $proc.Id
                    break
                } elseif ($idleElapsed -ge $IdleTimeoutSec) {
                    $timedOut = $true
                    $timeoutReason = "Komut $IdleTimeoutSec sn boyunca ne cikti ne de CPU aktivitesi uretti (tam donma/deadlock)"
                    Stop-ProcessTree -rootPid $proc.Id
                    break
                }
            }
        }

        if (-not ($proc.HasExited -and $outDone -and $errDone)) {
            $waitTasks = [System.Collections.Generic.List[System.Threading.Tasks.Task]]::new()
            if (-not $outDone) { $waitTasks.Add($outTask) }
            if (-not $errDone) { $waitTasks.Add($errTask) }
            if ($waitTasks.Count -gt 0) {
                try {
                    $null = [System.Threading.Tasks.Task]::WaitAny($waitTasks.ToArray(), 100)
                } catch {
                    Start-Sleep -Milliseconds 50
                }
            } else {
                Start-Sleep -Milliseconds 50
            }
        }
    }

    if ($timedOut) {
        $cmdPreview = if ($Command.Length -gt 140) { $Command.Substring(0, 137) + "..." } else { $Command }
        $diagMsg = "`n[VIGILES WATCHDOG TIMEOUT (EXIT 124)]: $timeoutReason. Alt surec agaci (PID $($proc.Id)) zorla sonlandirildi. (Komut: $cmdPreview)"
        [Console]::Error.WriteLine($diagMsg)
        Send-WatchdogLiveAlert -artDir $artifactDir -cid $conversationId -reasonText $timeoutReason -cmdPreview $cmdPreview
        $finalExitCode = 124
    } else {
        $proc.WaitForExit()
        $finalExitCode = $proc.ExitCode
    }
} finally {
    if ($proc -and -not $proc.HasExited) {
        Stop-ProcessTree -rootPid $proc.Id
    }
    if ($proc) {
        try { $proc.Dispose() } catch {}
    }
    if (Test-Path $execScriptPath) {
        Remove-Item $execScriptPath -Force -ErrorAction SilentlyContinue
    }
    if ($shouldDeletePayload -and (Test-Path $PayloadFile)) {
        Remove-Item $PayloadFile -Force -ErrorAction SilentlyContinue
    }
}

exit $finalExitCode
