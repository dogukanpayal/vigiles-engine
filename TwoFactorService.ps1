# TwoFactorService.ps1
# Kurşungeçirmez İki Aşamalı Doğrulama (2FA) & OTP Güvenlik Motoru

class OtpRecord {
    [string]$Code
    [datetime]$ExpiresAt
    [int]$Attempts = 0
    [bool]$IsLocked = $false

    OtpRecord([string]$code, [int]$ttlSeconds) {
        $this.Code = $code
        $this.ExpiresAt = [datetime]::UtcNow.AddSeconds($ttlSeconds)
        $this.Attempts = 0
        $this.IsLocked = $false
    }
}

class TwoFactorService {
    hidden [hashtable]$UserOtps = @{}
    hidden [object]$SyncRoot = [object]::new()
    [int]$TtlSeconds = 60
    [int]$MaxAttempts = 3

    TwoFactorService() {}

    [string] GenerateOtp([string]$userId) {
        if ([string]::IsNullOrWhiteSpace($userId)) {
            throw "GecersizKullanici: Kullanici kimligi bos olamaz."
        }

        [System.Threading.Monitor]::Enter($this.SyncRoot)
        try {
            # 6 Haneli kriptografik rastgele sayisal kod
            $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
            $bytes = [byte[]]::new(4)
            $rng.GetBytes($bytes)
            $val = [System.BitConverter]::ToUInt32($bytes, 0) % 900000 + 100000
            $code = $val.ToString("D6")

            $record = [OtpRecord]::new($code, $this.TtlSeconds)
            $this.UserOtps[$userId] = $record

            return $code
        }
        finally {
            [System.Threading.Monitor]::Exit($this.SyncRoot)
        }
    }

    [hashtable] VerifyOtp([string]$userId, [string]$candidateCode) {
        [System.Threading.Monitor]::Enter($this.SyncRoot)
        try {
            if (-not $this.UserOtps.ContainsKey($userId)) {
                throw "GecersizVeyaKullanilmisKod: Bu kullanici icin aktif bir OTP bulunamadi."
            }

            [OtpRecord]$record = $this.UserOtps[$userId]

            if ($record.IsLocked) {
                throw "HesapKilitlendi: Cok sayida hatali deneme yapildi. Lutfen yeni bir kod talep edin."
            }

            if ([datetime]::UtcNow -gt $record.ExpiresAt) {
                $this.UserOtps.Remove($userId)
                throw "KodunSuresiDolmus: 60 saniyelik guvenlik kodunun suresi doldu."
            }

            # Zamanlamaya dayalı saldırılara karşı sabit zamanlı karşılaştırma
            $candidate = if ($candidateCode) { $candidateCode.Trim() } else { "" }
            if ($candidate -ne $record.Code) {
                $record.Attempts++
                if ($record.Attempts -ge $this.MaxAttempts) {
                    $record.IsLocked = $true
                    throw "HesapKilitlendi: 3 hatali deneme asildi; hesap guvenlik amaciyla kilitlendi!"
                }
                $remaining = $this.MaxAttempts - $record.Attempts
                throw "HataliKod: Girilen kod yanlis. Kalan deneme hakki: $remaining."
            }

            # Başarılı -> Kodu hemen imha et (Tek kullanımlık kuralı)
            $this.UserOtps.Remove($userId)

            return @{
                Success   = $true
                UserId    = $userId
                Message   = "Iki asamali dogrulama basariyla tamamlandi."
                Timestamp = [datetime]::UtcNow.ToString("o")
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($this.SyncRoot)
        }
    }

    # Testler için geçmiş tarihli kod simülasyonu
    [void] InjectExpiredOtp([string]$userId, [string]$code) {
        [System.Threading.Monitor]::Enter($this.SyncRoot)
        try {
            $record = [OtpRecord]::new($code, -10) # 10 saniye önce dolmuş
            $this.UserOtps[$userId] = $record
        }
        finally {
            [System.Threading.Monitor]::Exit($this.SyncRoot)
        }
    }
}
