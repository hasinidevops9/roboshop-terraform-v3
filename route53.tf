# Database names stay A records pointed at the instance private IP.
# The name is <component>.<domain> with no -dev suffix.
resource "aws_route53_record" "main" {
  for_each = local.db_components

  zone_id = var.zone_id
  name    = "${each.key}.${var.domain_name}"
  type    = "A"
  ttl     = var.ttl
  records = [aws_instance.main[each.key].private_ip]
}

# Application names are CNAMEs. Frontend follows the public ALB.
# Catalogue follows the internal ALB. The catalogue service still uses these hostnames.
resource "aws_route53_record" "app" {
  for_each = local.app_components

  zone_id = var.zone_id
  name    = "${each.key}.${var.domain_name}"
  type    = "CNAME"
  ttl     = var.ttl
  records = [aws_lb.app[each.key].dns_name]
}
