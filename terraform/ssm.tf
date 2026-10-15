resource "aws_ssm_association" "backup" {
  name                = "AWS-RunPowerShellScript"
  association_name    = "windows-backup-dr-daily-backup"
  schedule_expression = "cron(0 23 * * ? *)"

  targets {
    key    = "InstanceIds"
    values = [aws_instance.server.id]
  }

  parameters = {
    commands = file("${path.module}/../scripts/Backup-Database.ps1")
  }
}

resource "aws_ssm_association" "restore_test" {
  name                = "AWS-RunPowerShellScript"
  association_name    = "windows-backup-dr-daily-restore-test"
  schedule_expression = "cron(30 23 * * ? *)"

  targets {
    key    = "InstanceIds"
    values = [aws_instance.server.id]
  }

  parameters = {
    commands = file("${path.module}/../scripts/Test-Restore.ps1")
  }
}