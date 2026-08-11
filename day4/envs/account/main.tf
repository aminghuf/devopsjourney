terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

  }
  backend "s3" {
    bucket       = "s3-bucket-devopsjourney"
    key          = "dev/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true # native S3 locking, TF >= 1.10
  }
}
provider "aws" {
  region = "eu-north-1"
}

resource "aws_budgets_budget" "budget" {
  name              = var.budget_name
  budget_type       = "COST"
  limit_amount      = var.budget_limit
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  notification {
    comparison_operator = "GREATER_THAN"
    notification_type   = "ACTUAL"
    threshold           = 80
    threshold_type      = "PERCENTAGE"
    subscriber_email_addresses = [var.budget_email]
  }
  notification {
    comparison_operator = "GREATER_THAN"
    notification_type   = "FORECASTED"
    threshold           = 100
    threshold_type      = "PERCENTAGE"
    subscriber_email_addresses = [var.budget_email]
  }
}