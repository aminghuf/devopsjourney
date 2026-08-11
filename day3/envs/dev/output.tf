output "server_ip" {
  description = "Public Elastic IP of the web server"
  value       = module.web_server.server_ip
}