check "scaling_thresholds" {
  assert {
    condition     = var.scale_in_cpu_threshold < var.scale_out_cpu_threshold
    error_message = "scale_in_cpu_threshold must be lower than scale_out_cpu_threshold."
  }
}

# Frontend and catalogue each have their own group. MySQL is not a member.
# target_group_arns registers every launched instance with that component's ALB.
# The group waits until MySQL provisioning finishes, matching the old Ansible order.

resource "aws_autoscaling_group" "app" {
  for_each = local.app_components

  name                      = "roboshop-${var.env}-${each.key}"
  min_size                  = each.value.asg_min
  max_size                  = each.value.asg_max
  desired_capacity          = each.value.asg_desired
  vpc_zone_identifier       = local.subnet_ids
  target_group_arns         = [aws_lb_target_group.app[each.key].arn]
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period
  wait_for_capacity_timeout = "${var.health_check_grace_period}s"

  launch_template {
    id      = aws_launch_template.app[each.key].id
    version = aws_launch_template.app[each.key].latest_version
  }

  dynamic "tag" {
    for_each = merge(local.common_tags, {
      Name = each.key
    })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  depends_on = [null_resource.db]
}

resource "aws_autoscaling_policy" "app" {
  for_each = local.app_scaling_policies

  name                      = "roboshop-${var.env}-${each.key}"
  autoscaling_group_name    = aws_autoscaling_group.app[each.value.component].name
  policy_type               = "StepScaling"
  adjustment_type           = "ChangeInCapacity"
  estimated_instance_warmup = each.value.policy_name == "scale_out" ? local.scaling_warmup_seconds : null

  dynamic "step_adjustment" {
    for_each = each.value.bound == "lower" ? [each.value.adjustment] : []
    content {
      scaling_adjustment          = step_adjustment.value
      metric_interval_lower_bound = 0
    }
  }

  dynamic "step_adjustment" {
    for_each = each.value.bound == "upper" ? [each.value.adjustment] : []
    content {
      scaling_adjustment          = step_adjustment.value
      metric_interval_upper_bound = 0
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "app" {
  for_each = local.app_scaling_policies

  alarm_name          = "roboshop-${var.env}-${each.key}-cpu"
  alarm_description   = "${each.value.component} ${each.value.policy_name} when average CPU crosses ${each.value.threshold} percent"
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = local.cpu_alarm_evaluation_periods
  datapoints_to_alarm = local.cpu_alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = local.cpu_alarm_period
  statistic           = "Average"
  threshold           = each.value.threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app[each.value.component].name
  }

  alarm_actions = [aws_autoscaling_policy.app[each.key].arn]
}
