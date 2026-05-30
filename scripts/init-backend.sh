#!/usr/bin/env bash
# init-backend.sh — Initialize the OpenTofu backend for an environment.
#
# Usage:
#   ./scripts/init-backend.sh <environment>
#
# Examples:
#   ./scripts/init-backend.sh lab
#   ./scripts/init-backend.sh production
#
# For remote backends, ensure the following environment variables are set
# before running this script:
#   AWS_ACCESS_KEY_ID       - S3-compatible backend access key
#   AWS_SECRET_ACCESS_KEY   - S3-compatible backend secret key
#   TF_VAR_ssh_public_key   - SSH public key for VM provisioning

set -euo pipefail

if ! command -v tofu >/dev/null 2>&1; then
  echo "Error: 'tofu' not found in PATH. Install OpenTofu: https://opentofu.org/docs/intro/install/" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${SCRIPT_DIR}")"

usage() {
  echo "Usage: $0 <environment>"
  echo ""
  echo "Available environments:"
  for dir in "${REPO_ROOT}/environments"/*/; do
    echo "  $(basename "${dir}")"
  done
  exit 1
}

if [[ $# -ne 1 ]]; then
  usage
fi

ENVIRONMENT="${1}"
ENV_DIR="${REPO_ROOT}/environments/${ENVIRONMENT}"

if [[ ! -d "${ENV_DIR}" ]]; then
  echo "Error: environment '${ENVIRONMENT}' not found at ${ENV_DIR}" >&2
  exit 1
fi

echo "Initializing OpenTofu backend for environment: ${ENVIRONMENT}"
echo "Directory: ${ENV_DIR}"
echo ""

# Guard 1: production must carry the remote S3 backend, not a local
# placeholder. Initializing local state in production silently forfeits the
# remote, locked, encrypted backend that ADR-0003 requires. The placeholder
# was replaced with the real `backend "s3"` (ADR-0011); this guard catches a
# regression where someone re-introduces a local backend.
if [[ "${ENVIRONMENT}" == "production" ]] &&
  grep -Eq '^\s*backend\s+"local"' "${ENV_DIR}/backend.tf" 2>/dev/null; then
  echo "WARNING: environments/production/backend.tf declares a 'backend" >&2
  echo "         \"local\"'. Production state must use the remote, locked," >&2
  echo "         encrypted S3 backend before any resources are created." >&2
  echo "         See docs/adr/0003-state-backend-strategy.md." >&2
  echo "" >&2
fi

# Guard 2: the production S3 backend authenticates via AWS_* environment
# variables (or an instance role). Initializing it without credentials fails
# at the backend step with an opaque AWS error; warn early with the fix.
if [[ "${ENVIRONMENT}" == "production" ]] &&
  grep -Eq '^\s*backend\s+"s3"' "${ENV_DIR}/backend.tf" 2>/dev/null &&
  [[ -z "${AWS_ACCESS_KEY_ID:-}" && -z "${AWS_PROFILE:-}" ]]; then
  echo "WARNING: production uses the S3 state backend but neither" >&2
  echo "         AWS_ACCESS_KEY_ID nor AWS_PROFILE is set. 'tofu init' will" >&2
  echo "         fail with 'No valid credential sources found' unless an EC2/" >&2
  echo "         instance role is available. Export credentials first:" >&2
  echo "           export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=..." >&2
  echo "" >&2
fi

cd "${ENV_DIR}"
tofu init

echo ""
echo "Backend initialized. Run 'tofu plan' to preview changes."
