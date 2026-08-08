module "web_server" {
  source = "../../modules/server"
  cloudflare_api_token = var.cloudflare_api_token
  hcloud_token = var.hcloud_token
  server_name = var.server_name
  server_type = var.server_type
  server_image = var.server_image
  server_location = var.server_location
  my_ip = var.my_ip
  cloudflare_zone_id = var.cloudflare_zone_id
  dns_record_name = var.dns_record_name
  ssh_key_name = var.ssh_key_name
  create_ssh_key = var.create_ssh_key
  firewall_name = var.firewall_name
}