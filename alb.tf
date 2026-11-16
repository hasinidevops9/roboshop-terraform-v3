# One ALB, target group, and listener per application component.
# Frontend is internet-facing. Catalogue is internal.
# The listener uses the component application port, so catalogue.hdevops09.online:8002
# still reaches catalogue through the internal load balancer.
# Instances join the target group through the Auto Scaling Group, not a
# Terraform target-group attachment.

resource "aws_lb" "app" {
  for_each = local.app_components

  name               = "roboshop-${var.env}-${each.key}"
  internal           = each.value.lb_internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[each.key].id]
  subnets            = data.aws_subnets.default.ids

  tags = merge(local.common_tags, {
    Name = each.key
  })
}

resource "aws_lb_target_group" "app" {
  for_each = local.app_components

  name     = "roboshop-${var.env}-${each.key}"
  port     = each.value.app_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = each.value.health_path
    protocol            = "HTTP"
    matcher             = "200"
    port                = "traffic-port"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, {
    Name = each.key
  })
}

resource "aws_lb_listener" "app" {
  for_each = local.app_components

  load_balancer_arn = aws_lb.app[each.key].arn
  port              = each.value.app_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app[each.key].arn
  }
}
