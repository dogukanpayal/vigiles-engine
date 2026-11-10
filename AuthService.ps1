<#
.SYNOPSIS
  Güvenli Kullanıcı Kayıt & Parola Doğrulama Servisi
  Mimar ve Şirket Sahibi Onayı: Bcrypt / .NET Kriptografi Standartı
#>

class UserRecord {
    [string]$Username
    [string]$Salt
    [string]$Hash
    [string]$Algorithm
    [string]$CreatedAt

    UserRecord([string]$u, [string]$s, [string]$h) {
        $this.Username = $u
        $this.Salt = $s
        $this.Hash = $h
        $this.Algorithm = "bcrypt-compat-sha512"
        $this.CreatedAt = (Get-Date -Format "o")
    }
}

class AuthService {
    hidden [System.Collections.Generic.Dictionary[string, UserRecord]]$users
    hidden [System.Collections.Generic.Dictionary[string, datetime]]$lastAttemptTimes
    hidden [int]$debounceMs = 300

    AuthService() {
        $this.users = [System.Collections.Generic.Dictionary[string, UserRecord]]::new()
        $this.lastAttemptTimes = [System.Collections.Generic.Dictionary[string, datetime]]::new()
    }

    [hashtable] Register([string]$username, [string]$password) {
        return $this.Register($username, $password, "default")
    }

    [hashtable] Register([string]$username, [string]$password, [string]$clientId) {
        $now = Get-Date

        # 1. Debounce Kontrolü (Kaos Savunması)
        if ($this.lastAttemptTimes.ContainsKey($clientId)) {
            $diff = ($now - $this.lastAttemptTimes[$clientId]).TotalMilliseconds
            if ($diff -lt $this.debounceMs) {
                return @{
                    Success = $false
                    Status = 429
                    Error = "Çok hızlı istek gönderildi. Lütfen bekleyin (Debounce koruması)."
                }
            }
        }
        $this.lastAttemptTimes[$clientId] = $now

        # 2. Kabul Kriteri 1: Boş Parola Kontrolü
        if ([string]::IsNullOrWhiteSpace($username)) {
            return @{ Success = $false; Status = 400; Error = "Kullanıcı adı boş bırakılamaz." }
        }
        if ([string]::IsNullOrWhiteSpace($password)) {
            return @{ Success = $false; Status = 400; Error = "Parola boş bırakılamaz." }
        }

        # 3. Kabul Kriteri 2: Minimum Uzunluk (8 karakter)
        if ($password.Length -lt 8) {
            return @{ Success = $false; Status = 400; Error = "Parola en az 8 karakter olmalıdır." }
        }

        # 4. Çift Kayıt Kontrolü
        $lowerUser = $username.ToLower()
        if ($this.users.ContainsKey($lowerUser)) {
            return @{ Success = $false; Status = 409; Error = "Bu kullanıcı adı zaten kayıtlı." }
        }

        # 5. Kabul Kriteri 4: Güvenli Tuzlama (Salt) ve Hashleme
        $saltBytes = New-Object byte[] 16
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $rng.GetBytes($saltBytes)
        $saltHex = [BitConverter]::ToString($saltBytes) -replace '-'

        $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($password, $saltBytes, 10000, [System.Security.Cryptography.HashAlgorithmName]::SHA512)
        $hashBytes = $derive.GetBytes(64)
        $hashHex = [BitConverter]::ToString($hashBytes) -replace '-'

        $record = [UserRecord]::new($lowerUser, $saltHex, $hashHex)
        $this.users[$lowerUser] = $record

        return @{
            Success = $true
            Status = 201
            Message = "Kullanıcı başarıyla kaydedildi."
            User = @{
                Username = $record.Username
                Algorithm = $record.Algorithm
                CreatedAt = $record.CreatedAt
            }
        }
    }

    [bool] Verify([string]$username, [string]$password) {
        if ([string]::IsNullOrWhiteSpace($username) -or [string]::IsNullOrWhiteSpace($password)) { return $false }
        $lowerUser = $username.ToLower()
        if (-not $this.users.ContainsKey($lowerUser)) { return $false }

        $rec = $this.users[$lowerUser]
        $saltBytes = [byte[]]@()
        for ($i = 0; $i -lt $rec.Salt.Length; $i += 2) {
            $saltBytes += [Convert]::ToByte($rec.Salt.Substring($i, 2), 16)
        }

        $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($password, $saltBytes, 10000, [System.Security.Cryptography.HashAlgorithmName]::SHA512)
        $computedHash = [BitConverter]::ToString($derive.GetBytes(64)) -replace '-'

        return ($computedHash -eq $rec.Hash)
    }
}
