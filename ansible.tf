# Provisioners run during resource creation.
# A null_resource runs again when its triggers change.
#
# Python 3.14 is used to install Ansible.
# ansible-pull executes roboshop-pull.yml locally.

resource "null_resource" "db" {
  for_each = local.db_components

  triggers = {
    instance_id               = aws_instance.main[each.key].id
    private_ip                = aws_instance.main[each.key].private_ip
    dns_name                  = aws_route53_record.main[each.key].fqdn
    ansible_bootstrap_version = "4"
  }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      host     = aws_instance.main[each.key].public_ip
      user     = var.ssh_user
      password = var.ssh_password
    }

    inline = [
      "sudo dnf install -y python3.14-pip git",
      "sudo python3.14 -m pip install ansible",
      "sudo /usr/local/bin/ansible-pull -U ${var.ansible_repo} roboshop-pull.yml -e component_name=${each.key}"
    ]
  }
}


# Application provisioning starts after database provisioning.

resource "null_resource" "app" {
  depends_on = [null_resource.db]

  for_each = local.app_instances

  triggers = {
    instance_id               = aws_instance.app[each.key].id
    private_ip                = aws_instance.app[each.key].private_ip
    dns_name                  = aws_route53_record.app[each.value.component_name].fqdn
    ansible_bootstrap_version = "4"
  }

  provisioner "remote-exec" {
    connection {
      type     = "ssh"
      host     = aws_instance.app[each.key].public_ip
      user     = var.ssh_user
      password = var.ssh_password
    }

    inline = [
      "sudo dnf install -y python3.14-pip git",
      "sudo python3.14 -m pip install ansible",
      "sudo /usr/local/bin/ansible-pull -U ${var.ansible_repo} roboshop-pull.yml -e component_name=${each.value.component_name}"
    ]
  }
}
