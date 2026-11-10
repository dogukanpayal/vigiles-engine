# WalletService.ps1
# Kurşungeçirmez Dijital Cüzdan ve Bakiye Servisi

class WalletService {
    [string]$UserId
    [double]$Balance
    [double]$MaxBalance = 10000.0
    [System.Collections.Generic.HashSet[string]]$UsedVouchers
    hidden [hashtable]$VoucherCatalog
    hidden [object]$SyncRoot = [object]::new()

    WalletService([string]$userId, [double]$initialBalance) {
        if ([string]::IsNullOrWhiteSpace($userId)) {
            throw "GecersizKullanici: Kullanici kimligi bos olamaz."
        }
        if ($initialBalance -lt 0) {
            throw "GecersizTutar: Baslangic bakiyesi negatif olamaz."
        }
        if ($initialBalance -gt $this.MaxBalance) {
            throw "BakiyeTavaniAsildi: Baslangic bakiyesi 10.000 TL tavanini asamaz."
        }

        $this.UserId = $userId
        $this.Balance = $initialBalance
        $this.UsedVouchers = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $this.VoucherCatalog = @{
            "HEDIYE50"  = 50.0
            "HEDIYE100" = 100.0
            "HEDIYE250" = 250.0
            "VIP500"    = 500.0
        }
    }

    [hashtable] TopUp([double]$amount) {
        [System.Threading.Monitor]::Enter($this.SyncRoot)
        try {
            if ($amount -le 0) {
                throw "GecersizTutar: Yukleme tutari sifirdan buyuk olmalidir."
            }
            if (($this.Balance + $amount) -gt $this.MaxBalance) {
                throw "BakiyeTavaniAsildi: Toplam bakiye maksimum limiti (10.000 TL) asamaz."
            }

            $this.Balance += $amount
            return @{
                Success    = $true
                Amount     = $amount
                NewBalance = $this.Balance
                Message    = "$amount TL basariyla yuklendi."
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($this.SyncRoot)
        }
    }

    [hashtable] Spend([double]$amount, [string]$description) {
        [System.Threading.Monitor]::Enter($this.SyncRoot)
        try {
            if ($amount -le 0) {
                throw "GecersizTutar: Harcama tutari sifirdan buyuk olmalidir."
            }
            if ($this.Balance -lt $amount) {
                throw "YetersizBakiye: Cuzdanda yeterli bakiye yok (Mevcut: $($this.Balance) TL, Istenen: $amount TL)."
            }

            $this.Balance -= $amount
            return @{
                Success     = $true
                Spent       = $amount
                NewBalance  = $this.Balance
                Description = $description
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($this.SyncRoot)
        }
    }

    [hashtable] RedeemVoucher([string]$voucherCode) {
        [System.Threading.Monitor]::Enter($this.SyncRoot)
        try {
            if ([string]::IsNullOrWhiteSpace($voucherCode)) {
                throw "GecersizKupon: Kupon kodu bos olamaz."
            }

            $code = $voucherCode.Trim().ToUpper()

            if (-not $this.VoucherCatalog.ContainsKey($code)) {
                throw "GecersizKupon: '$code' kuponu sistemde tanimli degil."
            }

            if ($this.UsedVouchers.Contains($code)) {
                throw "KuponZatenKullanildi: '$code' kuponu hesaba daha once yuklenmistir."
            }

            $voucherValue = [double]$this.VoucherCatalog[$code]

            if (($this.Balance + $voucherValue) -gt $this.MaxBalance) {
                throw "BakiyeTavaniAsildi: Kupon ile bakiye maksimum 10.000 TL tavanini asamaz."
            }

            $this.UsedVouchers.Add($code) | Out-Null
            $this.Balance += $voucherValue

            return @{
                Success     = $true
                VoucherCode = $code
                Value       = $voucherValue
                NewBalance  = $this.Balance
                Message     = "$code kuponu uygulandi, $voucherValue TL yuklendi."
            }
        }
        finally {
            [System.Threading.Monitor]::Exit($this.SyncRoot)
        }
    }
}
