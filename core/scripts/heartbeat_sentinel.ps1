param(
    [int]$IntervalHours = 5,
    [switch]$Once,
    [switch]$DryRun,
    [string]$LogPath = "",
    [string]$Model = "gemini-3.8-flash-low"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$scriptRoot = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($LogPath)) {
    $workspaceCandidate = Resolve-Path (Join-Path $scriptRoot "..\..") -ErrorAction SilentlyContinue
    if ($workspaceCandidate -and (Test-Path $workspaceCandidate)) {
        $LogPath = Join-Path $workspaceCandidate "heartbeat.log"
    } else {
        $LogPath = Join-Path $env:USERPROFILE ".gemini\antigravity\heartbeat.log"
    }
}

function Write-LogEntry([string]$level, [string]$message) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$level] $message"
    try {
        Add-Content -Path $LogPath -Value $entry -Encoding UTF8
    } catch {
        # Fail-safe: loglama engellenemez
    }
    Write-Host $entry -ForegroundColor $(if ($level -eq "SUCCESS") { "Green" } elseif ($level -eq "WARNING" -or $level -eq "ERROR") { "Red" } else { "Cyan" })
}

function Send-LiveTelemetry([string]$status, [string]$detail) {
    try {
        $telemetryUrl = "http://localhost:9999/api/telemetry"
        $body = @{
            node = "KD"
            nodeName = "18. KOTA DÜRTÜCÜSÜ (Heartbeat)"
            status = $status
            detail = $detail
            timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        } | ConvertTo-Json -Compress

        $null = Invoke-RestMethod -Uri $telemetryUrl -Method Post -Body $body -ContentType "application/json" -TimeoutSec 1 -ErrorAction SilentlyContinue
    } catch {
        # Telemetri sunucusu kapalıysa sessizce devam et (Fail-safe)
    }
}

function Invoke-MicroPing {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Write-LogEntry "INFO" "Kota Dürtme (Heartbeat) döngüsü başlatıldı. Hedef model: $Model"
    Send-LiveTelemetry "ACTIVE" "Mikro-ping gönderiliyor ($Model)..."

    if ($DryRun) {
        Start-Sleep -Milliseconds 150
        $sw.Stop()
        Write-LogEntry "SUCCESS" "[DRY-RUN] Mikro-ping başarıyla simüle edildi. Süre: $($sw.ElapsedMilliseconds)ms"
        Send-LiveTelemetry "SUCCESS" "[DRY-RUN] Simüle mikro-ping tamamlandı."
        return $true
    }

    try {
        # agy CLI ile tek atımlık prompt icrası
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "agy.exe"
        $processInfo.Arguments = "--effort low --model $Model --print=""ping"""
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null

        $completed = $process.WaitForExit(35000) # 35 saniye zaman aşımı
        $sw.Stop()

        if (-not $completed) {
            try { $process.Kill() } catch {}
            Write-LogEntry "WARNING" "Mikro-ping 35 saniyede yanıt alamadı (Zaman Aşımı)."
            Send-LiveTelemetry "WARNING" "Zaman aşımı oluştu."
            return $false
        }

        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()

        if ($process.ExitCode -eq 0) {
            $cleanResponse = ($stdout.Trim() -replace "`r`n", " ")[0..60] -join ""
            Write-LogEntry "SUCCESS" "Mikro-ping başarıyla teslim edildi. Yanıt: '$cleanResponse'. Süre: $($sw.ElapsedMilliseconds)ms"
            Send-LiveTelemetry "SUCCESS" "Kota başarıyla dürtüldü ($($sw.ElapsedMilliseconds)ms)."
            return $true
        } else {
            Write-LogEntry "ERROR" "agy hata kodu ile çıktı ($($process.ExitCode)): $stderr"
            Send-LiveTelemetry "ERROR" "Dürtme hatası: exit $($process.ExitCode)"
            return $false
        }
    } catch {
        $sw.Stop()
        Write-LogEntry "ERROR" "Dürtme işlemi sırasında istisna: $($_.Exception.Message)"
        Send-LiveTelemetry "ERROR" "İstisna oluştu."
        return $false
    }
}

# --- YÜRÜTME DÖNGÜSÜ ---
if ($Once) {
    $ok = Invoke-MicroPing
    exit $(if ($ok) { 0 } else { 1 })
} else {
    Write-LogEntry "INFO" "Vigiles Kota Dürtücüsü daemon modunda başlatıldı. Periyot: $IntervalHours saat."
    while ($true) {
        $null = Invoke-MicroPing
        Write-LogEntry "INFO" "Sonraki dürtme için $IntervalHours saat bekleniyor..."
        $sleepSeconds = [Math]::Max(60, $IntervalHours * 3600)
        # 10 saniyelik periyotlarla uyutarak iptallere açık tut
        $elapsed = 0
        while ($elapsed -lt $sleepSeconds) {
            Start-Sleep -Seconds 10
            $elapsed += 10
        }
    }
}
