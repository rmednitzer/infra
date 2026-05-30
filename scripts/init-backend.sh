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

# Guard: warn (do not block) if production still carries the placeholder
# local backend. Initializing local state in production silently forfeits
# the remote, locked, encrypted backend that ADR-0003 requires.
if [[ "${ENVIRONMENT}" == "production" ]] &&
  grep -Eq '^\s*backend\s+"local"' "${ENV_DIR}/backend.tf" 2>/dev/null; then
  echo "WARNING: environments/production/backend.tf still declares the" >&2
  echo "         placeholder 'backend \"local\"'. Production state must use a" >&2
  echo "         remote, locked, encrypted backend before any resources are" >&2
  echo "         created. See docs/adr/0003-state-backend-strategy.md." >&2
  echo "" >&2
fi

cd "${ENV_DIR}"
tofu init

echo ""
echo "Backend initialized. Run 'tofu plan' to preview changes."
