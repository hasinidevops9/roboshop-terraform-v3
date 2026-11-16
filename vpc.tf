data "aws_vpc" "default" {
  default = true
}

# Default subnets in the default VPC. These already sit on the public route table.
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}
