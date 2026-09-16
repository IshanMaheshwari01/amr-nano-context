#!/usr/bin/env bash
#
# Emit the terraform outputs as shell exports.
#
#   source terraform/env.sh
#   nextflow run . -profile awsbatch --outdir "$NXF_RESULTS"
#
# Note: intentionally no `set -e` / `set -u`. This file is meant to be sourced,
# and those options would leak into the caller's interactive shell, where a
# single non-zero exit code would close the terminal.

_nxf_env_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v terraform >/dev/null 2>&1; then
  echo "env.sh: terraform not found on PATH" >&2
elif ! command -v jq >/dev/null 2>&1; then
  echo "env.sh: jq not found on PATH" >&2
else
  _nxf_out="$(terraform -chdir="$_nxf_env_dir" output -json 2>/dev/null)"

  if [ -z "$_nxf_out" ] || [ "$_nxf_out" = "{}" ]; then
    echo "env.sh: no terraform outputs. Has the stack been applied?" >&2
  else
    export AWS_REGION="$(echo "$_nxf_out"        | jq -r '.aws_region.value')"
    export NXF_WORK="$(echo "$_nxf_out"          | jq -r '.work_dir.value')"
    export NXF_RESULTS="$(echo "$_nxf_out"       | jq -r '.results_dir.value')"
    export NXF_BATCH_QUEUE="$(echo "$_nxf_out"   | jq -r '.job_queue_name.value')"
    export NXF_BATCH_JOB_ROLE="$(echo "$_nxf_out"| jq -r '.job_role_arn.value')"
    export NXF_AWS_CLI_PATH="$(echo "$_nxf_out"  | jq -r '.aws_cli_path.value')"

    echo "Environment configured for ${AWS_REGION}"
    echo "  work dir : ${NXF_WORK}"
    echo "  results  : ${NXF_RESULTS}"
    echo "  queue    : ${NXF_BATCH_QUEUE}"
  fi
  unset _nxf_out
fi

unset _nxf_env_dir
