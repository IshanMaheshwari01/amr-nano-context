# ---------------------------------------------------------------------------
# IAM
#
# Four distinct identities, because they are used by four different things and
# collapsing them would hand every container the permissions of the scheduler:
#
#   batch_service   AWS Batch itself, to manage EC2 capacity on your behalf
#   ecs_instance    the EC2 host, to register with ECS and pull images
#   job             the container the pipeline process runs in, to reach S3
#   nextflow_client a customer-managed policy you attach to your own identity
#
# The client policy is created but deliberately not attached to anything.
# Creating an IAM user with access keys in Terraform writes those keys into
# state in plaintext, so the module stops at producing the policy and leaves
# attaching it to a human decision.
# ---------------------------------------------------------------------------

# --- AWS Batch service role ------------------------------------------------

data "aws_iam_policy_document" "batch_service_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["batch.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "batch_service" {
  name_prefix        = "${local.name_prefix}-batch-svc-"
  description        = "Allows AWS Batch to manage compute capacity"
  assume_role_policy = data.aws_iam_policy_document.batch_service_assume.json
}

resource "aws_iam_role_policy_attachment" "batch_service" {
  role       = aws_iam_role.batch_service.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AWSBatchServiceRole"
}

# --- EC2 container instance role -------------------------------------------

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_instance" {
  name_prefix        = "${local.name_prefix}-ecs-inst-"
  description        = "Role assumed by Batch EC2 container instances"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Session Manager access, so a stuck instance can be inspected without opening
# SSH or attaching a key pair. Costs nothing and removes the temptation to add
# an ingress rule during a bad debugging session.
resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name_prefix = "${local.name_prefix}-ecs-inst-"
  role        = aws_iam_role.ecs_instance.name

  lifecycle {
    create_before_destroy = true
  }
}

# --- Job (container) role ---------------------------------------------------

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "job_s3" {
  statement {
    sid    = "ListPipelineBucket"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [aws_s3_bucket.pipeline.arn]
  }

  statement {
    sid    = "ReadWritePipelineObjects"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]

    resources = ["${aws_s3_bucket.pipeline.arn}/*"]
  }
}

resource "aws_iam_role" "job" {
  name_prefix        = "${local.name_prefix}-job-"
  description        = "Role assumed by pipeline containers running on Batch"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "job_s3" {
  name_prefix = "s3-access-"
  role        = aws_iam_role.job.id
  policy      = data.aws_iam_policy_document.job_s3.json
}

# --- Nextflow client policy -------------------------------------------------

data "aws_iam_policy_document" "nextflow_client" {
  statement {
    sid    = "SubmitAndMonitorBatchJobs"
    effect = "Allow"

    actions = [
      "batch:DescribeJobQueues",
      "batch:DescribeComputeEnvironments",
      "batch:DescribeJobDefinitions",
      "batch:DescribeJobs",
      "batch:ListJobs",
      "batch:RegisterJobDefinition",
      "batch:SubmitJob",
      "batch:TerminateJob",
      "batch:CancelJob",
      "batch:TagResource",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "InspectRunningTasks"
    effect = "Allow"

    actions = [
      "ecs:DescribeTasks",
      "ecs:DescribeContainerInstances",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceAttribute",
      "ec2:DescribeInstanceStatus",
    ]

    resources = ["*"]
  }

  statement {
    sid    = "ReadJobLogs"
    effect = "Allow"

    actions = [
      "logs:DescribeLogStreams",
      "logs:GetLogEvents",
      "logs:FilterLogEvents",
    ]

    resources = ["arn:${local.partition}:logs:${var.aws_region}:${local.account_id}:log-group:/aws/batch/job:*"]
  }

  statement {
    sid    = "PipelineBucketAccess"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]

    resources = [
      aws_s3_bucket.pipeline.arn,
      "${aws_s3_bucket.pipeline.arn}/*",
    ]
  }

  # Nextflow registers job definitions that reference the job role, which
  # requires PassRole. Scoped to that one role rather than left as a wildcard,
  # because a broad PassRole is a privilege escalation path.
  statement {
    sid       = "PassJobRoleToBatch"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.job.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "nextflow_client" {
  name_prefix = "${local.name_prefix}-nextflow-client-"
  description = "Attach to the identity that runs the Nextflow head process"
  policy      = data.aws_iam_policy_document.nextflow_client.json
}
