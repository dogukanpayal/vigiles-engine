param(
    [Parameter(Mandatory=$true)]
    [string]$BranchName,

    [Parameter(Mandatory=$true)]
    [string]$CommitMessage,

    [string]$PrTitle = "",
    [string]$PrBody = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

Write-Host "🔀 [GİT & PR FABRİKASI]: İşlem başlatılıyor..." -ForegroundColor Cyan

# 1. Yeni veya var olan branch'e geç
git checkout -b $BranchName 2>$null
if ($LASTEXITCODE -ne 0) {
    git checkout $BranchName
}

# 2. Değişiklikleri ekle ve commit at
git add .
git commit -m $CommitMessage

Write-Host "✅ Commit oluşturuldu: $CommitMessage" -ForegroundColor Green

# 3. Eğer GitHub CLI (gh) yüklüyse ve PR başlığı verilmişse PR aç
if ($PrTitle -and (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "🚀 GitHub Pull Request oluşturuluyor..." -ForegroundColor Yellow
    git push -u origin $BranchName
    gh pr create --title "$PrTitle" --body "$PrBody"
    Write-Host "🎉 Pull Request başarıyla açıldı!" -ForegroundColor Green
} else {
    Write-Host "ℹ️ PR oluşturma atlandı (Lokal branch güncellendi)." -ForegroundColor DarkGray
}
