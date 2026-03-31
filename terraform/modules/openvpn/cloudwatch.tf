resource "aws_cloudwatch_metric_alarm" "system_status_check_failed" {
  alarm_actions       = ["arn:aws:automate:${data.aws_region.current.name}:ec2:recover"]
  alarm_description   = "Trigger a recovery when an underlying system status check fails for 3 consecutive minutes."
  alarm_name          = "${var.name}-system-check-failure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "StatusCheckFailed_System"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "0"
  dimensions = {
    InstanceId = aws_instance.openvpn.id
  }
}

resource "aws_cloudwatch_metric_alarm" "instance_status_check_failed" {
  alarm_actions       = ["arn:aws:automate:${data.aws_region.current.name}:ec2:reboot"]
  alarm_description   = "Trigger a reboot when instance status check fails for 3 consecutive minutes."
  alarm_name          = "${var.name}-instance-check-failure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "StatusCheckFailed_Instance"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Minimum"
  threshold           = "0"
  dimensions = {
    InstanceId = aws_instance.openvpn.id
  }
}
