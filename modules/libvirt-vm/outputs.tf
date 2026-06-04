output "vm_id" {
  description = "Libvirt domain ID of the provisioned VM."
  value       = libvirt_domain.vm.id
}

output "vm_name" {
  description = "Libvirt domain name of the provisioned VM."
  value       = libvirt_domain.vm.name
}

output "ip_address" {
  description = "VM IP address from its first DHCP lease, or null if no lease is available yet. Queried via the libvirt_domain_interface_addresses data source (libvirt 0.9.x removed the 0.8.x network_interface[].addresses surface); the value is null until the guest boots and acquires a lease."
  value       = try(data.libvirt_domain_interface_addresses.vm.interfaces[0].addrs[0].addr, null)
}

output "mac_address" {
  description = "VM MAC address on the first network interface as reported by libvirt, or null if unavailable. libvirt auto-assigns the MAC for this module's VMs, so it is read back from the interface-addresses data source rather than the (unset) config."
  value       = try(data.libvirt_domain_interface_addresses.vm.interfaces[0].hwaddr, null)
}

output "data_disk_ids" {
  description = "Map of additional data-disk name to libvirt volume ID. Empty when no additional_disks are configured. Partitioning, formatting, and mounting these volumes is the configuration-management (Ansible) layer's responsibility, not this module's (ADR-0004)."
  value       = { for name, volume in libvirt_volume.data : name => volume.id }
}

output "cloudinit_disk_id" {
  description = "Libvirt volume ID of the cloud-init NoCloud disk attached to the domain (the pool volume holding the generated ISO, attached as a CD-ROM). In 0.9.x this is the uploaded libvirt_volume, distinct from the libvirt_cloudinit_disk ISO-generator resource."
  value       = libvirt_volume.cloudinit.id
}
