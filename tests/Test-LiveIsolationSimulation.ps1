# ==============================================================================
# Test-LiveIsolationSimulation.ps1
# Canli Karsilastirmali Test: Normal Sohbet vs /pro-/lite (Sessiz) vs /live
# ==============================================================================
param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$configScripts = "$HOME\.gemini\config\scripts"
$ensureScript = Join-Path $configScripts "ensure_live_mission_control.ps1"
$sentinelScript = Join-Path $configScripts "sentinel_guard.ps1"
$stopScript = Join-Path $configScripts "on_mission_complete.ps1"

function Invoke-SimHook([string]$scriptPath, [hashtable]$payloadObj) {
    $json = $payloadObj | ConvertTo-Json -Depth 6 -Compress
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "powershell.exe"
    $pinfo.Arguments = "-ExecutionPolicy Bypass -NoProfile -File `"$scriptPath`""
    $pinfo.RedirectStandardInput = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $proc = [System.Diagnostics.Process]::Start($pinfo)
    $proc.StandardInput.Write($json)
    $proc.StandardInput.Close()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    return ($stdout -replace '[\r\n]+$', '').Trim()
}

$tempRoot = Join-Path $env:TEMP "vigiles_live_simulation_$(Get-Random)"
$tempCfg = Join-Path $tempRoot "cfg"
$dirNonVigiles = Join-Path $tempRoot "scenario_A_normal"
$dirProSilent = Join-Path $tempRoot "scenario_B_pro_silent"
$dirLive = Join-Path $tempRoot "scenario_C_live"

New-Item -ItemType Directory -Path $tempCfg, $dirNonVigiles, $dirProSilent, $dirLive -Force | Out-Null

$simPort = 19995
for ($p = 19995; $p -lt 20080; $p++) {
    $inUse = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    if (-not $inUse) {
        $simPort = $p
        break
    }
}

$prevCfg = $env:VIGILES_CONFIG_DIR
$prevPort = $env:VIGILES_TELEMETRY_PORT
$env:VIGILES_CONFIG_DIR = $tempCfg
$env:VIGILES_TELEMETRY_PORT = "$simPort"

$results = @{
    ScenarioA = @{}
    ScenarioB = @{}
    ScenarioC = @{}
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "CANLI IZOLASYON KARSILASTIRMA VE TEST RAPORU (3 SENARYO)" -ForegroundColor Yellow
Write-Host "   1. Senaryo A: Normal Sohbet (/pro, /lite, /live YOK)" -ForegroundColor Gray
Write-Host "   2. Senaryo B: /pro ve /lite Oturumu (Sessiz Yerel Kayit)" -ForegroundColor Gray
Write-Host "   3. Senaryo C: /live Oturumu (Tam Canli Operasyon Merkezi)" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

try {
    # --------------------------------------------------------------------------
    # SENARYO A: NORMAL SOHBET
    # --------------------------------------------------------------------------
    Write-Host "`n>>> [SENARYO A]: NORMAL SOHBET TEST EDILIYOR..." -ForegroundColor Yellow

    $outA_PreInv = Invoke-SimHook $ensureScript @{
        lastUserInput = "Merhaba bana basit bir fibonacci fonksiyonu yazar misin?"
        conversationId = "test-scenario-A-normal"
        artifactDirectoryPath = $dirNonVigiles
        invocationNum = 1
    }
    $results.ScenarioA["PreInvocation_Output"] = $outA_PreInv
    $results.ScenarioA["Vigiles_Active_Marker"] = Test-Path (Join-Path $dirNonVigiles ".vigiles_active")
    $results.ScenarioA["Live_Active_Marker"] = Test-Path (Join-Path $dirNonVigiles ".live_active")
    $results.ScenarioA["Live_Control_HTML_Copied"] = Test-Path (Join-Path $dirNonVigiles "live_mission_control.html")
    $results.ScenarioA["Injected_System_Message"] = ($outA_PreInv -match "CANLI OPERASYON MERKEZI DEVREDE")

    $outA_Tool = Invoke-SimHook $sentinelScript @{
        toolCall = @{
            name = "write_file"
            args = @{ Path = "C:\temp\fibonacci.js"; Content = "function fib(n){ return n<=1?n:fib(n-1)+fib(n-2); }" }
        }
        conversationId = "test-scenario-A-normal"
        artifactDirectoryPath = $dirNonVigiles
    }
    $results.ScenarioA["Tool_Decision"] = $outA_Tool
    $results.ScenarioA["Telemetry_Generated"] = Test-Path (Join-Path $dirNonVigiles "live_state.json")

    $outA_Stop = Invoke-SimHook $stopScript @{
        conversationId = "test-scenario-A-normal"
        artifactDirectoryPath = $dirNonVigiles
    }
    $results.ScenarioA["Stop_Output"] = $outA_Stop

    Write-Host "  -> PreInvocation Ciktisi : $($results.ScenarioA.PreInvocation_Output)" -ForegroundColor DarkGray
    Write-Host "  -> .vigiles_active       : $($results.ScenarioA.Vigiles_Active_Marker)" -ForegroundColor Green
    Write-Host "  -> .live_active          : $($results.ScenarioA.Live_Active_Marker)" -ForegroundColor Green
    Write-Host "  -> Telemetri Uretildi mi : $($results.ScenarioA.Telemetry_Generated)" -ForegroundColor Green

    # --------------------------------------------------------------------------
    # SENARYO B: /pro SESSIZ OTURUM (SAYFA/PORT ACILMAZ, YEREL KAYIT CALISIR)
    # --------------------------------------------------------------------------
    Write-Host "`n>>> [SENARYO B]: /pro SESSIZ OTURUM TEST EDILIYOR..." -ForegroundColor Yellow

    $outB_PreInv = Invoke-SimHook $ensureScript @{
        lastUserInput = "/pro kimlik dogrulama modulu ve testleri insa et"
        conversationId = "test-scenario-B-pro"
        artifactDirectoryPath = $dirProSilent
        invocationNum = 1
    }
    $results.ScenarioB["PreInvocation_Output"] = $outB_PreInv
    $results.ScenarioB["Vigiles_Active_Marker"] = Test-Path (Join-Path $dirProSilent ".vigiles_active")
    $results.ScenarioB["Live_Active_Marker"] = Test-Path (Join-Path $dirProSilent ".live_active")
    $results.ScenarioB["Live_Control_HTML_Copied"] = Test-Path (Join-Path $dirProSilent "live_mission_control.html")
    $results.ScenarioB["Injected_System_Message"] = ($outB_PreInv -match "CANLI OPERASYON MERKEZI DEVREDE")
    $results.ScenarioB["Port_Started"] = [bool](Get-NetTCPConnection -LocalPort $simPort -State Listen -ErrorAction SilentlyContinue)

    $outB_Tool = Invoke-SimHook $sentinelScript @{
        toolCall = @{
            name = "run_command"
            args = @{ CommandLine = "npm test -- auth.spec.js" }
        }
        conversationId = "test-scenario-B-pro"
        artifactDirectoryPath = $dirProSilent
    }
    $results.ScenarioB["Tool_Decision"] = $outB_Tool
    $results.ScenarioB["Local_State_Recorded"] = Test-Path (Join-Path $dirProSilent "live_state.json")
    $stateContentB = if ($results.ScenarioB.Local_State_Recorded) { Get-Content -Raw -Encoding UTF8 (Join-Path $dirProSilent "live_state.json") } else { "" }
    $results.ScenarioB["Active_Node"] = if ($stateContentB -match '"activeNode"\s*:\s*"([^"]+)"') { $matches[1] } else { "none" }

    Write-Host "  -> PreInvocation Yaniti  : $($results.ScenarioB.PreInvocation_Output)" -ForegroundColor Green
    Write-Host "  -> .vigiles_active       : $($results.ScenarioB.Vigiles_Active_Marker) | .live_active: $($results.ScenarioB.Live_Active_Marker)" -ForegroundColor Green
    Write-Host "  -> HTML Kopyalandi mi    : $($results.ScenarioB.Live_Control_HTML_Copied) | Port Basladi mi: $($results.ScenarioB.Port_Started)" -ForegroundColor Green
    Write-Host "  -> Yerel Kayit Aktif mi  : $($results.ScenarioB.Local_State_Recorded) (Aktif Dugum: $($results.ScenarioB.Active_Node))" -ForegroundColor Green

    # --------------------------------------------------------------------------
    # SENARYO C: /live OTURUMU (TAM CANLI OPERASYON MERKEZI)
    # --------------------------------------------------------------------------
    Write-Host "`n>>> [SENARYO C]: /live CANLI MERKEZ TEST EDILIYOR..." -ForegroundColor Yellow

    $outC_PreInv = Invoke-SimHook $ensureScript @{
        lastUserInput = "/live"
        conversationId = "test-scenario-C-live"
        artifactDirectoryPath = $dirLive
        invocationNum = 1
    }
    $results.ScenarioC["Vigiles_Active_Marker"] = Test-Path (Join-Path $dirLive ".vigiles_active")
    $results.ScenarioC["Live_Active_Marker"] = Test-Path (Join-Path $dirLive ".live_active")
    $results.ScenarioC["Live_Control_HTML_Copied"] = Test-Path (Join-Path $dirLive "live_mission_control.html")
    $results.ScenarioC["Injected_System_Message"] = ($outC_PreInv -match "CANLI OPERASYON MERKEZI DEVREDE")
    $results.ScenarioC["Port_Started"] = [bool](Get-NetTCPConnection -LocalPort $simPort -State Listen -ErrorAction SilentlyContinue)

    Invoke-SimHook $sentinelScript @{
        toolCall = @{
            name = "run_command"
            args = @{ CommandLine = "npm test -- live.spec.js" }
        }
        conversationId = "test-scenario-C-live"
        artifactDirectoryPath = $dirLive
    } | Out-Null

    Invoke-SimHook $stopScript @{
        conversationId = "test-scenario-C-live"
        artifactDirectoryPath = $dirLive
    } | Out-Null

    Start-Sleep -Milliseconds 150
    $serverSessions = Invoke-RestMethod -Uri "http://localhost:$simPort/sessions" -TimeoutSec 15 -ErrorAction Stop
    $results.ScenarioC["Sessions_Fetched"] = ($null -ne $serverSessions)
    $results.ScenarioC["Pro_Silent_Leaked_To_Server"] = (@($serverSessions | Where-Object { $_.conversationId -eq "test-scenario-B-pro" }).Count -gt 0)
    $serverStateC = Invoke-RestMethod -Uri "http://localhost:$simPort/state?cid=test-scenario-C-live" -TimeoutSec 10 -ErrorAction Stop
    $results.ScenarioC["Final_Status"] = $serverStateC.status

    Write-Host "  -> .live_active          : $($results.ScenarioC.Live_Active_Marker) | HTML: $($results.ScenarioC.Live_Control_HTML_Copied)" -ForegroundColor Green
    Write-Host "  -> Sistem Mesaji Enjekte : $($results.ScenarioC.Injected_System_Message) | Port: $($results.ScenarioC.Port_Started)" -ForegroundColor Green
    Write-Host "  -> Sessiz /pro Sizdi mi  : $($results.ScenarioC.Pro_Silent_Leaked_To_Server)" -ForegroundColor Green
    Write-Host "  -> Final Durumu (Sunucu) : $($results.ScenarioC.Final_Status)" -ForegroundColor Green

    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host "CANLI INCELEME SONUC RAPORU:" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan

    $scenarioA_Clean = (-not $results.ScenarioA.Vigiles_Active_Marker) -and (-not $results.ScenarioA.Live_Active_Marker) -and (-not $results.ScenarioA.Injected_System_Message) -and (-not $results.ScenarioA.Telemetry_Generated)
    $scenarioB_Silent = $results.ScenarioB.Vigiles_Active_Marker -and (-not $results.ScenarioB.Live_Active_Marker) -and (-not $results.ScenarioB.Live_Control_HTML_Copied) -and (-not $results.ScenarioB.Injected_System_Message) -and (-not $results.ScenarioB.Port_Started) -and $results.ScenarioB.Local_State_Recorded -and ($results.ScenarioB.Active_Node -eq "node-tester")
    $scenarioC_Live = $results.ScenarioC.Vigiles_Active_Marker -and $results.ScenarioC.Live_Active_Marker -and $results.ScenarioC.Live_Control_HTML_Copied -and $results.ScenarioC.Injected_System_Message -and $results.ScenarioC.Port_Started -and $results.ScenarioC.Sessions_Fetched -and (-not $results.ScenarioC.Pro_Silent_Leaked_To_Server) -and ($results.ScenarioC.Final_Status -eq "TESLIM_EDILDI")

    if ($scenarioA_Clean -and $scenarioB_Silent -and $scenarioC_Live) {
        Write-Host "[BASARILI] Cift bayrakli izolasyon %100 kusursuz calisiyor!" -ForegroundColor Green
        Write-Host "  - Senaryo A (Normal): Tamamen uykuda, 0 mudahale, 0 kayit." -ForegroundColor Green
        Write-Host "  - Senaryo B (/pro & /lite): Sayfa/Port ACILMADI, guvenlik ve sessiz yerel kayit aktif, acik panele SIZMADI." -ForegroundColor Green
        Write-Host "  - Senaryo C (/live): Yalnizca /live komutuyla Canli Merkez ve Port aktif." -ForegroundColor Green
        exit 0
    } else {
        Write-Host "[HATA] Izolasyon kriterlerinde uyumsuzluk tespit edildi!" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "[HATA] Simulasyon istisnasi: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    try {
        $procs = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
                 Where-Object { $_.CommandLine -match "telemetry_server\.ps1" -and $_.CommandLine -match "-Port $simPort" }
        foreach ($p in $procs) {
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
    } catch {}

    $env:VIGILES_CONFIG_DIR = $prevCfg
    $env:VIGILES_TELEMETRY_PORT = $prevPort
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
