# Infrastructure as code

Terraform module that provisions the AWS environment this pipeline runs in:
object storage, a Batch compute environment, a job queue, and the IAM roles
that bind them together. Nothing here is created by hand, and the whole stack
can be destroyed and rebuilt from an empty account in about ten minutes.

The point is not that AWS Batch is the only way to run this pipeline. It is
that the execution environment is now a versioned artefact rather than a set of
console clicks that only exist in one person's account.

## What gets created

| Resource | Purpose |
|---|---|
| VPC, 3 public subnets, internet gateway | Network for compute instances |
| S3 gateway endpoint | Keeps pipeline data off the public path, no charge |
| Security group | Outbound only, no inbound rules |
| S3 bucket | `work/` for the Nextflow work directory, `results/` for outputs |
| S3 lifecycle rules | Expire work directory after 14 days, tier results to IA after 30 |
| Launch template | 200 GB gp3 root volume, host-installed AWS CLI v2, IMDSv2 required |
| Batch compute environment | Managed, Spot, scales 0 to 64 vCPUs |
| Batch job queue | Single queue that Nextflow submits to |
| 4 IAM roles and policies | Batch service, EC2 instance, job container, Nextflow client |

```
              nextflow run -profile awsbatch
                          |
                          v
   +---------------------------------------------+
   |  Nextflow head process (laptop or CI runner) |
   |  identity carries the nextflow_client policy |
   +---------------------------------------------+
              |                          |
      submits jobs                stages files
              |                          |
              v                          v
      +---------------+          +----------------+
      |  Batch queue  |          |   S3 bucket    |
      +-------+-------+          |  work/         |
              |                  |  results/      |
              v                  +--------+-------+
   +----------------------+               ^
   | Compute environment  |               |
   |  Spot, 0-64 vCPUs    |  job role ----+
   |  launch template:    |
   |   200 GB gp3         |
   |   /opt/aws-cli       |
   +----------------------+
```

## Prerequisites

- Terraform 1.6 or later
- AWS credentials with permission to create VPC, S3, IAM, EC2 and Batch resources
- `jq`, used by `env.sh`
- Nextflow 23.10 or later on the machine running the head process

## Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit if needed
terraform init
terraform plan
terraform apply
```

Attach the generated client policy to whichever identity runs Nextflow. The
module creates the policy but does not attach it, because creating an IAM user
with access keys in Terraform would write those keys into state in plaintext.

```bash
aws iam attach-user-policy \
  --user-name YOUR_IAM_USER \
  --policy-arn "$(terraform output -raw nextflow_client_policy_arn)"
```

Then load the outputs into the shell and run:

```bash
cd ..
source terraform/env.sh
nextflow run . -profile awsbatch --outdir "$NXF_RESULTS"
```

`env.sh` reads the Terraform outputs and exports `AWS_REGION`, `NXF_WORK`,
`NXF_RESULTS`, `NXF_BATCH_QUEUE`, `NXF_BATCH_JOB_ROLE` and `NXF_AWS_CLI_PATH`.
`conf/awsbatch.config` reads all of them from the environment, so no account
identifier ever appears in a committed file.

## Verifying it works before spending money

```bash
# 1. Terraform is internally consistent
terraform validate
terraform fmt -check -recursive

# 2. The compute environment reached VALID, not INVALID
aws batch describe-compute-environments \
  --query 'computeEnvironments[].{name:computeEnvironmentName,status:status,reason:statusReason}'

# 3. The pipeline's process graph is sound, without launching an instance
nextflow run . -profile awsbatch -stub-run --outdir "$NXF_RESULTS"

# 4. A single small process really lands on Batch
nextflow run . -profile awsbatch --outdir "$NXF_RESULTS" -entry SMOKE_TEST
```

Step 3 is the one that matters. A stub run exercises the full workflow graph,
channel wiring and file staging logic in seconds without launching a single
instance. Structural faults surface before any compute is billed.

## Cost

The design target was an idle cost of effectively zero.

| Item | Cost when idle | Notes |
|---|---|---|
| Batch compute environment | 0 | `min_vcpus = 0`, no instances exist between runs |
| VPC, subnets, internet gateway | 0 | |
| S3 gateway endpoint | 0 | Gateway endpoints are free, unlike interface endpoints |
| S3 storage | approx 0.023 USD per GB per month | Work directory expires after 14 days |
| CloudWatch logs | negligible | 14 day retention when managed |

The deliberate omission is a NAT gateway. Putting compute in private subnets
behind NAT would cost roughly 32 USD per month before any traffic flows,
several times the expected compute bill for this project. Instances sit in
public subnets with no inbound rules instead. A platform handling patient data
would make the opposite call and pay for the NAT gateway; the trade is recorded
here rather than left implicit.

During a run, cost is Spot instance hours. Spot typically runs 60 to 90 percent
below On-Demand. `max_vcpus` is the hard ceiling and the main guard against a
runaway bill.

## Design decisions

**Provider version pinned to 5.x.** The AWS provider changed the Batch resource
schema in 6.x and again in 7.x, renaming several arguments. This module is
written against the 5.x schema. Upgrading should be a deliberate task with a
plan reviewed, not something that happens silently on a fresh `terraform init`.

**Spot with `SPOT_CAPACITY_OPTIMIZED`.** The cheapest-pool strategy interrupts
more often, which matters for a metaFlye assembly that has been running for six
hours. Capacity-optimised draws from the deepest pools instead, trading a small
amount of price for a large reduction in interruption. The Nextflow profile
retries host-level exit codes rather than blanket-retrying, so a genuine
pipeline bug still fails fast.

**Larger root volume in a launch template.** The stock ECS-optimised AMI ships
30 GB. Long-read assembly intermediates fill it and the job dies with a
misleading out-of-space error from inside the container. 200 GB of gp3 is the
fix, and it belongs in infrastructure code rather than in a runbook.

**AWS CLI installed on the host, not in the containers.** Nextflow stages files
to and from S3 by shelling out to `aws s3`. Most Biocontainers images do not
include the CLI. Installing it once on the instance through launch template
user data and pointing `aws.batch.cliPath` at it makes Nextflow bind-mount the
directory into every container, so no container has to be rebuilt.

**Four IAM roles rather than one.** The scheduler, the EC2 host, the pipeline
container and the human submitting jobs need different permissions. Collapsing
them would give every container the permissions of the scheduler. The container
role can reach exactly one bucket and nothing else.

**`create_before_destroy` on the compute environment.** Most changes to a Batch
compute environment force replacement rather than an in-place update. Combined
with `compute_environment_name_prefix`, this lets a replacement be built before
the old one is torn down. See troubleshooting for the caveat.

**`ignore_changes` on `desired_vcpus`.** Batch adjusts this as it scales.
Without the exclusion, every plan after a run shows drift that is not drift.

## Troubleshooting

**Compute environment status is `INVALID`.** Almost always the instance profile
or service role. Read the `statusReason` field from
`aws batch describe-compute-environments`. IAM propagation can also lag by a
few seconds on first apply, so a second `terraform apply` sometimes clears it.

**`Cannot delete, found existing JobQueue relationship`.** AWS will not delete a
compute environment while a job queue still references it, and the association
is eventually consistent, so `create_before_destroy` can still race. Break it
manually:

```bash
aws batch update-job-queue --job-queue <name> --state DISABLED
# wait for the queue to report UPDATING -> VALID
terraform apply
aws batch update-job-queue --job-queue <name> --state ENABLED
```

**Jobs sit in `RUNNABLE` forever.** The compute environment cannot place them.
Usual causes: a job requesting more vCPUs or memory than any instance type in
`instance_types` provides, `max_vcpus` already saturated, or no Spot capacity in
the selected availability zones. Widen `instance_types` or set
`use_spot = false` temporarily.

**`no space left on device` inside a container.** Raise
`instance_ebs_size_gb` and apply. The launch template updates, and because
`update_default_version` is set, the next instances pick it up.

**`aws: command not found` during file staging.** The launch template user data
did not complete. Connect with Session Manager, which the instance role already
permits, and read `/var/log/cloud-init-output.log`.

**A log group named `/aws/batch/job` already exists.** Leave
`manage_batch_log_group = false`. Batch creates the group itself; Terraform only
needs to manage it if you want a retention policy on it.

## Teardown

```bash
terraform destroy
```

`force_destroy_bucket` defaults to `true`, so the bucket is emptied and deleted
along with everything else. Set it to `false` if you want destroy to refuse
while results are still present.

## Next

The observability stack, Prometheus and Grafana reading the Nextflow trace
output, lives in `observability/` and consumes the trace file that
`conf/awsbatch.config` writes on every run.
