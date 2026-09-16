output "aws_region" {
  description = "Region the stack was deployed into."
  value       = var.aws_region
}

output "bucket_name" {
  description = "S3 bucket holding the Nextflow work directory and published results."
  value       = aws_s3_bucket.pipeline.id
}

output "work_dir" {
  description = "Value to pass to nextflow run -work-dir."
  value       = "s3://${aws_s3_bucket.pipeline.id}/work"
}

output "results_dir" {
  description = "Suggested publishDir target for pipeline outputs."
  value       = "s3://${aws_s3_bucket.pipeline.id}/results"
}

output "job_queue_name" {
  description = "Batch job queue name, used as process.queue in the Nextflow config."
  value       = aws_batch_job_queue.main.name
}

output "job_queue_arn" {
  description = "ARN of the Batch job queue."
  value       = aws_batch_job_queue.main.arn
}

output "compute_environment_arn" {
  description = "ARN of the Batch compute environment."
  value       = aws_batch_compute_environment.main.arn
}

output "job_role_arn" {
  description = "IAM role assumed by pipeline containers. Set as aws.batch.jobRole in the Nextflow config."
  value       = aws_iam_role.job.arn
}

output "nextflow_client_policy_arn" {
  description = "Attach this policy to the IAM user or role that runs the Nextflow head process."
  value       = aws_iam_policy.nextflow_client.arn
}

output "aws_cli_path" {
  description = "Host path to the AWS CLI installed by the launch template. Set as aws.batch.cliPath."
  value       = "${local.aws_cli_root}/bin/aws"
}

output "vpc_id" {
  description = "VPC containing the compute environment."
  value       = aws_vpc.main.id
}

# Everything needed to run the pipeline, printed as a single block so there is
# no transcription step between terraform apply and the first submitted job.
output "nextflow_profile_values" {
  description = "Values to paste into conf/awsbatch.config."
  value       = <<-EOT

    Add to conf/awsbatch.config, or export as environment variables:

      AWS_REGION           = ${var.aws_region}
      NXF_WORK             = s3://${aws_s3_bucket.pipeline.id}/work
      NXF_BATCH_QUEUE      = ${aws_batch_job_queue.main.name}
      NXF_BATCH_JOB_ROLE   = ${aws_iam_role.job.arn}
      NXF_AWS_CLI_PATH     = ${local.aws_cli_root}/bin/aws

    Run with:

      nextflow run . -profile awsbatch \
        -work-dir s3://${aws_s3_bucket.pipeline.id}/work \
        --outdir s3://${aws_s3_bucket.pipeline.id}/results

    Attach the client policy to your own identity first:

      aws iam attach-user-policy \
        --user-name YOUR_IAM_USER \
        --policy-arn ${aws_iam_policy.nextflow_client.arn}

  EOT
}
