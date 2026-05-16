/**
 * k3s edge cluster Terraform skeleton.
 *
 * Provisions a k3s cluster on lightweight Linux hosts. Designed for
 * trackside, factory floor or other edge environments where a full RKE2
 * control plane is too heavy.
 */

terraform {
  required_version = ">= 1.6"
}

variable "server_address" {
  description = "k3s server (control plane) host address."
  type        = string
}

variable "agent_addresses" {
  description = "List of k3s agent host addresses."
  type        = list(string)
  default     = []
}

variable "ssh_user" {
  description = "SSH user for node access."
  type        = string
  default     = "ubuntu"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key."
  type        = string
}

# ---- Install k3s on the server --------------------------------------------

resource "null_resource" "k3s_server" {
  triggers = { address = var.server_address }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = var.server_address
      user        = var.ssh_user
      private_key = file(var.ssh_private_key_path)
    }
    inline = [
      "curl -sfL https://get.k3s.io | sh -s - server --cluster-init --disable=traefik",
      "sudo cat /var/lib/rancher/k3s/server/node-token | sudo tee /tmp/node-token",
    ]
  }
}

# ---- Capture the join token -----------------------------------------------

data "external" "node_token" {
  depends_on = [null_resource.k3s_server]
  program    = ["bash", "-c", "ssh -i ${var.ssh_private_key_path} -o StrictHostKeyChecking=no ${var.ssh_user}@${var.server_address} 'sudo cat /tmp/node-token' | jq -Rn '{token: input}'"]
}

# ---- Install k3s agents ---------------------------------------------------

resource "null_resource" "k3s_agents" {
  for_each = toset(var.agent_addresses)
  triggers = { address = each.key }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = each.key
      user        = var.ssh_user
      private_key = file(var.ssh_private_key_path)
    }
    inline = [
      "curl -sfL https://get.k3s.io | K3S_URL=https://${var.server_address}:6443 K3S_TOKEN=${data.external.node_token.result.token} sh -",
    ]
  }

  depends_on = [data.external.node_token]
}

output "server_address" {
  value = var.server_address
}

output "agent_count" {
  value = length(var.agent_addresses)
}
