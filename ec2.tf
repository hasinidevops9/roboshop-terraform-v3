# Database components stay one standalone instance.
# This project does not manage the existing workstation instance.
# Frontend and catalogue are launched by the Auto Scaling Groups in autoscaling.tf.
resource "aws_instance" "main" {
  for_each = local.db_components

  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.main[each.key].id]
  associate_public_ip_address = true

  tags = merge(local.common_tags, {
    Name = each.key
  })
}
