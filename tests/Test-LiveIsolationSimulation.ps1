# ==============================================================================
# Test-LiveIsolationSimulation.ps1
# Canli Karsilastirmali Test: /vigiles KULLANILAN vs KULLANILMAYAN Senaryo
# ==============================================================================
param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$configScripts = "$HOME\.gemini\config\scripts"
$ensureScript = Join-Path $configScripts "ensure_live_mission_control.ps1"
$sentinelScript = Join-Path $configScripts "sentinel_guard.ps1"
$stopScript = Join-Path $configScripts "on_mission_complete.ps1"

$tempRoot = Join-Path $env:TEMP "vigiles_live_simulation_$(Get-Random)"
$dirNonVigiles = Join-Path $tempRoot "scenario_A_normal"
$dirVigiles = Join-Path $tempRoot "scenario_B_vigiles"

New-Item -ItemType Directory -Path $dirNonVigiles -Force | Out-Null
New-Item -ItemType Directory -Path $dirVigiles -Force | Out-Null

$results = @{
    ScenarioA = @{}
    ScenarioB = @{}
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "CANLI IZOLASYON KARSILASTIRMA VE TEST RAPORU" -ForegroundColor Yellow
Write-Host "   1. Senaryo A: /vigiles KULLANILMAYAN Normal Sohbet" -ForegroundColor Gray
Write-Host "   2. Senaryo B: /vigiles KULLANILAN Tam Mimari Oturum" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# SENARYO A: /vigiles KULLANILMAYAN DURUM
# ------------------------------------------------------------------------------
Write-Host "`n>>> [SENARYO A]: /vigiles KULLANILMAYAN NORMAL SOHBET TEST EDILIYOR..." -ForegroundColor Yellow

# Adim 1: PreInvocation (ensure_live_mission_control.ps1)
$payloadA_PreInv = @{
    lastUserInput = "Merhaba bana basit bir fibonacci fonksiyonu yazar misin?"
    conversationId = "session-scenario-A-normal"
    artifactDirectoryPath = $dirNonVigiles
    invocationNum = 1
} | ConvertTo-Json -Compress

$outA_PreInv = $payloadA_PreInv | powershell -ExecutionPolicy Bypass -NoProfile -File $ensureScript
$results.ScenarioA["PreInvocation_Output"] = $outA_PreInv
$results.ScenarioA["Vigiles_Active_Marker"] = Test-Path (Join-Path $dirNonVigiles ".vigiles_active")
$results.ScenarioA["Live_Control_HTML_Copied"] = Test-Path (Join-Path $dirNonVigiles "live_mission_control.html")
$results.ScenarioA["Injected_System_Message"] = ($outA_PreInv -match "CANLI OPERASYON MERKEZI DEVREDE")

# Adim 2: PreToolUse (sentinel_guard.ps1) - write_file cagiriliyor
$payloadA_Tool = @{
    toolCall = @{
        name = "write_file"
        args = @{ Path = "C:\temp\fibonacci.js"; Content = "function fib(n){ return n<=1?n:fib(n-1)+fib(n-2); }" }
    }
    conversationId = "session-scenario-A-normal"
    artifactDirectoryPath = $dirNonVigiles
} | ConvertTo-Json -Compress

$outA_Tool = $payloadA_Tool | powershell -ExecutionPolicy Bypass -NoProfile -File $sentinelScript
$results.ScenarioA["Tool_Decision"] = $outA_Tool
$results.ScenarioA["Telemetry_Generated"] = Test-Path (Join-Path $dirNonVigiles "live_state.json")
$results.ScenarioA["Events_Logged"] = Test-Path (Join-Path $dirNonVigiles "live_events.jsonl")

# Adim 3: Stop Hook (on_mission_complete.ps1)
$payloadA_Stop = @{
    conversationId = "session-scenario-A-normal"
    artifactDirectoryPath = $dirNonVigiles
} | ConvertTo-Json -Compress

$outA_Stop = $payloadA_Stop | powershell -ExecutionPolicy Bypass -NoProfile -File $stopScript
$results.ScenarioA["Stop_Output"] = $outA_Stop

Write-Host "  -> PreInvocation Ciktisi : $($results.ScenarioA.PreInvocation_Output)" -ForegroundColor DarkGray
Write-Host "  -> .vigiles_active Bayragi: $($results.ScenarioA.Vigiles_Active_Marker)" -ForegroundColor $(if (-not $results.ScenarioA.Vigiles_Active_Marker) { "Green" } else { "Red" })
Write-Host "  -> Sistem Mesaji Enjekte : $($results.ScenarioA.Injected_System_Message)" -ForegroundColor $(if (-not $results.ScenarioA.Injected_System_Message) { "Green" } else { "Red" })
Write-Host "  -> Tool Karari           : $($results.ScenarioA.Tool_Decision)" -ForegroundColor Green
Write-Host "  -> Telemetri Uretildi mi : $($results.ScenarioA.Telemetry_Generated)" -ForegroundColor $(if (-not $results.ScenarioA.Telemetry_Generated) { "Green" } else { "Red" })
Write-Host "  -> Stop Ciktisi          : $($results.ScenarioA.Stop_Output)" -ForegroundColor Green

# ------------------------------------------------------------------------------
# SENARYO B: /vigiles KULLANILAN DURUM
# ------------------------------------------------------------------------------
Write-Host "`n>>> [SENARYO B]: /vigiles KULLANILAN VIGILES OTURUMU TEST EDILIYOR..." -ForegroundColor Yellow

# Adim 1: PreInvocation (ensure_live_mission_control.ps1)
$payloadB_PreInv = @{
    lastUserInput = "/vigiles kimlik dogrulama modulu ve testleri insa et"
    conversationId = "session-scenario-B-vigiles"
    artifactDirectoryPath = $dirVigiles
    invocationNum = 1
} | ConvertTo-Json -Compress

$outB_PreInv = $payloadB_PreInv | powershell -ExecutionPolicy Bypass -NoProfile -File $ensureScript
$results.ScenarioB["PreInvocation_Output_Length"] = $outB_PreInv.Length
$results.ScenarioB["Vigiles_Active_Marker"] = Test-Path (Join-Path $dirVigiles ".vigiles_active")
$results.ScenarioB["Live_Control_HTML_Copied"] = Test-Path (Join-Path $dirVigiles "live_mission_control.html")
$results.ScenarioB["Injected_System_Message"] = ($outB_PreInv -match "CANLI OPERASYON MERKEZI DEVREDE")

# Adim 2: PreToolUse (sentinel_guard.ps1) - run_command (npm test) cagiriliyor
$payloadB_Tool = @{
    toolCall = @{
        name = "run_command"
        args = @{ CommandLine = "npm test -- auth.spec.js" }
    }
    conversationId = "session-scenario-B-vigiles"
    artifactDirectoryPath = $dirVigiles
} | ConvertTo-Json -Compress

$outB_Tool = $payloadB_Tool | powershell -ExecutionPolicy Bypass -NoProfile -File $sentinelScript
$results.ScenarioB["Tool_Decision"] = $outB_Tool
$results.ScenarioB["Telemetry_Generated"] = Test-Path (Join-Path $dirVigiles "live_state.json")
$results.ScenarioB["Events_Logged"] = Test-Path (Join-Path $dirVigiles "live_events.jsonl")

$stateContentB = if ($results.ScenarioB.Telemetry_Generated) {
    Get-Content -Raw -Encoding UTF8 (Join-Path $dirVigiles "live_state.json")
} else { "" }
$results.ScenarioB["Active_Node"] = if ($stateContentB -match '"activeNode"\s*:\s*"([^"]+)"') { $matches[1] } else { "none" }
$results.ScenarioB["Active_Sender"] = if ($stateContentB -match '"sender"\s*:\s*"([^"]+)"') { $matches[1] } else { "none" }

# Adim 3: Stop Hook (on_mission_complete.ps1)
$payloadB_Stop = @{
    conversationId = "session-scenario-B-vigiles"
    artifactDirectoryPath = $dirVigiles
} | ConvertTo-Json -Compress

$outB_Stop = $payloadB_Stop | powershell -ExecutionPolicy Bypass -NoProfile -File $stopScript
$finalStateB = if (Test-Path (Join-Path $dirVigiles "live_state.json")) {
    Get-Content -Raw -Encoding UTF8 (Join-Path $dirVigiles "live_state.json")
} else { "" }
$results.ScenarioB["Final_Status"] = if ($finalStateB -match '"status"\s*:\s*"([^"]+)"') { $matches[1] } else { "none" }

Write-Host "  -> PreInvocation Yaniti  : Sistem Mesaji Basariyla Enjekte Edildi ($($results.ScenarioB.PreInvocation_Output_Length) karakter)" -ForegroundColor Green
Write-Host "  -> .vigiles_active Bayragi: $($results.ScenarioB.Vigiles_Active_Marker)" -ForegroundColor Green
Write-Host "  -> live_control.html     : $($results.ScenarioB.Live_Control_HTML_Copied)" -ForegroundColor Green
Write-Host "  -> Tool Karari           : $($results.ScenarioB.Tool_Decision)" -ForegroundColor Green
Write-Host "  -> Telemetri Uretildi mi : $($results.ScenarioB.Telemetry_Generated) (Aktif Rol: $($results.ScenarioB.Active_Sender))" -ForegroundColor Green
Write-Host "  -> Final Durumu (Stop)   : $($results.ScenarioB.Final_Status)" -ForegroundColor Green

# ------------------------------------------------------------------------------
# RAPOR CIKTISI
# ------------------------------------------------------------------------------
$summaryJson = $results | ConvertTo-Json -Depth 4
Set-Content -Path (Join-Path $tempRoot "summary_report.json") -Value $summaryJson -Encoding UTF8

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host "CANLI INCELEME SONUC RAPORU:" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$scenarioA_Clean = (-not $results.ScenarioA.Vigiles_Active_Marker) -and (-not $results.ScenarioA.Injected_System_Message) -and (-not $results.ScenarioA.Telemetry_Generated)
$scenarioB_Active = $results.ScenarioB.Vigiles_Active_Marker -and $results.ScenarioB.Injected_System_Message -and $results.ScenarioB.Telemetry_Generated -and ($results.ScenarioB.Final_Status -eq "TESLIM_EDILDI")

if ($scenarioA_Clean -and $scenarioB_Active) {
    Write-Host "[BASARILI] Izolasyon %100 kusursuz calisiyor!" -ForegroundColor Green
    Write-Host "  - Senaryo A (/vigiles yokken): Vigiles tamamen UYKUDA, 0 mudahale, 0 telemetri." -ForegroundColor Green
    Write-Host "  - Senaryo B (/vigiles varken): Vigiles TAM GUC devrede, 20 eleman ve Canli Merkez aktif." -ForegroundColor Green
    exit 0
} else {
    Write-Host "[HATA] Izolasyon kriterlerinde uyumsuzluk tespit edildi!" -ForegroundColor Red
    exit 1
}
