# Placeholder local backend so `tofu init -backend=false && tofu validate`
# works in CI. Must not be used to manage real production state — replace
# with the S3-compatible backend (encryption at rest, `use_lockfile = true`)
# before adding any resources. Full rationale and worked configuration:
# docs/adr/0003-state-backend-strategy.md (and the bootstrap walkthrough in
# environments/production/README.md).
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
