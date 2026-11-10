# core/scripts/git_push_manager.ps1
# Vigiles Engine - Guvenli Git Pipeline Yoneticisi (Add -> Commit -> Push)
# Kullanici /push komutunu calistirdiginda tetiklenir.

param(
    [string]$Remote = "origin",
    [string]$Branch = "",
    [string]$CommitMessage = "",
    [switch]$DryRun = $false
)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ">> VIGILES ENGINE - GUVENLI GIT PIPELINE (ADD/COMMIT/PUSH)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Git deposu kontrolu
$isInsideRepo = (& git rev-parse --is-inside-work-tree 2>$null)
if ($LASTEXITCODE -ne 0 -or $isInsideRepo -ne "true") {
    Write-Host "[HATA]: Mevcut calisma dizini bir Git deposu degil!" -ForegroundColor Red
    exit 1
}

# 2. Aktif branch tespiti
if ([string]::IsNullOrWhiteSpace($Branch)) {
    $Branch = (& git branch --show-current 2>$null)
    if ($Branch) { $Branch = $Branch.Trim() }
}

if ([string]::IsNullOrWhiteSpace($Branch)) {
    Write-Host "[HATA]: Aktif Git branch adi tespit edilemedi (Detached HEAD olabilir)." -ForegroundColor Red
    exit 1
}

Write-Host "[*] Aktif Branch : $Branch" -ForegroundColor Gray
Write-Host "[*] Hedef Remote : $Remote" -ForegroundColor Gray

# 3. Remote URL dogrulamasi
$remoteUrl = (& git remote get-url $Remote 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remoteUrl)) {
    Write-Host "[HATA]: '$Remote' adinda bir uzak depo (remote) bulunamadi!" -ForegroundColor Red
    exit 1
}
Write-Host "[*] Remote URL   : $remoteUrl" -ForegroundColor Gray

# 4. ADIM 1 & 2: git add ve git commit (Calisma dizinindeki degisiklikleri paketle)
$dirtyFiles = (& git status --porcelain 2>$null)
$committedNow = $false

if ($dirtyFiles) {
    Write-Host "`n[ADIM 1 - GIT ADD]: Degisiklikler sahneye ekleniyor..." -ForegroundColor Cyan
    foreach ($line in $dirtyFiles) {
        Write-Host "   + $line" -ForegroundColor DarkCyan
    }

    if (-not $DryRun) {
        & git add -A
        
        # Eger kullanici ozel commit mesaji vermemisse standart mesaj belirle
        if ([string]::IsNullOrWhiteSpace($CommitMessage)) {
            $CommitMessage = "feat: update system improvements and verified changes"
        }

        Write-Host "`n[ADIM 2 - GIT COMMIT]: Commit olusturuluyor: '$CommitMessage'..." -ForegroundColor Cyan
        & git commit -m "$CommitMessage"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Commit basariyla kaydedildi." -ForegroundColor Green
            $committedNow = $true
        } else {
            Write-Host "[UYARI] Commit olusturulamadi veya degisiklik algilanmadi." -ForegroundColor DarkYellow
        }
    } else {
        Write-Host "`n[DRY-RUN]: 'git add -A' ve 'git commit' simule edildi (gercek commit atilmadi)." -ForegroundColor Yellow
    }
} else {
    Write-Host "`n[BILGI]: Calisma dizini temiz, commitlenecek yeni dosya yok." -ForegroundColor DarkGray
}

# 5. ADIM 3: Push bekleyen commitlerin tespiti
$hasUpstream = $false
& git rev-parse --abbrev-ref '@{u}' 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    $hasUpstream = $true
}

$pendingCommits = @()
if ($hasUpstream) {
    $pendingCommits = (& git log '@{u}..HEAD' --oneline 2>$null)
} else {
    $remoteBranchExists = (& git rev-parse --verify "refs/remotes/$Remote/$Branch" 2>$null)
    if ($LASTEXITCODE -eq 0) {
        $pendingCommits = (& git log "$Remote/$Branch..HEAD" --oneline 2>$null)
    } else {
        $pendingCommits = (& git log "HEAD" -n 5 --oneline 2>$null)
    }
}

# String dizisine donustur ve bos satirlari ayikla
if ($pendingCommits -is [string]) {
    $pendingCommits = @($pendingCommits)
}
$validCommits = @()
if ($pendingCommits) {
    foreach ($item in $pendingCommits) {
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $validCommits += $item
        }
    }
}

if ($validCommits.Count -eq 0 -and -not $committedNow) {
    Write-Host "`n[BILGI]: Uzak depo zaten guncel! Pushlanacak bekleyen yeni commit bulunmuyor." -ForegroundColor Green
    exit 0
}

Write-Host "`n[ADIM 3 - GIT PUSH]: Pushlanacak Commitler ($($validCommits.Count) adet):" -ForegroundColor Cyan
foreach ($c in $validCommits) {
    Write-Host "   -> $c" -ForegroundColor White
}

if ($DryRun) {
    Write-Host "`n[DRY-RUN]: Push simulasyonu tamamlandi. Gercek push yapilmadi." -ForegroundColor Yellow
    exit 0
}

# 6. Guvenli Push Islemi
Write-Host "`n[PUSH]: GitHub'a aktariliyor ($Remote/$Branch)..." -ForegroundColor Yellow

if (-not $hasUpstream) {
    & git push -u $Remote $Branch
} else {
    & git push $Remote $Branch
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n==========================================================" -ForegroundColor Green
    Write-Host "[BASARILI]: Pipeline tamamlandi! (add -> commit -> push)" -ForegroundColor Green
    Write-Host "   Branch : $Branch" -ForegroundColor White
    Write-Host "   Hedef  : $remoteUrl" -ForegroundColor White
    Write-Host "==========================================================" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n[HATA]: Git push islemi basarisiz oldu (Exit Code: $LASTEXITCODE)!" -ForegroundColor Red
    Write-Host "   Lutfen uzaktaki degisiklikleri cekmeyi ('git pull --rebase') veya erisim izinlerinizi kontrol edin." -ForegroundColor DarkGray
    exit 1
}
