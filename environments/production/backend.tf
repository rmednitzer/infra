# Production state backend.
# Remote backend configuration is required for production. See ADR-0003
# (docs/adr/0003-state-backend-strategy.md) for the full rationale.
#
# Example using an S3-compatible backend (AWS S3, MinIO, Ceph RGW, etc.)
# with OpenTofu 1.10+ native S3 state locking:
#
# terraform {
#   backend "s3" {
#     bucket = "infra-ops-tfstate"
#     key    = "production/terraform.tfstate"
#     region = "us-east-1"
#
#     # For non-AWS S3 implementations, set the endpoints map
#     # (the top-level `endpoint = "..."` attribute is deprecated):
#     # endpoints = {
#     #   s3 = "https://s3.example.com"
#     # }
#     # use_path_style              = true   # replaces deprecated force_path_style
#     # skip_credentials_validation = true
#     # skip_metadata_api_check     = true
#     # skip_region_validation      = true
#
#     # Native S3 state locking via conditional writes (OpenTofu 1.10+).
#     # Preferred over `dynamodb_table = "..."`, which remains supported
#     # for backward compatibility but is no longer the recommended path.
#     use_lockfile = true
#
#     # Server-side encryption at rest is mandatory for production state.
#     # The bucket must additionally enforce SSE via bucket policy / default
#     # encryption, and versioning should be enabled for recovery.
#     encrypt = true
#   }
# }

# Placeholder: configure the backend above before deploying production
# infrastructure. The placeholder local backend exists only so that
# `tofu init -backend=false && tofu validate` works in CI; it must not be
# used to manage real production state.
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
