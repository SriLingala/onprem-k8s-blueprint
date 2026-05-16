# Example variables for the k3s edge module.
# Copy to `terraform.tfvars` and adjust to your edge site.
#
# Usage:
#   # 1. Capture the server's SSH host key first so the token capture step
#   #    can verify it instead of trusting on first use:
#   ssh-keyscan 10.20.30.40 > ./known_hosts.edge
#
#   # 2. Apply:
#   terraform init
#   terraform apply -var-file=edge.tfvars

server_address       = "10.20.30.40"
agent_addresses      = ["10.20.30.41", "10.20.30.42"]
ssh_user             = "ubuntu"
ssh_private_key_path = "~/.ssh/edge_k3s"
known_hosts_path     = "./known_hosts.edge"
k3s_version          = "v1.30.3+k3s1"

# Toggle off for the very first apply if you want to bring the cluster up
# without add-ons (useful when bandwidth to chart repos is limited at the
# edge and you'd rather mirror first).
install_platform_addons = true

# Skip MetalLB entirely on single-node edge sites by setting this to "".
# On multi-node edge sites, pick a free L2 range.
metallb_address_pool = "10.20.30.200-10.20.30.210"
