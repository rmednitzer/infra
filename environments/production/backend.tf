# Production remote state backend (ADR-0003).
#
# S3-compatible backend with OpenTofu 1.10+ native locking (use_lockfile),
# encryption at rest, and the endpoints = { s3 = "…" } map. Every value here
# is NON-SECRET configuration (bucket, key, region, endpoint); credentials are
# injected out of band via the AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
# environment variables in CI and on operator/prod hosts — never committed.
#
# CI keeps using `tofu init -backend=false`, so this block is parsed and
# validated but the backend is not contacted (no network/creds needed for
# `tofu validate -backend=false`). A real `tofu init` against this backend
# requires the bucket to exist and AWS_* to be set; see the README.
#
#   - use_lockfile = true   native S3 conditional-write locking (OpenTofu
#                           1.10+); NOT dynamodb_table (ADR-0003, CLAUDE.md).
#   - endpoints  = { s3 } 	the map form; NOT the deprecated top-level
#                           `endpoint = "…"` attribute (ADR-0003).
#   - encrypt    = true     server-side encryption at rest; the bucket must
#                           additionally enforce SSE via bucket policy.
#   - use_path_style        path-style URLs for non-AWS S3 implementations
#                           (MinIO, Ceph RGW, Hetzner Object Storage); the
#                           legacy `force_path_style` is deprecated.
#
# The bucket/key/region/endpoint below are placeholders for the org's real
# state store. Replace them with the provisioned values (the bucket must have
# versioning + default encryption + public-access-block per the README) and
# then run `../../scripts/init-backend.sh production`.
terraform {
  backend "s3" {
    bucket = "rmednitzer-infra-tfstate-prod"
    key    = "production/terraform.tfstate"
    region = "us-east-1"

    endpoints = {
      s3 = "https://s3.us-east-1.amazonaws.com"
    }

    encrypt        = true
    use_lockfile   = true
    use_path_style = true
  }
}
