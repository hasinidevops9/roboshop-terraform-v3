output "instance_ids" {
  value = merge(
    { for name, instance in aws_instance.main : name => instance.id },
    { for name, instance in aws_instance.app : name => instance.id }
  )
}

output "private_ips" {
  value = merge(
    { for name, instance in aws_instance.main : name => instance.private_ip },
    { for name, instance in aws_instance.app : name => instance.private_ip }
  )
}

output "public_ips" {
  value = merge(
    { for name, instance in aws_instance.main : name => instance.public_ip },
    { for name, instance in aws_instance.app : name => instance.public_ip }
  )
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

output "vpc_id" {
  value = data.aws_vpc.default.id
}

output "environment" {
  value = var.env
}
