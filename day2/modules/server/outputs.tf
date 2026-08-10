output "server_ip" {
  value = hcloud_floating_ip.web.ip_address
}

output "server_ipv4" {
  value = hcloud_server.web.ipv4_address
}

output "server_id" {
  value = hcloud_server.web.id
}

output "fqdn" {
  value = cloudflare_record.server_dns.hostname
}

output "ssh_key_id" {
  value = hcloud_ssh_key.web.id
}