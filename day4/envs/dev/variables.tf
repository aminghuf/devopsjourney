variable "my_ip" {
  description = "The IP address of the client to allow SSH access from."
  type        = string
}

variable "server_name" {
  description = "The name of the server to be created."
  type        = string
}

variable "server_type" {
  description = "The type of the server to be created."
  type        = string
}

variable "server_image" {
  description = "The image of the server to be created."
  type        = string
}

variable "server_location" {
  description = "The location of the server to be created."
  type        = string
}

variable "dns_record_name" {
  description = "The name of the DNS record to be created."
  type        = string
}

variable "ssh_key_name" {
  description = "name of ssh key"
  type        = string
}

variable "firewall_name" {
  description = "name of firewall"
  type        = string
}

variable "ssh_key_public" {
  description = "The public SSH key to be used for the server."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "The DNS Zone ID of your domain in Cloudflare"
  type        = string
}

variable "vpc_name" {
  description = "The name of the VPC to be created."
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR block of the VPC to be created."
  type        = string
}