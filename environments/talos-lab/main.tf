provider "libvirt" {
  uri = var.libvirt_uri
}

# The talos provider needs no static configuration; it derives connection
# parameters from the resources/data sources in the module (client
# configuration produced by talos_machine_secrets).
provider "talos" {}

module "talos" {
  source = "../../modules/talos-cluster"

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  talos_image        = var.talos_image
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  control_plane_nodes = var.control_plane_nodes
  worker_nodes        = var.worker_nodes
}
