# Lab backend: local state, acceptable for single-operator iteration
# (ADR-0003). Talos lab clusters are reproducible from this configuration;
# losing the state destroys and re-creates a few VMs.
#
# NOTE: the talos-lab state contains talos_machine_secrets (the cluster CA +
# bootstrap token). The state file and the rendered kubeconfig/talosconfig
# are gitignored (see .gitignore). A PRODUCTION Talos environment must use
# the encrypted remote backend instead (ADR-0011, ADR-0015) -- never a local
# backend for production secrets.
terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}
