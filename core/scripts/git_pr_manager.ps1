# core/scripts/git_pr_manager.ps1
# Vigiles Engine - Git ve PR Yoneticisi (Sifir Otomatik Push Prensipli)

param(
    [Parameter(Mandatory=$true)]
    [string]$BranchName,

    [Parameter(Mandatory=$true)]
    [string]$CommitMessage,

    [string]$PrTitle = "",
    [string]$PrBody = "",
    [switch]$PushToRemote = $false
)

Write-Host "[GIT & PR FABRIKASI]: Islem baslatiliyor..." -ForegroundColor Cyan

# 1. Yeni veya var olan branch'e gec
& git checkout -b $BranchName 2>$null
if ($LASTEXITCODE -ne 0) {
    & git checkout $BranchName 2>$null
}

# 2. Degisiklikleri ekle ve commit at
& git add .
& git commit -m $CommitMessage

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Commit olusturuldu: $CommitMessage" -ForegroundColor Green
} else {
    Write-Host "[BILGI] Yeni commit olusturulmadi (degisiklik yok veya zaten commitlenmis)." -ForegroundColor DarkGray
}

# 3. Push ve PR Kontrolu (Sifir Otomatik Push İlkesi)
if ($PushToRemote -and $PrTitle -and (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "[PUSH]: GitHub Pull Request olusturuluyor..." -ForegroundColor Yellow
    & git push -u origin $BranchName
    & gh pr create --title "$PrTitle" --body "$PrBody"
    Write-Host "[BASARILI]: Pull Request basariyla acildi!" -ForegroundColor Green
} else {
    Write-Host "`n[BILGI]: Degisiklikler yerel branch'e ($BranchName) kaydedildi." -ForegroundColor Cyan
    Write-Host "[PUSH HAZIR]: GitHub'a aktarmak icin '/push' komutunu kullanabilirsiniz." -ForegroundColor Yellow
}
