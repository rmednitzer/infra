output "kubeconfig" {
  description = "Raw kubeconfig YAML for the bootstrapped cluster. Sensitive: contains the cluster CA and a client certificate/key. Write it to a file out of band (e.g. tofu output -raw kubeconfig > kubeconfig) and keep it out of git."
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "talosconfig" {
  description = "Raw talosconfig YAML for talosctl, targeting the control-plane endpoints. Sensitive: contains the Talos client CA and client certificate/key. Keep it out of git."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "cluster_endpoint" {
  description = "The Kubernetes API endpoint the cluster was configured with (echoes var.cluster_endpoint)."
  value       = var.cluster_endpoint
}

output "control_plane_node_ips" {
  description = "Map of control-plane node name to its static IP address."
  value       = { for name, spec in var.control_plane_nodes : name => spec.ip }
}

output "worker_node_ips" {
  description = "Map of worker node name to its static IP address. Empty for a control-plane-only cluster."
  value       = { for name, spec in var.worker_nodes : name => spec.ip }
}

output "node_ips" {
  description = "Map of every Talos node name (control-plane and worker) to its static IP address."
  value       = { for name, node in local.all_nodes : name => node.ip }
}

output "bootstrap_node_ip" {
  description = "IP address of the control-plane node that was bootstrapped (the first control-plane node by sorted name)."
  value       = local.bootstrap_node_ip
}

output "machine_secrets_id" {
  description = "The computed ID of the Talos cluster's machine secrets. The secrets themselves are not exported (they live in state, which must be an encrypted remote backend per ADR-0015); this ID is a non-sensitive handle for reference."
  value       = talos_machine_secrets.this.id
}
