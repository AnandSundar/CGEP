# terraform/baselines/aws/outputs.tf

output "cloudtrail_arn" {
  description = "ARN of the new multi-region CloudTrail."
  value       = aws_cloudtrail.mgmt.arn
}

output "cloudtrail_name" {
  description = "Name of the new multi-region CloudTrail."
  value       = aws_cloudtrail.mgmt.name
}

output "trail_bucket" {
  description = "S3 bucket that receives CloudTrail log files."
  value       = aws_s3_bucket.trail.bucket
}

output "security_hub_arn" {
  description = "ARN of the Security Hub hub (us-east-1 default hub for the account)."
  value       = aws_securityhub_account.this.arn
}
