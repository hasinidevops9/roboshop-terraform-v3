locals {
  # sort() keeps subnet order stable between plans.
  # MySQL stays on the first default subnet. Application ASGs use every default subnet,
  # the same set the load balancers already use.
  subnet_ids = sort(data.aws_subnets.default.ids)
  subnet_id  = local.subnet_ids[0]

  common_tags = {
    Environment = var.env
  }

  db_components = {
    for name, component in var.components : name => component if component.tier == "db"
  }

  # Application settings stay in var.components. This map only selects the app
  # tier and derives the single non-SSH port for the listener and target group.
  app_components = {
    for name, component in var.components : name => merge(component, {
      app_port = one([
        for port_name, port in component.ports : port if port_name != "ssh"
      ])
    }) if component.tier == "app"
  }

  # One scale-out and one scale-in step for every application ASG.
  scaling_policies = {
    scale_out = {
      comparison_operator = "GreaterThanThreshold"
      threshold           = var.scale_out_cpu_threshold
      adjustment          = var.scale_out_adjustment
      bound               = "lower"
    }
    scale_in = {
      comparison_operator = "LessThanThreshold"
      threshold           = var.scale_in_cpu_threshold
      adjustment          = var.scale_in_adjustment
      bound               = "upper"
    }
  }

  app_scaling_policies = merge([
    for name, component in local.app_components : {
      for policy_name, policy in local.scaling_policies :
      "${name}-${policy_name}" => merge(policy, {
        component   = name
        policy_name = policy_name
      })
    }
  ]...)

  cpu_alarm_period             = 60
  cpu_alarm_evaluation_periods = 2
  scaling_warmup_seconds       = 300
}
