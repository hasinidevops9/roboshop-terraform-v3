# Database components stay one standalone instance.
# This project does not manage the existing workstation instance.
resource "aws_instance" "main" {
  for_each = local.db_components

  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.main[each.key].id]
  associate_public_ip_address = true

  tags = {
    Name        = each.key
    Environment = var.env
  }
}

# Application components get instance_count instances and share one target group.
# Public IPs stay so Ansible Pull can SSH in, same as the database instances.
resource "aws_instance" "app" {
  for_each = local.app_instances

  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.main[each.value.component_name].id]
  associate_public_ip_address = true

  tags = {
    Name        = each.key
    Environment = var.env
  }
}
