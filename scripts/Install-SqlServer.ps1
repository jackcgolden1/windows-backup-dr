$ErrorActionPreference = "Stop"

$InstallerUrl = "https://download.microsoft.com/download/29654887-7cde-4397-bba3-d7f087970845/SQL2022-SSEI-Expr.exe"
$SetupDir     = "C:\SQLSetup"

New-Item -ItemType Directory -Path $SetupDir -Force | Out-Null

# 1. Download the small installer, then use it to download the full setup files
Invoke-WebRequest -Uri $InstallerUrl -OutFile "$SetupDir\SQLExpress.exe" -UseBasicParsing
Start-Process -FilePath "$SetupDir\SQLExpress.exe" -ArgumentList "/ACTION=Download /MEDIAPATH=$SetupDir /MEDIATYPE=Core /QUIET" -Wait

# 2. Unpack the setup files
Start-Process -FilePath "$SetupDir\SQLEXPR_x64_ENU.exe" -ArgumentList "/q /x:$SetupDir\Extract" -Wait

# 3. Install SQL Server silently (skip the online update check that failed before)
Start-Process -FilePath "$SetupDir\Extract\setup.exe" -ArgumentList '/Q /ACTION=Install /FEATURES=SQLEngine /INSTANCENAME=SQLEXPRESS /SQLSYSADMINACCOUNTS="BUILTIN\Administrators" /IACCEPTSQLSERVERLICENSETERMS /UPDATEENABLED=False' -Wait

# 4. Install the SqlServer PowerShell module used by the backup and restore scripts
Install-PackageProvider -Name NuGet -Force | Out-Null
Install-Module SqlServer -Force -AllowClobber -Scope AllUsers

Get-Service 'MSSQL$SQLEXPRESS'