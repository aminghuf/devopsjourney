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

Terraform reads these at plan/apply time via `aws_ssm_parameter` data sources ([envs/dev/main.tf](envs/dev/main.tf), [envs/staging/main.tf](envs/staging/main.tf)) — they are not stored in `.tfvars` or state.

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