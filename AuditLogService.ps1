# AuditLogService.ps1
# Kurumsal Seviye Kriptografik Denetim Günlüğü (Audit Log) Servisi
# Thread-safe, SHA256 Zincirli, Kurcalamaya Karşı Korumalı

class AuditLogEntry {
    [string]$Id
    [string]$Timestamp
    [string]$UserId
    [string]$Action
    [string]$Status
    [string]$Details
    [string]$PreviousHash
    [string]$Hash

    AuditLogEntry([string]$id, [string]$userId, [string]$action, [string]$status, [string]$details, [string]$prevHash) {
        $this.Id = $id
        $this.Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        $this.UserId = $userId
        $this.Action = $action
        $this.Status = $status
        $this.Details = $details
        $this.PreviousHash = $prevHash
        $this.Hash = $this.ComputeHash()
    }

    [string] ComputeHash() {
        $raw = "$($this.Id)|$($this.Timestamp)|$($this.UserId)|$($this.Action)|$($this.Status)|$($this.Details)|$($this.PreviousHash)"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha.ComputeHash($bytes)
        $sha.Dispose()
        return -join ($hashBytes | ForEach-Object { "{0:x2}" -f $_ })
    }
}

class AuditLogService {
    [System.Collections.Generic.List[AuditLogEntry]]$Logs
    hidden [object]$SyncRoot = [object]::new()
    hidden [string]$LastHash = "GENESIS_HASH_00000000000000000000000000000000000000000000000000000000"

    AuditLogService() {
        $this.Logs = [System.Collections.Generic.List[AuditLogEntry]]::new()
    }

    [AuditLogEntry] LogAction([string]$userId, [string]$action, [string]$status, [string]$details) {
        if ([string]::IsNullOrWhiteSpace($userId)) {
            throw "GecersizKullanici: Kullanici kimligi bos olamaz."
        }
        if ([string]::IsNullOrWhiteSpace($action)) {
            throw "GecersizAksiyon: Aksiyon alani bos olamaz."
        }

        [System.Threading.Monitor]::Enter($this.SyncRoot)
        try {
            $entryId = [System.Guid]::NewGuid().ToString("N")
            $entry = [AuditLogEntry]::new($entryId, $userId, $action, $status, $details, $this.LastHash)
            $this.Logs.Add($entry)
            $this.LastHash = $entry.Hash
            return $entry
        } finally {
            [System.Threading.Monitor]::Exit($this.SyncRoot)
        }
    }

    [bool] VerifyIntegrity() {
        [System.Threading.Monitor]::Enter($this.SyncRoot)
        try {
            $expectedPrev = "GENESIS_HASH_00000000000000000000000000000000000000000000000000000000"
            foreach ($log in $this.Logs) {
                if ($log.PreviousHash -ne $expectedPrev) {
                    return $false
                }
                $calculated = $log.ComputeHash()
                if ($calculated -ne $log.Hash) {
                    return $false
                }
                $expectedPrev = $log.Hash
            }
            return $true
        } finally {
            [System.Threading.Monitor]::Exit($this.SyncRoot)
        }
    }

    [int] GetCount() {
        return $this.Logs.Count
    }
}
