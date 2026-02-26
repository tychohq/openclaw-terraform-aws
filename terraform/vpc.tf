# VPC - Created or Existing
#
# When existing_vpc_id is set, we use the provided VPC/subnet.
# Otherwise, we create a minimal VPC with a single public subnet.

locals {
  use_existing_vpc = var.existing_vpc_id != ""
  vpc_id           = local.use_existing_vpc ? var.existing_vpc_id : aws_vpc.main[0].id
  subnet_id        = local.use_existing_vpc ? var.existing_subnet_id : aws_subnet.public[0].id
}

# ── New VPC (when no existing VPC provided) ───────────────────────────────────

data "aws_ec2_instance_type_offerings" "instance_azs" {
  count         = local.use_existing_vpc ? 0 : 1
  location_type = "availability-zone"

  filter {
    name   = "instance-type"
    values = [var.instance_type]
  }
}

locals {
  instance_az = local.use_existing_vpc ? null : (
    length(data.aws_ec2_instance_type_offerings.instance_azs[0].locations) > 0
    ? data.aws_ec2_instance_type_offerings.instance_azs[0].locations[0]
    : null
  )
}

resource "aws_vpc" "main" {
  count                = local.use_existing_vpc ? 0 : 1
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.deployment_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  count  = local.use_existing_vpc ? 0 : 1
  vpc_id = aws_vpc.main[0].id

  tags = {
    Name = "${var.deployment_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = local.use_existing_vpc ? 0 : 1
  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = local.instance_az

  tags = {
    Name = "${var.deployment_name}-public"
  }
}

resource "aws_route_table" "public" {
  count  = local.use_existing_vpc ? 0 : 1
  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = {
    Name = "${var.deployment_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = local.use_existing_vpc ? 0 : 1
  subnet_id      = aws_subnet.public[0].id
  route_table_id = aws_route_table.public[0].id
}

# Restrict default security group (only for new VPCs)
resource "aws_default_security_group" "default" {
  count  = local.use_existing_vpc ? 0 : 1
  vpc_id = aws_vpc.main[0].id

  tags = {
    Name = "${var.deployment_name}-default-sg-restricted"
  }
}
