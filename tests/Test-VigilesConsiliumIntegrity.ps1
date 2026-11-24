# Test-VigilesConsiliumIntegrity.ps1
# Vigiles Think (/think) & ThinkDeep (/thinkdeep) Butunluk, Salt-Okunur Kanca ve 19-Eleman Senkron Testi

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ws = Split-Path -Parent $PSScriptRoot
$globalConfig = Join-Path $HOME ".gemini\config\skills"
$globalScripts = Join-Path $HOME ".gemini\config\scripts"
$coreSkills = Join-Path $ws "core\skills"
$coreScripts = Join-Path $ws "core\scripts"

$failures = 0

function Assert-Condition([bool]$condition, [string]$testName, [string]$detail) {
    if ($condition) {
        Write-Host "  [OK] $testName" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $testName - $detail" -ForegroundColor Red
        $script:failures++
    }
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "VIGILES THINK & THINKDEEP (CONSILIUM) BUTUNLUK TESTI" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Dosya Varlik Testleri
$coreThink = Join-Path $coreSkills "think\SKILL.md"
$coreThinkDeep = Join-Path $coreSkills "thinkdeep\SKILL.md"
$globalThink = Join-Path $globalConfig "think\SKILL.md"
$globalThinkDeep = Join-Path $globalConfig "thinkdeep\SKILL.md"
$coreGuard = Join-Path $coreScripts "think_readonly_guard.ps1"
$globalGuard = Join-Path $globalScripts "think_readonly_guard.ps1"
$coreHooks = Join-Path $ws "core\hooks.json"
$globalHooks = Join-Path $HOME ".gemini\config\hooks.json"

Assert-Condition (Test-Path $coreThink) "1. Core think/SKILL.md varligi" "Dosya bulunamadi: $coreThink"
Assert-Condition (Test-Path $coreThinkDeep) "2. Core thinkdeep/SKILL.md varligi" "Dosya bulunamadi: $coreThinkDeep"
Assert-Condition (Test-Path $globalThink) "3. Global think/SKILL.md varligi" "Dosya bulunamadi: $globalThink"
Assert-Condition (Test-Path $globalThinkDeep) "4. Global thinkdeep/SKILL.md varligi" "Dosya bulunamadi: $globalThinkDeep"
Assert-Condition (Test-Path $coreGuard) "5. Core think_readonly_guard.ps1 varligi" "Dosya bulunamadi: $coreGuard"
Assert-Condition (Test-Path $globalGuard) "6. Global think_readonly_guard.ps1 varligi" "Dosya bulunamadi: $globalGuard"

# 2. Hızlı Düşünme (/think) Denetimi
if (Test-Path $coreThink) {
    $thinkContent = Get-Content -Raw -Encoding UTF8 $coreThink
    Assert-Condition ($thinkContent -match 'name:\s*think') "7. /think frontmatter name: think" "Frontmatter'da name: think yok"
    Assert-Condition ($thinkContent -match '/think' -and $thinkContent -match '/thinkdeep') "8. /think -> /thinkdeep yonlendirmesi" "/think veya /thinkdeep tanimi eksik"
    Assert-Condition ($thinkContent -match 'think-readonly-guard') "9. /think salt-okunur kanca korumasi" "think-readonly-guard referansi eksik"
    Assert-Condition ($thinkContent -match '/pro' -and $thinkContent -match '/lite') "10. /think -> /pro ve /lite devir koprusu" "/pro veya /lite yonlendirmesi eksik"
}

# 3. Vigiles ThinkDeep / Consilium (/thinkdeep) Icerik ve Anayasal Kural Denetimi
if (Test-Path $coreThinkDeep) {
    $content = Get-Content -Raw -Encoding UTF8 $coreThinkDeep

    Assert-Condition ($content -match 'name:\s*thinkdeep') "11. /thinkdeep frontmatter name: thinkdeep" "Frontmatter'da name: thinkdeep yok"
    Assert-Condition ($content -match 'Strict Read-Only' -or $content -match 'SIFIR DOSYA YAZMA') "12. Anayasa: Sifir Dosya Yazma & Kod Dokunulmazligi" "Strict Read-Only ilkesi eksik"
    Assert-Condition ($content -match 'think-readonly-guard') "13. /thinkdeep think-readonly-guard kancasi" "think-readonly-guard belirtilmemis"

    # 5 Cekirdek Dusunce Rolu
    Assert-Condition ($content -match 'SOKRATES' -or $content -match 'Sokrates') "14. Rol: Sokrates (Dugum Cozucu)" "Sokrates rolu eksik"
    Assert-Condition ($content -match 'Deep Scout' -or $content -match 'ARASTIRMACI' -or $content -match 'Archaeologist') "15. Rol: Bas Arastirmaci (Deep Scout)" "Arastirmaci rolu eksik"
    Assert-Condition ($content -match "Adversary" -or $content -match "Devil" -or $content -match "AVUKAT") "16. Rol: Seytanin Avukati (Adversary)" "Seytanin Avukati rolu eksik"
    Assert-Condition ($content -match 'FEYNMAN' -or $content -match 'Feynman') "17. Rol: Feynman (Gorsellestirici)" "Feynman rolu eksik"
    Assert-Condition ($content -match 'STRATEJ' -or $content -match 'Roadmap Crafter') "18. Rol: Bas Stratejist & Vigiles Elcisi" "Stratejist rolu eksik"

    # 4 Dusunce Senaryosu & Devir Koprusu
    Assert-Condition ($content -match 'Kafa Kar' -and $content -match 'Trade-Off' -and $content -match 'Röntgen|Sensemaking' -and $content -match 'Roadmap|Yol Harit') "19. 4 Temel Dusunce Senaryosu" "Senaryolardan biri eksik"
    Assert-Condition ($content -match '/pro' -and $content -match '/lite') "20. Vigiles Pro ve Lite paslasma koprusu" "/pro ve /lite yonlendirmesi eksik"

    # Minimal Gemini 4 Model & Vites Matrisi (Alternatif ve uzun aciklama yok) & 19 Elemanlı Kadro
    Assert-Condition ($content -match 'Carbon' -and $content -match 'Argon' -and $content -match 'Hydrogen' -and $content -match 'XHigh') "21. Gemini 4 Model & Efor Matrisi" "Carbon/Argon/Hydrogen veya XHigh tanimi eksik"
    Assert-Condition (($content -match '\*\*Vites:\*\*') -and ($content -match '\*\*Model:\*\*') -and ($content -notmatch 'Seçenek B|\*\*Alternatif:\*\*|Alternatif \(Seçenek B\)')) "22. Minimal Teslimat Sablonu (Alternatifsiz)" "Vites/Model satiri eksik veya eski Alternatif/Secenek B kalintisi var"
    Assert-Condition ($content -match '19 Elemanlı Kadro' -and $content -notmatch '20 Elemanlı Kadro') "23. 19 Elemanlı Kadro guncellemesi" "thinkdeep/SKILL.md hala 20 Elemanli Kadro iceriyor"
}

# 4. Hooks ve Dosya Senkronizasyonu
if ((Test-Path $coreHooks) -and (Test-Path $globalHooks)) {
    $coreHooksRaw = Get-Content -Raw -Encoding UTF8 $coreHooks
    $globalHooksRaw = Get-Content -Raw -Encoding UTF8 $globalHooks
    Assert-Condition (($coreHooksRaw -match 'think-readonly-guard') -and ($globalHooksRaw -match 'think-readonly-guard')) "24. hooks.json think-readonly-guard kaydi" "core veya global hooks.json icinde think-readonly-guard eksik"
}

if ((Test-Path $coreThink) -and (Test-Path $globalThink) -and (Test-Path $coreThinkDeep) -and (Test-Path $globalThinkDeep)) {
    $hashMatch = ((Get-FileHash $coreThink).Hash -eq (Get-FileHash $globalThink).Hash) -and
                 ((Get-FileHash $coreThinkDeep).Hash -eq (Get-FileHash $globalThinkDeep).Hash)
    Assert-Condition $hashMatch "25. Core ve Global think/thinkdeep dosya eslesmesi" "core ve global think/thinkdeep dosyalari farkli (install.ps1 calistirilmali)"
}

Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
if ($failures -eq 0) {
    Write-Host "TUM TESTLER BASARIYLA GECTI! (0 Hata)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$failures TEST BASARISIZ OLDU!" -ForegroundColor Red
    exit 1
}
