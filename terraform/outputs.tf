output "cloudfront_distribution_id" {
  description = "The id of the cloudfront distribution hosting docs."
  value       = aws_cloudfront_distribution.docs.id
}

output "docs_bucket_name" {
  description = "The name of the bucket for hosting docs."
  value       = aws_s3_bucket.docs-bucket.id
}

output "upload_role_arn" {
  description = "The ARN of a role to assume to do uploads to the doc bucket"
  value       = aws_iam_role.docs-deploy.arn
  sensitive   = true
}
