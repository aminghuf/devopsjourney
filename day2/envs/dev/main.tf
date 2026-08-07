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