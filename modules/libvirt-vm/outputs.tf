output "vm_id" {
  description = "Libvirt domain ID of the provisioned VM."
  value       = libvirt_domain.vm.id
}

output "vm_name" {
  description = "Libvirt domain name of the provisioned VM."
  value       = libvirt_domain.vm.name
}

output "ip_address" {
  description = "VM IP address assigned via DHCP, or null if no lease is available yet."
  value       = try(libvirt_domain.vm.network_interface[0].addresses[0], null)
}

output "mac_address" {
  description = "VM MAC address on the primary network interface, or null if unavailable."
  value       = try(libvirt_domain.vm.network_interface[0].mac, null)
}

output "data_disk_ids" {
  description = "Map of additional data-disk name to libvirt volume ID. Empty when no additional_disks are configured. Partitioning, formatting, and mounting these volumes is the configuration-management (Ansible) layer's responsibility, not this module's (ADR-0004)."
  value       = { for name, volume in libvirt_volume.data : name => volume.id }
}

output "cloudinit_disk_id" {
  description = "Libvirt volume ID of the cloud-init NoCloud disk attached to the domain."
  value       = libvirt_cloudinit_disk.init.id
}
