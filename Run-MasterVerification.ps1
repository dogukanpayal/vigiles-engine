# Vigiles Engine - Master Verification Runner (All Suites)
# Runs every unit, integration, simulation, and chaos test under .\tests\ with per-suite OS timeout protection

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8
$ws = $PSScriptRoot

$suiteTimeoutSec = 180
if ($env:VIGILES_SUITE_TIMEOUT_SEC -match '^\d+$') {
    $parsedTimeout = [int]$env:VIGILES_SUITE_TIMEOUT_SEC
    if ($parsedTimeout -ge 5) { $suiteTimeoutSec = $parsedTimeout }
}
$suiteTimeoutMs = $suiteTimeoutSec * 1000

$suites = @(
    "tests\Test-CommandWatchdog.ps1",
    "tests\Test-GitPushManager.ps1",
    "tests\Test-SessionPushIsolation.ps1",
    "tests\Test-MultiSessionTelemetri.ps1",
    "tests\Test-WorkersSubNodes.ps1",
    "tests\Test-AuxiliarySection.ps1",
    "tests\Test-VigilesLightIntegrity.ps1",
    "tests\Test-VigilesIsolation.ps1",
    "tests\Test-LiveIsolationSimulation.ps1",
    "tests\Test-VigilesConsiliumIntegrity.ps1",
    "tests\Test-ConsiliumScenarioSimulation.ps1",
    "tests\Test-SentinelGuardRoleDispatch.ps1",
    "tests\Scenario-RoleOrderLifecycle.ps1",
    "tests\Test-AllChatsDiscovery.ps1",
    "tests\Test-ProjectPillsAndRecency.ps1",
    "tests\Test-PillsClickKeepOpen.ps1",
    "tests\Test-AntigravityDbTitles.ps1",
    "tests\Test-AntiSlopDesignSystem.ps1",
    "tests\Test-MultiSessionWorktree.ps1",
    "tests\Chaos-MultiSession.ps1",
    "tests\Chaos-WorkersSubNodes.ps1",
    "tests\Chaos-AuxiliarySection.ps1",
    "tests\Chaos-ParallelProSessions.ps1"
)

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " VIGILES ENGINE - MASTER TEST SUITE ($($suites.Count) Suites | Max ${suiteTimeoutSec}s/suite)" -ForegroundColor Cyan
Write-Host " Workspace: $ws" -ForegroundColor DarkGray
Write-Host "=====================================================" -ForegroundColor Cyan

$startedTestTelemetryServer = $false
$testTelemetryPid = $null
$port9999Up = [bool](Get-NetTCPConnection -LocalPort 9999 -State Listen -ErrorAction SilentlyContinue)
if (-not $port9999Up) {
    $serverScript = Join-Path $ws "core\scripts\telemetry_server.ps1"
    if (Test-Path $serverScript) {
        Write-Host "`n[INFO] Port 9999 kapali; telemetri testleri icin gecici test sunucusu baslatiliyor..." -ForegroundColor DarkCyan
        $proc = Start-Process powershell.exe -ArgumentList "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-NoProfile", "-File", "`"$serverScript`"" -PassThru -WindowStyle Hidden
        $testTelemetryPid = $proc.Id
        $startedTestTelemetryServer = $true
        for ($i = 0; $i -lt 25; $i++) {
            Start-Sleep -Milliseconds 150
            if (Get-NetTCPConnection -LocalPort 9999 -State Listen -ErrorAction SilentlyContinue) {
                break
            }
        }
    }
}

$totalPassed = 0
$totalFailed = 0
$failedSuites = @()

try {
    foreach ($s in $suites) {
        $fullPath = Join-Path $ws $s
        if (-not (Test-Path $fullPath)) {
            Write-Host "`n[MISSING] $s" -ForegroundColor Red
            $totalFailed++
            $failedSuites += "$s (missing)"
            continue
        }

        Write-Host "`n>>> Running: $s" -ForegroundColor Yellow

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$fullPath`""
        $psi.WorkingDirectory = $ws
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.EnvironmentVariables["CI"] = "true"
        $psi.EnvironmentVariables["NPM_CONFIG_YES"] = "true"
        $psi.EnvironmentVariables["GIT_TERMINAL_PROMPT"] = "0"

        $suiteProc = [System.Diagnostics.Process]::Start($psi)
        try { $suiteProc.StandardInput.Close() } catch {}

        $outTask = $suiteProc.StandardOutput.ReadLineAsync()
        $errTask = $suiteProc.StandardError.ReadLineAsync()
        $outDone = $false
        $errDone = $false
        $timedOut = $false
        $swSuite = [System.Diagnostics.Stopwatch]::StartNew()

        while (-not ($suiteProc.HasExited -and $outDone -and $errDone)) {
            if (-not $outDone -and $outTask.IsCompleted) {
                $line = $null
                try { $line = $outTask.Result } catch { $line = $null }
                if ($null -ne $line) {
                    Write-Host "  $line"
                    $outTask = $suiteProc.StandardOutput.ReadLineAsync()
                } else {
                    $outDone = $true
                }
            }
            if (-not $errDone -and $errTask.IsCompleted) {
                $errLine = $null
                try { $errLine = $errTask.Result } catch { $errLine = $null }
                if ($null -ne $errLine) {
                    Write-Host "  $errLine" -ForegroundColor DarkYellow
                    $errTask = $suiteProc.StandardError.ReadLineAsync()
                } else {
                    $errDone = $true
                }
            }
            if (-not $suiteProc.HasExited -and $swSuite.ElapsedMilliseconds -ge $suiteTimeoutMs) {
                $timedOut = $true
                try { $null = & cmd.exe /c "taskkill /PID $($suiteProc.Id) /T /F" 2>&1 } catch {}
                try { Stop-Process -Id $suiteProc.Id -Force -ErrorAction SilentlyContinue } catch {}
                break
            }
            if (-not ($suiteProc.HasExited -and $outDone -and $errDone)) {
                $waiters = [System.Collections.Generic.List[System.Threading.Tasks.Task]]::new()
                if (-not $outDone) { $waiters.Add($outTask) }
                if (-not $errDone) { $waiters.Add($errTask) }
                if ($waiters.Count -gt 0) {
                    try { $null = [System.Threading.Tasks.Task]::WaitAny($waiters.ToArray(), 100) } catch { Start-Sleep -Milliseconds 50 }
                } else {
                    Start-Sleep -Milliseconds 50
                }
            }
        }
        $swSuite.Stop()

        if ($timedOut) {
            try { $suiteProc.WaitForExit(1500) | Out-Null } catch {}
            Write-Host "[TIMEOUT] $s (${suiteTimeoutSec}s tavani asildigi icin süreç ağacı kesildi!)" -ForegroundColor Red
            $totalFailed++
            $failedSuites += "$s (TIMEOUT > ${suiteTimeoutSec}s)"
            try { $suiteProc.Dispose() } catch {}
            continue
        }

        $suiteProc.WaitForExit()
        $exitCode = $suiteProc.ExitCode
        try { $suiteProc.Dispose() } catch {}

        if ($exitCode -eq 0) {
            Write-Host "[OK] $s" -ForegroundColor Green
            $totalPassed++
        } else {
            Write-Host "[FAIL] $s (ExitCode: $exitCode)" -ForegroundColor Red
            $totalFailed++
            $failedSuites += "$s (ExitCode: $exitCode)"
        }
    }
} finally {
    if ($startedTestTelemetryServer -and $testTelemetryPid) {
        Write-Host "`n[INFO] Testler icin acilan gecici Port 9999 sunucusu kapatiliyor (PID: $testTelemetryPid)..." -ForegroundColor DarkCyan
        try { $null = & cmd.exe /c "taskkill /PID $testTelemetryPid /T /F" 2>&1 } catch {}
        Stop-Process -Id $testTelemetryPid -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n=====================================================" -ForegroundColor Cyan
Write-Host " SUMMARY: $totalPassed / $($suites.Count) Passed | Failed: $totalFailed" -ForegroundColor $(if ($totalFailed -eq 0) { "Green" } else { "Red" })
if ($failedSuites.Count -gt 0) {
    Write-Host " Failed suites:" -ForegroundColor Red
    $failedSuites | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}
Write-Host "=====================================================" -ForegroundColor Cyan

if ($totalFailed -gt 0) { exit 1 } else { exit 0 }
