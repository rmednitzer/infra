config {
  call_module_type = "all"
}

# Pin the terraform ruleset explicitly rather than relying on the version
# bundled with the tflint binary, so lint results do not silently shift when
# the tflint binary is upgraded. `tflint --init` downloads the pinned
# release. 0.14.1 matches the version bundled with tflint 0.62.1, so this is
# a pin, not a behaviour change.
#
# Note: there is no official libvirt TFLint ruleset, so provider-specific
# issues in dmacvicar/libvirt resources are lint-blind; rely on
# `tofu validate`, Trivy, and the module's tofu test suite for those.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
  source  = "github.com/terraform-linters/tflint-ruleset-terraform"
  version = "0.14.1"
}
