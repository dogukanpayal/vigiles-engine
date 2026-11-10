param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

$rawInput = [Console]::In.ReadToEnd()

if ([string]::IsNullOrWhiteSpace($rawInput)) {
    Write-Output '{"decision":"allow"}'
    exit 0
}

try {
    $payload = $rawInput | ConvertFrom-Json
} catch {
    Write-Output '{"decision":"allow"}'
    exit 0
}

$toolCall = $payload.toolCall
if (-not $toolCall) {
    Write-Output '{"decision":"allow"}'
    exit 0
}

$toolName = $toolCall.name
$args = $toolCall.args
$artifactDir = $payload.artifactDirectoryPath
if ([string]::IsNullOrWhiteSpace($artifactDir)) {
    $artifactDir = "C:\Users\Dogukan\.gemini\antigravity\brain\f6dee0d7-3f60-474d-8a94-ce06e0039c63"
}

# --- YARDIMCI: TELEMETRI YAYINI ---
function Send-Telemetry([hashtable]$state) {
    try {
        $stateJson = $state | ConvertTo-Json -Depth 6 -Compress

        # 1. live_state.js (Zero-CORS fallback)
        $jsContent = "// Antigravity Canli Telemetri Kancasi`nwindow.__ANTIGRAVITY_STATE__ = $stateJson;`nif (typeof window.onAntigravityStateUpdate === 'function') { window.onAntigravityStateUpdate(window.__ANTIGRAVITY_STATE__); }"
        $jsPath = Join-Path $artifactDir "live_state.js"
        [System.IO.File]::WriteAllText($jsPath, $jsContent, [System.Text.Encoding]::UTF8)

        # 2. live_state.json
        $jsonPath = Join-Path $artifactDir "live_state.json"
        [System.IO.File]::WriteAllText($jsonPath, $stateJson, [System.Text.Encoding]::UTF8)

        # 3. live_events.jsonl (Olay Gunlugu)
        $logPath = Join-Path $artifactDir "live_events.jsonl"
        $eventEntry = @{
            timestamp = $state.timestamp
            sender    = $state.sender
            title     = $state.title
            node      = $state.activeNode
            tool      = $toolName
        } | ConvertTo-Json -Compress
        [System.IO.File]::AppendAllText($logPath, "$eventEntry`n", [System.Text.Encoding]::UTF8)

        # 4. Yerel SSE Sunucusuna HTTP POST (Port 9999) - Hizli ve Non-Blocking
        try {
            $req = [System.Net.WebRequest]::Create("http://localhost:9999/notify")
            $req.Method = "POST"
            $req.ContentType = "application/json; charset=utf-8"
            $req.Timeout = 150
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($stateJson)
            $req.ContentLength = $bytes.Length
            $stream = $req.GetRequestStream()
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Dispose()
            $resp = $req.GetResponse()
            $resp.Dispose()
        } catch {}
    } catch {}
}

# --- 1. GUVENLIK VE SIZINTI KONTROLLERI (Zero-Leak Muhafizi) ---
if ($toolName -in @("write_file", "edit_file")) {
    $textToCheck = ""
    if ($args.Content) { $textToCheck += $args.Content }
    if ($args.Replacement) { $textToCheck += " " + $args.Replacement }

    $secretPatterns = @(
        'AKIA[0-9A-Z]{16}',
        'sk-[a-zA-Z0-9]{20,}',
        '(sk|rk)_(live|test)_[0-9a-zA-Z]{24,}',
        'ghp_[0-9a-zA-Z]{36}',
        '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
    )

    foreach ($pattern in $secretPatterns) {
        if ($textToCheck -match $pattern) {
            $telemetry = @{
                step        = 9
                totalSteps  = 15
                activeNode  = "node-shield"
                animClass   = "node-active-red"
                status      = "GUVENLIK_ENGELI"
                title       = "GUVENLIK IHLALI: Kod Icinde API Anahtari Engellendi!"
                sender      = "[9. GUVENLIK MUHAFIZI]"
                message     = "Zero-Leak Kalkani: Kod icine acik API anahtari yazilmaya calisildi; islem bloke edildi!"
                timestamp   = (Get-Date).ToString("HH:mm:ss")
                badge       = @{ id = "badge-shield"; text = "SIZINTI ENGELLENDI"; class = "bg-rose-500/20 text-rose-400 border-rose-500/40 font-bold animate-pulse" }
            }
            Send-Telemetry $telemetry

            $response = @{
                decision = "deny"
                reason = "[ZERO-LEAK GUVENLIK MUHAFIZI]: Kod icinde acik API anahtari tespit edildi! Lutfen process.env kullanin."
            }
            Write-Output ($response | ConvertTo-Json -Compress)
            exit 0
        }
    }
}

if ($toolName -eq "run_command") {
    $cmd = if ($args.CommandLine) { $args.CommandLine } else { "" }

    if ($cmd -match 'git\s+add\s+.*\.env(\s|$)' -or $cmd -match 'git\s+commit\s+.*\.env') {
        $response = @{
            decision = "deny"
            reason = "[ZERO-LEAK GUVENLIK MUHAFIZI]: .env dosyasini git deposuna ekleyemezsiniz!"
        }
        Write-Output ($response | ConvertTo-Json -Compress)
        exit 0
    }

    if ($cmd -match 'git\s+push\s+.*--force.*(main|master)') {
        $response = @{
            decision = "deny"
            reason = "[GUVENLIK MUHAFIZI]: Ana branch uzerine force push yapamazsiniz!"
        }
        Write-Output ($response | ConvertTo-Json -Compress)
        exit 0
    }

    if ($cmd -match '(npm\s+(i|install|add)|yarn\s+add|pnpm\s+add)\s+.*(moment|lodash)(\s|$)' -and -not ($cmd -match 'lodash-es')) {
        $response = @{
            decision = "deny"
            reason = "[ANTI-BLOAT MUHAFIZI]: 15MB+ siskin kutuphane (moment/lodash) tespit edildi!"
        }
        Write-Output ($response | ConvertTo-Json -Compress)
        exit 0
    }
}

# --- 2. AKILLI 20-ELEMAN TELEMETRI ESLEMESI ---
$isInternalStateFile = $false
if ($toolName -in @("write_file", "edit_file") -and $args.Path) {
    if ($args.Path -match 'live_state|live_events|telemetry') {
        $isInternalStateFile = $true
    }
}

if (-not $isInternalStateFile) {
    $time = (Get-Date).ToString("HH:mm:ss")
    $telemetry = $null

    if ($toolName -eq "run_command") {
        $cmd = if ($args.CommandLine) { $args.CommandLine } else { "" }
        if ($cmd -match 'Test-|pester|pytest|npm test') {
            $telemetry = @{
                step        = 5
                totalSteps  = 15
                activeNode  = "node-tester"
                animClass   = "node-active-default"
                status      = "TEST_KOSULUYOR"
                title       = "ASAMA 5 / 15: Ozel Testci Devrede"
                sender      = "[11. OZEL TESTCI (TDD)]"
                message     = "Birim Testi Kosuluyor: $cmd"
                desc        = "TDD Dongusu: Testler otonom olarak terminal uzerinden calistiriliyor."
                timestamp   = $time
                badge       = @{ id = "badge-tester"; text = "Test Kosuluyor"; class = "bg-rose-500/20 text-rose-400 border-rose-500/40 font-bold animate-pulse" }
            }
        } elseif ($cmd -match 'Chaos-') {
            $telemetry = @{
                step        = 8
                totalSteps  = 15
                activeNode  = "node-chaos"
                animClass   = "node-active-chaos"
                status      = "KAOS_SALDIRISI"
                title       = "ASAMA 8 / 15: Kaos Muhendisi Devrede"
                sender      = "[12. KAOS MUHENDISI]"
                message     = "Dayaniklilik ve Yaris Durumu Saldirisi: $cmd"
                desc        = "Kaos Testi: Eszamanli istekler ve sinir deger saldirilari puskurtuluyor."
                timestamp   = $time
                badge       = @{ id = "badge-chaos"; text = "Stres Saldirisi"; class = "bg-amber-500/20 text-amber-400 border-amber-500/40 font-bold animate-pulse" }
            }
        } elseif ($cmd -match 'git') {
            $telemetry = @{
                step        = 12
                totalSteps  = 15
                activeNode  = "node-pr"
                animClass   = "node-active-default"
                status      = "GIT_ISLEMI"
                title       = "ASAMA 12 / 15: Git ve PR Fabrikasi"
                sender      = "[20. GIT VE PR FABRIKASI]"
                message     = "Versiyonlama ve Branch Yonetimi: $cmd"
                desc        = "Surum Yonetimi: Git deposu guncelleniyor."
                timestamp   = $time
                badge       = @{ id = "badge-pr"; text = "Git Calisiyor"; class = "bg-purple-500/20 text-purple-400 border-purple-500/40 font-bold" }
            }
        } else {
            $telemetry = @{
                step        = 7
                totalSteps  = 15
                activeNode  = "node-workers"
                animClass   = "node-active-default"
                status      = "KOMUT_CALISIYOR"
                title       = "ASAMA 7 / 15: Isciler (Terminal Komutu)"
                sender      = "[7. ISCILER (Autonomous Workers)]"
                message     = "Terminal Komutu Yurutuluyor: $cmd"
                desc        = "Isci Birimi: Yerel ortamda komut calistiriliyor."
                timestamp   = $time
                badge       = @{ id = "badge-workers"; text = "Komut Yurutuluyor"; class = "bg-emerald-500/20 text-emerald-400 border-emerald-500/40 font-bold animate-pulse" }
            }
        }
    }
    elseif ($toolName -in @("write_file", "edit_file")) {
        $path = if ($args.Path) { $args.Path } else { "" }
        $leaf = Split-Path $path -Leaf

        if ($path -match 'DURUM\.md') {
            $telemetry = @{
                step        = 2
                totalSteps  = 15
                activeNode  = "node-architect"
                animClass   = "node-active-architect"
                status      = "MIMARI_PLANLAMA"
                title       = "ASAMA 2 / 15: Bas Mimar Statik Planlama"
                sender      = "[2. BAS MIMAR (Lead Planner)]"
                message     = "Kabul Kriterleri ve Santiye Defteri (DURUM.md) guncelleniyor."
                desc        = "Mimari Sozlesme: Gorevin sinirlari ve kabul kriterleri belirleniyor."
                timestamp   = $time
                badge       = @{ id = "badge-architect"; text = "Plan Ciziliyor"; class = "bg-indigo-500/20 text-indigo-400 border-indigo-500/40 font-bold animate-pulse" }
            }
        } elseif ($path -match 'KURALLAR\.md') {
            $telemetry = @{
                step        = 14
                totalSteps  = 15
                activeNode  = "node-memory"
                animClass   = "node-active-default"
                status      = "HAFIZA_GUNCELLEME"
                title       = "ASAMA 14 / 15: Hafiza Uzmani Devrede"
                sender      = "[14. HAFIZA UZMANI (Memory Extractor)]"
                message     = "Sirket Anayasasi ve Kurallar (KURALLAR.md) guncelleniyor."
                desc        = "Kurumsal Hafiza: Gorevden ogrenilen dersler kalici anayasaya isleniyor."
                timestamp   = $time
                badge       = @{ id = "badge-memory"; text = "Hafiza Kaydediliyor"; class = "bg-purple-500/20 text-purple-400 border-purple-500/40 font-bold animate-pulse" }
            }
        } elseif ($path -match 'Test-') {
            $telemetry = @{
                step        = 5
                totalSteps  = 15
                activeNode  = "node-tester"
                animClass   = "node-active-default"
                status      = "TEST_YAZILIYOR"
                title       = "ASAMA 5 / 15: Ozel Testci (Test Dosyasi)"
                sender      = "[11. OZEL TESTCI (TDD)]"
                message     = "Test Dosyasi Hazirlaniyor: $leaf"
                desc        = "TDD Kirmizi Faz: Kabul kriterlerini dogrulayan birim test yaziliyor."
                timestamp   = $time
                badge       = @{ id = "badge-tester"; text = "Test Yaziliyor"; class = "bg-rose-500/20 text-rose-400 border-rose-500/40 font-bold animate-pulse" }
            }
        } elseif ($path -match 'Chaos-') {
            $telemetry = @{
                step        = 8
                totalSteps  = 15
                activeNode  = "node-chaos"
                animClass   = "node-active-chaos"
                status      = "KAOS_KODLANIYOR"
                title       = "ASAMA 8 / 15: Kaos Muhendisi (Stres Kodu)"
                sender      = "[12. KAOS MUHENDISI]"
                message     = "Kaos Saldiri Senaryosu Kodlaniyor: $leaf"
                desc        = "Dayaniklilik Testi: Eszamanli cekim ve negatif yukleme senaryosu kuruluyor."
                timestamp   = $time
                badge       = @{ id = "badge-chaos"; text = "Kaos Kodlaniyor"; class = "bg-amber-500/20 text-amber-400 border-amber-500/40 font-bold animate-pulse" }
            }
        } elseif ($path -match 'live_playground') {
            $telemetry = @{
                step        = 15
                totalSteps  = 15
                activeNode  = "node-playground"
                animClass   = "node-active-green"
                status      = "CANLI_ARAYUZ_HAZIR"
                title       = "ASAMA 15 / 15: Canli Deneme Tahtasi Hazir!"
                sender      = "[16. CANLI DENEME TAHTASI]"
                message     = "Interaktif Test Arayuzu (live_playground.html) guncellendi."
                desc        = "Vibe Coder Deneyimi: Urunu tarayicinizda canli deneyebilirsiniz."
                timestamp   = $time
                badge       = @{ id = "badge-playground"; text = "CANLI AKTIF"; class = "bg-emerald-500/20 text-emerald-400 border-emerald-500/40 font-bold animate-pulse" }
            }
        } else {
            $telemetry = @{
                step        = 6
                totalSteps  = 15
                activeNode  = "node-workers"
                animClass   = "node-active-default"
                status      = "KOD_GELISTIRILIYOR"
                title       = "ASAMA 6 / 15: Isciler Kaynak Kod Yaziyor"
                sender      = "[7. ISCILER (Autonomous Workers)]"
                message     = "Kaynak Dosyasi Gelistiriliyor: $leaf"
                desc        = "TDD Yesil Faz: Testleri gececek uretim kodu yaziliyor."
                timestamp   = $time
                badge       = @{ id = "badge-workers"; text = "Kod Yaziliyor"; class = "bg-emerald-500/20 text-emerald-400 border-emerald-500/40 font-bold animate-pulse" }
            }
        }
    }
    elseif ($toolName -eq "ask_question") {
        $telemetry = @{
            step        = 3
            totalSteps  = 15
            activeNode  = "node-gatekeeper"
            animClass   = "node-active-default"
            status      = "POPUP_BEKLENIYOR"
            title       = "ASAMA 3 / 15: Karar Suzgeci (Pop-Up)"
            sender      = "[4. KARAR SUZGECI (Gatekeeper)]"
            message     = "Tek Yonlu Kapi (Irreversible): Sirket Sahibinin pop-up secimi bekleniyor..."
            desc        = "Gercek Zamanli Duraklama: Siz secim yapana kadar sistem bu adimda kilitlidir."
            timestamp   = $time
            badge       = @{ id = "badge-gatekeeper"; text = "Pop-Up Bekleniyor"; class = "bg-amber-500/20 text-amber-400 border-amber-500/40 font-bold animate-pulse" }
        }
    }
    elseif ($toolName -eq "invoke_subagent") {
        $role = if ($args.Role) { $args.Role } else { "Alt Ajan" }
        $telemetry = @{
            step        = 4
            totalSteps  = 15
            activeNode  = "node-orch"
            animClass   = "node-active-default"
            status      = "ALT_AJAN_DEVREDE"
            title       = "ASAMA 4 / 15: Orkestrator Alt Ajan Baslatti"
            sender      = "[5. ORKESTRATOR VE BEYIN]"
            message     = "Gorev Devredildi: $role"
            desc        = "Is Dagitimi: Bagimsiz alt ajan arka planda gorevlendirildi."
            timestamp   = $time
            badge       = @{ id = "badge-orch"; text = "Ajan Devrede"; class = "bg-blue-500/20 text-blue-400 border-blue-500/40 font-bold animate-pulse" }
        }
    }
    elseif ($toolName -eq "read_file") {
        $path = if ($args.Path) { $args.Path } else { "" }
        $leaf = Split-Path $path -Leaf
        if ($path -match 'KURALLAR|DURUM') {
            $telemetry = @{
                step        = 1
                totalSteps  = 15
                activeNode  = "node-architect"
                animClass   = "node-active-architect"
                status      = "INCELEME"
                title       = "ASAMA 1 / 15: Bas Mimar Santiye Incelemesi"
                sender      = "[2. BAS MIMAR]"
                message     = "Mevcut Kurallar ve Santiye Defteri Inceleniyor: $leaf"
                desc        = "Analiz: Onceden konulmus kurallar ve durum kontrol ediliyor."
                timestamp   = $time
                badge       = @{ id = "badge-architect"; text = "Inceleniyor"; class = "bg-indigo-500/20 text-indigo-400 border-indigo-500/40 font-bold" }
            }
        }
    }

    if ($telemetry) {
        Send-Telemetry $telemetry
    }
}

Write-Output '{"decision":"allow"}'
exit 0
