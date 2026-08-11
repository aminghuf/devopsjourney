Day 3 — Migrate off Hetzner onto AWS

Scenario: day2 left us with a clean `modules/server` + `envs/dev`/`envs/staging` split, but everything under it was Hetzner (`hcloud_server`, `hcloud_firewall`, `hcloud_floating_ip`, ...) with real tokens sitting in plaintext `terraform.tfvars` on disk. Ship: re-platform the same module onto AWS (EC2 + EIP + security group), move state off local disk into a real remote backend, and get secrets out of tfvars entirely.

Hook: the SSH-key reuse pattern day2's retro said to watch out for came back anyway, on AWS, in a different shape — and it broke exactly the way that retro predicted.

## Log

**Resource swap: Hetzner → AWS**
- `hcloud_ssh_key` / `data.hcloud_ssh_key` → `aws_key_pair` / `data.aws_key_pair`, same create-vs-reuse `count` pattern carried over from day2.
- `hcloud_server` → `aws_instance`, with `ami` resolved via a `data "aws_ami" "ubuntu"` lookup (Canonical owner id, name filter on `var.server_image`) instead of hardcoding an image string.
- `hcloud_firewall` → `aws_security_group` (22 from `var.my_ip`, 80/443 from anywhere, open egress).
- `hcloud_floating_ip` + `hcloud_floating_ip_assignment` → `aws_eip` + `aws_eip_association`.
- Dropped the cloud-init `netplan` block entirely — that existed only to hand-wire Hetzner's floating IP onto the NIC on first boot; AWS's EIP association does that natively, so the whole `user_data` block was dead weight on AWS.
- `cloudflare_record.server_dns` content now points at `aws_eip.web.public_ip` instead of the Hetzner floating IP.
- Variable renaming stayed minimal on purpose: `server_type`/`server_image`/`server_location` kept their names (so env tfvars didn't need restructuring) but changed meaning — instance type, Ubuntu version string, availability zone respectively.

**AMI lookup: the two flags that have to travel together**
- First pass dropped `most_recent = true` from the `aws_ami` data source. That's not cosmetic — without it the data source can match more than one AMI and `plan` hard-errors with "your query returned more than one result," and it's not a hypothetical, it happens the moment Canonical ships a second build under the same filter.
- Also added `lifecycle { ignore_changes = [ami] }` on `aws_instance.web` — solves a different problem: once `most_recent` picks a single AMI, a *newer* one landing later would otherwise force-replace the running instance on the next `plan` even though nothing we configured changed.
- Caught mid-review that a later edit re-broke `most_recent` and, separately, left `variables.tf` with `server_image` declared twice (duplicate variable block, hard `terraform validate` failure). Both fixed.

**Secrets out of tfvars, into SSM**
- `cloudflare_api_token` and `cloudflare_zone_id` were sitting in plaintext in both envs' `terraform.tfvars`, alongside an already-revoked `hcloud_token`. Rather than just gitignoring harder, moved both into AWS SSM Parameter Store as `SecureString` params under `/day3/<env>/cloudflare_api_token` and `/day3/<env>/cloudflare_zone_id`, read at plan time via `data "aws_ssm_parameter"` with `with_decryption = true`.
- Confirmed via `git ls-files` / `git check-ignore` that `*.tfvars` was already gitignored repo-wide and nothing had ever actually been committed — the leak was local-disk-only, not a git-history problem. Rotated the token anyway.
- Wrote `BOOTSTRAP.md` documenting the bucket and both parameters as the one thing that has to be created by hand, with the exact `aws ssm put-parameter` / `aws s3api` commands, because they have to exist before `terraform init` can run at all — nothing in the Terraform config can create the thing Terraform's own backend depends on.

**Remote state: local disk → S3**
- Added an `s3` backend block to both envs, initially copy-pasted with placeholder Hetzner-object-storage values (`endpoints`, `skip_credentials_validation`, etc.) from a generic template. Once confirmed the bucket (`s3-bucket-devopsjourney`) was a real AWS bucket in `eu-north-1`, stripped all the non-AWS-S3-clone overrides down to a plain `bucket` / `key` / `region` / `encrypt` / `use_lockfile` block — `use_lockfile` gets native S3 locking on Terraform >= 1.10, no DynamoDB table needed.
- `dev`'s `-migrate-state` looked like it succeeded (the backend pointer in `.terraform/terraform.tfstate` matched) but never actually pushed an object to the new key — `terraform state list` failed with "No state file was found!" and `aws s3api list-objects-v2` confirmed the key genuinely didn't exist yet. Fixed with a manual `terraform state push`. Root-caused as ~nothing-lost, since the local state being migrated was already empty (that env's one prior EC2 instance was already `terminated`, confirmed directly against the EC2 API rather than trusting any state file).
- `staging` migrated cleanly the first time; verified live with `terraform state list` rather than trusting the raw state JSON, which turned out to matter — an S3 object downloaded mid-investigation showed stale resource types from an earlier state revision (bucket versioning means `get-object` without a version id isn't guaranteed to match what `state list` reports as current).
- Bucket already had versioning, Block Public Access, and default SSE-S3 encryption enabled — verified live against the account rather than assumed, then documented as the baseline in `BOOTSTRAP.md`.

**Staging depending on dev's key pair — the day2 lesson, again**
- Staging was set `create_ssh_key = false`, looking up dev's `devenv` key pair via `data.aws_key_pair.existing`. First `apply` on staging (before dev existed) failed with "no matching EC2 Key Pair found" — the exact cross-environment ordering coupling day2's retro flagged and said to avoid, just recreated on AWS instead of Hetzner.
- Applying dev first made staging's apply succeed, but that's papering over it, not fixing it: destroy dev and staging breaks again on next apply, same as day2.
- Fix: staging now creates its own key pair (`create_ssh_key = true`, `ssh_key_name = "stagingenv"`, its own `ssh_key_public` var/tfvar) instead of borrowing dev's. AWS doesn't allow swapping an instance's key pair in place, so this forced a real replace of the already-running `staging-server-01` — confirmed the blast radius (EIP allocation itself is untouched, so the public IP/DNS record doesn't change, ~30s of actual downtime) before applying. Verified after: `dev-server-01` on `devenv`, `staging-server-01` on `stagingenv`, fully independent key pairs, no more shared lookup.

## What's missing — the actual ticket isn't in here yet

Mentor feedback, verbatim, because it's correct and shouldn't get softened in the rewrite: "Lock proof and drift demo are nowhere in the repo. You did the drift exercise with me and produced a good plan diff — none of it is written down. That plus the lock test is Day 3. Right now the repo shows a cloud migration, not the ticket."

Concretely still owed:
- **State lock proof.** `use_lockfile = true` is sitting in both backend blocks and gets asserted as "native S3 locking" above, but that's a claim, not a demonstration. Never actually ran a concurrent `apply`/`plan` against the same state and captured what happens when the lock is held — no proof it works, no proof of what the error looks like, nothing to point at.
- **Drift demo.** Was actually done — live, interactively, produced a real plan diff worth keeping — and then never written down anywhere. The repo currently has zero evidence this happened: no captured `plan` output, no note on what was changed out-of-band to cause the drift, no explanation of what the diff showed or how it was reconciled.
- Everything logged above (Hetzner→AWS, SSM, S3 backend, staging/dev decoupling) is real work and stays in this file, but it was scope creep relative to what day3 was actually supposed to prove out. It shouldn't be read as a substitute for the lock/drift ticket.

## What I'd do differently

Should have asked "what does creating an existing-lookup `data` source between two environments cost me" *before* wiring it up, not after the first failed apply — this is the identical mistake day2's retro named and said to check for up front, and it still shipped, just on a different provider. The check is cheap: for any cross-env data source or lookup, write down what an isolated `terraform apply` of the *other* environment alone requires, before deciding it's independent.

Also worth tightening: AWS CLI in this session is authenticated as the account root user. Fine for a solo learning exercise, but before this goes any further (a CI pipeline, another collaborator), that needs to become a scoped IAM role/user rather than root credentials sitting in a local profile.

## How to run this

See [README.md](./README.md) for how to run each env, and [BOOTSTRAP.md](./BOOTSTRAP.md) for the one-time manual setup (S3 backend bucket + SSM parameters) that has to exist before `terraform init` works.