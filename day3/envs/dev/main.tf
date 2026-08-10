terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }

  }
}
provider "aws" {
  region = "eu-north-1"
}

data "aws_ssm_parameter" "cloudflare_api_token" {
  name            = "/day3/dev/cloudflare_api_token"
  with_decryption = true
}

data "aws_ssm_parameter" "cloudflare_zone_id" {
  name            = "/day3/dev/cloudflare_zone_id"
  with_decryption = true
}

provider "cloudflare" {
  api_token = data.aws_ssm_parameter.cloudflare_api_token.value
}

module "web_server" {
  source             = "../../modules/server"
  server_name        = var.server_name
  server_type        = var.server_type
  server_image       = var.server_image
  server_location    = var.server_location
  my_ip              = var.my_ip
  cloudflare_zone_id = data.aws_ssm_parameter.cloudflare_zone_id.value
  dns_record_name    = var.dns_record_name
  ssh_key_name       = var.ssh_key_name
  create_ssh_key     = true
  firewall_name      = var.firewall_name
  ssh_key_public     = var.ssh_key_public
}