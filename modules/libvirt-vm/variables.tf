variable "vm_name" {
  description = "VM hostname. Used as the libvirt domain name and cloud-init hostname."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.vm_name))
    error_message = "vm_name must be a valid RFC 1123 hostname label: lowercase alphanumerics and hyphens, 1-63 characters, no leading or trailing hyphen."
  }
}

variable "vcpus" {
  description = "Number of virtual CPUs to allocate to the VM."
  type        = number
  default     = 2

  validation {
    condition     = var.vcpus >= 1 && floor(var.vcpus) == var.vcpus
    error_message = "vcpus must be a whole number greater than or equal to 1."
  }
}

variable "memory_mib" {
  description = "Memory allocated to the VM in MiB."
  type        = number
  default     = 2048

  validation {
    condition     = var.memory_mib >= 512 && floor(var.memory_mib) == var.memory_mib
    error_message = "memory_mib must be a whole number of at least 512 MiB."
  }
}

variable "disk_size_gib" {
  description = "Root disk size in GiB. Must be greater than or equal to the virtual size of base_image."
  type        = number
  default     = 20

  validation {
    condition     = var.disk_size_gib >= 1 && floor(var.disk_size_gib) == var.disk_size_gib
    error_message = "disk_size_gib must be a whole number of at least 1 GiB."
  }
}

variable "base_image" {
  description = "Path or URL to a cloud-init compatible base image. Version-neutral: any cloud image that ships cloud-init and netplan works, including Ubuntu 24.04 LTS (noble, cloud-images.ubuntu.com/noble/) and Ubuntu 26.04 LTS (resolute, kernel 7.0, cloud-images.ubuntu.com/resolute/). The shipped cloud_init.cfg is distro-neutral across both."
  type        = string

  validation {
    condition     = length(trimspace(var.base_image)) > 0
    error_message = "base_image must not be empty."
  }
}

variable "network_name" {
  description = "Libvirt network name to attach the VM to."
  type        = string
  default     = "default"
}

variable "storage_pool" {
  description = "Libvirt storage pool in which to create the VM volumes and cloud-init disk."
  type        = string
  default     = "default"

  validation {
    condition     = length(trimspace(var.storage_pool)) > 0
    error_message = "storage_pool must not be empty."
  }
}

variable "ssh_public_key" {
  description = "SSH public key injected via cloud-init for the default user."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\\.com|sk-ecdsa-sha2-nistp256@openssh\\.com) +[A-Za-z0-9+/]+=*( .*)?$", trimspace(var.ssh_public_key)))
    error_message = "ssh_public_key must be a complete OpenSSH public key: a supported key type (ssh-rsa, ssh-ed25519, ecdsa-sha2-nistp256/384/521, sk-ssh-ed25519@openssh.com, sk-ecdsa-sha2-nistp256@openssh.com) followed by base64 key material."
  }
}

variable "additional_disks" {
  description = "Optional list of additional data disks to attach to the VM."
  type = list(object({
    name     = string
    size_gib = number
  }))
  default = []

  validation {
    condition     = length(var.additional_disks) == length(distinct([for disk in var.additional_disks : disk.name]))
    error_message = "additional_disks names must be unique."
  }

  validation {
    condition     = alltrue([for disk in var.additional_disks : disk.size_gib >= 1])
    error_message = "Each additional disk size_gib must be at least 1 GiB."
  }
}

variable "autostart" {
  description = "Whether the VM should start automatically when the libvirt host boots."
  type        = bool
  default     = true
}

variable "graphics" {
  description = "Optional graphics device for the domain. Defaults to null, which omits the graphics device entirely (no SPICE/VNC listener) per ADR-0008; set it only for VMs that genuinely need graphical console access. listen_address binds the listener (e.g. \"127.0.0.1\" to keep it host-local); leave it null for the libvirt default. autoport lets libvirt pick the port. (libvirt 0.9.x models graphics per protocol, so listen_type from 0.8.x is gone.)"
  type = object({
    type           = string
    listen_address = optional(string)
    autoport       = optional(bool)
  })
  default = null

  validation {
    condition     = var.graphics == null || contains(["spice", "vnc"], try(var.graphics.type, ""))
    error_message = "graphics.type must be either \"spice\" or \"vnc\"."
  }
}
