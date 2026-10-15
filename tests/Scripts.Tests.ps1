BeforeDiscovery {
    $scripts = Get-ChildItem "$PSScriptRoot/../scripts" -Filter *.ps1
}

Describe "<_.Name>" -ForEach $scripts {
    BeforeAll {
        $path    = $_.FullName
        $content = Get-Content $path -Raw
    }

    It "has no syntax errors" {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It "stops on errors" {
        $content | Should -Match '\$ErrorActionPreference\s*=\s*"Stop"'
    }

    It "contains no AWS access keys" {
        $content | Should -Not -Match 'AKIA[0-9A-Z]{16}'
    }

    It "passes PSScriptAnalyzer with no errors" {
        Invoke-ScriptAnalyzer -Path $path -Severity Error | Should -BeNullOrEmpty
    }
}

Describe "Backup-Database.ps1" {
    BeforeAll {
        $content = Get-Content "$PSScriptRoot/../scripts/Backup-Database.ps1" -Raw
    }

    It "verifies backups with a checksum" {
        $content | Should -Match '-Checksum'
    }

    It "reports results to CloudWatch" {
        $content | Should -Match 'BackupSuccess'
    }

    It "exits with an error code on failure" {
        $content | Should -Match 'exit 1'
    }
}