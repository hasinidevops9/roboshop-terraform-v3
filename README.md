# RoboShop Terraform v3

Terraform project for the RoboShop lab in AWS. MySQL stays one EC2 instance. Frontend and catalogue run in their own Auto Scaling Groups, launched from their own launch templates and registered with the existing application load balancers.

The project uses the default VPC, `for_each`, and a local backend. It does not create extra microservices.

## Architecture

| Component | Compute | Port | Health check | DNS |
| --- | --- | --- | --- | --- |
| frontend | Auto Scaling Group | 80 | `GET /health` expects HTTP 200 | `frontend.hdevops09.online` CNAME to the public ALB |
| catalogue | Auto Scaling Group | 8002 | `GET /health` expects HTTP 200 | `catalogue.hdevops09.online` CNAME to the internal ALB |
| mysql | Standalone EC2 | 3306 | none | `mysql.hdevops09.online` A record to the private IP |

```text
browser
  -> frontend ALB :80
       -> frontend instance :80
            -> catalogue ALB :8002
                 -> catalogue instance :8002
                      -> mysql.hdevops09.online:3306
```

Both groups start at min 1, desired 1, max 5. Those three numbers are set separately on `frontend` and `catalogue` in `env-dev/ec2.auto.tfvars`.

MySQL is provisioned with Ansible Pull over SSH. Frontend and catalogue install themselves from EC2 user data when the group launches an instance. The groups wait until the MySQL provisioner has finished, so catalogue schema load runs against a database that is already up.

## Launch templates

| Template | Instance | User data |
| --- | --- | --- |
| `roboshop-dev-frontend` | `t3.small`, practice AMI, public IP | Nginx, Node.js 20, frontend static build |
| `roboshop-dev-catalogue` | `t3.small`, practice AMI, public IP | Go catalogue service, MySQL client, schema load |

`update_default_version` is on. The Auto Scaling Group uses `latest_version`. A user-data change creates a new template version. Instances already running keep their current copy until a later scale event replaces them.

Security groups are unchanged. SSH and MySQL remain open to `0.0.0.0/0`. Application ports accept traffic only from that component's load balancer security group. User data still needs a public IP because the default subnets have no NAT gateway; package downloads and the artifact fetch go out through the internet gateway.

The groups use every default subnet, sorted so the plan stays stable. The load balancers already use those subnets. MySQL stays on the first sorted default subnet.

## Scaling

Each application group has two step-scaling policies and two CloudWatch alarms. The alarms use `AWS/EC2` `CPUUtilization` with dimension `AutoScalingGroupName`, average over two 60-second periods.

| Alarm | Condition | Step |
| --- | --- | --- |
| scale out | CPU greater than 50% | add 1 instance |
| scale in | CPU less than 20% | remove 1 instance |

The step bounds are `metric_interval_lower_bound = 0` for scale out and `metric_interval_upper_bound = 0` for scale in, so one step covers the whole breach. New instances have a 300 second warmup before they count toward the next step. Missing metric data does not breach. Capacity cannot pass the min or max for that group.

Thresholds and the +1 / -1 adjustments are variables in `env-dev/ec2.auto.tfvars`. A later `terraform apply` sets desired capacity back to the value in that file, including after a scaling event.

The group health check type is `ELB`. The grace period is 1200 seconds, long enough for the Node build and the Go build. Terraform waits the same amount of time for the instances to become healthy.

## User data

`userdata/frontend.sh.tpl` follows `roboshop-ansible` `roles/frontend`:

- install and start Nginx
- install Node.js 20 from NodeSource
- download `frontend.zip` from `raghudevopsb90/roboshop-microservices`
- `npm install` and `npm run build`
- publish `/tmp/frontend/out` to `/usr/share/nginx/html`
- write the practice Nginx config, including the catalogue proxy to `catalogue.hdevops09.online:8002`
- `nginx -t` and restart Nginx

`userdata/catalogue.sh.tpl` follows `roles/catalogue`, `roles/common/tasks/golang.yml`, `mysql-schema.yml`, and `systemd.yml`:

- system user `appuser`, home `/app`
- install `golang`, `git`, and `mysql8.4`
- download `catalogue.zip`, `go mod tidy`, and `CGO_ENABLED=0 go build -o /app/catalogue .`
- wait for `mysql.hdevops09.online`
- load `schema.sql` only when the `catalogue` database is missing
- load `app-user.sql` only when `catalogue@%` is missing
- load `master-data.sql` on every boot (`INSERT IGNORE`)
- install `/etc/systemd/system/catalogue.service` with the same environment as the Ansible template: `MYSQL_HOST`, user `catalogue`, database `catalogue`, port `8002`
- enable and restart the `catalogue` service

Logs from both scripts go to `/var/log/roboshop-user-data.log`.

## Health checks

Target groups use path `/health`, HTTP, matcher `200`, on the traffic port. Interval 30 seconds, timeout 5 seconds, two successes to become healthy, two failures to become unhealthy.

Frontend did not have this route. `roles/frontend/templates/nginx-practice.conf` is the file the Ansible role installs, and `nginx.conf` is the full virtual-host template. Both now contain:

```nginx
location = /health {
    default_type text/plain;
    access_log off;
    return 200 'OK';
}
```

The launch-template user data writes the same location, so a new frontend instance returns HTTP 200 without another Ansible run.

Catalogue already exposes the route. In the published `catalogue.zip`, `main.go` registers it only after MySQL connects:

```go
r.GET("/health", func(c *gin.Context) {
    c.JSON(http.StatusOK, gin.H{"status": "OK", "service": "catalogue"})
})
```

That response is HTTP 200. The handler does not check the database again. If MySQL is still down after the process starts, the binary retries for about 60 seconds and then exits, so the target stays unhealthy until the service is listening. No catalogue code change was required.

## What stays as it was

- Default VPC and its default subnets. No new network is created.
- Security groups and their rules.
- Both ALBs, their listeners, and listener ports. Frontend is internet-facing on port 80. Catalogue is internal on port 8002.
- Route 53 records in `hdevops09.online`. Application names stay CNAMEs to the load balancers. MySQL stays an A record.
- MySQL instance, Ansible Pull command, root password flow, and `roboshop-pull.yml`.
- No user, cart, shipping, payment, ratings, orders, MongoDB, Redis, or RabbitMQ resources.

The frontend practice Nginx config still proxies only `/api/catalogue/`. The other API paths in `nginx.conf` are not installed by the role and are not added here.

## File structure

| File | Purpose |
| --- | --- |
| `provider.tf` | AWS provider, region `us-east-1` |
| `versions.tf` | Terraform and provider constraints. No backend block |
| `variables.tf` | Input variables, including per-app ASG capacity and CPU thresholds |
| `locals.tf` | Subnet IDs, common tags, database and application views, scaling-policy map |
| `vpc.tf` | Data sources for the default VPC and its default subnets |
| `security-groups.tf` | One security group per component, plus one per load balancer |
| `ec2.tf` | MySQL EC2 instance |
| `alb.tf` | Application load balancers, target groups, listeners |
| `route53.tf` | Private-IP A record for MySQL and CNAME records for the load balancers |
| `launch-template.tf` | Frontend and catalogue launch templates |
| `autoscaling.tf` | Auto Scaling Groups, step policies, CloudWatch alarms |
| `userdata/*.sh.tpl` | Frontend and catalogue user data |
| `ansible.tf` | Ansible Pull for MySQL only |
| `outputs.tf` | MySQL addresses, DNS names, load balancers, templates, groups, alarms |
| `env-dev/ec2.auto.tfvars` | AMI, instance type, ports, ASG sizes, CPU thresholds |
| `env-dev/route53.auto.tfvars` | Hosted zone ID, domain, TTL |

Application ports and ASG sizes live in `env-dev/ec2.auto.tfvars` only. `locals.tf` does not declare a second frontend or catalogue. It keeps the shared subnet IDs and `Environment` tag, and it selects the database tier from `var.components`.

## Commands

Run these from the project root. `.auto.tfvars` files in `env-dev/` are not loaded automatically.

```bash
terraform init
terraform fmt
terraform validate
terraform plan -var-file="env-dev/ec2.auto.tfvars" -var-file="env-dev/route53.auto.tfvars"
```

Apply and destroy use the same `-var-file` arguments. This directory has no remote backend. State is `terraform.tfstate`, and that file is gitignored.

`Makefile` is the class file. `make init` expects `env-dev/state.tfvars`, and `make plan` expects `env-dev/main.tfvars`. Those files are not part of this project. Use the `terraform` commands above.
