# terraform/main.tf
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Project         = var.project_name
      Environment     = "evidence"
      ManagedBy       = "terraform"
      ComplianceScope = "cge-p-lab"
    }
  }
}

resource "random_id" "suffix" { byte_length = 4 }

locals {
  vault_name = "${var.project_name}-grc-evidence-vault-${random_id.suffix.hex}"
}

# SC-12: cryptographic key establishment. We own the key, not AWS.
# SC-13: cryptographic protection — CMK with annual automatic rotation.
# Key policy grants the S3 service use of the key, scoped to this account.
resource "aws_kms_key" "vault" {
  description         = "CMK for ${var.project_name} GRC evidence vault"
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableRootAccountFullAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowS3ServiceUse"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      }
    ]
  })
}

resource "aws_kms_alias" "vault" {
  name          = "alias/${var.project_name}-grc-vault"
  target_key_id = aws_kms_key.vault.id
}

resource "aws_s3_bucket" "vault" {
  bucket              = local.vault_name
  object_lock_enabled = true        # MUST be set at bucket creation
}

resource "aws_s3_bucket_versioning" "vault" {
  bucket = aws_s3_bucket.vault.id
  versioning_configuration { status = "Enabled" }   # Object Lock requires versioning
}

resource "aws_s3_bucket_object_lock_configuration" "vault" {
  bucket = aws_s3_bucket.vault.id

  rule {
    default_retention {
      mode = var.lock_mode           # GOVERNANCE for labs, COMPLIANCE for production
      days = var.retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.vault]
}

# SC-28: Protection of information at rest — customer-managed KMS key.
# CMKs give key rotation, audit trail, and separation of duties that S3-managed
# AES256 cannot. bucket_key_enabled reduces KMS request costs.
resource "aws_s3_bucket_server_side_encryption_configuration" "vault" {
  bucket = aws_s3_bucket.vault.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.vault.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "vault" {
  bucket                  = aws_s3_bucket.vault.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Refuse bucket deletion from anyone except the account root.
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "vault" {
  bucket = aws_s3_bucket.vault.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyBucketDeletion"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:DeleteBucket"
      Resource  = aws_s3_bucket.vault.arn
      Condition = {
        StringNotEquals = {
          "aws:PrincipalArn" = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
      }
    }]
  })
}