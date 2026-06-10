terraform {
  # >= 1.11: required by modules/talos-cluster's write-only arguments (ADR-0017).
  required_version = ">= 1.11"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.11.0"
    }
  }
}
