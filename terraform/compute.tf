# ---------------------------------------------------------------------------
# Compute
#
# The launch template solves two problems that bite every Nextflow-on-Batch
# setup and are not obvious from the AWS documentation:
#
#   1. Disk. The stock ECS-optimised AMI ships a 30 GB root volume. A long-read
#      metagenomic assembly will fill that and the job will die with a confusing
#      "no space left on device" from inside the container.
#
#   2. The AWS CLI. Nextflow stages files in and out of S3 by shelling out to
#      `aws s3`. Most Biocontainers images do not include it. Rather than
#      rebuilding every container, the CLI is installed on the host and Nextflow
#      is pointed at it via aws.batch.cliPath, which makes Nextflow bind-mount
#      the install directory into each container automatically.
# ---------------------------------------------------------------------------

locals {
  # Installed under a single parent directory so that the bind mount Nextflow
  # derives from cliPath covers both the binaries and the runtime they link to.
  aws_cli_root = "/opt/aws-cli"

  launch_template_user_data = <<-EOT
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="==BATCH-BOUNDARY=="

    --==BATCH-BOUNDARY==
    Content-Type: text/x-shellscript; charset="us-ascii"

    #!/bin/bash
    # Deliberately no `set -e`: a silent failure here yields an instance that
    # accepts jobs but cannot stage files, surfacing as a confusing exit 127
    # inside the container rather than as a launch failure.
    #
    # Ordering matters more than it looks. The ECS agent starts early in boot
    # and registers the instance as available as soon as it is up, so Batch
    # will place jobs on a host whose user data is still running. Those jobs
    # die at exit 127 because the CLI does not exist yet. Stopping the agent
    # first and starting it only after the install completes makes readiness
    # mean what Batch assumes it means.
    #
    # The AWS CLI comes from conda rather than the official v2 installer: the
    # v2 binary links against host system libraries, and Nextflow bind-mounts
    # only the install directory into each container. Minimal Biocontainers
    # images have no libz, so a mounted v2 binary fails at the dynamic linker.
    # A conda prefix is self-contained.

    echo "=== nextflow bootstrap starting $(date -Is) ==="

    systemctl stop ecs 2>/dev/null || echo "ecs service not yet running"

    if [ -x "${local.aws_cli_root}/bin/aws" ]; then
      echo "AWS CLI already present"
    else
      curl --fail --silent --show-error --location --retry 5 \
        "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" \
        -o /tmp/miniconda.sh

      bash /tmp/miniconda.sh -b -f -p "${local.aws_cli_root}"
      rm -f /tmp/miniconda.sh

      "${local.aws_cli_root}/bin/conda" install -y -q -c conda-forge awscli
      "${local.aws_cli_root}/bin/conda" clean -afy
    fi

    if "${local.aws_cli_root}/bin/aws" --version; then
      echo "=== nextflow bootstrap OK $(date -Is) ==="
      touch /var/log/nextflow-bootstrap-ok
    else
      echo "=== nextflow bootstrap FAILED: staging will not work ==="
    fi

    # Only now is the host genuinely ready to accept work.
    systemctl start ecs

    --==BATCH-BOUNDARY==--
  EOT
}

resource "aws_launch_template" "batch" {
  name_prefix = "${local.name_prefix}-batch-"
  description = "Batch container instances: larger root volume plus host AWS CLI"

  update_default_version = true

  user_data = base64encode(local.launch_template_user_data)

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.instance_ebs_size_gb
      volume_type           = "gp3"
      throughput            = 250
      iops                  = 3000
      encrypted             = true
      delete_on_termination = true
    }
  }

  # IMDSv2 required. The hop limit of 2 is necessary so that processes inside
  # a container, which is one network hop further out, can still reach the
  # instance metadata service to pick up credentials.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${local.name_prefix}-batch-instance"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_batch_compute_environment" "main" {
  # name_prefix rather than a fixed name, paired with create_before_destroy.
  # Most changes to a compute environment force replacement, and AWS will not
  # delete a compute environment while a job queue still references it. See the
  # troubleshooting section of the README if a replacement ever gets stuck.
  compute_environment_name_prefix = "${local.name_prefix}-ce-"

  type         = "MANAGED"
  state        = "ENABLED"
  service_role = aws_iam_role.batch_service.arn

  compute_resources {
    type = var.use_spot ? "SPOT" : "EC2"

    # SPOT_CAPACITY_OPTIMIZED draws from the deepest Spot pools rather than the
    # cheapest, which materially reduces interruption rate for long assembly
    # steps. It also removes the need for an explicit Spot fleet role.
    allocation_strategy = var.use_spot ? "SPOT_CAPACITY_OPTIMIZED" : "BEST_FIT_PROGRESSIVE"
    bid_percentage      = var.use_spot ? var.spot_bid_percentage : null

    # min_vcpus of zero is what makes this stack cost nothing when idle.
    # Instances are launched on job submission and terminated when the queue
    # drains.
    min_vcpus     = 0
    desired_vcpus = 0
    max_vcpus     = var.max_vcpus

    instance_type      = var.instance_types
    instance_role      = aws_iam_instance_profile.ecs_instance.arn
    subnets            = aws_subnet.public[*].id
    security_group_ids = [aws_security_group.batch.id]

    # Pinned to an explicit version, not "$Latest". AWS Batch resolves the
    # launch template version once when the compute environment is created and
    # caches it, so updating the template afterwards has no effect on an
    # existing environment: instances keep booting the version that was current
    # at creation time, while the console reports "$Latest" and the template
    # default sits several versions ahead. Referencing latest_version makes any
    # template change force a compute environment replacement, which is the
    # only thing that actually propagates it.
    launch_template {
      launch_template_id = aws_launch_template.batch.id
      version            = aws_launch_template.batch.latest_version
    }

    tags = {
      Name = "${local.name_prefix}-batch-compute"
    }
  }

  depends_on = [aws_iam_role_policy_attachment.batch_service]

  lifecycle {
    create_before_destroy = true

    # Batch adjusts desired_vcpus as it scales. Without this, every plan after
    # a run would show spurious drift.
    ignore_changes = [compute_resources[0].desired_vcpus]
  }
}

resource "aws_batch_job_queue" "main" {
  name     = "${local.name_prefix}-queue"
  state    = "ENABLED"
  priority = 1

  compute_environment_order {
    order               = 1
    compute_environment = aws_batch_compute_environment.main.arn
  }
}

resource "aws_cloudwatch_log_group" "batch" {
  count = var.manage_batch_log_group ? 1 : 0

  name              = "/aws/batch/job"
  retention_in_days = var.log_retention_days
}
