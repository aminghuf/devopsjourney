variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API Token with DNS edit permissions"
  sensitive   = true
}

variable "cloudflare_zone_id" {
  type        = string
  description = "The DNS Zone ID of your domain in Cloudflare"
}
variable "hcloud_token" {
  sensitive = true
}

variable "my_ip" {
  description = "The IP address of the client to allow SSH access from."
  type        = string
}