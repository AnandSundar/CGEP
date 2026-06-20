# terraform/baselines/aws/variables.tf

variable "aws_region" {
  type        = string
  description = "AWS region for the Security Hub hub and the CloudTrail bucket policy aws:SourceArn condition."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Short project identifier, used in default_tags.Project."
  default     = "cgep"
}

variable "environment" {
  type        = string
  description = "Deployment environment tag value."
  default     = "dev"
}

variable "trail_name" {
  type        = string
  description = "Name of the multi-region CloudTrail. Also used in the bucket policy aws:SourceArn condition, so changing it after apply requires re-applying the policy."
  default     = "cgep-lab-mgmt"
}
