Day 2 — Modularize for a second environment

Scenario: Sales closed a deal that requires a dedicated staging environment. Right now we have one hand-rolled Terraform root module from DEV-141 that provisions exactly one box. Ops wants dev and staging to be structurally identical — same resources, same wiring, same DNS pattern — but sized differently: dev is a toy, staging mirrors prod topology and needs to survive a load test.

Ship: extract day1's single root module into a reusable `modules/server` module, then two thin env roots (`envs/dev`, `envs/staging`) that call it with different sizing and DNS names.

Hook: create-vs-reuse for the SSH key — worth a data-source detour, then worth ripping back out?

## Log

**Extracting the module**
- Moved everything from day1's flat root — `hcloud_ssh_key`, `hcloud_server`, `hcloud_firewall`, `hcloud_floating_ip`, `hcloud_floating_ip_assignment`, `cloudflare_record` — into `modules/server`, parameterized on `server_name`, `server_type`, `server_image`, `server_location`, `my_ip`, `dns_record_name`, `ssh_key_name`, `firewall_name`.
- `envs/dev` and `envs/staging` became thin callers: providers + a `module "web_server"` block passing in env-specific values. Same wiring in both, different tfvars.

**Provider blocks leaking into the module**
- First pass put `provider "hcloud"` / `provider "cloudflare"` config, including `hcloud_token` and `cloudflare_api_token`, straight into `modules/server/main.tf`. That's wrong layering, and not just by convention: a module with its own provider block can't be called with `count`, `for_each`, or `depends_on` — that's a hard error, and it would have blocked exactly the kind of multi-environment reuse this refactor exists to enable. Provider configs also get recorded in state; if the module block is ever removed later, Terraform has no provider left to destroy the resources through, which means orphaned infra and manual state surgery to clean up.
- Moved both provider blocks up into each env root; the module lost `hcloud_token`/`cloudflare_api_token` as inputs entirely — it only takes the values it actually operates on now.

**Reuse-vs-create SSH key detour**
- First modeled the SSH key as optionally reusable: a `create_ssh_key` bool, a `count`-gated `hcloud_ssh_key.default`, a `count`-gated `data.hcloud_ssh_key.existing`, and a `local.ssh_key_id` picking between them. Dev created its own key; staging was set to `create_ssh_key = false` and look up an existing one by name.
- Ripped it back out — not because the conditional was ugly, but because of what it actually did: staging's `data "hcloud_ssh_key" "existing"` lookup meant staging depended on dev having been applied first and left alone. Destroy dev on a Friday and staging's next `apply` breaks, even though dev and staging are supposed to be two independent environments with independent state. That's an undeclared ordering requirement between two separate Terraform state files — exactly the kind of coupling this refactor was supposed to remove, not add. Replaced it with a single unconditional `hcloud_ssh_key.web` per environment, keyed by `var.ssh_key_name` (`amin-dev` / `amin-staging`), fed by an `ssh_key_public` value instead of reading `~/.ssh/id_ed25519.pub` off disk — the module shouldn't assume it's running on the same machine as the key, and now it doesn't assume it's running after some other environment either.

**Sizing dev vs staging**
- `terraform.tfvars.example` is the only place dev and staging config actually diverges day to day: `server_type = "cx22"` for dev (toy), `cx23` for staging (closer to what a load test needs to survive), plus per-env `server_name`, `dns_record_name`, `ssh_key_name`, `firewall_name` so the two environments never collide on a Hetzner resource name or a DNS record.
- Everything structural — firewall rules, floating IP, cloud-init netplan bootstrap, the DNS record shape — stays identical between envs because it lives in the shared module. Ops gets what they asked for: same topology, different size.

**Cleanup pass**
- Filled in real-looking `terraform.tfvars.example` files for both envs, then caught myself before committing them with placeholder-shaped-but-real-looking secrets (`opiq_1230912...`, a fake token/zone id) — swapped every credential-shaped value back to an obvious `<your-...>` placeholder so nobody mistakes the example for a working credential.
- `fmt`-aligned the `=` signs across both env `main.tf` files and the module's `variables.tf`/`outputs.tf` (leftover from copy-pasting between dev and staging out of order).
- Added `server_id`, `fqdn`, and `ssh_key_id` outputs on the module, and re-pointed each env's `server_ip`/`server_ipv4` outputs at `module.web_server.*` instead of the resources directly, now that those resources live one level down.

## What I'd do differently

The reuse-vs-create SSH key detour was avoidable — I designed the "staging looks up dev's key" path before asking what happens when dev gets destroyed. The dependency between two independent state files should have been the first question, not something I noticed after wiring it up. Next time: before adding any cross-environment lookup (data source, remote state, shared name), write down what each environment's `destroy` does to the others. If the answer isn't "nothing," don't build it that way.

Also left for later, not yet done: `ssh_key_public` is currently hardcoded per-env in `main.tf` rather than sourced from `terraform.tfvars`, so cloning this and running it from zero doesn't work for anyone but me — that needs to become a variable before this is actually reusable by someone else.

## How to run this

See [README.md](./README.md).
