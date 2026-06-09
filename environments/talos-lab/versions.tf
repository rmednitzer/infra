terraform {
  # 1.11 floor: modules/talos-cluster uses write-only (_wo) secret arguments,
  # which need OpenTofu's write-only attribute support from 1.11 (ADR-0017).
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
