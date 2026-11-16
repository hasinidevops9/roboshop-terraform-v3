locals {
  # Instances stay on one default subnet. sort() keeps the choice stable between plans.
  # Load balancers use every default subnet, because an ALB needs two Availability Zones.
  subnet_id = sort(data.aws_subnets.default.ids)[0]

  db_components = {
    for name, component in var.components : name => component if component.tier == "db"
  }

  # The application port is the one port that is not SSH.
  app_components = {
    for name, component in var.components : name => merge(component, {
      app_port = one([
        for port_name, port in component.ports : port if port_name != "ssh"
      ])
    }) if component.tier == "app"
  }

  # frontend-1, catalogue-1, and further indexes when instance_count is raised.
  app_instances = merge([
    for name, component in local.app_components : {
      for index in range(component.instance_count) :
      "${name}-${index + 1}" => {
        component_name = name
      }
    }
  ]...)
}
