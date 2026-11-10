# Scenario-RoleOrderLifecycle.ps1
# Vigiles Uctan Uca Gercekci Senaryo Simulasyonu ve Rol Siralamasi Dogrulamasi

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$global:scenarioPassed = 0
$global:scenarioFailed = 0

function Assert-Step([string]$stepNumber, [string]$stepName, [bool]$condition, [string]$detail = "") {
    if ($condition) {
        Write-Host "  [ADIM ${stepNumber} - GECTI] $stepName" -ForegroundColor Green
        if ($detail) { Write-Host "     -> $detail" -ForegroundColor DarkGray }
        $global:scenarioPassed++
    } else {
        Write-Host "  [ADIM ${stepNumber} - BASARISIZ] $stepName" -ForegroundColor Red
        if ($detail) { Write-Host "     -> HATA: $detail" -ForegroundColor Yellow }
        $global:scenarioFailed++
    }
}

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "SCENARIO: VIGILES UCTAN UCA GERCEKCI GELISME VE ROL SIRALAMASI" -ForegroundColor Yellow
Write-Host "Gorev: 'Kullanici Bildirim Servisi (Notification Service) Gelistirme'" -ForegroundColor Gray
Write-Host "==================================================================" -ForegroundColor Cyan

$scriptToTest = "c:\Users\Dogukan\Desktop\Antigravity Improvement\core\scripts\sentinel_guard.ps1"
if (-not (Test-Path $scriptToTest)) {
    $scriptToTest = Join-Path $HOME ".gemini\config\scripts\sentinel_guard.ps1"
}

$tempScenarioDir = Join-Path ([System.IO.Path]::GetTempPath()) "vigiles_scenario_$(Get-Random)"
New-Item -ItemType Directory -Path $tempScenarioDir -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $tempScenarioDir ".vigiles_active") -Force | Out-Null

function Invoke-ScenarioAction([hashtable]$toolCallPayload) {
    $payloadObj = @{
        conversationId        = "scenario-notification-svc-999"
        artifactDirectoryPath = $tempScenarioDir
        workspacePaths        = @("C:\Projects\NotificationService")
        toolCall              = $toolCallPayload
    }
    $json = $payloadObj | ConvertTo-Json -Depth 6 -Compress

    $stateFile = Join-Path $tempScenarioDir "live_state.json"
    if (Test-Path $stateFile) { Remove-Item $stateFile -Force }

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = "powershell.exe"
    $pinfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptToTest`""
    $pinfo.RedirectStandardInput = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false

    $p = [System.Diagnostics.Process]::Start($pinfo)
    $p.StandardInput.Write($json)
    $p.StandardInput.Close()
    $p.WaitForExit()

    $state = $null
    if (Test-Path $stateFile) {
        try {
            $state = Get-Content -Raw -Encoding UTF8 $stateFile | ConvertFrom-Json
        } catch {}
    }
    return $state
}

try {
    # -------------------------------------------------------------
    # FAZ 1: ŞANTİYE KEŞFİ VE ZEMİN ETÜDÜ (BAŞ MİMAR)
    # -------------------------------------------------------------
    Write-Host "`n--- FAZ 1: Santiye Kesfi ve Zemin Etudu (Bas Mimar) ---" -ForegroundColor Cyan

    # Adım 1.1: Proje dizin taraması
    $s1 = Invoke-ScenarioAction @{ name = "run_command"; args = @{ CommandLine = "Get-ChildItem -Recurse" } }
    Assert-Step "1.1" "Dizin Taramasi (Get-ChildItem) -> Bas Mimar Kesfi" ($s1.activeNode -eq "node-architect" -and $s1.step -eq 1) "Düğüm: $($s1.activeNode) | Başlık: $($s1.title)"

    # Adım 1.2: Git durum incelemesi (ESKİDEN node-pr YAKAN KRİTİK NOKTA)
    $s2 = Invoke-ScenarioAction @{ name = "run_command"; args = @{ CommandLine = "git status" } }
    Assert-Step "1.2" "Git Durum Incelemesi (git status) -> Kesif Fazinda Kalmali (node-pr ASLA olmamali)" ($s2.activeNode -eq "node-architect" -and $s2.activeNode -ne "node-pr") "Düğüm: $($s2.activeNode) | Başlık: $($s2.title)"

    # Adım 1.3: Git fark incelemesi
    $s3 = Invoke-ScenarioAction @{ name = "run_command"; args = @{ CommandLine = "git diff HEAD~1" } }
    Assert-Step "1.3" "Git Fark Incelemesi (git diff) -> Depo ve Versiyon Kesfi" ($s3.activeNode -eq "node-architect") "Düğüm: $($s3.activeNode) | Başlık: $($s3.title)"

    # Adım 1.4: Mevcut paket/ayar dosyasını okuma (ESKİDEN null DÖNEN KÖR NOKTA)
    $s4 = Invoke-ScenarioAction @{ name = "read_file"; args = @{ Path = "C:\Projects\NotificationService\package.json" } }
    Assert-Step "1.4" "Paket Ayarlarini Okuma (package.json) -> Mimari Kod Incelemesi" ($s4.activeNode -eq "node-architect" -and $s4.step -eq 1) "Düğüm: $($s4.activeNode) | Başlık: $($s4.title)"

    # -------------------------------------------------------------
    # FAZ 2: MİMARİ SÖZLEŞME VE ŞANTİYE DEFTERİ (BAŞ MİMAR)
    # -------------------------------------------------------------
    Write-Host "`n--- FAZ 2: Mimari Sozlesme ve Santiye Plani (Bas Mimar) ---" -ForegroundColor Cyan

    # Adım 2: DURUM.md yazımı
    $s5 = Invoke-ScenarioAction @{ name = "write_file"; args = @{ Path = "C:\Projects\NotificationService\DURUM.md"; Content = "# Plan" } }
    Assert-Step "2.1" "Santiye Defteri (DURUM.md) -> Asama 2: Bas Mimar Statik Planlama" ($s5.activeNode -eq "node-architect" -and $s5.step -eq 2) "Düğüm: $($s5.activeNode) | Başlık: $($s5.title)"

    # -------------------------------------------------------------
    # FAZ 3: KRİTİK YOL AYRIMI (KARAR SÜZGECİ)
    # -------------------------------------------------------------
    Write-Host "`n--- FAZ 3: Karar Suzgeci (Type-1 Door Pop-Up) ---" -ForegroundColor Cyan

    # Adım 3: ask_question pop-up
    $s6 = Invoke-ScenarioAction @{ name = "ask_question"; args = @{ questions = @(@{ question = "Kuyruk motoru seçimi?"; options = @("Redis Streams", "RabbitMQ") }) } }
    Assert-Step "3.1" "Kritik Karar Pop-Up (ask_question) -> Asama 3: Karar Suzgeci" ($s6.activeNode -eq "node-gatekeeper" -and $s6.step -eq 3) "Düğüm: $($s6.activeNode) | Başlık: $($s6.title)"

    # -------------------------------------------------------------
    # FAZ 4: İŞ DAĞITIMI (SUBAGENT SAHA ŞEFİ)
    # -------------------------------------------------------------
    Write-Host "`n--- FAZ 4: Is Dagitimi (Subagent Saha Sefi) ---" -ForegroundColor Cyan

    # Adım 4: invoke_subagent
    $s7 = Invoke-ScenarioAction @{ name = "invoke_subagent"; args = @{ Role = "Notification FullStack Dev"; Prompt = "Bildirim servisini kodla" } }
    Assert-Step "4.1" "Alt Ajan Gorevlendirme (invoke_subagent) -> Asama 4: Saha Sefi" ($s7.activeNode -eq "node-chief" -and $s7.step -eq 4) "Düğüm: $($s7.activeNode) | Başlık: $($s7.title)"

    # -------------------------------------------------------------
    # FAZ 5: TDD KIRMIZI FAZ (ÖZEL TESTÇİ)
    # -------------------------------------------------------------
    Write-Host "`n--- FAZ 5: TDD Kirmizi Faz (Ozel Testci) ---" -ForegroundColor Cyan

    # Adım 5: Test dosyası oluşturma
    $s8 = Invoke-ScenarioAction @{ name = "write_file"; args = @{ Path = "C:\Projects\NotificationService\Test-Notification.ps1"; Content = "# Test suite" } }
    Assert-Step "5.1" "Test Dosyasi Uretimi (Test-*.ps1) -> Asama 5: Ozel Testci" ($s8.activeNode -eq "node-tester" -and $s8.step -eq 5) "Düğüm: $($s8.activeNode) | Başlık: $($s8.title)"

    # -------------------------------------------------------------
    # FAZ 6: TDD YEŞİL FAZ (İŞÇİLER KAYNAK KOD GELİŞTİRME)
    # -------------------------------------------------------------
    Write-Host "`n--- FAZ 6: TDD Yesil Faz (Isciler Kaynak Kod) ---" -ForegroundColor Cyan

    # Adım 6.1: Kaynak kod dosyası yazımı
    $s9 = Invoke-ScenarioAction @{ name = "write_file"; args = @{ Path = "C:\Projects\NotificationService\NotificationService.ps1"; Content = "function Send-Notification {}" } }
    Assert-Step "6.1" "Uretim Kodu Gelistirme (NotificationService.ps1) -> Asama 6: Isciler" ($s9.activeNode -eq "node-workers" -and $s9.step -eq 6) "Düğüm: $($s9.activeNode) | Başlık: $($s9.title)"

    # Adım 6.2: Geliştirme ortamı komutu yürütme
    $s10 = Invoke-ScenarioAction @{ name = "run_command"; args = @{ CommandLine = "node server.js" } }
    Assert-Step "6.2" "Komut Yurütme (node server.js) -> Asama 7: Isciler Komut Calisiyor" ($s10.activeNode -eq "node-workers" -and $s10.step -eq 7) "Düğüm: $($s10.activeNode) | Başlık: $($s10.title)"

    # -------------------------------------------------------------
    # FAZ 7: BİRİM TEST KOŞUMU (ÖZEL TESTÇİ)
    # -------------------------------------------------------------
    Write-Host "`n--- FAZ 7: Birim Test Kosumu (Ozel Testci) ---" -ForegroundColor Cyan

    # Adım 7: Test-Notification koşumu
    $s11 = Invoke-ScenarioAction @{ name = "run_command"; args = @{ CommandLine = "powershell -File .\Test-Notification.ps1" } }
    Assert-Step "7.1" "Birim Test Kosumu (powershell Test-*.ps1) -> Asama 5: Ozel Testci" ($s11.activeNode -eq "node-tester" -and $s11.step -eq 5) "Düğüm: $($s11.activeNode) | Başlık: $($s11.title)"

    # -------------------------------------------------------------
    # FAZ 8: KAOS VE STRES TESTİ (KAOS MÜHENDİSİ)
    # -------------------------------------------------------------
    Write-Host "`n--- FAZ 8: Kaos ve Dayaniklilik Testi (Kaos Muhendisi) ---" -ForegroundColor Cyan

    # Adım 8: Kaos saldırısı
    $s12 = Invoke-ScenarioAction @{ name = "run_command"; args = @{ CommandLine = "powershell -File .\Chaos-NotificationLoad.ps1" } }
    Assert-Step "8.1" "Dayaniklilik Saldirisi (Chaos-*.ps1) -> Asama 8: Kaos Muhendisi" ($s12.activeNode -eq "node-chaos" -and $s12.step -eq 8) "Düğüm: $($s12.activeNode) | Başlık: $($s12.title)"

    # -------------------------------------------------------------
    # FAZ 9: KURUMSAL HAFIZA GÜNCELLEMESİ (HAFIZA UZMANI)
    # -------------------------------------------------------------
    Write-Host "`n--- FAZ 9: Kurumsal Hafiza ve Anayasa (Hafiza Uzmani) ---" -ForegroundColor Cyan

    # Adım 9: KURALLAR.md güncellemesi
    $s13 = Invoke-ScenarioAction @{ name = "write_file"; args = @{ Path = "C:\Projects\NotificationService\KURALLAR.md"; Content = "* [KURAL-999]: Test kuralı" } }
    Assert-Step "9.1" "Anayasa Guncellemesi (KURALLAR.md) -> Asama 14: Hafiza Uzmani" ($s13.activeNode -eq "node-memory" -and $s13.step -eq 14) "Düğüm: $($s13.activeNode) | Başlık: $($s13.title)"

    # -------------------------------------------------------------
    # FAZ 10: CANLI DENEME TAHTASI (INTERACTIVE PLAYGROUND)
    # -------------------------------------------------------------
    Write-Host "`n--- FAZ 10: Canli Deneme Tahtasi (Playground) ---" -ForegroundColor Cyan

    # Adım 10: live_playground.html güncellemesi
    $s14 = Invoke-ScenarioAction @{ name = "write_file"; args = @{ Path = "C:\Projects\NotificationService\live_playground.html"; Content = "<html></html>" } }
    Assert-Step "10.1" "Interaktif Test Arayuzu (live_playground) -> Asama 15: Canli Deneme Tahtasi" ($s14.activeNode -eq "node-playground" -and $s14.step -eq 15) "Düğüm: $($s14.activeNode) | Başlık: $($s14.title)"

    # -------------------------------------------------------------
    # FAZ 11: GERÇEK VERSİYONLAMA VE DAĞITIM (GİT & PR FABRİKASI)
    # -------------------------------------------------------------
    Write-Host "`n--- FAZ 11: Gercek Versiyonlama ve Dagitim (Git & PR Fabrikasi) ---" -ForegroundColor Cyan

    # Adım 11: git_push_manager.ps1 (/push komutu)
    $s15 = Invoke-ScenarioAction @{ name = "run_command"; args = @{ CommandLine = "powershell -File C:\scripts\git_push_manager.ps1 -CommitMessage 'feat: notification service ready'" } }
    Assert-Step "11.1" "Tek Komutla /push (git_push_manager.ps1) -> Asama 12: Git ve PR Fabrikasi (YALNIZCA BURADA!)" ($s15.activeNode -eq "node-pr" -and $s15.step -eq 12) "Düğüm: $($s15.activeNode) | Başlık: $($s15.title)"

} finally {
    if (Test-Path $tempScenarioDir) {
        Remove-Item -Path $tempScenarioDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n==================================================================" -ForegroundColor Cyan
$color = if ($global:scenarioFailed -eq 0) { "Green" } else { "Red" }
Write-Host "SENARYO SIMULASYON SONUCU: $global:scenarioPassed GECTI | $global:scenarioFailed BASARISIZ" -ForegroundColor $color
Write-Host "==================================================================" -ForegroundColor Cyan

if ($global:scenarioFailed -gt 0) {
    exit 1
} else {
    exit 0
}
