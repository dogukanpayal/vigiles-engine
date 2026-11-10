# start_10_workers_demo.ps1
# 10 Paralel Iscinin Canli Operasyon Merkezinde Canli Gosterim Betigi

param()

$cid = "55264183-75b1-4214-bab2-b80572ce9283"
$artifactDir = "C:\Users\Dogukan\.gemini\antigravity\brain\$cid"
$time = (Get-Date).ToString("HH:mm:ss")

$workers = @(
    @{ id = 1;  name = "Isci #1";  role = "TDD Backend";       detail = "AuthService.ps1 gelistiriliyor";          statusLabel = "Aktif"; status = "active" },
    @{ id = 2;  name = "Isci #2";  role = "Birim Testci";      detail = "Test-Auth.ps1 senaryolari kosuluyor";     statusLabel = "Aktif"; status = "active" },
    @{ id = 3;  name = "Isci #3";  role = "UI / Gorsel";       detail = "Tailwind CSS renk paleti isleniyor";      statusLabel = "Aktif"; status = "active" },
    @{ id = 4;  name = "Isci #4";  role = "API Entegrasyon";   detail = "REST endpoint yonlendirmeleri kuruluyor"; statusLabel = "Aktif"; status = "active" },
    @{ id = 5;  name = "Isci #5";  role = "Veri Modeli";       detail = "Sema ve veri dogrulama denetleniyor";     statusLabel = "Aktif"; status = "active" },
    @{ id = 6;  name = "Isci #6";  role = "Zero-Leak Bekcisi"; detail = "API anahtari ve .env sizinti taramasi";   statusLabel = "Aktif"; status = "active" },
    @{ id = 7;  name = "Isci #7";  role = "Performans";        detail = "Bellek ve hiz optimizasyonu suruyor";     statusLabel = "Aktif"; status = "active" },
    @{ id = 8;  name = "Isci #8";  role = "Kaos Muhendisi";    detail = "Eszamanli istek dayaniklilik testi";      statusLabel = "Aktif"; status = "active" },
    @{ id = 9;  name = "Isci #9";  role = "Log Dedektifi";     detail = "SSE telemetri paketleri dinleniyor";      statusLabel = "Aktif"; status = "active" },
    @{ id = 10; name = "Isci #10"; role = "Kod Denetcisi";     detail = "Kurumsal mimari kurallari denetleniyor";  statusLabel = "Aktif"; status = "active" }
)

$state = @{
    conversationId = $cid
    workspaceName  = "Antigravity Improvement"
    step           = 6
    totalSteps     = 15
    activeNode     = "node-workers"
    animClass      = "node-active-default"
    status         = "10_ISCI_CALISIYOR"
    title          = "ASAMA 6 / 15: 10 Paralel Isci Sahada Kod Yaziyor"
    sender         = "[7. ISCILER (10 Otonom Alt Ajan)]"
    message        = "10 Bagimsiz Alt Isci Devreye Alindi - Eszamanli Gorev Icrasi Baslatildi."
    desc           = "Canli Inceleme Modu: 10 adet kucuk isci kutusu hiyerarsik baglanti agaciyla ekranda aktif."
    timestamp      = $time
    badge          = @{
        id    = "badge-workers"
        text  = "10 Isci Aktif"
        class = "bg-emerald-500/20 text-emerald-400 border-emerald-500/40 font-bold animate-pulse"
    }
    workerCount    = 10
    workers        = $workers
    stats          = @{
        testsPassed    = 15
        testsFailed    = 0
        defectsOpen    = 0
        secretsBlocked = 0
        bloatBlocked   = 0
    }
}

$stateJson = $state | ConvertTo-Json -Depth 6 -Compress

# 1. Artifact dosyalarini guncelle
if (Test-Path $artifactDir) {
    # active_workers.json
    $workersFile = Join-Path $artifactDir "active_workers.json"
    [System.IO.File]::WriteAllText($workersFile, ($workers | ConvertTo-Json -Depth 4), [System.Text.Encoding]::UTF8)

    # live_state.json
    $jsonFile = Join-Path $artifactDir "live_state.json"
    [System.IO.File]::WriteAllText($jsonFile, $stateJson, [System.Text.Encoding]::UTF8)

    # live_state.js
    $jsFile = Join-Path $artifactDir "live_state.js"
    $jsWrap = "// Antigravity Canli Telemetri Kancasi`nwindow.__ANTIGRAVITY_STATE__ = $stateJson;`nif (typeof window.onAntigravityStateUpdate === 'function') { window.onAntigravityStateUpdate(window.__ANTIGRAVITY_STATE__); }"
    [System.IO.File]::WriteAllText($jsFile, $jsWrap, [System.Text.Encoding]::UTF8)
}

# 2. Port 9999 SSE Sunucusuna Bildir
try {
    $req = [System.Net.WebRequest]::Create("http://localhost:9999/notify")
    $req.Method = "POST"
    $req.ContentType = "application/json; charset=utf-8"
    $req.Headers.Add("X-Conversation-Id", $cid)
    $req.Timeout = 500
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($stateJson)
    $req.ContentLength = $bytes.Length
    $stream = $req.GetRequestStream()
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Dispose()
    $resp = $req.GetResponse()
    $resp.Dispose()
    Write-Host "SUCCESS: 10 Iscili Canli Telemetri Port 9999 SSE hattina firlatildi!"
} catch {
    Write-Host "FALLBACK: Artifact dosyalari dogrudan guncellendi."
}
