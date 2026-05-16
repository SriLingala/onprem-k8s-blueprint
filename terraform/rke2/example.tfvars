# Example variables for the RKE2 module.
# Copy to `terraform.tfvars` and adjust to your environment.
#
# Usage:
#   terraform init
#   terraform apply -var-file=example.tfvars

cluster_name         = "dc1-rke2"
kubernetes_version   = "v1.30.3+rke2r1"
ssh_user             = "rancher"
ssh_private_key_path = "~/.ssh/onprem_rke2"

# Capture host keys before applying so token and kubeconfig pulls are not
# trust-on-first-use:
#   for ip in 10.10.10.11 10.10.10.12 10.10.10.13 10.10.10.21 10.10.10.22; \
#     do ssh-keyscan "$ip"; done > ./known_hosts.dc1
known_hosts_path = "./known_hosts.dc1"

control_plane_nodes = [
  "10.10.10.11", # first entry is the cluster-init node
  "10.10.10.12",
  "10.10.10.13",
]

worker_nodes = [
  "10.10.10.21",
  "10.10.10.22",
]

# Required on bare metal — without an L2 pool, ingress-nginx never gets
# an external IP and Services of type LoadBalancer hang in <pending>.
# Pick a range outside your DHCP scope but inside the same L2 broadcast
# domain as the worker nodes.
metallb_address_pool = "10.10.10.200-10.10.10.220"
