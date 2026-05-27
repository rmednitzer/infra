variable "libvirt_uri" {
  description = "Libvirt connection URI for the production KVM host. See https://libvirt.org/uri.html for full syntax."
  type        = string

  validation {
    condition     = can(regex("^qemu(\\+[a-z0-9]+)?:///?[^?#]*/(system|session)([?#].*)?$", var.libvirt_uri))
    error_message = "libvirt_uri must be a QEMU URI of the form qemu[+transport]://[user@host[:port]]/system or /session. Examples: qemu:///system, qemu+ssh://user@host/system, qemu+tls://host:16514/system."
  }
}
