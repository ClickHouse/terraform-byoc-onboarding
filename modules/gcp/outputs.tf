output "clickhouse_management_sa_name" {
  value       = google_service_account.clickhouse_management_sa.name
  description = "The name of the ClickHouse Management Service Account"
}

output "clickhouse_management_sa_roles" {
  value = concat(
    [for role_assignment in google_project_iam_member.clickhouse_sa_roles : role_assignment.role],
    [google_project_iam_member.clickhouse_sa_storage_objects_role.role],
  )
  description = "List of role IDs assigned to the ClickHouse Management Service Account, including clickhouseStorageObjectsRole, which is conditioned on ClickHouse-managed monitoring buckets"
}

output "shared_vpc_enabled" {
  value       = local.shared_vpc
  description = "Whether Shared VPC host-project resources were provisioned (true when shared_vpc_host_project_id is set)"
}

output "shared_vpc_host_role" {
  value       = one(google_project_iam_custom_role.clickhouse_shared_vpc_host_role[*].id)
  description = "The ID of the ClickHouse Shared VPC host role granted in the host project, or null when Shared VPC is not used"
}

output "gke_service_agent_member" {
  value       = local.shared_vpc ? local.gke_service_agent_member : null
  description = "The service project's GKE service agent granted access to the Shared VPC host project, or null when Shared VPC is not used"
}

output "gke_shared_vpc_firewall_role" {
  value       = one(google_project_iam_custom_role.clickhouse_gke_shared_vpc_firewall_role[*].id)
  description = "The ID of the firewall role granted to the GKE service agent in the host project, or null when Shared VPC is not used"
}
