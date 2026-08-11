# Bootstrap Resources

These are created manually because they must exist before `terraform init` can run.

## S3 bucket (Terraform state backend)

- **Name:** `s3-bucket-devopsjourney`
- **Region:** `eu-north-1`
- **Why it exists:** holds the remote Terraform state for both the `dev` and `staging` environments (`day3/dev/platform.tfstate` and `day3/staging/platform.tfstate`), so state isn't kept only on a local disk and both environments can lock/share state safely via the S3 backend's native locking.

### Commands to recreate it

```sh
# Create the bucket
aws s3api create-bucket \
  --bucket s3-bucket-devopsjourney \
  --region eu-north-1 \
  --create-bucket-configuration LocationConstraint=eu-north-1

# Enable versioning (protects state history / recovery from bad writes)
aws s3api put-bucket-versioning \
  --bucket s3-bucket-devopsjourney \
  --versioning-configuration Status=Enabled

# Block all public access
aws s3api put-public-access-block \
  --bucket s3-bucket-devopsjourney \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Enable default encryption (SSE-S3 / AES256)
aws s3api put-bucket-encryption \
  --bucket s3-bucket-devopsjourney \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": { "SSEAlgorithm": "AES256" },
        "BucketKeyEnabled": true
      }
    ]
  }'
```

## SSM parameters (Cloudflare secrets)

These are no longer read by Terraform itself (no `aws_ssm_parameter` data source in `main.tf` anymore). Instead, each env's `.envrc` (direnv) fetches them from SSM at shell-load time and exports them as plain env vars:

```sh
export CLOUDFLARE_API_TOKEN=$(aws ssm get-parameter --name "/day3/<env>/cloudflare_api_token" --region eu-north-1 --with-decryption --query Parameter.Value --output text)
export TF_VAR_cloudflare_zone_id=$(aws ssm get-parameter --name "/day3/<env>/cloudflare_zone_id" --region eu-north-1 --with-decryption --query Parameter.Value --output text)
```

- `CLOUDFLARE_API_TOKEN` is picked up natively by the Cloudflare provider (`provider "cloudflare" {}` is intentionally empty in both envs' `main.tf`) — no Terraform variable involved.
- `CLOUDFLARE_ZONE_ID` has no such native provider env var (zone id is a per-resource argument, not a provider setting), so it's exported with the `TF_VAR_` prefix instead, which Terraform maps directly onto `var.cloudflare_zone_id` (declared in each env's `variables.tf`, passed into `modules/server` from `main.tf`).
- Practical effect: `terraform init`/`plan`/`apply` no longer need `ssm:GetParameter` IAM permission themselves — direnv does that lookup once, before Terraform even runs. Whatever shell runs `cd envs/<env>` needs `direnv` installed and `direnv allow`'d, plus the same `ssm:GetParameter` permission on `/day3/<env>/*`, just earlier in the pipeline than before.
- Still not stored in `.tfvars`, state, or git — same guarantee as before, just a different mechanism for getting the value from SSM into the process.

### dev

```sh
aws ssm put-parameter \
  --name "/day3/dev/cloudflare_api_token" \
  --type SecureString \
  --value "<placeholder>" \
  --region eu-north-1

aws ssm put-parameter \
  --name "/day3/dev/cloudflare_zone_id" \
  --type SecureString \
  --value "<placeholder>" \
  --region eu-north-1
```

### staging

```sh
aws ssm put-parameter \
  --name "/day3/staging/cloudflare_api_token" \
  --type SecureString \
  --value "<placeholder>" \
  --region eu-north-1

aws ssm put-parameter \
  --name "/day3/staging/cloudflare_zone_id" \
  --type SecureString \
  --value "<placeholder>" \
  --region eu-north-1
```