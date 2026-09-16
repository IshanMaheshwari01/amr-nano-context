# ---------------------------------------------------------------------------
# Networking
#
# Design note: compute instances sit in public subnets with public IPs rather
# than in private subnets behind a NAT gateway. A NAT gateway costs about 32
# USD per month before a single byte flows through it, which would dwarf the
# actual compute cost of this stack. The instances need outbound access only,
# to pull containers and reach S3, and the security group blocks all inbound
# traffic, so the exposure is acceptable here. A production platform handling
# patient data would make the opposite trade and pay for the NAT gateway.
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  count = var.availability_zone_count

  vpc_id                  = aws_vpc.main.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${local.azs[count.index]}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = var.availability_zone_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# S3 traffic goes over a gateway endpoint rather than the internet gateway.
# The endpoint is free, and it removes S3 transfer from the data path that
# would otherwise be billed and routed publicly. For a pipeline that moves
# tens of gigabytes per run this is the single cheapest optimisation available.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id]

  tags = {
    Name = "${local.name_prefix}-s3-endpoint"
  }
}

resource "aws_security_group" "batch" {
  name_prefix = "${local.name_prefix}-batch-"
  description = "AWS Batch compute instances. Outbound only, no inbound."
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-batch-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Egress is written as a separate rule rather than inline so that changing it
# does not force replacement of the security group, which would in turn force
# replacement of the compute environment.
resource "aws_vpc_security_group_egress_rule" "batch_all" {
  security_group_id = aws_security_group.batch.id
  description       = "Allow all outbound: container registries, S3, AWS APIs"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
