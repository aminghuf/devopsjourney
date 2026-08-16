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
  description = "The AWS EC2 instance type (e.g. t3.micro)."
  type        = string
}

variable "server_image" {
  description = "The Ubuntu release version to look up an AMI for (e.g. 24.04)."
  type        = string
}

variable "dns_record_name" {
  description = "The name of the DNS record to be created."
  type        = string
}

variable "ssh_key_name" {
  description = "Name of the SSH key pair: created in AWS when create_ssh_key is true, or looked up by this name when create_ssh_key is false."
  type        = string
}

variable "create_ssh_key" {
  description = "Whether to create a new EC2 key pair in AWS (true) or reuse an existing one by name via a data source (false)."
  type        = bool
  default     = true
}

variable "firewall_name" {
  description = "name of security group"
  type        = string
}

variable "ssh_key_public" {
  description = "The public SSH key to register when create_ssh_key is true. Unused when reusing an existing key."
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "The ID of the VPC to launch the instance in."
  type        = string
}

variable "subnet_id" {
  description = "The ID of the subnet to launch the instance in."
  type        = string
}