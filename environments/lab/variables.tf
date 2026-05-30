variable "libvirt_uri" {
  description = "Libvirt connection URI for the KVM host."
  type        = string
  default     = "qemu:///system"
}

variable "base_image" {
  description = "Path or URL to the Ubuntu cloud image used as the base for all VMs. Version-neutral: Ubuntu 24.04 LTS (noble, cloud-images.ubuntu.com/noble/) or 26.04 LTS (resolute, kernel 7.0, cloud-images.ubuntu.com/resolute/)."
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key injected into all VMs via cloud-init."
  type        = string
  sensitive   = true
}

variable "network_name" {
  description = "Libvirt network name to attach VMs to."
  type        = string
  default     = "default"
}
