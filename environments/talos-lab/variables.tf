variable "libvirt_uri" {
  description = "Libvirt connection URI for the KVM host hosting the Talos lab cluster."
  type        = string
  default     = "qemu:///system"
}

variable "talos_image" {
  description = "Path or URL to the Talos Linux disk image used as the boot disk for every node. Download from the Talos image factory (factory.talos.dev) for the desired version/schematic/architecture."
  type        = string
}

variable "cluster_name" {
  description = "Name of the lab Talos cluster."
  type        = string
  default     = "lab-talos"
}

variable "cluster_endpoint" {
  description = "Kubernetes API endpoint URL for the lab cluster (the single control-plane node's IP)."
  type        = string
  default     = "https://10.5.0.10:6443"
}

variable "talos_version" {
  description = "Talos version contract for machine secrets/config generation. Should match talos_image."
  type        = string
  default     = "v1.10.5"
}

variable "kubernetes_version" {
  description = "Kubernetes version Talos installs (no leading v)."
  type        = string
  default     = "1.32.3"
}

variable "control_plane_nodes" {
  description = "Map of control-plane node name to {ip, mac, vcpus?, memory_mib?, disk_gib?}."
  type = map(object({
    ip         = string
    mac        = string
    vcpus      = optional(number, 2)
    memory_mib = optional(number, 4096)
    disk_gib   = optional(number, 20)
  }))
  default = {
    cp-01 = { ip = "10.5.0.10", mac = "52:54:00:00:00:10" }
  }
}

variable "worker_nodes" {
  description = "Map of worker node name to {ip, mac, vcpus?, memory_mib?, disk_gib?}."
  type = map(object({
    ip         = string
    mac        = string
    vcpus      = optional(number, 2)
    memory_mib = optional(number, 2048)
    disk_gib   = optional(number, 20)
  }))
  default = {
    work-01 = { ip = "10.5.0.20", mac = "52:54:00:00:00:20" }
    work-02 = { ip = "10.5.0.21", mac = "52:54:00:00:00:21" }
  }
}
