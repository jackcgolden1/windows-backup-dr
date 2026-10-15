$ErrorActionPreference = "Stop"

$Instance  = ".\SQLEXPRESS"
$Database  = "AdventureWorksLT"
$Bucket    = "windows-backup-dr-594116288653"
$BackupDir = "C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup"
$File      = Join-Path $BackupDir "dr-restore.bak"

# 1. Download the newest backup from S3 (separate process so the AWS and SqlServer modules don't clash)
$Key = powershell.exe -NoProfile -Command {
    param($Bucket, $File)
    $ErrorActionPreference = "Stop"
    $latest = Get-S3Object -BucketName $Bucket -KeyPrefix "backups/" -Region us-east-1 |
        Sort-Object LastModified -Descending | Select-Object -First 1
    Read-S3Object -BucketName $Bucket -Key $latest.Key -File $File -Region us-east-1 | Out-Null
    $latest.Key
} -args $Bucket, $File
if (-not (Test-Path $File)) { throw "Download from S3 failed" }
Write-Output "Downloaded: $Key"

# 2. Restore it as the real database
Restore-SqlDatabase -ServerInstance $Instance -Database $Database -BackupFile $File -AutoRelocateFile -ReplaceDatabase -TrustServerCertificate
Write-Output "Restored $Database"

# 3. Prove the data is back
$count = (Invoke-Sqlcmd -ServerInstance $Instance -TrustServerCertificate -Query "SELECT COUNT(*) AS N FROM [$Database].SalesLT.Customer").N
Write-Output "Customers restored: $count"

Remove-Item $File