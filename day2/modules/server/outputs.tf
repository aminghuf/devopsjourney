output "server_ip" {
  value = hcloud_floating_ip.web.ip_address
}