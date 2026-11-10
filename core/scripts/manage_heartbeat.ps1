param(
    [ValidateSet("status", "install", "uninstall", "trigger")]
    [string]$Action = "status",
    [int]$IntervalHours = 5
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$taskName = "VigilesKotaDurtucusu"
$scriptRoot = $PSScriptRoot
$sentinelScript = Join-Path $scriptRoot "heartbeat_sentinel.ps1"
$globalConfigDir = Join-Path $env:USERPROFILE ".gemini\config\scripts"
$globalSentinel = Join-Path $globalConfigDir "heartbeat_sentinel.ps1"

# Eger yerel script yoksa globale bak, varsa globale de kopyala
if (-not (Test-Path $sentinelScript) -and (Test-Path $globalSentinel)) {
    $sentinelScript = $globalSentinel
}

switch ($Action) {
    "status" {
        Write-Host "[KOTA DURTUCUSU]: Durum Denetleniyor..." -ForegroundColor Cyan
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
            Write-Host "  [OK] Gorev Kurulu: Evet ($taskName)" -ForegroundColor Green
            Write-Host "  Durum: $($task.State)" -ForegroundColor Green
            Write-Host "  Son Calisma: $($taskInfo.LastRunTime)" -ForegroundColor Yellow
            Write-Host "  Sonraki Calisma: $($taskInfo.NextRunTime)" -ForegroundColor Yellow
            Write-Host "  Son Sonuc Kodu: $($taskInfo.LastTaskResult)" -ForegroundColor Cyan
        } else {
            Write-Host "  [INFO] Gorev su anda Windows Gorev Zamanlayicisi'nda kurulu degil." -ForegroundColor Yellow
        }
        exit 0
    }

    "install" {
        Write-Host "[KOTA DURTUCUSU]: Kurulum Baslatiliyor (Periyot: $IntervalHours saat)..." -ForegroundColor Cyan

        # Global dizine kopyala
        if (-not (Test-Path $globalConfigDir)) {
            New-Item -ItemType Directory -Path $globalConfigDir -Force | Out-Null
        }
        Copy-Item -Path $sentinelScript -Destination $globalSentinel -Force
        $targetScript = $globalSentinel

        # Eski gorevi temizle
        $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existing) {
            Write-Host "  [INFO] Mevcut gorev guncelleniyor..." -ForegroundColor Yellow
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        }

        # Yeni eylem ve tetikleyici olustur
        $actionArgs = "-WindowStyle Hidden -ExecutionPolicy Bypass -NoProfile -File `"$targetScript`" -Once -IntervalHours $IntervalHours"
        $actionDef = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $actionArgs
        
        # Her X saatte bir tetikleme
        $startTime = (Get-Date).AddMinutes(1)
        $triggerDef = New-ScheduledTaskTrigger -Once -At $startTime -RepetitionInterval (New-TimeSpan -Hours $IntervalHours) -RepetitionDuration (New-TimeSpan -Days 3650)
        
        $settingsDef = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

        Register-ScheduledTask -TaskName $taskName -Action $actionDef -Trigger $triggerDef -Settings $settingsDef -Description "Vigiles Otonom Kota Durtucusu (Heartbeat Sentinel - 5 Saatlik Periyot)" | Out-Null

        Write-Host "  [BASARILI]: Gorev Windows Gorev Zamanlayicisi'na basariyla kaydedildi: $taskName" -ForegroundColor Green
        Write-Host "  Ilk calisma 1 dakika sonra baslayacak, ardindan her $IntervalHours saatte bir otomatik tekrarlanacaktir." -ForegroundColor Green
        exit 0
    }

    "uninstall" {
        Write-Host "[KOTA DURTUCUSU]: Gorev Kaldiriliyor..." -ForegroundColor Yellow
        $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($existing) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
            Write-Host "  [BASARILI]: Gorev sistemden kaldirildi: $taskName" -ForegroundColor Green
        } else {
            Write-Host "  [INFO] Zaten kurulu bir gorev bulunamadi." -ForegroundColor Yellow
        }
        exit 0
    }

    "trigger" {
        Write-Host "[KOTA DURTUCUSU]: Manuel Tetikleme Baslatiliyor..." -ForegroundColor Cyan
        & powershell.exe -ExecutionPolicy Bypass -NoProfile -File $sentinelScript -Once
        exit $LASTEXITCODE
    }
}
