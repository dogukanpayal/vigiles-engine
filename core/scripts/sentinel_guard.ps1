param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

$rawInput = [Console]::In.ReadToEnd()

if ([string]::IsNullOrWhiteSpace($rawInput)) {
    Write-Output '{"decision":"allow"}'
    exit 0
}

$rawInput = $rawInput.Trim().Trim([char]65279)

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

# Dizin belirleme (Öncelik: payload.artifactDirectoryPath -> payload.conversationId)
$artifactDir = $payload.artifactDirectoryPath
$cid = $payload.conversationId
$wsName = if ($payload.workspacePaths -and $payload.workspacePaths.Count -gt 0) { Split-Path $payload.workspacePaths[0] -Leaf } else { "Antigravity Workspace" }

if ([string]::IsNullOrWhiteSpace($artifactDir) -and -not [string]::IsNullOrWhiteSpace($cid)) {
    $artifactDir = Join-Path $HOME ".gemini\antigravity\brain\$cid"
}

$telemetryPort = 9999
if ($env:VIGILES_TELEMETRY_PORT -match '^\d+$') {
    $parsedPort = [int]$env:VIGILES_TELEMETRY_PORT
    if ($parsedPort -ge 1024 -and $parsedPort -le 65535) {
        $telemetryPort = $parsedPort
    }
}

# Vigiles İzolasyon Kontrolü:
# Bu oturumda /pro, /lite veya /live komutu çalıştırılmamışsa (artifact dizininde .vigiles_active yoksa)
# kanca hiçbir güvenlik kısıtlaması uygulamadan ve telemetri üretmeden anında 'allow' vererek çıkar.
$isVigilesActive = $false
$isLiveActive = $false
if (-not [string]::IsNullOrWhiteSpace($artifactDir) -and (Test-Path $artifactDir)) {
    $markerFile = Join-Path $artifactDir ".vigiles_active"
    if (Test-Path $markerFile) {
        $isVigilesActive = $true
    }
    $liveMarkerFile = Join-Path $artifactDir ".live_active"
    if (Test-Path $liveMarkerFile) {
        $isLiveActive = $true
    }
}

if (-not $isVigilesActive) {
    Write-Output '{"decision":"allow"}'
    exit 0
}

# --- 0. COKLU OTURUM NABIZ & WORKTREE YOL KALKANI (ADR-025) ---
function Normalize-GuardPath([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return "" }
    try {
        return [System.IO.Path]::GetFullPath($p.Trim().Replace('/', '\')).TrimEnd('\')
    } catch {
        return $p.Trim().Replace('/', '\').TrimEnd('\')
    }
}

function Test-PathUnderDir([string]$candidatePath, [string]$dirPath) {
    if ([string]::IsNullOrWhiteSpace($candidatePath) -or [string]::IsNullOrWhiteSpace($dirPath)) { return $false }
    $c = Normalize-GuardPath $candidatePath
    $d = Normalize-GuardPath $dirPath
    return ($c.Equals($d, [System.StringComparison]::OrdinalIgnoreCase) -or
            $c.StartsWith("$d\", [System.StringComparison]::OrdinalIgnoreCase))
}

$worktreeSessionInfo = $null
if (-not [string]::IsNullOrWhiteSpace($artifactDir) -and (Test-Path $artifactDir)) {
    # 0.1 Nabiz damgasini (lastHeartbeatAt) yenile
    $sessPointerPath = Join-Path $artifactDir ".vigiles_session"
    if (Test-Path $sessPointerPath) {
        try {
            $ptr = [System.IO.File]::ReadAllText($sessPointerPath, [System.Text.Encoding]::UTF8).Trim().Trim([char]65279) | ConvertFrom-Json
            if ($ptr -and $ptr.sessionFile -and (Test-Path $ptr.sessionFile)) {
                $sRaw = [System.IO.File]::ReadAllText($ptr.sessionFile, [System.Text.Encoding]::UTF8).Trim().Trim([char]65279)
                $sObj = $sRaw | ConvertFrom-Json
                if ($sObj) {
                    $sObj | Add-Member -NotePropertyName "lastHeartbeatAt" -NotePropertyValue ([datetimeoffset]::Now.ToString("o")) -Force
                    if ($sObj.status -in @("COMPLETED", "READY_TO_MERGE", "STALE")) {
                        $sObj | Add-Member -NotePropertyName "status" -NotePropertyValue "ACTIVE" -Force
                    }
                    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                    [System.IO.File]::WriteAllText($ptr.sessionFile, ($sObj | ConvertTo-Json -Depth 6), $utf8NoBom)
                }
            }
        } catch {}
    }

    # 0.2 Worktree izolasyon bilgisini yukle
    $wtMarkerPath = Join-Path $artifactDir ".vigiles_worktree"
    if (Test-Path $wtMarkerPath) {
        try {
            $worktreeSessionInfo = [System.IO.File]::ReadAllText($wtMarkerPath, [System.Text.Encoding]::UTF8).Trim().Trim([char]65279) | ConvertFrom-Json
        } catch {}
    }
}

# --- YARDIMCI: TELEMETRI YAYINI ---
function Get-ActiveWorkers() {
    $workersFile = Join-Path $artifactDir "active_workers.json"
    $list = @()
    if (Test-Path $workersFile) {
        try {
            $parsed = Get-Content -Raw -Encoding UTF8 $workersFile | ConvertFrom-Json
            if ($parsed -is [array]) {
                $list = $parsed
            } elseif ($parsed) {
                $list = @($parsed)
            }
        } catch {}
    }
    return $list
}

function Register-ActiveWorker([string]$role, [string]$detail) {
    $workersFile = Join-Path $artifactDir "active_workers.json"
    $list = [System.Collections.Generic.List[hashtable]]::new()
    $existing = Get-ActiveWorkers
    foreach ($w in $existing) {
        $list.Add(@{
            id          = $w.id
            name        = $w.name
            role        = $w.role
            detail      = $w.detail
            statusLabel = "Aktif 🟢"
        })
    }
    $newIndex = $list.Count + 1
    $list.Add(@{
        id          = $newIndex
        name        = "İşçi #$newIndex"
        role        = $role
        detail      = $detail
        statusLabel = "Aktif 🟢"
    })
    try {
        $json = ($list | ConvertTo-Json -Depth 4)
        [System.IO.File]::WriteAllText($workersFile, $json, [System.Text.Encoding]::UTF8)
    } catch {}
    return $list
}

function Send-Telemetry([hashtable]$state) {
    try {
        if (-not $state.ContainsKey("conversationId") -and -not [string]::IsNullOrWhiteSpace($cid)) {
            $state["conversationId"] = $cid
        }
        if (-not $state.ContainsKey("workspaceName")) {
            $state["workspaceName"] = $wsName
        }

        $stateJson = $state | ConvertTo-Json -Depth 6 -Compress

        if (-not [string]::IsNullOrWhiteSpace($artifactDir) -and (Test-Path $artifactDir)) {
            # 1. live_state.js (Zero-CORS fallback)
            $jsContent = "// Antigravity Canli Telemetri Kancasi`nwindow.__ANTIGRAVITY_STATE__ = $stateJson;`nif (typeof window.onAntigravityStateUpdate === 'function') { window.onAntigravityStateUpdate(window.__ANTIGRAVITY_STATE__); }"
            $jsPath = Join-Path $artifactDir "live_state.js"
            [System.IO.File]::WriteAllText($jsPath, $jsContent, [System.Text.Encoding]::UTF8)

            # 2. live_state.json
            $jsonPath = Join-Path $artifactDir "live_state.json"
            [System.IO.File]::WriteAllText($jsonPath, $stateJson, [System.Text.Encoding]::UTF8)

            # 3. live_events.jsonl (Olay Günlüğü)
            $logPath = Join-Path $artifactDir "live_events.jsonl"
            $eventEntry = @{
                timestamp = $state.timestamp
                sender    = $state.sender
                title     = $state.title
                node      = $state.activeNode
                tool      = $toolName
            } | ConvertTo-Json -Compress
            [System.IO.File]::AppendAllText($logPath, "$eventEntry`n", [System.Text.Encoding]::UTF8)
        }

        # 4. Yerel SSE Sunucusuna HTTP POST - Yalnizca bu oturumda /live aktifse (.live_active) gonder
        if ($isLiveActive) {
            try {
                $req = [System.Net.WebRequest]::Create("http://localhost:$telemetryPort/notify")
                $req.Method = "POST"
                $req.ContentType = "application/json; charset=utf-8"
                if (-not [string]::IsNullOrWhiteSpace($cid)) {
                    $req.Headers.Add("X-Conversation-Id", $cid)
                }
                $req.ServicePoint.Expect100Continue = $false
                $req.Timeout = 800
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($stateJson)
                $req.ContentLength = $bytes.Length
                $stream = $req.GetRequestStream()
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Dispose()
                $resp = $req.GetResponse()
                $resp.Dispose()
            } catch {}
        }
    } catch {}
}

# --- 1. GÜVENLİK, WORKTREE YOL KALKANI VE SIZINTI KONTROLLERİ (Zero-Leak + ADR-025) ---
$writeLikeTools = @("write_file", "edit_file", "write_to_file", "replace_file_content", "multi_replace_file_content", "delete_file")

if ($worktreeSessionInfo -and $worktreeSessionInfo.mode -eq "WORKTREE" -and
    -not [string]::IsNullOrWhiteSpace($worktreeSessionInfo.repoRoot) -and
    -not [string]::IsNullOrWhiteSpace($worktreeSessionInfo.worktreePath)) {
    if ($toolName -in $writeLikeTools) {
        $targetArgPath = ""
        if ($args.Path) { $targetArgPath = [string]$args.Path }
        elseif ($args.TargetFile) { $targetArgPath = [string]$args.TargetFile }
        elseif ($args.path) { $targetArgPath = [string]$args.path }

        if (-not [string]::IsNullOrWhiteSpace($targetArgPath)) {
            $normTarget = Normalize-GuardPath $targetArgPath
            $normRepo   = Normalize-GuardPath $worktreeSessionInfo.repoRoot
            $normWt     = Normalize-GuardPath $worktreeSessionInfo.worktreePath

            $inMainRepo = Test-PathUnderDir -candidatePath $normTarget -dirPath $normRepo
            $inWorktree = Test-PathUnderDir -candidatePath $normTarget -dirPath $normWt
            $inArtifact = (-not [string]::IsNullOrWhiteSpace($artifactDir)) -and (Test-PathUnderDir -candidatePath $normTarget -dirPath $artifactDir)

            if ($inMainRepo -and -not $inWorktree -and -not $inArtifact) {
                $relPart = $normTarget.Substring($normRepo.Length).TrimStart('\')
                $redirectPath = if ([string]::IsNullOrWhiteSpace($relPart)) { $normWt } else { Join-Path $normWt $relPart }
                $shortWtId = if ($worktreeSessionInfo.shortId) { $worktreeSessionInfo.shortId } else { "izole" }

                $wtTelemetry = @{
                    step        = 9
                    totalSteps  = 15
                    activeNode  = "node-shield"
                    animClass   = "node-active-red"
                    status      = "WORKTREE_YOL_ENGELI"
                    title       = "YOL KALKANI: Ana Klasöre Yazma Engellendi!"
                    sender      = "[9. GÜVENLİK MUHAFIZI]"
                    message     = "Paralel worktree oturumu ana klasördeki '$targetArgPath' yoluna yazamaz; '$redirectPath' yoluna yönlendirildi."
                    timestamp   = (Get-Date).ToString("HH:mm:ss")
                    badge       = @{ id = "badge-shield"; text = "YOL KORUMASI"; class = "bg-rose-500/20 text-rose-400 border-rose-500/40 font-bold animate-pulse" }
                }
                Send-Telemetry $wtTelemetry

                $wtResp = @{
                    decision = "deny"
                    reason   = "[VIGILES WORKTREE YOL KALKANI]: Bu oturum paralel izole santiyede (.worktrees/pro-$shortWtId) calisiyor! Ana klasordeki '$targetArgPath' dosyasina yazamazsiniz; bunun yerine su izole worktree yolunu kullanin: '$redirectPath'"
                }
                Write-Output ($wtResp | ConvertTo-Json -Compress)
                exit 0
            }
        }
    }
}

if ($toolName -in $writeLikeTools) {
    $textToCheck = ""
    if ($args.Content) { $textToCheck += $args.Content }
    if ($args.CodeContent) { $textToCheck += " " + $args.CodeContent }
    if ($args.Replacement) { $textToCheck += " " + $args.Replacement }
    if ($args.ReplacementContent) { $textToCheck += " " + $args.ReplacementContent }

    $secretPatterns = @(
        'AKIA[0-9A-Z]{16}',
        '(?<![a-zA-Z0-9_-])sk-(?:proj-|svcacct-|admin-)[a-zA-Z0-9_-]{20,}|(?<![a-zA-Z0-9_-])sk-[a-zA-Z0-9]{20,}',
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
                title       = "GÜVENLİK İHLALİ: Kod İçinde API Anahtarı Engellendi!"
                sender      = "[9. GÜVENLİK MUHAFIZI]"
                message     = "Zero-Leak Kalkanı: Kod içine açık API anahtarı yazılmaya çalışıldı; işlem bloke edildi!"
                timestamp   = (Get-Date).ToString("HH:mm:ss")
                badge       = @{ id = "badge-shield"; text = "SIZINTI ENGELLENDİ"; class = "bg-rose-500/20 text-rose-400 border-rose-500/40 font-bold animate-pulse" }
            }
            Send-Telemetry $telemetry

            $response = @{
                decision = "deny"
                reason = "[ZERO-LEAK GÜVENLİK MUHAFIZI]: Kod içinde açık API anahtarı tespit edildi! Lütfen process.env kullanın."
            }
            Write-Output ($response | ConvertTo-Json -Compress)
            exit 0
        }
    }
}

function Resolve-EffectiveCommandLine([string]$rawCmd) {
    if ([string]::IsNullOrWhiteSpace($rawCmd)) { return "" }
    if ($rawCmd -match 'invoke_with_timeout\.ps1' -and $rawCmd -match '-PayloadFile\s+(?:"([^"]+)"|''([^'']+)''|([^\s]+))') {
        $pFile = if ($matches[1]) { $matches[1] } elseif ($matches[2]) { $matches[2] } else { $matches[3] }
        if ($pFile -and (Test-Path -LiteralPath $pFile)) {
            try {
                $pJson = [System.IO.File]::ReadAllText($pFile, [System.Text.Encoding]::UTF8).Trim().Trim([char]65279) | ConvertFrom-Json
                if ($pJson -and $pJson.command) {
                    return [string]$pJson.command
                }
            } catch {}
        }
    }
    return $rawCmd
}

if ($toolName -eq "run_command") {
    $rawCmd = if ($args.CommandLine) { [string]$args.CommandLine } else { "" }
    $cmd = Resolve-EffectiveCommandLine $rawCmd

    if ($cmd -match 'git\s+add\s+.*\.env(?!\.(example|template|sample))(\.[a-zA-Z0-9_-]+)?(\s|$|["''])' -or
        $cmd -match 'git\s+commit\s+.*\.env(?!\.(example|template|sample))(\.[a-zA-Z0-9_-]+)?(\s|$|["''])' -or
        $cmd -match 'git_push_manager.*-Action\s+Add.*\.env(?!\.(example|template|sample))(\.[a-zA-Z0-9_-]+)?(\s|$|["''])') {
        $response = @{
            decision = "deny"
            reason = "[ZERO-LEAK GÜVENLİK MUHAFIZI]: .env dosyasını git deposuna veya push paketine ekleyemezsiniz!"
        }
        Write-Output ($response | ConvertTo-Json -Compress)
        exit 0
    }

    if ($cmd -match 'git\s+push\s+.*--force.*(main|master)') {
        $response = @{
            decision = "deny"
            reason = "[GÜVENLİK MUHAFIZI]: Ana branch üzerine force push yapamazsınız!"
        }
        Write-Output ($response | ConvertTo-Json -Compress)
        exit 0
    }

    if ($cmd -match '(npm\s+(i|install|add)|yarn\s+add|pnpm\s+add)\s+.*(moment|lodash)(\s|$)' -and -not ($cmd -match 'lodash-es')) {
        $response = @{
            decision = "deny"
            reason = "[ANTI-BLOAT MUHAFIZI]: 15MB+ şişkin kütüphane (moment/lodash) tespit edildi!"
        }
        Write-Output ($response | ConvertTo-Json -Compress)
        exit 0
    }

    if ($worktreeSessionInfo -and $worktreeSessionInfo.mode -eq "WORKTREE") {
        $isReadInspectCmd = ($cmd -match '^\s*(Get-Content|gc|cat|type|Select-String|rg|grep|git\s+(status|diff|log|show)|Test-|Chaos-)')
        $isInstallExec = (-not $isReadInspectCmd) -and ($cmd -match '(?i)(^|[;&|\s"''\\/])install\.ps1(\s|$|["'';&|])')
        if ($isInstallExec) {
            $response = @{
                decision = "deny"
                reason = "[VIGILES WORKTREE KALKANI]: Izole paralel santiyede kuresel install.ps1 calistirilamaz! Once degisiklikleri /merge ile ana klasore aktarin, ardindan install.ps1 calistirin."
            }
            Write-Output ($response | ConvertTo-Json -Compress)
            exit 0
        }
    }
}

# --- 2. AKILLI 19-ELEMAN TELEMETRİ EŞLEMESİ ---
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
        $rawCmd = if ($args.CommandLine) { [string]$args.CommandLine } else { "" }
        $cmd = Resolve-EffectiveCommandLine $rawCmd
        if ($cmd -match 'Test-|pester|pytest|npm test|vitest|jest') {
            $telemetry = @{
                step        = 5
                totalSteps  = 15
                activeNode  = "node-tester"
                animClass   = "node-active-default"
                status      = "TEST_KOSULUYOR"
                title       = "AŞAMA 5 / 15: Özel Testçi Devrede"
                sender      = "[11. ÖZEL TESTÇİ (TDD)]"
                message     = "Birim Testi Koşuluyor: $cmd"
                desc        = "TDD Döngüsü: Testler otonom olarak terminal üzerinden çalıştırılıyor."
                timestamp   = $time
                badge       = @{ id = "badge-tester"; text = "Test Koşuluyor"; class = "bg-rose-500/20 text-rose-400 border-rose-500/40 font-bold animate-pulse" }
            }
        } elseif ($cmd -match 'Chaos-') {
            $telemetry = @{
                step        = 8
                totalSteps  = 15
                activeNode  = "node-chaos"
                animClass   = "node-active-chaos"
                status      = "KAOS_SALDIRISI"
                title       = "AŞAMA 8 / 15: Kaos Mühendisi Devrede"
                sender      = "[12. KAOS MÜHENDİSİ]"
                message     = "Dayanıklılık ve Yarış Durumu Saldırısı: $cmd"
                desc        = "Kaos Testi: Eşzamanlı istekler ve sınır değer saldırıları püskürtülüyor."
                timestamp   = $time
                badge       = @{ id = "badge-chaos"; text = "Stres Saldırısı"; class = "bg-amber-500/20 text-amber-400 border-amber-500/40 font-bold animate-pulse" }
            }
        } elseif ($cmd -match 'git_push_manager.*-Action\s+(Prep|Remove|Add|Status|Reset)') {
            $telemetry = @{
                step        = 12
                totalSteps  = 15
                activeNode  = "node-pr"
                animClass   = "node-active-default"
                status      = "GIT_HAZIRLIK"
                title       = "AŞAMA 12 / 15: PushPrep Seçici Paketleme"
                sender      = "[19. GİT VE PR FABRİKASI]"
                message     = "Push Önizleme ve Manifesto Yönetimi: $cmd"
                desc        = "Seçici Dağıtım: Pushlanacak dosyalar listeleniyor ve filtreleniyor."
                timestamp   = $time
                badge       = @{ id = "badge-pr"; text = "PushPrep Aktif"; class = "bg-purple-500/20 text-purple-400 border-purple-500/40 font-bold" }
            }
        } elseif ($cmd -match 'git\s+(commit|push|checkout\s+-b|tag|merge|rebase|stash|cherry-pick)' -or 
                  $cmd -match 'git_push_manager|git_pr_manager|gh\s+pr') {
            $telemetry = @{
                step        = 12
                totalSteps  = 15
                activeNode  = "node-pr"
                animClass   = "node-active-default"
                status      = "GIT_ISLEMI"
                title       = "AŞAMA 12 / 15: Git ve PR Fabrikası"
                sender      = "[19. GİT VE PR FABRİKASI]"
                message     = "Versiyonlama ve Dağıtım: $cmd"
                desc        = "Sürüm Yönetimi: Git deposu güncelleniyor ve dağıtıma hazırlanıyor."
                timestamp   = $time
                badge       = @{ id = "badge-pr"; text = "Git Çalışıyor"; class = "bg-purple-500/20 text-purple-400 border-purple-500/40 font-bold" }
            }
        } elseif ($cmd -match 'git\s+(status|diff|log|show|branch|remote|describe|check-ignore|rev-parse)') {
            $telemetry = @{
                step        = 1
                totalSteps  = 15
                activeNode  = "node-architect"
                animClass   = "node-active-architect"
                status      = "GIT_KESFI"
                title       = "AŞAMA 1 / 15: Baş Mimar Depo ve Versiyon Keşfi"
                sender      = "[2. BAŞ MİMAR (Lead Planner)]"
                message     = "Git Deposu ve Değişiklik Durumu İnceleniyor: $cmd"
                desc        = "Mimari Zemin Etüdü: Depodaki branch, commit geçmişi ve çalışma ağacı inceleniyor."
                timestamp   = $time
                badge       = @{ id = "badge-architect"; text = "Depo İnceleniyor"; class = "bg-indigo-500/20 text-indigo-400 border-indigo-500/40 font-bold animate-pulse" }
            }
        } elseif ($cmd -match '^\s*(dir|ls|tree|Get-ChildItem|gci|Get-Content|gc|type|cat|head|tail|findstr|Select-String|grep|Test-Path|Get-Item|gi|Get-Command|gcm)(\s|$)' -or
                  $cmd -match 'Get-ChildItem|Select-String|Compare-Object|Test-Path|Get-Item') {
            $telemetry = @{
                step        = 1
                totalSteps  = 15
                activeNode  = "node-architect"
                animClass   = "node-active-architect"
                status      = "SANTIYE_KESFI"
                title       = "AŞAMA 1 / 15: Baş Mimar Şantiye Keşfi & Analiz"
                sender      = "[2. BAŞ MİMAR (Lead Planner)]"
                message     = "Dosya ve Dizinler Taranıyor: $cmd"
                desc        = "Mimari Keşif: Proje dizin yapısı, konfigürasyonlar ve mevcut kod yapısı taranıyor."
                timestamp   = $time
                badge       = @{ id = "badge-architect"; text = "Şantiye Keşfi"; class = "bg-indigo-500/20 text-indigo-400 border-indigo-500/40 font-bold animate-pulse" }
            }
        } else {
            $telemetry = @{
                step        = 7
                totalSteps  = 15
                activeNode  = "node-workers"
                animClass   = "node-active-default"
                status      = "KOMUT_CALISIYOR"
                title       = "AŞAMA 7 / 15: İşçiler (Terminal Komutu)"
                sender      = "[7. İŞÇİLER (Autonomous Workers)]"
                message     = "Terminal Komutu Yürütülüyor: $cmd"
                desc        = "İşçi Birimi: Yerel ortamda komut çalıştırılıyor."
                timestamp   = $time
                badge       = @{ id = "badge-workers"; text = "Komut Yürütülüyor"; class = "bg-emerald-500/20 text-emerald-400 border-emerald-500/40 font-bold animate-pulse" }
            }
            $activeWorkers = Get-ActiveWorkers
            if ($activeWorkers -and $activeWorkers.Count -gt 0) {
                $telemetry["workerCount"] = $activeWorkers.Count
                $telemetry["workers"] = $activeWorkers
                $telemetry["badge"] = @{ id = "badge-workers"; text = "$($activeWorkers.Count) İşçi Aktif ⚡"; class = "bg-emerald-500/20 text-emerald-400 border-emerald-500/40 font-bold animate-pulse" }
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
                title       = "AŞAMA 2 / 15: Baş Mimar Statik Planlama"
                sender      = "[2. BAŞ MİMAR (Lead Planner)]"
                message     = "Kabul Kriterleri ve Şantiye Defteri (DURUM.md) güncelleniyor."
                desc        = "Mimari Sözleşme: Görevin sınırları ve kabul kriterleri belirleniyor."
                timestamp   = $time
                badge       = @{ id = "badge-architect"; text = "Plan Çiziliyor"; class = "bg-indigo-500/20 text-indigo-400 border-indigo-500/40 font-bold animate-pulse" }
            }
        } elseif ($path -match 'KURALLAR\.md') {
            $telemetry = @{
                step        = 14
                totalSteps  = 15
                activeNode  = "node-memory"
                animClass   = "node-active-default"
                status      = "HAFIZA_GUNCELLEME"
                title       = "AŞAMA 14 / 15: Hafıza Uzmanı Devrede"
                sender      = "[14. HAFIZA UZMANI (Memory Extractor)]"
                message     = "Şirket Anayasası ve Kurallar (KURALLAR.md) güncelleniyor."
                desc        = "Kurumsal Hafıza: Görevden öğrenilen dersler kalıcı anayasaya işleniyor."
                timestamp   = $time
                badge       = @{ id = "badge-memory"; text = "Hafıza Kaydediliyor"; class = "bg-purple-500/20 text-purple-400 border-purple-500/40 font-bold animate-pulse" }
            }
        } elseif ($path -match '(^|[\\/])DESIGN\.md$') {
            $telemetry = @{
                step        = 2
                totalSteps  = 15
                activeNode  = "node-figma"
                animClass   = "node-active-default"
                status      = "TASARIM_SOZLESMESI"
                title       = "AŞAMA 2 / 15: Tasarım Sözleşmesi & Anti-Slop Kalkanı"
                sender      = "[3. FİGMA & TASARIM KÖPRÜSÜ]"
                message     = "Tasarım Sözleşmesi (DESIGN.md) güncelleniyor: $leaf"
                desc        = "Anti-Slop Tasarım Sistemi: Tipografi, renk tokenları ve estetik kurallar sözleşmeye işleniyor."
                timestamp   = $time
                badge       = @{ id = "badge-figma"; text = "Tasarım Sözleşmesi"; class = "bg-pink-500/20 text-pink-300 border-pink-500/40 font-bold animate-pulse" }
            }
        } elseif ($path -match 'Test-') {
            $telemetry = @{
                step        = 5
                totalSteps  = 15
                activeNode  = "node-tester"
                animClass   = "node-active-default"
                status      = "TEST_YAZILIYOR"
                title       = "AŞAMA 5 / 15: Özel Testçi (Test Dosyası)"
                sender      = "[11. ÖZEL TESTÇİ (TDD)]"
                message     = "Test Dosyası Hazırlanıyor: $leaf"
                desc        = "TDD Kırmızı Faz: Kabul kriterlerini doğrulayan birim test yazılıyor."
                timestamp   = $time
                badge       = @{ id = "badge-tester"; text = "Test Yazılıyor"; class = "bg-rose-500/20 text-rose-400 border-rose-500/40 font-bold animate-pulse" }
            }
        } elseif ($path -match 'Chaos-') {
            $telemetry = @{
                step        = 8
                totalSteps  = 15
                activeNode  = "node-chaos"
                animClass   = "node-active-chaos"
                status      = "KAOS_KODLANIYOR"
                title       = "AŞAMA 8 / 15: Kaos Mühendisi (Stres Kodu)"
                sender      = "[12. KAOS MÜHENDİSİ]"
                message     = "Kaos Saldırı Senaryosu Kodlanıyor: $leaf"
                desc        = "Dayanıklılık Testi: Eşzamanlı çekim ve negatif yükleme senaryosu kuruluyor."
                timestamp   = $time
                badge       = @{ id = "badge-chaos"; text = "Kaos Kodlanıyor"; class = "bg-amber-500/20 text-amber-400 border-amber-500/40 font-bold animate-pulse" }
            }
        } elseif ($path -match 'live_playground') {
            $telemetry = @{
                step        = 15
                totalSteps  = 15
                activeNode  = "node-playground"
                animClass   = "node-active-green"
                status      = "CANLI_ARAYUZ_HAZIR"
                title       = "AŞAMA 15 / 15: Canlı Deneme Tahtası Hazır!"
                sender      = "[16. CANLI DENEME TAHTASI]"
                message     = "İnteraktif Test Arayüzü (live_playground.html) güncellendi."
                desc        = "Vibe Coder Deneyimi: Ürünü tarayıcınızda canlı deneyebilirsiniz."
                timestamp   = $time
                badge       = @{ id = "badge-playground"; text = "CANLI AKTİF"; class = "bg-emerald-500/20 text-emerald-400 border-emerald-500/40 font-bold animate-pulse" }
            }
        } else {
            $telemetry = @{
                step        = 6
                totalSteps  = 15
                activeNode  = "node-workers"
                animClass   = "node-active-default"
                status      = "KOD_GELISTIRILIYOR"
                title       = "AŞAMA 6 / 15: İşçiler Kaynak Kod Yazıyor"
                sender      = "[7. İŞÇİLER (Autonomous Workers)]"
                message     = "Kaynak Dosyası Geliştiriliyor: $leaf"
                desc        = "TDD Yeşil Faz: Testleri geçecek üretim kodu yazılıyor."
                timestamp   = $time
                badge       = @{ id = "badge-workers"; text = "Kod Yazılıyor"; class = "bg-emerald-500/20 text-emerald-400 border-emerald-500/40 font-bold animate-pulse" }
            }
            $activeWorkers = Get-ActiveWorkers
            if ($activeWorkers -and $activeWorkers.Count -gt 0) {
                $telemetry["workerCount"] = $activeWorkers.Count
                $telemetry["workers"] = $activeWorkers
                $telemetry["badge"] = @{ id = "badge-workers"; text = "$($activeWorkers.Count) İşçi Aktif ⚡"; class = "bg-emerald-500/20 text-emerald-400 border-emerald-500/40 font-bold animate-pulse" }
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
            title       = "AŞAMA 3 / 15: Karar Süzgeci (Pop-Up)"
            sender      = "[4. KARAR SÜZGECİ (Gatekeeper)]"
            message     = "Tek Yönlü Kapı (Irreversible): Şirket Sahibinin pop-up seçimi bekleniyor..."
            desc        = "Gerçek Zamanlı Duraklama: Siz seçim yapana kadar sistem bu adımda kilitlidir."
            timestamp   = $time
            badge       = @{ id = "badge-gatekeeper"; text = "Pop-Up Bekleniyor"; class = "bg-amber-500/20 text-amber-400 border-amber-500/40 font-bold animate-pulse" }
        }
    }
    elseif ($toolName -eq "invoke_subagent") {
        $role = if ($args.Role) { $args.Role } else { "Alt Ajan" }
        $currentWorkers = Register-ActiveWorker -role $role -detail "Bağımsız alt ajan görevlendirildi."
        $telemetry = @{
            step        = 4
            totalSteps  = 15
            activeNode  = "node-chief"
            animClass   = "node-active-default"
            status      = "ALT_AJAN_DEVREDE"
            title       = "AŞAMA 7 / 15: Subagent Şefi İşçi Dağıttı"
            sender      = "[7. SUBAGENT ŞEFİ (Saha Şefi)]"
            message     = "Yeni İşçi Görevlendirildi: $role ($($currentWorkers.Count) İşçi Aktif)"
            desc        = "İş Dağıtımı: Sahada $($currentWorkers.Count) otonom işçi paralel çalışıyor."
            timestamp   = $time
            badge       = @{ id = "badge-chief"; text = "$($currentWorkers.Count) İşçi Sahada"; class = "bg-emerald-500/20 text-emerald-400 border-emerald-500/40 font-bold animate-pulse" }
            workerCount = $currentWorkers.Count
            workers     = $currentWorkers
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
                title       = "AŞAMA 1 / 15: Baş Mimar Şantiye İncelemesi"
                sender      = "[2. BAŞ MİMAR]"
                message     = "Mevcut Kurallar ve Şantiye Defteri İnceleniyor: $leaf"
                desc        = "Analiz: Önceden konulmuş kurallar ve durum kontrol ediliyor."
                timestamp   = $time
                badge       = @{ id = "badge-architect"; text = "İnceleniyor"; class = "bg-indigo-500/20 text-indigo-400 border-indigo-500/40 font-bold" }
            }
        } else {
            $telemetry = @{
                step        = 1
                totalSteps  = 15
                activeNode  = "node-architect"
                animClass   = "node-active-architect"
                status      = "KOD_INCELEME"
                title       = "AŞAMA 1 / 15: Baş Mimar Mimari Kod İncelemesi"
                sender      = "[2. BAŞ MİMAR (Lead Planner)]"
                message     = "Kaynak Dosyası Analiz Ediliyor: $leaf"
                desc        = "Mimari Analiz: Dosya içeriği ve kod mimarisi zemin etüdü için inceleniyor."
                timestamp   = $time
                badge       = @{ id = "badge-architect"; text = "Mimari Analiz"; class = "bg-indigo-500/20 text-indigo-400 border-indigo-500/40 font-bold animate-pulse" }
            }
        }
    }

    if ($telemetry) {
        Send-Telemetry $telemetry
    }
}

Write-Output '{"decision":"allow"}'
exit 0