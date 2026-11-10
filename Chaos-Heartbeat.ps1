param(
    [switch]$VerboseOutput
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$scriptRoot = $PSScriptRoot
$sentinelScript = Join-Path $scriptRoot "core\scripts\heartbeat_sentinel.ps1"

Write-Host "🐒 [KAOS MÜHENDİSİ]: Stres ve Sınır Değer Kaos Saldırıları Başlatılıyor..." -ForegroundColor Magenta

$passed = 0
$failed = 0

function Assert-Chaos([string]$name, [scriptblock]$condition) {
    try {
        $result = & $condition
        if ($result) {
            Write-Host "  🛡️ [DİRENÇLİ] $name" -ForegroundColor Green
            $script:passed++
        } else {
            Write-Host "  💥 [YIKILDI] $name" -ForegroundColor Red
            $script:failed++
        }
    } catch {
        Write-Host "  💥 [HATA] $name -> $($_.Exception.Message)" -ForegroundColor Red
        $script:failed++
    }
}

# 1. Bozuk / Yetkisiz Log Yolu Kaosu (Fail-Safe Denetimi)
Assert-Chaos "1. Bozuk veya geçersiz log dizininde betik çökmeksizin (graceful) çalışmalı" {
    $badLog = "Z:\gecersiz_surucu_9999\olmayan_dizin\heartbeat.log"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $sentinelScript -Once -DryRun -LogPath $badLog
    # Çökmemeli, exit code 0 dönmeli
    return ($LASTEXITCODE -eq 0)
}

# 2. Hatalı Model İsmi ile CLI Zafiyet Kaosu
Assert-Chaos "2. Geçersiz model adı verildiğinde kilitlenmeden hata logu üretip kontrollü çıkmalı" {
    $tempLog = Join-Path $scriptRoot "chaos_invalid_model.log"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $sentinelScript -Once -Model "nonexistent-model-xyz-999" -LogPath $tempLog
    $exitCode = $LASTEXITCODE
    $hasLog = Test-Path $tempLog
    if ($hasLog) {
        $logContent = Get-Content $tempLog -Raw -Encoding UTF8
        Remove-Item $tempLog -Force
        return ($exitCode -ne 0 -and ($logContent -match "ERROR" -or $logContent -match "WARNING"))
    }
    return ($exitCode -ne 0)
}

# 3. Seri / Eşzamanlı Çift Tetikleme Kaosu (Race Condition)
Assert-Chaos "3. Çift ardışık tetiklemede log dosyası kilitlenmemeli (Concurrency Safe)" {
    $concurrencyLog = Join-Path $scriptRoot "chaos_concurrent.log"
    if (Test-Path $concurrencyLog) { Remove-Item $concurrencyLog -Force }

    $job1 = Start-Job -ScriptBlock {
        param($script, $log)
        & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Once -DryRun -LogPath $log
    } -ArgumentList $sentinelScript, $concurrencyLog

    $job2 = Start-Job -ScriptBlock {
        param($script, $log)
        & powershell -NoProfile -ExecutionPolicy Bypass -File $script -Once -DryRun -LogPath $log
    } -ArgumentList $sentinelScript, $concurrencyLog

    Wait-Job $job1, $job2 -Timeout 10 | Out-Null
    Receive-Job $job1, $job2 | Out-Null
    Remove-Job $job1, $job2 -Force

    $hasLog = Test-Path $concurrencyLog
    if ($hasLog) {
        $lines = Get-Content $concurrencyLog -Encoding UTF8
        Remove-Item $concurrencyLog -Force
        return ($lines.Count -ge 2)
    }
    return $false
}

Write-Host "---"
Write-Host "Kaos Sonucu: $passed Dirençli, $failed Yıkıldı" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Magenta" })

if ($failed -gt 0) { exit 1 } else { exit 0 }
