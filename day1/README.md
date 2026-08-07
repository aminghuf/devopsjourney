1. Prereqs: Terraform installed, an ed25519 keypair at `~/.ssh/id_ed25519(.pub)`, a Hetzner API token, a Cloudflare API token scoped to **Zone → DNS → Edit** on the target zone, and that zone's ID.
2. Fill in `terraform.tfvars` (gitignored, never commit it):
   ```
   hcloud_token         = "..."
   my_ip                = "<your public IP>"
   cloudflare_api_token = "..."
   cloudflare_zone_id   = "..."
   ```
3. `terraform init`
4. `terraform plan` — review before applying.
5. `terraform apply` — provisions SSH key, server, firewall, floating IP + assignment, and the DNS record; cloud-init binds the floating IP on first boot automatically.
6. `terraform output server_ip` — the address to hit (also what the DNS record points to).
7. `terraform destroy` — tears everything back down to zero.