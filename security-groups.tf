# One security group per component. The ports map is different for each one,
# so a dynamic block is used instead of repeating ingress blocks.
# SSH and database ports stay open to 0.0.0.0/0.
# Application ports accept traffic only from that component's load balancer.
resource "aws_security_group" "main" {
  for_each = var.components

  name        = "roboshop-${var.env}-${each.key}"
  description = "${each.key} security group"
  vpc_id      = data.aws_vpc.default.id

  dynamic "ingress" {
    for_each = {
      for name, port in each.value.ports : name => port
      if each.value.tier == "db" || name == "ssh"
    }
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      description = ingress.key
    }
  }

  dynamic "ingress" {
    for_each = {
      for name, port in each.value.ports : name => port
      if each.value.tier == "app" && name != "ssh"
    }
    content {
      from_port       = ingress.value
      to_port         = ingress.value
      protocol        = "tcp"
      security_groups = [aws_security_group.alb[each.key].id]
      description     = ingress.key
    }
  }

  # Terraform removes the AWS default outbound rule, so add it back.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = each.key
  })
}

# Frontend listener is public. Catalogue listener accepts the VPC CIDR,
# which is how the frontend instances reach the internal load balancer.
resource "aws_security_group" "alb" {
  for_each = local.app_components

  name        = "roboshop-${var.env}-${each.key}-alb"
  description = "${each.key} load balancer"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = each.value.app_port
    to_port     = each.value.app_port
    protocol    = "tcp"
    cidr_blocks = each.value.lb_internal ? [data.aws_vpc.default.cidr_block] : ["0.0.0.0/0"]
    description = each.value.lb_internal ? "vpc" : "http"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${each.key}-alb"
  })
}
