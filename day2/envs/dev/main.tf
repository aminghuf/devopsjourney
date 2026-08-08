terraform {
  required_version = ">= 1.5.0"
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

provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

module "web_server" {
  source             = "../../modules/server"
  server_name        = var.server_name
  server_type        = var.server_type
  server_image       = var.server_image
  server_location    = var.server_location
  my_ip              = var.my_ip
  cloudflare_zone_id = var.cloudflare_zone_id
  dns_record_name    = var.dns_record_name
  ssh_key_name       = var.ssh_key_name
  firewall_name      = var.firewall_name
  ssh_key_public     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPgVm8z/o6wJqDa951vcCIjVO/3qykgHHEAWM+IL4nez amin.gha98@gmail.com"
}