# Create Clickhouse Management SA
resource "google_service_account" "clickhouse_management_sa" {
  account_id   = "clickhouse-management"
  display_name = "ClickHouse Management Service Account"
  description  = "Service account for ClickHouse Management"
}

# Make sure that Cloud Resource Manager is enabled
resource "google_project_service" "cloud_resource_manager" {
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}

# Enable the Service Usage API. Terraform itself does not need this enabled here
# (it calls Service Usage under your own credentials and quota project), but the
# ClickHouse onboarding validator does: it impersonates the management SA below
# with this project as the API consumer, so reading which APIs are enabled fails
# with SERVICE_DISABLED unless Service Usage is enabled in this project. Without
# it every API-enablement preflight check reports a false failure.
resource "google_project_service" "service_usage" {
  service            = "serviceusage.googleapis.com"
  disable_on_destroy = false
}

# Enable Compute Engine API
resource "google_project_service" "compute_engine" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

# Enable Network Connectivity API
resource "google_project_service" "network_connectivity_api" {
  service            = "networkconnectivity.googleapis.com"
  disable_on_destroy = false
}

# Enable Identity and Access Management (IAM) API
resource "google_project_service" "iam_api" {
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

# Enable Kubernetes Engine API
resource "google_project_service" "container_api" {
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

# Enable Cloud KMS API — only when BYOC+TDE is enabled, since that is the only ClickHouse
# feature that provisions KMS resources in this project.
resource "google_project_service" "cloudkms_api" {
  count              = var.include_tde_permissions ? 1 : 0
  service            = "cloudkms.googleapis.com"
  disable_on_destroy = false
}

# Grant IAM roles to ClickHouse Management SA
resource "google_project_iam_member" "clickhouse_sa_roles" {
  for_each = local.clickhouse_custom_roles

  depends_on = [google_project_service.cloud_resource_manager]
  project    = var.project_id
  role       = each.value
  member     = google_service_account.clickhouse_management_sa.member
}

resource "google_project_iam_member" "clickhouse_sa_storage_objects_role" {
  depends_on = [google_project_service.cloud_resource_manager]
  project    = var.project_id
  role       = google_project_iam_custom_role.clickhouse_storage_objects_role.id
  member     = google_service_account.clickhouse_management_sa.member

  condition {
    title       = "clickhouse-monitoring-buckets-only"
    description = "Object access limited to ClickHouse-managed monitoring buckets (infra-*/testinfra-* ending in ${local.clickhouse_monitoring_bucket_suffix})"
    expression  = local.clickhouse_storage_objects_condition
  }
}

# Allow Crossplane to impersonate ClickHouse Management SA
resource "google_service_account_iam_binding" "impersonation_binding" {
  service_account_id = google_service_account.clickhouse_management_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  members            = local.clickhouse_crossplane_sa_map[var.environment]
}
