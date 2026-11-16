# RoboShop Terraform v1

Terraform project for a small RoboShop lab in AWS. It creates three EC2 instances in the default VPC, private DNS records in an existing public hosted zone, and configures each instance with Ansible Pull.

This follows the class layout: separate Terraform files, `for_each`, locals, a dynamic security-group block, and `null_resource` with `remote-exec`. It does not use Terraform modules or a remote backend.

## Architecture

Three instances only. The existing workstation is not managed by this project.

| Component | Role | Port | DNS |
| --- | --- | --- | --- |
| frontend | Nginx | 80 | `frontend.hdevops09.online` |
| catalogue | Golang catalogue service | 8002 | `catalogue.hdevops09.online` |
| mysql | MySQL database | 3306 | `mysql.hdevops09.online` |

```text
browser
  -> frontend.hdevops09.online:80
       -> catalogue.hdevops09.online:8002
            -> mysql.hdevops09.online:3306
```

Each A record points at the instance private IP. The instances still receive public IPs so Terraform can SSH in and run Ansible Pull.

## AWS configuration

| Setting | Value |
| --- | --- |
| Region | `us-east-1` |
| AMI | `ami-0eec78ea4cbaaf5bd` |
| Instance type | `t3.small` |
| Environment | `dev` |
| Network | Existing default VPC and one of its default subnets |
| Public IP | Associated on each instance |
| Credentials | The AWS CLI profile or environment already configured on this machine |

No new VPC, subnet, S3 bucket, or DynamoDB table is created.

## File structure

| File | Purpose |
| --- | --- |
| `provider.tf` | AWS provider, region `us-east-1` |
| `versions.tf` | Terraform and provider version constraints. No backend block |
| `variables.tf` | Input variables |
| `locals.tf` | Subnet choice, and the split between database and application components |
| `vpc.tf` | Data sources for the default VPC and its default subnets |
| `security-groups.tf` | One security group per component, built with `for_each` and a dynamic ingress block |
| `ec2.tf` | The three EC2 instances |
| `route53.tf` | The three private-IP A records |
| `ansible.tf` | Ansible Pull over `remote-exec` |
| `outputs.tf` | Instance IDs, IPs, DNS names, VPC ID, environment |
| `env-dev/ec2.auto.tfvars` | Environment, AMI, instance type, component map |
| `env-dev/route53.auto.tfvars` | Hosted zone ID, domain, TTL |
| `Makefile` | Unchanged class Makefile. See the limitation below |

## Local backend

There is no `backend` block and no `state.tf`. Terraform stores state in `terraform.tfstate` in this directory. That file is gitignored. Do not configure an S3 backend for this project.

## Route 53

Hosted zone ID: `Z02185673PPMYAJHNLF1`

Domain: `hdevops09.online`

| Record | Value |
| --- | --- |
| `frontend.hdevops09.online` | frontend private IP |
| `catalogue.hdevops09.online` | catalogue private IP |
| `mysql.hdevops09.online` | mysql private IP |

TTL is 30. The names do not include `-dev`.

These names match the Ansible repository:

- `roles/catalogue/templates/catalogue.service` uses `mysql.hdevops09.online`
- `roles/common/tasks/mysql-schema.yml` uses `mysql.hdevops09.online`
- `roles/frontend/vars/main.yml` sets `catalogue_host` to `catalogue.hdevops09.online`
- `run.sh` connects to `<component>.hdevops09.online`

## Ansible Pull

After the instances and DNS records exist, Terraform SSHes to each public IP as `ec2-user` and runs:

```bash
sudo dnf install ansible git -y
ansible-pull -U https://github.com/hasinidevops9/roboshop-ansible.git roboshop.yml -e component_name=<component>
```

`roboshop.yml` applies the role named by `component_name`. The role names in the repository are `frontend`, `catalogue`, and `mysql`.

`null_resource.db` runs first and configures MySQL. `null_resource.app` depends on it, then configures catalogue and frontend. Catalogue needs the database because `roles/common/tasks/mysql-schema.yml` loads SQL through `mysql.hdevops09.online`.

Triggers are the instance ID, private IP, and DNS name. Replacing an instance or changing its address runs the provisioner again.

## Commands

Run these from the project root.

`.auto.tfvars` files are loaded automatically only when they are in the working directory. Files under `env-dev/` are not loaded. Pass both files on every plan, apply, and destroy.

Initialize:

```bash
terraform init
```

Plan:

```bash
terraform plan -var-file="env-dev/ec2.auto.tfvars" -var-file="env-dev/route53.auto.tfvars"
```

Apply:

```bash
terraform apply -var-file="env-dev/ec2.auto.tfvars" -var-file="env-dev/route53.auto.tfvars"
```

Destroy:

```bash
terraform destroy -var-file="env-dev/ec2.auto.tfvars" -var-file="env-dev/route53.auto.tfvars"
```

## Makefile limitation

`Makefile` is the original class file and is intentionally unchanged. Its targets are not the commands for this project.

- `make init` runs `terraform init -backend-config=env-$(env)/state.tfvars`. `env-dev/state.tfvars` does not exist. This project has no S3 backend, so that flag does not apply.
- `make plan` calls `init`, then `terraform plan -var-file=env-$(env)/main.tfvars`. `env-dev/main.tfvars` does not exist, so this target cannot succeed.
- `make apply` and `make destroy` also call `init`, so they stop on the missing `state.tfvars` as well.
- `init` deletes `*.auto.tfvars` in the project root and copies `env-$(env)/*.auto.tfvars` there. The working commands above do not use that copy. They pass the files in `env-dev/` directly.

Use the `terraform` commands in the previous section.

## Dependencies and limitations

Configured here:

- Catalogue depends on MySQL at `mysql.hdevops09.online`. Terraform provisions MySQL before catalogue.
- Frontend proxies catalogue through `catalogue.hdevops09.online:8002`.

Present in Ansible, not created by this Terraform project:

- `roles/frontend/templates/nginx.conf` also proxies to `user.hdevops09.online:8001`, `cart.hdevops09.online:8003`, `shipping.hdevops09.online:8004`, `payment.hdevops09.online:8005`, `ratings.hdevops09.online:8006`, and `orders.hdevops09.online:8007`.
- Those hostnames and services are outside this three-instance lab. Nginx will still start. Those API paths fail until those servers exist. This project does not create them.

The three Ansible roles used here do not install MongoDB, Redis, Valkey, or RabbitMQ.

Other lab limits:

- Security groups follow the class dynamic-block example and allow the listed ports from `0.0.0.0/0`, including SSH and MySQL. That is suitable for this practice account, not for a locked-down environment.
- SSH uses the practice AMI password `DevOps321` for `ec2-user`. The Ansible README documents the same login.
- All three instances go into one default subnet, chosen with `sort()` so the plan stays stable.
- Ansible Pull needs the instance to reach the internet (package install and the Git clone) and needs passwordless sudo for `ec2-user`, which the practice AMI provides.
- The hosted zone ID is the value supplied for this account. It is not looked up with a data source.
