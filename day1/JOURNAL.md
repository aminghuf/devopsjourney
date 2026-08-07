Day 1 — Provision from zero Scenario: Staging burned down. Recreate it from an empty account. Ship: Terraform for Hetzner: server, SSH key, firewall, floating IP, Cloudflare DNS record. terraform apply from nothing to a pingable host. Hook: Why count vs for_each?

## Log

**Base infra (Hetzner via `hcloud` provider)**
- `hcloud_ssh_key`, `hcloud_server` (cx23, ubuntu-24.04, fsn1), `hcloud_firewall` (SSH restricted to my IP, 80/443 open to the world).
- Fixed a couple of early bugs: the `server_ip` output was pointing at a plain input variable instead of the real server attribute, and the firewall's SSH rule was scoping to the *server's own* IP instead of my client IP — both corrected to use the right references.
- SSH key path needed `pathexpand("~/.ssh/id_ed25519.pub")` — Terraform's `file()` doesn't expand `~` on its own.

**"SSH key not unique" error**
- Hetzner enforces uniqueness on the key *fingerprint*, not just the name. Queried the Hetzner API directly and found the same public key already registered under a different name (`omen`) from an earlier, unrelated upload. Imported it into state (`terraform import`) instead of trying to recreate it.

**Floating IP**
- Added `hcloud_floating_ip`, first wired directly via `server_id`.
- Discovered assigning a floating IP in Hetzner only sets up routing — it does **not** configure the address inside the server's own OS. Traffic to it silently timed out even though the console showed it "assigned."
- Also confirmed the firewall has no ICMP rule, so `ping` is blocked by design regardless of the IP — only TCP 22/80/443 are open.

**Automating the floating IP OS config**
- First pass: a `null_resource` with `file` + `remote-exec` provisioners that SSHed into the server (via its stable primary IP) after creation and wrote/applied the netplan config for the floating IP. Worked, but provisioners are a known Terraform anti-pattern (fragile, needs live SSH from the apply machine).
- Switched to the more idiomatic route: cloud-init via `user_data` on `hcloud_server.web`, baking the netplan config in at first boot.
- That required decoupling the floating IP from the server: `hcloud_floating_ip` now creates independently via `home_location = "fsn1"` instead of `server_id`, with a separate `hcloud_floating_ip_assignment` resource doing the actual binding — otherwise `server → floating_ip → server` was a dependency cycle.
- Consequence: adding `user_data` to an *existing* server forces replacement (cloud-init only runs at first boot). Accepted a one-time rebuild of `web-server-01` to get there. The floating IP address itself was preserved throughout — only the server and its primary IP changed. Verified afterward that the floating IP responds directly (SSH banner) without any manual step.

**Cloudflare DNS**
- Added `cloudflare_record` (`day1.<domain>` → floating IP, proxied).
- Provider deprecation: `value` → `content` argument rename in `cloudflare/cloudflare` v4.
- Chased a real "Authentication error (10000)" through several layers: a mangled/duplicated token value (leftover characters from a previous token stuck onto a new paste), then a token that was valid but missing DNS scope, then confirmed a properly-scoped token via a direct `dns_records` API call. Learned `/user/tokens/verify` can report "invalid" for a token that's actually fine, if it lacks a separate "read own token" permission — `/accounts/{id}/tokens/verify` or a real scoped call (like listing DNS records) is the trustworthy check.

**State drift false alarm**
- `terraform plan` kept showing `hcloud_server.web` "must be replaced" over a `location` mismatch, even right after a refresh. Root cause: the provider wasn't populating `location`/`datacenter` back into state from Hetzner's current API response shape, so it read back empty every time. Since `location` is set-once (`ForceNew`) and the server already existed in the right place, removed it from config entirely rather than fight the provider or hand-edit state.

**Cleanup pass**
- Re-added `location = "fsn1"` to `hcloud_server.web` — safe now since the server was already rebuilt fresh for the cloud-init change, so state actually has a real value to read back instead of the stale empty one from before.
- Dropped the unused `null` provider from `required_providers` (leftover from the abandoned `null_resource`/SSH-provisioner approach, no longer referenced anywhere).
- Flipped `cloudflare_record.server_dns` from `proxied = true` to `proxied = false` — DNS now points straight at the Hetzner floating IP instead of going through Cloudflare's proxy/CDN.
- Wrote the README.
- Ran `terraform destroy` → `terraform apply` from clean, timed it, then `terraform plan` came back with zero changes — config and real infra fully agree.

## How to run this

