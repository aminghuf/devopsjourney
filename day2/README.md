Two environments, one module: `modules/server` holds the shared infra (SSH key, server, firewall, floating IP, Cloudflare DNS record); `envs/dev` and `envs/staging` are thin roots that call it with different sizing.

1. Prereqs: Terraform >= 1.5.0, an ed25519 keypair, a Hetzner API token, a Cloudflare API token scoped to **Zone → DNS → Edit** on the target zone, and that zone's ID.
2. Pick an environment: `cd envs/dev` or `cd envs/staging`.
3. Copy `terraform.tfvars.example` to `terraform.tfvars` (gitignored, never commit it) and fill it in:
   ```
   server_name = "..."
   server_type = "cx22"          # dev is a toy; staging uses a bigger type for load testing
   server_image = "ubuntu-24.04"
   server_location = "fsn1"

   hcloud_token         = "..."
   my_ip                = "<your public IP>"
   cloudflare_zone_id   = "..."
   cloudflare_api_token = "..."

   dns_record_name = "..."
   ssh_key_name    = "..."
   firewall_name   = "..."
   ```
4. `terraform init`
5. `terraform plan` — review before applying.
6. `terraform apply` — provisions SSH key, server, firewall, floating IP + assignment, and the DNS record; cloud-init binds the floating IP on first boot automatically.
7. `terraform output server_ip` — the address to hit (also what the DNS record points to).
8. `terraform destroy` — tears that environment back down to zero.

Dev and staging are fully independent state — running `apply`/`destroy` in one never touches the other. To change what both environments provision, edit `modules/server`; to change how big or how they're named, edit each env's `terraform.tfvars`.
