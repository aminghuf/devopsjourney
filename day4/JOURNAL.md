Day 4 — AWS, day one: VPC, subnets, IAM role, budget alarm

Scenario: a client insists on AWS for a POC, and the "AWS familiarity" part of that POC starts today — day3 already had EC2 running, but in AWS's default VPC. Ship: a real VPC with public/private subnets across two AZs, a security group, one t3.micro, one IAM role, all free tier, with a budget alarm set up *before* anything billable exists.

Hook: the day3 retro flagged that AWS CLI was authenticated as root and said that needed to become scoped before this went further. It didn't get scoped this round either — noted again below — but a smaller version of "config copied from the wrong place" bit twice today instead, once in a module file and once in an env file.

## Log

**New root: `envs/account` for the budget alarm**
- A third root module alongside `dev`/`staging`, holding only `aws_budgets_budget` — 80% actual-spend and 100% forecasted-spend thresholds, both notifying `budget_email`. Its own state key (`day4/account/platform.tfstate`), applied independently of and before either environment, per the day's own instruction to set the alarm first.
- `terraform.tfvars` initially had only `budget_email` — `budget_name` and `budget_limit` are required variables with no default, so `terraform validate` passed (it doesn't check tfvars) but `plan` would have failed immediately on `No value for required variable`. Added both.

**Provider and backend blocks belong only in the root module — not in a module meant to be called from elsewhere**
- `modules/network/main.tf` started out with a full `terraform { backend "s3" {...} }` block and a `provider "aws" {...}` block, copy-pasted straight out of `envs/account/main.tf` — down to reusing *account's* state key (`day4/account/platform.tfstate`), not even a network-specific one.
- That's broken in two independent ways, not one. A `backend` block only does something in the module Terraform is actually run against directly — a root module. A child module doesn't get its own state file just because it declares a backend block; it inherits whatever backend/state the calling root already initialized against. Sticking a backend in `modules/network` doesn't split network resources into their own state — it's simply not consulted at all when the module is called from `envs/dev` or `envs/staging`. Separately, a hardcoded `provider "aws"` block inside a reusable module removes the calling root's ability to configure that provider itself — both `dev` and `staging` call `modules/network`, and if the module pins its own provider block, both envs are fighting over (or silently sharing) one hardcoded config instead of each root supplying its own region/credentials.
- The fix is the general rule, not a one-off patch: root modules (the things you actually run `terraform init` in — `envs/*`) own `provider` blocks and `backend` blocks. Child modules (`modules/*`) only declare `required_providers` — version constraints — and take everything else as input variables or the provider configuration inherited from whoever called them. `modules/network/main.tf` now has neither a `backend` nor a `provider` block, only `required_providers`.

**Network module: wiring it up exposed three separate breaks**
- `modules/network/outputs.tf` referenced `module.vpc.vpc_id` and `module.vpc.public_subnet_ids` — but `modules/network/main.tf` never declares a `module "vpc"`; the VPC and subnets are plain resources (`aws_vpc.vpc`, `aws_subnet.public_1`, `aws_subnet.public_2`) directly in that file, not wrapped in a nested module. `terraform plan` failed with "No module call named 'vpc' is declared in module.network." Fixed by pointing the outputs straight at the resources: `aws_vpc.vpc.id` and `[aws_subnet.public_1.id, aws_subnet.public_2.id]`.
- `envs/dev/main.tf` (and `staging`) never actually had a `module "network"` block, even though `envs/dev/output.tf` already referenced `module.network.vpc_id`. `modules/server`'s `vpc_id`/`subnet_id` inputs were being fed from `var.vpc_id`/`var.subnet_id` instead — variables with no declared source anywhere. Added the `module "network"` call in both envs, then repointed `web_server`'s `vpc_id`/`subnet_id` at `module.network.vpc_id` / `module.network.public_subnet_ids[0]` instead of the orphaned input vars.
- Fixing that surfaced a naming mismatch: `envs/dev/output.tf` asked for `module.network.public_subnet_id` (singular) against a module output named `public_subnet_ids` (plural, a list). Reconciled to the plural name with a `[0]` index at the call site.

**Subnet CIDRs: hardcoded once, needed to vary per environment**
- All four subnets (`public_1`, `public_2`, `private_1`, `private_2`) had literal `cidr_block` values (`10.0.1.0/24`, `10.0.2.0/24`, `10.0.11.0/24`, `10.0.12.0/24`) while `vpc_cidr` was already a per-env input variable. That's a real blast-radius problem, not a style nit: give dev `10.0.0.0/16` and staging `10.1.0.0/16` (the whole point of per-env VPCs — isolated address space, peerable later, no future collision) and staging's `plan` fails outright, because `10.0.1.0/24` doesn't fall inside `10.1.0.0/16` — AWS rejects a subnet CIDR that isn't a subset of its VPC's CIDR. The alternative, giving both envs the identical `10.0.0.0/16`, "works" but throws away the actual reason to have two VPCs: two VPCs with identical address space can never be peered and are dead on arrival for any future VPN or transit gateway.
- Fixed with `cidrsubnet(var.vpc_cidr, 8, N)` on all four subnets instead of literals — `newbits = 8` because every env's VPC is a `/16` and every subnet is a `/24` (24 − 16 = 8), and `N` (1, 2, 11, 12) reproduces the exact octets that were hardcoded before, so dev's existing `/24`s don't drift. Now each env's subnets automatically live inside that env's own `vpc_cidr`, whatever it's set to.
- Mid-fix, the subnet `tags` blocks got a bad edit along the way: `Name = "${aws_subnet.public_1.name}-subnet"` — a resource referencing its own `.name` attribute from inside its own block. Two problems at once: `aws_subnet` has no `name` attribute (AWS subnets are identified by tags, not a `name` field), and even if it did, that's a self-reference, which Terraform rejects outright regardless. Fixed by going back to `"${var.vpc_name}-public-subnet-1"` style tags built from the input variable — and made all four subnet tags distinct in the process (the original had both public subnets sharing one `Name` tag).

**IAM role for SSM**
- `modules/server` gained `aws_iam_role` (trust policy scoped to `ec2.amazonaws.com`), `aws_iam_role_policy_attachment` for the AWS-managed `AmazonSSMManagedInstanceCore` policy, and `aws_iam_instance_profile`, attached to `aws_instance.web` via `iam_instance_profile`. This is the day's "one IAM role" requirement and also means the instance is reachable through SSM Session Manager without needing inbound SSH open — SSH is still allowed from `my_ip` for now, but doesn't have to be the only path in.

**Placement: `availability_zone` → `subnet_id`**
- `aws_instance.web` previously set `availability_zone = var.server_location` directly (a leftover from when this module still had one flat network, no VPC/subnet of its own). Once the instance needed to land inside a specific subnet of a specific VPC, that became `subnet_id = var.subnet_id` instead — the subnet already pins the AZ, so specifying both would be redundant, and `server_location` was dropped from `modules/server/variables.tf` entirely.
- That drop didn't get carried through to the callers: `envs/dev/main.tf` and `envs/staging/main.tf` were still passing `server_location = var.server_location` into `module "web_server"`, which the module no longer accepts. `terraform validate` failed with "An argument named 'server_location' is not expected here" in both envs. Removed the line from both `main.tf`s and the now-dead `server_location` variable from both `variables.tf`s.
- That in turn exposed how stale `envs/dev/terraform.tfvars` actually was: `server_type = "cx22"` and `server_location = "fsn1"` are Hetzner values (instance type and datacenter code) left over from the pre-day3 Hetzner setup, and `server_image = "ubuntu-24.04"` didn't match the AMI filter's expected format (`${var.server_image}` gets interpolated into an `aws_ami` name filter as `...-ubuntu-*-${var.server_image}-amd64-server-*`, which wants just `24.04`, not `ubuntu-24.04`). None of this would have been caught by `validate` — only a real `plan` against AWS would have rejected `cx22` as an invalid instance type. Fixed to `t3.micro` / `24.04`, `my_ip` filled in with a real IPv4 (the naive `curl ifconfig.me` in this shell returns IPv6 first — needed `curl -4`), and `vpc_name`/`vpc_cidr` added since those are now required inputs the tfvars file predates.
- `envs/staging/terraform.tfvars` didn't exist at all — `staging` had never actually been planned since the network module was wired in. Created it from scratch, mirroring dev's shape with staging's own names (`amin-staging`, `amin-frw-staging`) and its own VPC CIDR (`10.1.0.0/16`, one `/16` up from dev's `10.0.0.0/16`).
- `envs/staging/.envrc` (and its `.envrc.example`) were pointing at `/day3/dev/cloudflare_api_token` and `/day3/dev/cloudflare_zone_id` — staging reading dev's SSM parameters, not its own. A copy-paste of dev's `.envrc` that never got the path updated. Fixed both to `/day3/staging/...`.

**State lock, mid-session**
- Hit a real S3-native-lock `412 PreconditionFailed` on `envs/dev` while another `plan` was still holding the lock (`Lock ID 51dec4a9-9b78-4041-cc4c-02eae4f20f8e`, `OperationTypePlan`). Same mechanism day3 proved deliberately — `use_lockfile = true`, no DynamoDB table — just hit incidentally this time from an interrupted run rather than as a planned exercise. Resolved with `terraform force-unlock <id>` after confirming nothing else was actually still running against that state.

## Verification: apply, then destroy — for real

No separate `apply` transcript was captured, but the `destroy` plans below are effectively proof of what `apply` built: real instance IDs, real attached EIPs, real Cloudflare DNS records, all created within the same minute per environment (`2026-08-16T08:45:44Z`–`08:46:50Z`), then torn down in this same session.

**`envs/dev`** — VPC `vpc-0b75c29b7996bb8c0` (`10.0.0.0/16`), instance `i-0310c5b8d13093d38` (`t3.micro`, key `amin-dev`), EIP `51.20.202.59` bound to it, DNS record `amin-dns-dev.aminghuf.dev` -> that EIP, IAM role `amin-dev-role` with `AmazonSSMManagedInstanceCore` attached:

```
Plan: 0 to add, 0 to change, 21 to destroy.

Changes to Outputs:
  - public_subnet_ids = "subnet-04a8db48cd2a8156f" -> null
  - server_ip         = "51.20.202.59" -> null
  - vpc_id            = "vpc-0b75c29b7996bb8c0" -> null

module.web_server.cloudflare_record.server_dns: Destruction complete after 0s
module.network.aws_route_table_association.*  (x4): Destruction complete
module.network.aws_route_table.private_rt: Destruction complete
module.network.aws_subnet.private_1 / private_2: Destruction complete
module.web_server.aws_eip_association.main: Destruction complete after 2s
module.web_server.aws_eip.web: Destruction complete after 1s
module.network.aws_route_table.public_rt: Destruction complete
module.network.aws_internet_gateway.igw: Destruction complete
module.web_server.aws_instance.web: Still destroying... [1m0s elapsed]
module.web_server.aws_instance.web: Destruction complete after 1m0s
module.web_server.aws_key_pair.default[0] / aws_iam_instance_profile.ec2_profile: Destroying...
module.network.aws_subnet.public_1 / public_2: Destroying...
# (output cut off here by paste length — final confirmation line not captured)
```

**`envs/staging`** — VPC `vpc-006433fbdd8bcda8e` (`10.1.0.0/16`), instance `i-0defcf25e4df85735` (`t3.micro`, key `amin-staging`), EIP `13.62.174.78`, DNS record `amin-dns-staging.aminghuf.dev`, IAM role `amin-staging-role`:

```
Plan: 0 to add, 0 to change, 21 to destroy.

Changes to Outputs:
  - public_subnet_ids = "subnet-077eff2cada1e2f5b" -> null
  - server_ip         = "13.62.174.78" -> null
  - vpc_id            = "vpc-006433fbdd8bcda8e" -> null

Destroy complete! Resources: 21 destroyed.
```

Both environments' plans match exactly: 21 resources each — VPC, 2 public + 2 private subnets, IGW, 2 route tables + 4 associations, security group, EC2 instance, EIP + association, IAM role + policy attachment + instance profile, key pair, Cloudflare DNS record. Confirms `dev` and `staging` really did build symmetric, independent infrastructure from the same module pair with only `vpc_cidr`/naming differing.

One live rerun of day3's "config copied from the wrong place" theme, caught in the terminal directly: `terraform destroy --auto-allow` on `dev` failed with `flag provided but not defined: -auto-allow` before anything ran — the correct flag is `--auto-approve`. No damage (it errored before touching AWS), just a typo, but it's the same day's pattern one more time — command/config carried over slightly wrong from whatever it was copied from.

**`envs/account`** — full apply-then-destroy cycle, the only one of the three with a captured `apply` transcript:

```
Plan: 1 to add, 0 to change, 0 to destroy.
  Enter a value: yes

aws_budgets_budget.budget: Creating...
aws_budgets_budget.budget: Creation complete after 9s [id=462052762470:day4-monthly-budget]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

`$10/month`, notifying `amin.gha98@gmail.com` at 80% actual / 100% forecasted — matches `terraform.tfvars` exactly. Then torn down:

```
Plan: 0 to add, 0 to change, 1 to destroy.
aws_budgets_budget.budget: Destroying... [id=462052762470:day4-monthly-budget]
aws_budgets_budget.budget: Destruction complete after 1s

Destroy complete! Resources: 1 destroyed.
```

**Still open:** the tail end of `dev`'s destroy confirmation and the `apply` transcripts for `dev`/`staging` aren't captured here — the destroy plans stand in as evidence of what was built, per above.

## What I'd do differently

Every one of today's bugs except the state lock was a **copy-paste that didn't get fully adapted to its new location** — `modules/network`'s backend/provider block copied from `envs/account`, `modules/network/outputs.tf`'s `module.vpc.*` references copied from a different module shape, `staging`'s `.envrc` copied from `dev` without updating the path, `dev`'s `terraform.tfvars` copied forward from the Hetzner era without updating the values, subnet tags copied-and-mangled mid-edit. None of these are conceptually hard mistakes — they're all "this came from somewhere else and one detail didn't get changed." `terraform validate` caught the ones that were structural (undeclared module, unexpected argument); it caught none of the ones that were valid HCL with wrong values (`cx22` as an instance type, `ubuntu-24.04` as an AMI filter fragment, dev's SSM path in staging's `.envrc`). The next multi-env change should include actually running `plan` — not just `validate` — against every environment being touched, specifically because `validate` only proves the config is well-formed, not that the values in it are real.

Also carried over unchanged from day3's retro: AWS CLI in this session is still authenticated as the account root user. Two days running now without addressing it — that's the one worth actually doing before day5.

## How to run this

See [README.md](./README.md) for the architecture diagram and full run-from-zero steps: apply `envs/account` first for the budget alarm, then `envs/dev` and/or `envs/staging` for the VPC + instance.
