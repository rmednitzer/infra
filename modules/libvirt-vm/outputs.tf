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
