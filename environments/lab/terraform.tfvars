# Lab environment variable defaults.
# Non-secret values only — do not add credentials to this file.
# Set ssh_public_key via: export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"

libvirt_uri  = "qemu:///system"
network_name = "default"

# Ubuntu 24.04 LTS (noble) cloud image
# Download from: https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
base_image = "/var/lib/libvirt/images/noble-server-cloudimg-amd64.img"

# Ubuntu 26.04 LTS (resolute, kernel 7.0) cloud image — uncomment to use instead.
# The shipped cloud_init.cfg (netplan/cloud-init) is unchanged across 24.04 and 26.04.
# Download from: https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img
# base_image = "/var/lib/libvirt/images/resolute-server-cloudimg-amd64.img"
