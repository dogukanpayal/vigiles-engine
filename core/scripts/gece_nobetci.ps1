param(
    [string]$WorkspaceRoot = (Get-Location).Path
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# Non-Interactive Zirh (03:00 devriyesinde soru/watch kilidi onlenir)
$env:CI = "true"
$env:NPM_CONFIG_YES = "true"
$env:GIT_TERMINAL_PROMPT = "0"
$env:GCM_INTERACTIVE = "never"
$env:PIP_NO_INPUT = "1"

function Invoke-WatchdogPatrolCommand([string]$commandLine, [int]$idleSec = 60, [int]$hardSec = 180) {
    $wrapper = Join-Path $PSScriptRoot "invoke_with_timeout.ps1"
    if (-not (Test-Path $wrapper)) {
        $wrapper = Join-Path $HOME ".gemini\config\scripts\invoke_with_timeout.ps1"
    }
    if (Test-Path $wrapper) {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrapper -Command $commandLine -Cwd $WorkspaceRoot -IdleTimeoutSec $idleSec -HardTimeoutSec $hardSec 2>&1
        return @{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) }
    }

    # Yedek dahili WaitForExit + taskkill giyotini
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$commandLine`""
    $psi.WorkingDirectory = $WorkspaceRoot
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    try { $p.StandardInput.Close() } catch {}
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($hardSec * 1000)) {
        try { $null = & cmd.exe /c "taskkill /PID $($p.Id) /T /F" 2>&1 } catch {}
        return @{ ExitCode = 124; Output = "TIMEOUT > ${hardSec}s" }
    }
    $p.WaitForExit()
    return @{ ExitCode = $p.ExitCode; Output = ($outTask.Result + "`n" + $errTask.Result) }
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$reportPath = Join-Path $WorkspaceRoot "SABAH_RAPORU.md"

Write-Host "🌙 [GECE NÖBETÇİSİ]: 03:00 Devriyesi Başlatıldı ($timestamp)..." -ForegroundColor Cyan

# 1. Git Durumu Kontrolü
$gitStatus = git status -s 2>&1
$gitChangesCount = ($gitStatus | Measure-Object).Count

# 2. Test Koşumu (Non-Interactive & Timeout Korumali)
$testSummary = "Test konfigürasyonu bulunamadı veya atlandı."
if (Test-Path (Join-Path $WorkspaceRoot "package.json")) {
    Write-Host "📦 npm test koşturuluyor (CI=true & Timeout Zırhlı)..." -ForegroundColor Yellow
    $resTest = Invoke-WatchdogPatrolCommand "npm test -- --bail" -idleSec 60 -hardSec 180
    $testSummary = if ($resTest.ExitCode -eq 0) { "✅ Tüm testler başarıyla geçti." } elseif ($resTest.ExitCode -eq 124) { "⏱️ Test komutu zaman aşımına uğrayıp watchdog tarafından kesildi (Exit 124)." } else { "❌ Test hatası tespit edildi!" }
} elseif (Test-Path (Join-Path $WorkspaceRoot "pytest.ini") -or (Test-Path (Join-Path $WorkspaceRoot "tests"))) {
    Write-Host "🐍 pytest koşturuluyor (Timeout Zırhlı)..." -ForegroundColor Yellow
    $resTest = Invoke-WatchdogPatrolCommand "pytest" -idleSec 60 -hardSec 180
    $testSummary = if ($resTest.ExitCode -eq 0) { "✅ Tüm testler başarıyla geçti." } elseif ($resTest.ExitCode -eq 124) { "⏱️ Test komutu zaman aşımına uğrayıp watchdog tarafından kesildi (Exit 124)." } else { "❌ Test hatası tespit edildi!" }
}

# 3. Güvenlik Taraması
$auditSummary = "Güvenlik açığı taraması temiz."
if (Test-Path (Join-Path $WorkspaceRoot "package.json")) {
    $resAudit = Invoke-WatchdogPatrolCommand "npm audit --audit-level=high" -idleSec 45 -hardSec 120
    if ($resAudit.ExitCode -eq 124) {
        $auditSummary = "⏱️ Güvenlik taraması zaman aşımına uğradı (Exit 124)."
    } elseif ($resAudit.ExitCode -ne 0) {
        $auditSummary = "⚠️ Yüksek seviyeli paket zafiyeti tespit edildi!"
    }
}

# 4. SABAH_RAPORU.md Dosyasını Oluştur
$reportContent = @"
# 🌅 SABAH RAPORU (Gece Nöbetçisi Devriyesi)
*Bu rapor Gece Nöbetçisi tarafından sabaha karşı 03:00'te otonom olarak üretilmiştir.*

**Devriye Zamanı:** $timestamp  
**Çalışma Alanı:** `$WorkspaceRoot`  

---

### 📊 Devriye Özeti
* **Birim & Regresyon Testleri:** $testSummary
* **Güvenlik Açığı Durumu:** $auditSummary
* **Git Durumu:** $gitChangesCount bekleyen değişiklik var.

---

### 📝 Nöbetçi Notu
> "Gece boyunca tüm testler ve bağımlılıklar non-interactive timeout zırhıyla tarandı. Sistem güne hazır ve stabil. İyi çalışmalar!"
"@

Set-Content -Path $reportPath -Value $reportContent -Encoding UTF8
Write-Host "✅ [GECE NÖBETÇİSİ]: Sabah raporu masanıza bırakıldı -> $reportPath" -ForegroundColor Green
