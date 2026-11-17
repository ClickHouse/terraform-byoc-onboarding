output "custom_constraint_names" {
  value       = { for k, c in google_org_policy_custom_constraint.this : k => c.name }
  description = "The custom constraint names, by key: `wi`, and `storage` and `storage_admin` when `enable_storage_member_rule` is `true`"
}

output "policy_names" {
  value       = { for k, p in google_org_policy_policy.this : k => p.name }
  description = "The organization policy names on `policy_parent`, by key"
}

output "live_enforced" {
  value       = var.live_enforce
  description = "Whether the custom constraints are enforced live. When `false`, they are in dry-run mode only"
}

output "public_access_prevention_enforced" {
  value       = var.enforce_public_access_prevention
  description = "Whether the managed storage.publicAccessPrevention constraint is enforced on `policy_parent`"
}
