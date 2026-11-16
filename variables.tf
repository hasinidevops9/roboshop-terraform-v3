# Values for these variables come from env-dev/*.auto.tfvars.
# Terraform does not auto-load .auto.tfvars files that sit in a subdirectory.

variable "env" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "instance_type" {
  type = string
}

# each.key is the component name (frontend, catalogue, mysql).
# tier is "db" or "app". Only application components carry ASG capacity.
# ports feeds the security group dynamic block. The non-SSH port is the
# application port used by the load balancer and launch template.
variable "components" {
  type = map(object({
    tier        = string
    ports       = map(number)
    lb_internal = optional(bool, false)
    health_path = optional(string, "/health")
    asg_min     = optional(number)
    asg_desired = optional(number)
    asg_max     = optional(number)
  }))

  validation {
    condition = alltrue([
      for component in var.components :
      component.tier != "app" || (
        component.asg_min != null &&
        component.asg_desired != null &&
        component.asg_max != null &&
        component.asg_min >= 1 &&
        component.asg_min <= component.asg_desired &&
        component.asg_desired <= component.asg_max
      )
    ])
    error_message = "Application components require asg_min >= 1 and asg_min <= asg_desired <= asg_max."
  }
}

variable "zone_id" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "ttl" {
  type = number
}

# Login for the DevOps Practice AMI. MySQL is still provisioned over SSH.
variable "ssh_user" {
  type    = string
  default = "ec2-user"
}

variable "ssh_password" {
  type      = string
  default   = "DevOps321"
  sensitive = true
}

variable "ansible_repo" {
  type    = string
  default = "https://github.com/hasinidevops9/roboshop-ansible.git"
}

variable "scale_out_cpu_threshold" {
  type = number

  validation {
    condition     = var.scale_out_cpu_threshold > 0 && var.scale_out_cpu_threshold < 100
    error_message = "scale_out_cpu_threshold must be between 0 and 100."
  }
}

variable "scale_in_cpu_threshold" {
  type = number

  validation {
    condition     = var.scale_in_cpu_threshold > 0 && var.scale_in_cpu_threshold < 100
    error_message = "scale_in_cpu_threshold must be between 0 and 100."
  }
}

variable "scale_out_adjustment" {
  type = number

  validation {
    condition     = var.scale_out_adjustment >= 1
    error_message = "scale_out_adjustment must be at least 1."
  }
}

variable "scale_in_adjustment" {
  type = number

  validation {
    condition     = var.scale_in_adjustment <= -1
    error_message = "scale_in_adjustment must be -1 or lower."
  }
}

variable "health_check_grace_period" {
  type = number

  validation {
    condition     = var.health_check_grace_period >= 0
    error_message = "health_check_grace_period must be zero or greater."
  }
}
