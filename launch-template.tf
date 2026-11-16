# One launch template per application. User data installs that component.
# update_default_version publishes each user-data change as the version the
# Auto Scaling Group reads. Existing instances keep running until a later
# scale or refresh event.

resource "aws_launch_template" "app" {
  for_each = local.app_components

  name                   = "roboshop-${var.env}-${each.key}"
  description            = "${each.key} launch template"
  image_id               = var.ami_id
  instance_type          = var.instance_type
  update_default_version = true

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.main[each.key].id]
    device_index                = 0
    delete_on_termination       = true
  }

  user_data = base64encode(templatefile("${path.module}/userdata/${each.key}.sh.tpl", {
    component_name = each.key
    catalogue_host = "catalogue.${var.domain_name}"
    mysql_host     = "mysql.${var.domain_name}"
    artifact_url   = "https://raw.githubusercontent.com/raghudevopsb90/roboshop-microservices/main/artifacts/${each.key}.zip"
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = each.key
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_tags, {
      Name = each.key
    })
  }

  tags = merge(local.common_tags, {
    Name = each.key
  })
}
