$ErrorActionPreference = "Stop"

$Instance  = ".\SQLEXPRESS"
$Database  = "AdventureWorksLT"
$TestDb    = "AdventureWorksLT_RestoreTest"
$Bucket    = "windows-backup-dr-594116288653"
$BackupDir = "C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup"
$DataDir   = "C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\DATA"
$LogDir    = "C:\BackupLogs"
$TestFile  = Join-Path $BackupDir "restore-test.bak"

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
Start-Transcript -Path "$LogDir\restore-test-$Timestamp.log"

$Succeeded = $false
try {
    # 1. Download the newest backup from S3 (separate process so the AWS and SqlServer modules don't clash)
    $Key = powershell.exe -NoProfile -Command {
        param($Bucket, $File)
        $ErrorActionPreference = "Stop"
        $latest = Get-S3Object -BucketName $Bucket -KeyPrefix "backups/" -Region us-east-1 |
            Sort-Object LastModified -Descending | Select-Object -First 1
        Read-S3Object -BucketName $Bucket -Key $latest.Key -File $File -Region us-east-1 | Out-Null
        $latest.Key
    } -args $Bucket, $TestFile
    if (-not (Test-Path $TestFile)) { throw "Download from S3 failed" }
    Write-Output "Downloaded: $Key"

    # 2. Restore it as a separate test database, giving its files new names so they don't overwrite the real database
    $files = Invoke-Sqlcmd -ServerInstance $Instance -TrustServerCertificate -Query "RESTORE FILELISTONLY FROM DISK = N'$TestFile'"
    $moves = foreach ($f in $files) {
        $ext = if ($f.Type -eq "L") { "ldf" } else { "mdf" }
        "MOVE N'$($f.LogicalName)' TO N'$DataDir\$TestDb-$($f.LogicalName).$ext'"
    }
    $restoreSql = "RESTORE DATABASE [$TestDb] FROM DISK = N'$TestFile' WITH REPLACE, CHECKSUM, " + ($moves -join ", ")
    Invoke-Sqlcmd -ServerInstance $Instance -TrustServerCertificate -QueryTimeout 600 -Query $restoreSql
    Write-Output "Restored as $TestDb"

    # 3. Check the restored database for corruption
    Invoke-Sqlcmd -ServerInstance $Instance -TrustServerCertificate -QueryTimeout 600 -Query "DBCC CHECKDB ([$TestDb]) WITH NO_INFOMSGS"
    Write-Output "Integrity check passed"

    # 4. Compare row counts between the real and restored databases
    $live     = (Invoke-Sqlcmd -ServerInstance $Instance -TrustServerCertificate -Query "SELECT COUNT(*) AS N FROM [$Database].SalesLT.Customer").N
    $restored = (Invoke-Sqlcmd -ServerInstance $Instance -TrustServerCertificate -Query "SELECT COUNT(*) AS N FROM [$TestDb].SalesLT.Customer").N
    if ($live -ne $restored) { throw "Row count mismatch: live=$live restored=$restored" }
    Write-Output "Row counts match: $restored customers"

    $Succeeded = $true
    Write-Output "Restore test PASSED"
}
catch {
    Write-Output "Restore test FAILED: $_"
}
finally {
    # 5. Clean up: drop the test database and delete the downloaded file
    Invoke-Sqlcmd -ServerInstance $Instance -TrustServerCertificate -Query "IF DB_ID('$TestDb') IS NOT NULL DROP DATABASE [$TestDb]" -ErrorAction SilentlyContinue
    Remove-Item $TestFile -ErrorAction SilentlyContinue

    # 6. Report the result to CloudWatch: 1 = success, 0 = failure
    $Value = if ($Succeeded) { 1 } else { 0 }
    powershell.exe -NoProfile -Command {
        param($Value)
        Import-Module AWSPowerShell
        $datum = New-Object Amazon.CloudWatch.Model.MetricDatum
        $datum.MetricName = "RestoreTestSuccess"
        $datum.Value = $Value
        $datum.Unit = "Count"
        Write-CWMetricData -Namespace "WindowsBackupDR" -MetricData $datum -Region us-east-1
    } -args $Value
    Write-Output "Published RestoreTestSuccess = $Value to CloudWatch"
    Stop-Transcript
}

if (-not $Succeeded) { exit 1 }