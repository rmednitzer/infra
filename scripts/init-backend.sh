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

cd "${ENV_DIR}"
tofu init

echo ""
echo "Backend initialized. Run 'tofu plan' to preview changes."
