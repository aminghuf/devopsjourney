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

resource "hcloud_ssh_key" "default" {
  count      = var.create_ssh_key ? 1 : 0
  name       = var.ssh_key_name
  public_key = var.ssh_key_public
}

data "hcloud_ssh_key" "existing" {
  count = var.create_ssh_key ? 0 : 1
  name  = var.ssh_key_name
}

locals {
  ssh_key_id = var.create_ssh_key ? hcloud_ssh_key.default[0].id : data.hcloud_ssh_key.existing[0].id
}

resource "hcloud_server" "web" {
  name         = var.server_name
  server_type  = var.server_type
  image        = var.server_image
  location     = var.server_location
  ssh_keys     = [local.ssh_key_id]
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

resource "hcloud_firewall" "web_and_ssh" {
  name = var.firewall_name

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
  home_location = var.server_location
}

resource "cloudflare_record" "server_dns" {
  zone_id = var.cloudflare_zone_id
  name    = var.dns_record_name
  content = hcloud_floating_ip.web.ip_address # Dynamically grabs the Hetzner IP
  type    = "A"
  proxied = false
}

resource "hcloud_floating_ip_assignment" "main" {
  floating_ip_id = hcloud_floating_ip.web.id
  server_id      = hcloud_server.web.id
}