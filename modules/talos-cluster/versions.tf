terraform {
  required_version = ">= 1.10"

  required_providers {
    # libvirt provisions the Talos VMs (volumes + domains). Pinned at the
    # patch level per ADR-0002, consistent with modules/libvirt-vm. The
    # 0.9.x migration is evaluated separately (ADR-0009, ADR-0012) and would
    # move this module and libvirt-vm together.
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
