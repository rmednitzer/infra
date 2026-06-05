config {
  call_module_type = "all"
}

# Pin the terraform ruleset explicitly rather than relying on the version
# bundled with the tflint binary, so lint results do not silently shift when
# the tflint binary is upgraded. `tflint --init` downloads the pinned
# release. 0.14.1 matches the version bundled with tflint 0.62.1, so this is
# a pin, not a behaviour change.
#
# Note: there is no official TFLint ruleset for dmacvicar/libvirt OR for
# siderolabs/talos, so provider-specific issues in those resources are
# lint-blind; rely on `tofu validate`, Trivy, and each module's tofu test
# suite for those. The terraform ruleset below still lints both modules for
# core issues (unused declarations, naming, typing, documentation).
plugin "terraform" {
  enabled = true
  preset  = "recommended"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
  version = "0.15.0"
}
