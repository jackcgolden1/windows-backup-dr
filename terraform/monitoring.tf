resource "aws_sns_topic" "alerts" {
  name = "windows-backup-dr-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "backup_failed" {
  alarm_name          = "windows-backup-dr-backup-failed"
  alarm_description   = "Daily SQL Server backup failed or did not run"
  namespace           = "WindowsBackupDR"
  metric_name         = "BackupSuccess"
  statistic           = "Minimum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "restore_test_failed" {
  alarm_name          = "windows-backup-dr-restore-test-failed"
  alarm_description   = "Daily restore test failed or did not run"
  namespace           = "WindowsBackupDR"
  metric_name         = "RestoreTestSuccess"
  statistic           = "Minimum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}