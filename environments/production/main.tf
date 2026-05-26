# Production placeholder: no resources yet. See environments/lab/main.tf for
# example module usage and environments/production/README.md for the backend
# setup prerequisite.

provider "libvirt" {
  uri = var.libvirt_uri
}
