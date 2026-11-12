locals {
  # Increase when this module adds an identity or a permission. ClickHouse reads the stamp from the
  # description of each service account and fails the preflight when it is lower than required.
  byo_iam_version = 1
  version_stamp   = "clickhouse-byo-iam-version=${local.byo_iam_version}"

  # Buckets that ClickHouse creates for the instances of this infra start with this prefix:
  # ch_<spoken>_<region>_. data-plane-management computes the same value. Underscores cannot
  # appear in a spoken name, so a spoken name that is a prefix of another does not match.
  bucket_prefix = "ch_${var.spoken_name}_${var.region}_"

  # Roles defined by the gcp onboarding module (modules/gcp). The IDs are a contract.
  dp_mgmt_role                  = "projects/${var.project_id}/roles/clickhouseDpMgmtRole"
  dp_mgmt_bucket_role           = "projects/${var.project_id}/roles/clickhouseDpMgmtBucketRole"
  bucket_reader_role            = "projects/${var.project_id}/roles/clickhouseBucketReaderRole"
  workload_identity_binder_role = "projects/${var.project_id}/roles/clickhouseWorkloadIdentityBinderRole"

  clickhouse_management_member = "serviceAccount:clickhouse-management@${var.project_id}.iam.gserviceaccount.com"

  # ClickHouse management cells of each environment. data-plane-management impersonates the
  # dp-mgmt service account of the infra as the gke-mgmt identity of its cell. ArgoCD reaches the
  # GKE cluster as the byoc-argocd identity of its cell.
  mgmt_cells = {
    "production"  = ["asia-ne1", "asia-southeast1", "europe-west4", "us-central1", "us-east1"]
    "staging"     = ["us-central1"]
    "development" = ["us-east1"]
  }
  mgmt_project = "dataplane-${var.environment}"

  dp_management_members = [
    for cell in local.mgmt_cells[var.environment] : "serviceAccount:${cell}-gke-mgmt@${local.mgmt_project}.iam.gserviceaccount.com"
  ]
  argocd_members = [
    for cell in local.mgmt_cells[var.environment] : "serviceAccount:${cell}-byoc-argocd@${local.mgmt_project}.iam.gserviceaccount.com"
  ]

  service_accounts = {
    clickhouse = {
      account_id   = "${var.spoken_name}-clickhouse"
      display_name = "ClickHouse server, ${var.spoken_name}"
    }
    scraper = {
      account_id   = "${var.spoken_name}-scraper"
      display_name = "ClickHouse scraper, ${var.spoken_name}"
    }
    kmf = {
      account_id   = "${var.spoken_name}-kmf"
      display_name = "ClickHouse kube metric forwarder, ${var.spoken_name}"
    }
    gke_node = {
      account_id   = "${var.spoken_name}-gke-node"
      display_name = "ClickHouse GKE nodes, ${var.spoken_name}"
    }
    monitoring = {
      account_id   = "${var.spoken_name}-monitoring"
      display_name = "ClickHouse monitoring, ${var.spoken_name}"
    }
    dp_mgmt = {
      account_id   = "${var.spoken_name}-dp-mgmt"
      display_name = "ClickHouse data plane management, ${var.spoken_name}"
    }
    tde_delegate = {
      account_id   = "${var.spoken_name}-tde-delegate"
      display_name = "ClickHouse BYOC+TDE delegate, ${var.spoken_name}"
    }
  }

  # The binder role lets ClickHouse add Workload Identity members on these service accounts only.
  # data-plane-management adds one member per ClickHouse instance on <spoken>-clickhouse, as the
  # dp-mgmt service account. Crossplane adds the static members of the other 3, as
  # clickhouse-management.
  binder_grants = {
    clickhouse = "serviceAccount:${var.spoken_name}-dp-mgmt@${var.project_id}.iam.gserviceaccount.com"
    scraper    = local.clickhouse_management_member
    kmf        = local.clickhouse_management_member
    monitoring = local.clickhouse_management_member
  }

  # IAM Conditions. Bucket access is checked on projects/_/buckets/<bucket> and on
  # projects/_/buckets/<bucket>/objects/<object>, so a prefix on the bucket name matches both.
  bucket_prefix_condition = "resource.name.startsWith(\"projects/_/buckets/${local.bucket_prefix}\")"

  # The monitoring bucket is <spoken>_<region-short>_gcp_clickhouse_cloud-monitoring. Spoken names
  # have no underscore, so the <spoken>_ prefix matches the buckets of this infra only.
  monitoring_bucket_prefix = "${var.spoken_name}_"
  monitoring_bucket_suffix = "_gcp_clickhouse_cloud-monitoring"
  monitoring_bucket_condition = join(" || ", [
    "(resource.name.startsWith(\"projects/_/buckets/${local.monitoring_bucket_prefix}\") && resource.name.extract(\"projects/_/buckets/{bucket}/objects/\") == \"\" && resource.name.endsWith(\"${local.monitoring_bucket_suffix}\"))",
    "(resource.name.extract(\"projects/_/buckets/{bucket}/objects/\").startsWith(\"${local.monitoring_bucket_prefix}\") && resource.name.extract(\"projects/_/buckets/{bucket}/objects/\").endsWith(\"${local.monitoring_bucket_suffix}\"))",
  ])

  # Cloud KMS keys that ClickHouse creates for the infra (BYOC+TDE and secure named collections).
  # The grants exist before the keys, and give no access while a key does not exist.
  key_ring_prefix   = "projects/${var.project_id}/locations/${var.region}/keyRings/${var.spoken_name}"
  tde_kek_name      = "${local.key_ring_prefix}-tde/cryptoKeys/tde-default-kek"
  snc_kek_name      = "${local.key_ring_prefix}-snc/cryptoKeys/snc-kek"
  tde_kek_condition = "resource.name == \"${local.tde_kek_name}\" || resource.name.startsWith(\"${local.tde_kek_name}/\")"
  snc_kek_condition = "resource.name == \"${local.snc_kek_name}\" || resource.name.startsWith(\"${local.snc_kek_name}/\")"

  # Restore sources have no region input, so the prefix is ch_<source-spoken>_ and covers every
  # region of that spoken name in the project. The trailing underscore still stops a prefix clash.
  restore_sources = {
    for name in var.restore_source_spoken_names : name => "ch_${name}_"
  }
}
