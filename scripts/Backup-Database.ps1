$ErrorActionPreference = "Stop"

$Instance  = ".\SQLEXPRESS"
$Database  = "AdventureWorksLT"
$Bucket    = "windows-backup-dr-594116288653"
$BackupDir = "C:\Program Files\Microsoft SQL Server\MSSQL17.SQLEXPRESS\MSSQL\Backup"
$LogDir    = "C:\BackupLogs"

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
Start-Transcript -Path "$LogDir\backup-$Timestamp.log"

$Succeeded = $false
try {
    $FileName   = "$Database-$Timestamp.bak"
    $BackupFile = Join-Path $BackupDir $FileName

    Backup-SqlDatabase -ServerInstance $Instance -Database $Database -BackupFile $BackupFile -Checksum -TrustServerCertificate
    Write-Output "Backup created: $BackupFile"

    # Upload in a separate PowerShell process so the AWS and SqlServer modules don't clash
    powershell.exe -NoProfile -Command "Write-S3Object -BucketName '$Bucket' -File '$BackupFile' -Key 'backups/$FileName' -Region us-east-1"
    if ($LASTEXITCODE -ne 0) { throw "S3 upload failed with exit code $LASTEXITCODE" }
    Write-Output "Uploaded to s3://$Bucket/backups/$FileName"

    Remove-Item $BackupFile
    $Succeeded = $true
    Write-Output "Backup succeeded"
}
catch {
    Write-Output "Backup FAILED: $_"
}
finally {
    # Report the result to CloudWatch: 1 = success, 0 = failure
    $Value = if ($Succeeded) { 1 } else { 0 }
    powershell.exe -NoProfile -Command {
        param($Value)
        Import-Module AWSPowerShell
        $datum = New-Object Amazon.CloudWatch.Model.MetricDatum
        $datum.MetricName = "BackupSuccess"
        $datum.Value = $Value
        $datum.Unit = "Count"
        Write-CWMetricData -Namespace "WindowsBackupDR" -MetricData $datum -Region us-east-1
    } -args $Value
    Write-Output "Published BackupSuccess = $Value to CloudWatch"
    Stop-Transcript
}

if (-not $Succeeded) { exit 1 }