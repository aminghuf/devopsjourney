output "server_ip" {
  value = hcloud_floating_ip.web.ip_address
}

output "server_ipv4" {
  value = hcloud_server.web.ipv4_address
}


output "fqdn" {
  value = module.web_server.fqdn
}
