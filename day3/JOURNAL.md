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

**Secrets out of tfvars, into SSM — then simplified again**
- `cloudflare_api_token` and `cloudflare_zone_id` were sitting in plaintext in both envs' `terraform.tfvars`, alongside an already-revoked `hcloud_token`. First move: both into AWS SSM Parameter Store as `SecureString` params, read at plan time via `data "aws_ssm_parameter"`.
- Confirmed via `git ls-files` / `git check-ignore` that `*.tfvars` was already gitignored repo-wide and nothing had ever actually been committed — the leak was local-disk-only, not a git-history problem. Rotated the token anyway.
- That data-source approach got replaced with `direnv`: each env's `.envrc` now runs `aws ssm get-parameter` on `cd` and exports `CLOUDFLARE_API_TOKEN`, which the Cloudflare provider reads natively (empty `provider "cloudflare" {}` block, no Terraform variable involved at all for the token).
- `cloudflare_zone_id` moved a second time, in the opposite direction: it's not actually a secret — it's an account identifier used as a resource argument, not a credential — so it came back out of SSM entirely and is now a plain required variable in `terraform.tfvars`. The `/day3/<env>/cloudflare_zone_id` SSM parameters were deleted once nothing read them anymore, so `BOOTSTRAP.md` doesn't tell people to create a parameter nothing consumes.
- Net design: only the real secret (API token) goes through SSM + `.envrc`; the non-secret identifier (zone ID) is a normal tfvar. `BOOTSTRAP.md` documents the one remaining SSM parameter per env; `README.md`'s architecture diagram and run steps were rewritten to match, including making `direnv allow` an explicit, called-out step — it was previously undocumented entirely, which meant the single step everything else depends on wasn't in the instructions.

**Remote state: local disk → S3**
- Added an `s3` backend block to both envs, initially copy-pasted with placeholder Hetzner-object-storage values (`endpoints`, `skip_credentials_validation`, etc.) from a generic template. Once confirmed the bucket (`s3-bucket-devopsjourney`) was a real AWS bucket in `eu-north-1`, stripped all the non-AWS-S3-clone overrides down to a plain `bucket` / `key` / `region` / `encrypt` / `use_lockfile` block — `use_lockfile` gets native S3 locking on Terraform >= 1.10, no DynamoDB table needed.
- `dev`'s `-migrate-state` looked like it succeeded (the backend pointer in `.terraform/terraform.tfstate` matched) but never actually pushed an object to the new key — `terraform state list` failed with "No state file was found!" and `aws s3api list-objects-v2` confirmed the key genuinely didn't exist yet. Fixed with a manual `terraform state push`. Root-caused as ~nothing-lost, since the local state being migrated was already empty (that env's one prior EC2 instance was already `terminated`, confirmed directly against the EC2 API rather than trusting any state file).
- `staging` migrated cleanly the first time; verified live with `terraform state list` rather than trusting the raw state JSON, which turned out to matter — an S3 object downloaded mid-investigation showed stale resource types from an earlier state revision (bucket versioning means `get-object` without a version id isn't guaranteed to match what `state list` reports as current).
- Bucket already had versioning, Block Public Access, and default SSE-S3 encryption enabled — verified live against the account rather than assumed, then documented as the baseline in `BOOTSTRAP.md`.

**Staging depending on dev's key pair — the day2 lesson, again**
- Staging was set `create_ssh_key = false`, looking up dev's `devenv` key pair via `data.aws_key_pair.existing`. First `apply` on staging (before dev existed) failed with "no matching EC2 Key Pair found" — the exact cross-environment ordering coupling day2's retro flagged and said to avoid, just recreated on AWS instead of Hetzner.
- Applying dev first made staging's apply succeed, but that's papering over it, not fixing it: destroy dev and staging breaks again on next apply, same as day2.
- Fix: staging now creates its own key pair (`create_ssh_key = true`, `ssh_key_name = "stagingenv"`, its own `ssh_key_public` var/tfvar) instead of borrowing dev's. AWS doesn't allow swapping an instance's key pair in place, so this forced a real replace of the already-running `staging-server-01` — confirmed the blast radius (EIP allocation itself is untouched, so the public IP/DNS record doesn't change, ~30s of actual downtime) before applying. Verified after: `dev-server-01` on `devenv`, `staging-server-01` on `stagingenv`, fully independent key pairs, no more shared lookup.

## The actual ticket: lock proof and drift demo

Mentor feedback that prompted this section, verbatim, because it was correct: "Lock proof and drift demo are nowhere in the repo... That plus the lock test is Day 3. Right now the repo shows a cloud migration, not the ticket." Everything above (Hetzner→AWS, SSM/direnv, S3 backend, staging/dev decoupling) is real, necessary work, but it was scope creep relative to what day3 was actually supposed to prove out — this section is the part that was actually owed.

**State lock proof.** Ran for real against the live `envs/dev` backend rather than just trusting `use_lockfile = true` in the config: held the S3 native lock (a real object at `day3/dev/platform.tfstate.tflock`, confirmed via `aws s3api list-objects-v2`), then ran `terraform plan` against it. Got a genuine S3 `412 PreconditionFailed` on the lock's conditional `PutObject`, with a real `Lock Info` block and `LOCK_ID`. Force-unlocked with that exact ID, confirmed the lock object was gone, confirmed `plan` worked normally again immediately after. Full transcript in [RUNBOOK.md § Proof](./RUNBOOK.md#proof-run-against-envsdev-2026-08-11).

**Drift demo.** Two sentences of context: added a port-8080 ingress rule to dev's security group directly via `aws ec2 authorize-security-group-ingress` (bypassing Terraform entirely, simulating a manual console change), then ran `terraform plan` and got a clean diff showing Terraform wanting to remove exactly that rule (`~ ingress = [ - { from_port = 8080, ... } ]`, `Plan: 0 to add, 2 to change, 0 to destroy`) — correct drift detection, nothing else touched. Reverted the rule out-of-band with `aws ec2 revoke-security-group-ingress` (not `terraform apply`, to prove the state/reality gap closes from either direction) and confirmed a subsequent `plan` no longer proposed any security-group change.

```
# after the out-of-band change, before revert:
  # module.web_server.aws_security_group.web_and_ssh will be updated in-place
  ~ resource "aws_security_group" "web_and_ssh" {
        id                     = "sg-0090ea40bf8f2311f"
      ~ ingress                = [
          - {
              - cidr_blocks      = ["0.0.0.0/0"]
              - description      = "manual drift test - added outside terraform"
              - from_port        = 8080
              - to_port          = 8080
              - protocol         = "tcp"
            },
            # (3 unchanged elements hidden)
        ]
        name                   = "devfw"
        # (9 unchanged attributes hidden)
    }

Plan: 0 to add, 2 to change, 0 to destroy.
```

## What I'd do differently

Should have asked "what does creating an existing-lookup `data` source between two environments cost me" *before* wiring it up, not after the first failed apply — this is the identical mistake day2's retro named and said to check for up front, and it still shipped, just on a different provider. The check is cheap: for any cross-env data source or lookup, write down what an isolated `terraform apply` of the *other* environment alone requires, before deciding it's independent.

Also worth tightening: AWS CLI in this session is authenticated as the account root user. Fine for a solo learning exercise, but before this goes any further (a CI pipeline, another collaborator), that needs to become a scoped IAM role/user rather than root credentials sitting in a local profile.

## How to run this

See [README.md](./README.md) for how to run each env, [BOOTSTRAP.md](./BOOTSTRAP.md) for the one-time manual setup (S3 backend bucket + per-env SSM parameter) that has to exist before `terraform init` works, and [RUNBOOK.md](./RUNBOOK.md) for state-lock and version-recovery procedures.