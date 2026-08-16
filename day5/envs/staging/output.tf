output "server_ip" {
  description = "Public Elastic IP of the web server"
  value       = module.web_server.server_ip
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.network.vpc_id
}
output "public_subnet_ids" {
  description = "Public Subnet IDs"
  value       = module.network.public_subnet_ids[0]
}