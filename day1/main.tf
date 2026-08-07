terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.45.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }

  }
}
variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API Token with DNS edit permissions"
  sensitive   = true
}

variable "cloudflare_zone_id" {
  type        = string
  description = "The DNS Zone ID of your domain in Cloudflare"
}
variable "hcloud_token" {
  sensitive = true
}
provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
variable "my_ip" {
  description = "The IP address of the client to allow SSH access from."
  type        = string
}

resource "hcloud_ssh_key" "default" {
  name       = "my-ssh-key"
  public_key = file(pathexpand("~/.ssh/id_ed25519.pub"))
}
resource "hcloud_server" "web" {
  name         = "web-server-01"
  server_type  = "cx23"
  image        = "ubuntu-24.04"
  location     = "fsn1"
  ssh_keys     = [hcloud_ssh_key.default.id]
  firewall_ids = [hcloud_firewall.web_and_ssh.id]

  # Natively configure persistent network settings on first boot
  user_data = <<-EOT
    #cloud-config
    write_files:
      - path: /etc/netplan/60-floating-ip.yaml
        content: |
          network:
            version: 2
            ethernets:
              eth0:
                addresses:
                  - ${hcloud_floating_ip.web.ip_address}/32
    runcmd:
      - netplan apply
  EOT
}

output "server_ip" {
  value = hcloud_floating_ip.web.ip_address
}

resource "hcloud_firewall" "web_and_ssh" {
  name = "firewall-web-and-ssh"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["${var.my_ip}/32"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

resource "hcloud_floating_ip" "web" {
  type          = "ipv4"
  home_location = "fsn1"
}

resource "cloudflare_record" "server_dns" {
  zone_id = var.cloudflare_zone_id
  name    = "day1"                                  # Creates app.yourdomain.com
  content = hcloud_floating_ip.web.ip_address # Dynamically grabs the Hetzner IP
  type    = "A"
  proxied = false                                   # Set to true for Cloudflare proxy/CDN, false for direct Hetzner IP exposure
}

resource "hcloud_floating_ip_assignment" "main" {
  floating_ip_id = hcloud_floating_ip.web.id
  server_id      = hcloud_server.web.id
}