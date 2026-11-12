output "service_account_emails" {
  value       = { for k, sa in google_service_account.this : k => sa.email }
  description = "The emails of the 7 service accounts of the infra, by purpose."
}

output "bucket_token" {
  value       = local.bucket_token
  description = "The name prefix of the instance buckets of the infra. ClickHouse computes the same value."
}

output "byo_iam_version" {
  value       = local.byo_iam_version
  description = "The version of this module's IAM contract, also written in the description of each service account."
}
