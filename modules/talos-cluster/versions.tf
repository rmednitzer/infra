terraform {
  # 1.11 floor: the talos_machine_configuration_apply / talos_machine_bootstrap
  # write-only (_wo) secret arguments need OpenTofu's write-only attribute
  # support, introduced in 1.11 (ADR-0017).
  required_version = ">= 1.11"

  required_providers {
    # libvirt provisions the Talos VMs (volumes + domains). Pinned at the
    # patch level per ADR-0002, consistent with modules/libvirt-vm. Moved to
    # 0.9.x together with libvirt-vm per the migration recorded in ADR-0016
    # (supersedes the ADR-0009/0012 evaluation trail).
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.0"
    }

    # siderolabs/talos generates the machine secrets and configuration,
    # applies it over the Talos API, bootstraps etcd, and exports the
    # kubeconfig/talosconfig. Pre-1.0 provider, so pinned at the patch level
    # per ADR-0002's reasoning (ADR-0014). 0.11.0 is the current stable
    # release on the Terraform registry as of 2026-05.
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.11.0"
    }
  }
}
