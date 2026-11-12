# Bring your own IAM (BYO-IAM) for one GCP BYOC infra. Apply once per infra, before ClickHouse
# creates the infra. The module creates the 7 service accounts of the infra and all their grants.
# It defines no custom roles: it binds the roles that the gcp onboarding module defines. Names are
# fixed: ClickHouse observes the service accounts by name.

resource "google_service_account" "this" {
  for_each = local.service_accounts

  project      = var.project_id
  account_id   = each.value.account_id
  display_name = each.value.display_name
  # ClickHouse reads the version stamp at preflight. Keep it in the description.
  description = "ClickHouse BYOC ${var.spoken_name} (${each.key}). ${local.version_stamp}"
}

# ---------------------------------------------------------------------------------------------
# Trust: the ClickHouse data plane management service impersonates <spoken>-dp-mgmt.
# ---------------------------------------------------------------------------------------------

resource "google_service_account_iam_member" "dp_mgmt_token_creator" {
  for_each = toset(local.dp_management_members)

  service_account_id = google_service_account.this["dp_mgmt"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}

# ---------------------------------------------------------------------------------------------
# Project grants.
# ---------------------------------------------------------------------------------------------

resource "google_project_iam_member" "gke_node_default_node_sa" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = google_service_account.this["gke_node"].member
}

resource "google_project_iam_member" "dp_mgmt_role" {
  project = var.project_id
  role    = local.dp_mgmt_role
  member  = google_service_account.this["dp_mgmt"].member
}

resource "google_project_iam_member" "dp_mgmt_bucket_role" {
  project = var.project_id
  role    = local.dp_mgmt_bucket_role
  member  = google_service_account.this["dp_mgmt"].member

  condition {
    title       = "clickhouse-${var.spoken_name}-buckets"
    description = "Only buckets of BYOC infra ${var.spoken_name} (prefix ${local.bucket_token})"
    expression  = local.bucket_prefix_condition
  }
}

# The ClickHouse data plane management and ArgoCD identities connect to the GKE control plane
# over the DNS-based endpoint, which needs container.clusters.connect.
resource "google_project_iam_member" "cluster_viewer" {
  for_each = toset(concat(local.dp_management_members, local.argocd_members))

  project = var.project_id
  role    = "roles/container.clusterViewer"
  member  = each.value
}

# ---------------------------------------------------------------------------------------------
# Buckets.
# ---------------------------------------------------------------------------------------------

# ClickHouse server: read and write objects in the instance buckets of this infra.
resource "google_project_iam_member" "clickhouse_buckets" {
  for_each = toset(["roles/storage.objectUser", "roles/storage.legacyBucketReader"])

  project = var.project_id
  role    = each.value
  member  = google_service_account.this["clickhouse"].member

  condition {
    title       = "clickhouse-${var.spoken_name}-buckets"
    description = "Only buckets of BYOC infra ${var.spoken_name} (prefix ${local.bucket_token})"
    expression  = local.bucket_prefix_condition
  }
}

# ClickHouse server: read the backups of other infras in this project, to restore them here.
resource "google_project_iam_member" "clickhouse_restore_sources" {
  for_each = {
    for pair in setproduct(keys(local.restore_sources), ["roles/storage.objectViewer", "roles/storage.legacyBucketReader"]) :
    "${pair[0]}/${pair[1]}" => { spoken_name = pair[0], token = local.restore_sources[pair[0]], role = pair[1] }
  }

  project = var.project_id
  role    = each.value.role
  member  = google_service_account.this["clickhouse"].member

  condition {
    title       = "clickhouse-${var.spoken_name}-restore-from-${each.value.spoken_name}"
    description = "Read only, buckets of BYOC infra ${each.value.spoken_name} (prefix ${each.value.token})"
    expression  = "resource.name.startsWith(\"projects/_/buckets/${each.value.token}\")"
  }
}

# Thanos and Prometheus: the monitoring bucket of this infra.
resource "google_project_iam_member" "monitoring_bucket" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = google_service_account.this["monitoring"].member

  condition {
    title       = "clickhouse-${var.spoken_name}-monitoring-bucket"
    description = "Only the monitoring bucket of BYOC infra ${var.spoken_name}, and its objects"
    expression  = local.monitoring_bucket_condition
  }
}

# ---------------------------------------------------------------------------------------------
# BYOC+TDE and secure named collections. ClickHouse creates the keys. The grants give no access
# while a key does not exist.
# ---------------------------------------------------------------------------------------------

# dp-mgmt impersonates the TDE delegate to wrap keys. The ClickHouse server impersonates it to
# unwrap them.
resource "google_service_account_iam_member" "tde_delegate_token_creator" {
  for_each = {
    dp_mgmt    = google_service_account.this["dp_mgmt"].member
    clickhouse = google_service_account.this["clickhouse"].member
  }

  service_account_id = google_service_account.this["tde_delegate"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}

resource "google_project_iam_member" "tde_delegate_kek" {
  for_each = toset(["roles/cloudkms.cryptoKeyEncrypterDecrypter", "roles/cloudkms.viewer"])

  project = var.project_id
  role    = each.value
  member  = google_service_account.this["tde_delegate"].member

  condition {
    title       = "clickhouse-${var.spoken_name}-tde-kek"
    description = "Only the BYOC+TDE key of BYOC infra ${var.spoken_name}"
    expression  = local.tde_kek_condition
  }
}

resource "google_project_iam_member" "snc_kek" {
  for_each = {
    dp_mgmt_encrypter    = { role = "roles/cloudkms.cryptoKeyEncrypter", member = google_service_account.this["dp_mgmt"].member }
    clickhouse_decrypter = { role = "roles/cloudkms.cryptoKeyDecrypter", member = google_service_account.this["clickhouse"].member }
  }

  project = var.project_id
  role    = each.value.role
  member  = each.value.member

  condition {
    title       = "clickhouse-${var.spoken_name}-snc-kek"
    description = "Only the named collections key of BYOC infra ${var.spoken_name}"
    expression  = local.snc_kek_condition
  }
}

# ---------------------------------------------------------------------------------------------
# Binder: the one IAM write that ClickHouse keeps. Granted on 4 service accounts, not on the
# project.
# ---------------------------------------------------------------------------------------------

resource "google_service_account_iam_member" "workload_identity_binder" {
  for_each = local.binder_grants

  service_account_id = google_service_account.this[each.key].name
  role               = local.workload_identity_binder_role
  member             = each.value
}
