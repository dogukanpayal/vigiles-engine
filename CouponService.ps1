<#
.SYNOPSIS
  Kupon ve İndirim Doğrulama Motoru (Coupon & Discount Engine)
  Mimar ve Şirket Sahibi Onayı: Yüzdelik İndirim & Tavan Sınırı
#>

class CouponRule {
    [string]$Code
    [string]$Type          # "PERCENTAGE" veya "FIXED"
    [double]$Value         # 20 (%20) veya 50 (50 TL)
    [double]$MinCartTotal  # Minimum sepet tutarı
    [double]$MaxDiscount   # İndirim tavanı

    CouponRule([string]$c, [string]$t, [double]$v, [double]$minC, [double]$maxD) {
        $this.Code = $c.ToUpper()
        $this.Type = $t
        $this.Value = $v
        $this.MinCartTotal = $minC
        $this.MaxDiscount = $maxD
    }
}

class CouponService {
    hidden [System.Collections.Generic.Dictionary[string, CouponRule]]$coupons
    hidden [System.Collections.Generic.HashSet[string]]$redeemedKeys
    hidden [System.Collections.Generic.Dictionary[string, datetime]]$lastAttemptTimes
    hidden [int]$debounceMs = 300
    hidden [object]$lockObj

    CouponService() {
        $this.coupons = [System.Collections.Generic.Dictionary[string, CouponRule]]::new()
        $this.redeemedKeys = [System.Collections.Generic.HashSet[string]]::new()
        $this.lastAttemptTimes = [System.Collections.Generic.Dictionary[string, datetime]]::new()
        $this.lockObj = [object]::new()

        # Varsayılan Onaylı Kuponlar
        $this.coupons["VETERAN20"] = [CouponRule]::new("VETERAN20", "PERCENTAGE", 20.0, 200.0, 100.0)
        $this.coupons["DEV50"] = [CouponRule]::new("DEV50", "FIXED", 50.0, 150.0, 50.0)
    }

    [hashtable] ApplyCoupon([string]$couponCode, [double]$cartTotal, [string]$userId) {
        return $this.ApplyCoupon($couponCode, $cartTotal, $userId, "default")
    }

    [hashtable] ApplyCoupon([string]$couponCode, [double]$cartTotal, [string]$userId, [string]$clientId) {
        $now = Get-Date

        # 1. Debounce Kontrolü (Kaos Savunması)
        [System.Threading.Monitor]::Enter($this.lockObj)
        try {
            if ($this.lastAttemptTimes.ContainsKey($clientId)) {
                $diff = ($now - $this.lastAttemptTimes[$clientId]).TotalMilliseconds
                if ($diff -lt $this.debounceMs) {
                    return @{
                        Success = $false
                        Status = 429
                        Error = "Cok hizli istek gonderildi. Lutfen bekleyin."
                    }
                }
            }
            $this.lastAttemptTimes[$clientId] = $now
        } finally {
            [System.Threading.Monitor]::Exit($this.lockObj)
        }

        # 2. Giriş Doğrulama (Kabul Kriteri 1)
        if ([string]::IsNullOrWhiteSpace($couponCode)) {
            return @{ Success = $false; Status = 400; Error = "Kupon kodu bos birakilamaz." }
        }
        if ([string]::IsNullOrWhiteSpace($userId)) {
            return @{ Success = $false; Status = 400; Error = "Kullanici kimligi bos birakilamaz." }
        }
        if ($cartTotal -le 0) {
            return @{ Success = $false; Status = 400; Error = "Gecersiz sepet tutari." }
        }

        $codeUpper = $couponCode.Trim().ToUpper()
        if (-not $this.coupons.ContainsKey($codeUpper)) {
            return @{ Success = $false; Status = 400; Error = "Gecersiz kupon kodu: '$couponCode'." }
        }

        $rule = $this.coupons[$codeUpper]

        # 3. Minimum Sepet Tutarı Kontrolü (Kabul Kriteri 2)
        if ($cartTotal -lt $rule.MinCartTotal) {
            return @{
                Success = $false
                Status = 400
                Error = "Bu kupon icin minimum sepet tutari $($rule.MinCartTotal) TL olmalidir."
            }
        }

        # 4. Tek Kullanımlık ve Çift Harcama Savunması (Thread-Safe Lock)
        $redemptionKey = "$($userId.ToLower()):$codeUpper"

        [System.Threading.Monitor]::Enter($this.lockObj)
        try {
            if ($this.redeemedKeys.Contains($redemptionKey)) {
                return @{
                    Success = $false
                    Status = 409
                    Error = "Bu kupon bu kullanici tarafindan daha once kullanilmistir."
                }
            }

            # 5. İndirim Hesaplama (Onaylanan Model)
            [double]$discount = 0.0
            if ($rule.Type -eq "PERCENTAGE") {
                $discount = $cartTotal * ($rule.Value / 100.0)
                if ($discount -gt $rule.MaxDiscount) {
                    $discount = $rule.MaxDiscount
                }
            } else {
                $discount = $rule.Value
            }

            [double]$finalTotal = [Math]::Max(0.0, $cartTotal - $discount)

            # Kuponu kullanıldı olarak işaretle
            $this.redeemedKeys.Add($redemptionKey) | Out-Null

            return @{
                Success = $true
                Status = 200
                Message = "Kupon basariyla uygulandi."
                Data = @{
                    CouponCode = $rule.Code
                    OriginalTotal = $cartTotal
                    DiscountAmount = $discount
                    FinalTotal = $finalTotal
                    UserId = $userId
                }
            }
        } finally {
            [System.Threading.Monitor]::Exit($this.lockObj)
        }
    }
}
