output "kubeconfig" {
  description = "Raw kubeconfig YAML for the lab Talos cluster. Sensitive: write it out of band (tofu output -raw kubeconfig > kubeconfig) and keep it out of git."
  value       = module.talos.kubeconfig
  sensitive   = true
}

output "talosconfig" {
  description = "Raw talosconfig YAML for talosctl against the lab cluster. Sensitive: keep it out of git."
  value       = module.talos.talosconfig
  sensitive   = true
}

output "node_ips" {
  description = "Map of every Talos node name to its static IP address."
  value       = module.talos.node_ips
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint of the lab cluster."
  value       = module.talos.cluster_endpoint
}
