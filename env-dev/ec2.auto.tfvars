env           = "dev"
ami_id        = "ami-0eec78ea4cbaaf5bd"
instance_type = "t3.small"

# Average CPU over two 60-second periods. Each step changes capacity by one instance.
scale_out_cpu_threshold   = 50
scale_in_cpu_threshold    = 20
scale_out_adjustment      = 1
scale_in_adjustment       = -1
health_check_grace_period = 1200

components = {
  frontend = {
    tier        = "app"
    lb_internal = false
    health_path = "/health"
    asg_min     = 1
    asg_desired = 1
    asg_max     = 5
    ports = {
      ssh  = 22
      http = 80
    }
  }
  catalogue = {
    tier        = "app"
    lb_internal = true
    health_path = "/health"
    asg_min     = 1
    asg_desired = 1
    asg_max     = 5
    ports = {
      ssh = 22
      app = 8002
    }
  }
  mysql = {
    tier = "db"
    ports = {
      ssh   = 22
      mysql = 3306
    }
  }
}
