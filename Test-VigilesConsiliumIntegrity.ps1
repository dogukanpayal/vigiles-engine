# Test-VigilesConsiliumIntegrity.ps1
# Vigiles Consilium Protocol (VCP /think) Butunluk ve Anayasal Kural Dogrulama Testi

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ws = "c:\Users\Dogukan\Desktop\Antigravity Improvement"
$globalConfig = Join-Path $HOME ".gemini\config\skills"
$coreSkills = Join-Path $ws "core\skills"

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
Write-Host "VIGILES CONSILIUM (THINK) BUTUNLUK TESTI" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Dosya Varlik Testleri
$coreThink = Join-Path $coreSkills "think\SKILL.md"
$coreConsilium = Join-Path $coreSkills "consilium\SKILL.md"
$globalThink = Join-Path $globalConfig "think\SKILL.md"
$globalConsilium = Join-Path $globalConfig "consilium\SKILL.md"

Assert-Condition (Test-Path $coreThink) "1. Core think/SKILL.md varligi" "Dosya bulunamadi: $coreThink"
Assert-Condition (Test-Path $coreConsilium) "2. Core consilium/SKILL.md varligi" "Dosya bulunamadi: $coreConsilium"
Assert-Condition (Test-Path $globalThink) "3. Global think/SKILL.md varligi" "Dosya bulunamadi: $globalThink"
Assert-Condition (Test-Path $globalConsilium) "4. Global consilium/SKILL.md varligi" "Dosya bulunamadi: $globalConsilium"

# 2. Icerik ve Anayasal Kural Denetimi
if (Test-Path $coreThink) {
    $content = Get-Content -Raw -Encoding UTF8 $coreThink

    # YAML Frontmatter
    Assert-Condition ($content -match 'name:\s*think') "5. Frontmatter name: think" "Frontmatter'da name: think yok"
    Assert-Condition ($content -match '/think' -and $content -match '/consilium') "6. Tetikleyici komutlar tanimli" "/think veya /consilium tetikleyicisi eksik"

    # Sifir Kod Dokunulmazligi (Zero Code Mutation)
    Assert-Condition ($content -match 'Zero Code Mutation' -or $content -match 'KOD DOKUNULMAZL') "7. Anayasa: Sifir Kod Dokunulmazligi Kuralı" "Sıfır Kod Dokunulmazlığı ilkesi eksik"
    Assert-Condition ($content -match 'ASLA' -and ($content -match 'kod' -or $content -match 'yasakt')) "8. Kod degisikligi yasagi acikca belirtilmis" "Kod degistirme yasagi vurgulanmamis"

    # 5 Cekirdek Dusunce Rolu
    Assert-Condition ($content -match 'SOKRATES' -or $content -match 'Sokrates') "9. Rol: Sokrates (Dugum Cozucu)" "Sokrates rolu eksik"
    Assert-Condition ($content -match 'Deep Scout' -or $content -match 'ARASTIRMACI' -or $content -match 'Archaeologist') "10. Rol: Bas Arastirmaci (Deep Scout)" "Arastirmaci rolu eksik"
    Assert-Condition ($content -match "Adversary" -or $content -match "Devil" -or $content -match "AVUKAT") "11. Rol: Seytanin Avukati (Adversary)" "Seytanin Avukati rolu eksik"
    Assert-Condition ($content -match 'FEYNMAN' -or $content -match 'Feynman') "12. Rol: Feynman (Gorsellestirici)" "Feynman rolu eksik"
    Assert-Condition ($content -match 'STRATEJ' -or $content -match 'Roadmap Crafter') "13. Rol: Bas Stratejist & Vigiles Elcisi" "Stratejist rolu eksik"

    # 4 Dusunce Senaryosu
    Assert-Condition ($content -match 'Kafa' -or $content -match 'Confusion' -or $content -match 'Sokratik') "14. Senaryo 1: Kafa Karisikligi Cozumu" "Kafa karisikligi senaryosu eksik"
    Assert-Condition ($content -match 'Trade-Off' -or $content -match 'Kiyaslama' -or $content -match 'Derin') "15. Senaryo 2: Derin Arastirma & Kiyaslama" "Derin arastirma senaryosu eksik"
    Assert-Condition ($content -match 'Rontgen' -or $content -match 'Sensemaking' -or $content -match 'Anlama') "16. Senaryo 3: Sistem Anlama & Rontgen" "Anlama / Rontgen senaryosu eksik"
    Assert-Condition ($content -match 'Mimari Planlama' -or $content -match 'Roadmap' -or $content -match 'ADR') "17. Senaryo 4: Mimari Planlama & ADR" "Mimari planlama senaryosu eksik"

    # Vigiles'e Devir Koprusu
    Assert-Condition ($content -match '/vigiles' -and $content -match '/lite') "18. Vigiles ve Lite paslasma koprusu" "/vigiles ve /lite yonlendirmesi eksik"

    # Gemini 4 Model & Efor Danismani (Secenek B)
    Assert-Condition ($content -match 'Carbon' -and $content -match 'Argon' -and $content -match 'Hydrogen' -and $content -match 'XHigh') "19. Gemini 4 Model & Efor Matrisi" "Carbon/Argon/Hydrogen veya XHigh tanimi eksik"
    Assert-Condition ($content -match 'Önerilen Vites' -and $content -match 'Önerilen Model' -and $content -match 'Alternatif') "20. Secenek B Teslimat Sablonu" "Önerilen Vites / Model / Alternatif alanlari eksik"
}

if ((Test-Path $coreThink) -and (Test-Path $coreConsilium)) {
    $consiliumContent = Get-Content -Raw -Encoding UTF8 $coreConsilium
    Assert-Condition ($consiliumContent -match 'Model, Efor ve Vites' -and $consiliumContent -match 'Alternatif') "21. consilium/SKILL.md Model Matrisi Senkronizasyonu" "consilium/SKILL.md icerigi guncel degil"
}

Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
if ($failures -eq 0) {
    Write-Host "TUM TESTLER BASARIYLA GECTI! (0 Hata)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$failures TEST BASARISIZ OLDU!" -ForegroundColor Red
    exit 1
}
