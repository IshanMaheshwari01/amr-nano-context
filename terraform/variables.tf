variable "aws_region" {
  description = "AWS region for all resources. eu-west-1 keeps data in the EU and is the cheapest European region for Spot compute."
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Short name used as a prefix on every resource. Lowercase alphanumeric and hyphens only."
  type        = string
  default     = "amr-nano-context"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,24}$", var.project_name))
    error_message = "project_name must be 3 to 24 characters of lowercase letters, digits or hyphens."
  }
}

variable "environment" {
  description = "Environment suffix, for example dev or prod."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.environment))
    error_message = "environment must be 2 to 10 lowercase alphanumeric characters."
  }
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.30.0.0/16"
}

variable "availability_zone_count" {
  description = "Number of availability zones to spread compute across. Two or three gives Spot a wider capacity pool to draw from."
  type        = number
  default     = 3

  validation {
    condition     = var.availability_zone_count >= 1 && var.availability_zone_count <= 4
    error_message = "availability_zone_count must be between 1 and 4."
  }
}

# ---------------------------------------------------------------------------
# Batch compute
# ---------------------------------------------------------------------------

variable "use_spot" {
  description = "Run the compute environment on Spot instances. Spot is roughly 60 to 90 percent cheaper and is the right default for restartable batch work. Set false if a long non-resumable job keeps getting interrupted."
  type        = bool
  default     = true
}

variable "spot_bid_percentage" {
  description = "Maximum Spot price as a percentage of the On-Demand price. 100 means never pay more than On-Demand, which is the sensible ceiling."
  type        = number
  default     = 100
}

variable "max_vcpus" {
  description = "Ceiling on total vCPUs the compute environment may scale to. This is the main guard against a runaway bill."
  type        = number
  default     = 64
}

variable "instance_types" {
  description = "Instance families Batch may choose from. Assembly steps such as metaFlye are memory-hungry, so r-family instances are included. 'optimal' would also work but gives Batch less to pick from on Spot."
  type        = list(string)
  default     = ["m5", "m5a", "r5", "r5a", "c5"]
}

variable "instance_ebs_size_gb" {
  description = "Root volume size for each compute instance. Long-read assembly intermediates are large, and the default ECS AMI volume is too small for them."
  type        = number
  default     = 200
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

variable "work_dir_expiry_days" {
  description = "Days after which objects under work/ are deleted. Nextflow work directories are disposable once results are published, and leaving them in place is the most common way a pipeline bucket quietly grows expensive."
  type        = number
  default     = 14
}

variable "force_destroy_bucket" {
  description = "Allow terraform destroy to delete a bucket that still has objects in it. True is convenient for a portfolio stack and dangerous anywhere real."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Optional extras
# ---------------------------------------------------------------------------

variable "manage_batch_log_group" {
  description = "Create and manage the /aws/batch/job CloudWatch log group. Leave false if the account already has one, because AWS Batch creates it automatically and Terraform will fail on the name collision."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days, used only when manage_batch_log_group is true."
  type        = number
  default     = 14
}
