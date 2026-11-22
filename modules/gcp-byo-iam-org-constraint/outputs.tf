output "custom_constraint_names" {
  value       = { for k, c in google_org_policy_custom_constraint.this : k => c.name }
  description = "The custom constraint names, by key: `wi` and `token`, and `storage` and `storage_admin` when `enable_storage_member_rule` is `true`"
}

output "policy_names" {
  value = merge(
    {
      wi    = google_org_policy_policy.wi.name
      token = google_org_policy_policy.token.name
    },
    { for p in google_org_policy_policy.storage : "storage" => p.name },
    { for p in google_org_policy_policy.storage_admin : "storage_admin" => p.name },
  )
  description = "The organization policy names on `policy_parent`, by key: `wi` and `token`, and `storage` and `storage_admin` when `enable_storage_member_rule` is `true`"
}

output "live_enforced" {
  value       = var.live_enforce
  description = "Whether the custom constraints are enforced live. When `false`, they are in dry-run mode only"
}

output "public_access_prevention_enforced" {
  value       = var.enforce_public_access_prevention
  description = "Whether the managed storage.publicAccessPrevention constraint is enforced on `policy_parent`"
}
