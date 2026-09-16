terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Pinned deliberately. The Batch resource schema changed in provider 6.x
      # and again in 7.x (several arguments renamed). Everything in this module
      # is written and tested against the 5.x schema, so the major version is
      # held. Upgrading is a deliberate task, not something that should happen
      # silently on a fresh `terraform init`.
      version = "~> 5.80"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote state is commented out on purpose. A single-operator portfolio stack
  # does not need it, and bootstrapping the state bucket is a chicken-and-egg
  # problem. If more than one person ever runs this, create a bucket with
  # versioning enabled and uncomment the block below.
  #
  # backend "s3" {
  #   bucket       = "REPLACE-with-your-state-bucket"
  #   key          = "amr-nano-context/terraform.tfstate"
  #   region       = "eu-west-1"
  #   encrypt      = true
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "terraform"
      Repository  = "github.com/IshanMaheshwari01/amr-nano-context"
      Environment = var.environment
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition

  # S3 bucket names are globally unique, so a short random suffix avoids
  # collisions without needing the account id in the name.
  bucket_name = "${local.name_prefix}-${random_id.suffix.hex}"

  azs = slice(data.aws_availability_zones.available.names, 0, var.availability_zone_count)
}
