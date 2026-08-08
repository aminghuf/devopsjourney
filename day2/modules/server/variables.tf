variable "cloudflare_zone_id" {
  type        = string
  description = "The DNS Zone ID of your domain in Cloudflare"
}

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
  description = "Name of the SSH key: created in Hetzner Cloud when create_ssh_key is true, or looked up by this name when create_ssh_key is false."
  type = string
}

variable "create_ssh_key" {
  description = "Whether to create a new SSH key in Hetzner Cloud (true) or reuse an existing one by name via a data source (false)."
  type        = bool
  default     = true
}

variable "firewall_name" {
  description = "name of firewall"
  type = string
}

variable "ssh_key_public" {
  description = "The public SSH key to register when create_ssh_key is true. Unused when reusing an existing key."
  type        = string
  default     = ""
}