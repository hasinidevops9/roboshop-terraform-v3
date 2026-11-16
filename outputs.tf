output "instance_ids" {
  value = { for name, instance in aws_instance.main : name => instance.id }
}

output "private_ips" {
  value = { for name, instance in aws_instance.main : name => instance.private_ip }
}

output "public_ips" {
  value = { for name, instance in aws_instance.main : name => instance.public_ip }
}

output "dns_records" {
  value = merge(
    { for name, record in aws_route53_record.main : name => record.fqdn },
    { for name, record in aws_route53_record.app : name => record.fqdn }
  )
}

output "alb_dns_names" {
  value = { for name, lb in aws_lb.app : name => lb.dns_name }
}

output "launch_template_ids" {
  value = { for name, template in aws_launch_template.app : name => template.id }
}

output "autoscaling_groups" {
  value = {
    for name, group in aws_autoscaling_group.app : name => {
      name    = group.name
      min     = group.min_size
      desired = group.desired_capacity
      max     = group.max_size
      arn     = group.arn
    }
  }
}

output "scaling_alarms" {
  value = { for name, alarm in aws_cloudwatch_metric_alarm.app : name => alarm.arn }
}

output "vpc_id" {
  value = data.aws_vpc.default.id
}

output "environment" {
  value = var.env
}
