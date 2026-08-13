terraform {
  required_version = ">= 1.10"
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
  backend "s3" {
    bucket       = "s3-bucket-devopsjourney"
    key          = "day4/staging/platform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true # native S3 locking, TF >= 1.10
  }
}
provider "aws" {
  region = "eu-north-1"
}

provider "cloudflare" {
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
  create_ssh_key     = true
  firewall_name      = var.firewall_name
  ssh_key_public     = var.ssh_key_public
  vpc_id             = module.network.vpc_id
  subnet_id          = module.network.public_subnet_ids[0]
}

module "network" {
  source   = "../../modules/network"
  vpc_name = var.vpc_name
  vpc_cidr = var.vpc_cidr
}