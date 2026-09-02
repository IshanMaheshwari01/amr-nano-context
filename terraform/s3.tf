# ---------------------------------------------------------------------------
# Object storage
#
# One bucket, two prefixes:
#   work/     Nextflow work directory. Disposable, expires automatically.
#   results/  Published outputs. Kept.
#
# Keeping both in one bucket means one set of permissions and one endpoint in
# the Nextflow config. The lifecycle rule is what makes it safe to do that.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "pipeline" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy_bucket

  tags = {
    Name = "${local.name_prefix}-pipeline-data"
  }
}

resource "aws_s3_bucket_public_access_block" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Versioning is deliberately left disabled. A Nextflow work directory rewrites
# the same object paths on every resumed run, so versioning would multiply
# storage for files that are already reproducible from the pipeline itself.
resource "aws_s3_bucket_versioning" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id

  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id

  depends_on = [aws_s3_bucket_versioning.pipeline]

  rule {
    id     = "expire-nextflow-work-dir"
    status = "Enabled"

    filter {
      prefix = "work/"
    }

    expiration {
      days = var.work_dir_expiry_days
    }
  }

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Published results move to Infrequent Access after a month. Nothing is
  # deleted; this only lowers the per-gigabyte rate on data that is being
  # kept for reference rather than actively read.
  rule {
    id     = "transition-results-to-ia"
    status = "Enabled"

    filter {
      prefix = "results/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
  }
}

# Reject any request that arrives over plain HTTP.
data "aws_iam_policy_document" "bucket_tls_only" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.pipeline.arn,
      "${aws_s3_bucket.pipeline.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "pipeline" {
  bucket = aws_s3_bucket.pipeline.id
  policy = data.aws_iam_policy_document.bucket_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.pipeline]
}
