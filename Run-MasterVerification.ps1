# Vigiles Engine - Master Verification Runner (All Suites)
# Runs every unit, integration, simulation, and chaos test under .\tests\

$ErrorActionPreference = "Continue"
$ws = $PSScriptRoot

$suites = @(
    "tests\Test-GitPushManager.ps1",
    "tests\Test-Heartbeat.ps1",
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
    "tests\Chaos-Heartbeat.ps1",
    "tests\Chaos-MultiSession.ps1",
    "tests\Chaos-WorkersSubNodes.ps1",
    "tests\Chaos-AuxiliarySection.ps1"
)

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host " VIGILES ENGINE - MASTER TEST SUITE ($($suites.Count) Suites)" -ForegroundColor Cyan
Write-Host " Workspace: $ws" -ForegroundColor DarkGray
Write-Host "=====================================================" -ForegroundColor Cyan

$totalPassed = 0
$totalFailed = 0
$failedSuites = @()

foreach ($s in $suites) {
    $fullPath = Join-Path $ws $s
    if (-not (Test-Path $fullPath)) {
        Write-Host "`n[MISSING] $s" -ForegroundColor Red
        $totalFailed++
        $failedSuites += "$s (missing)"
        continue
    }

    Write-Host "`n>>> Running: $s" -ForegroundColor Yellow
    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $fullPath 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host "  $_" }

    if ($exitCode -eq 0) {
        Write-Host "[OK] $s" -ForegroundColor Green
        $totalPassed++
    } else {
        Write-Host "[FAIL] $s (ExitCode: $exitCode)" -ForegroundColor Red
        $totalFailed++
        $failedSuites += "$s (ExitCode: $exitCode)"
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
