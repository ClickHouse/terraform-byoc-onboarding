locals {
  clickhouse_custom_roles = merge(
    {
      common_role  = google_project_iam_custom_role.clickhouse_common_role.id
      vpc_role     = google_project_iam_custom_role.clickhouse_vpc_role.id
      cluster_role = google_project_iam_custom_role.clickhouse_cluster_role.id
      storage_role = google_project_iam_custom_role.clickhouse_storage_role.id
      iam_role     = google_project_iam_custom_role.clickhouse_iam_role.id
    },
    var.include_vpc_write_permissions ? {
      vpc_write_role = google_project_iam_custom_role.clickhouse_vpc_write_role[0].id
    } : {},
    var.include_tde_permissions ? {
      tde_role = google_project_iam_custom_role.clickhouse_tde_role[0].id
    } : {},
  )

  # Object-level access is required to tear down ClickHouse-managed buckets:
  # bucket deletion runs with force_destroy=true, which must first list and
  # delete the objects inside (e.g. the monitoring bucket's Thanos TSDB
  # blocks) before removing the bucket. Without these, bucket delete 403s and
  # the infra is stuck terminating (BYOC-768).
  clickhouse_storage_object_permissions = [
    "storage.objects.list",
    "storage.objects.get",
    "storage.objects.delete",
  ]

  # ClickHouse names every infra's monitoring bucket <infra-name>_<region-short>_gcp_clickhouse_cloud-monitoring.
  # Matching on the suffix alone covers every infra in the project, including custom-named ones,
  # without listing them.
  clickhouse_monitoring_bucket_suffix = "_gcp_clickhouse_cloud-monitoring"

  # storage.objects.list is evaluated against the bucket (projects/_/buckets/BUCKET) and
  # get/delete against each object (projects/_/buckets/BUCKET/objects/OBJECT). The bucket
  # clause must exclude object names, which could themselves end with the suffix.
  clickhouse_storage_objects_condition = join(" || ", [
    "(resource.name.startsWith(\"projects/_/buckets/\") && resource.name.extract(\"projects/_/buckets/{bucket}/objects/\") == \"\" && resource.name.endsWith(\"${local.clickhouse_monitoring_bucket_suffix}\"))",
    "resource.name.extract(\"projects/_/buckets/{bucket}/objects/\").endsWith(\"${local.clickhouse_monitoring_bucket_suffix}\")",
  ])

  # Roles ClickHouse may grant, by where it grants them. IAM Conditions cap each list at 10 roles.
  clickhouse_grantable_project_roles = [
    "roles/container.defaultNodeServiceAccount",                      # the per-infra GKE node service account
    "roles/container.clusterViewer",                                  # ClickHouse management plane, to reach the GKE cluster
    google_project_iam_custom_role.clickhouse_dp_mgmt_role.id,        # the per-infra management service account
    google_project_iam_custom_role.clickhouse_dp_mgmt_bucket_role.id, # the per-infra management service account
  ]
  clickhouse_grantable_service_account_roles = [
    "roles/iam.workloadIdentityUser",       # bind ClickHouse workloads to ClickHouse service accounts
    "roles/iam.serviceAccountTokenCreator", # ClickHouse management plane to its per-infra service accounts
  ]
  clickhouse_grantable_bucket_roles = [
    "roles/storage.objectAdmin",        # monitoring bucket: the per-infra monitoring service account
    "roles/storage.objectUser",         # instance buckets: the ClickHouse server service account
    "roles/storage.legacyBucketReader", # instance buckets: the ClickHouse server service account
    "roles/storage.objectViewer",       # instance buckets: the ClickHouse server service account, to restore from another instance's backup
    "roles/storage.admin",              # instance buckets: only to remove the grant made before ClickHouse moved to objectUser
  ]

  # ClickHouse names instance data buckets <random>_<region>_gcs_gcp_<domain> and backup buckets
  # <random>-backup_<region>_gcs_gcp_<domain>; older ones use "." instead of "_".
  clickhouse_instance_bucket_suffixes = {
    "production"  = ["_gcs_gcp_clickhouse_cloud", ".gcs.gcp.clickhouse.cloud"]
    "staging"     = ["_gcs_gcp_clickhouse-staging_com", ".gcs.gcp.clickhouse-staging.com"]
    "development" = ["_gcs_gcp_clickhouse-dev_com", ".gcs.gcp.clickhouse-dev.com"]
  }
  clickhouse_bucket_suffixes = concat(
    [local.clickhouse_monitoring_bucket_suffix],
    local.clickhouse_instance_bucket_suffixes[var.environment],
  )
  clickhouse_grantable_kms_roles = [
    "roles/cloudkms.cryptoKeyEncrypterDecrypter", # BYOC+TDE delegate
    "roles/cloudkms.viewer",                      # BYOC+TDE delegate
    "roles/cloudkms.cryptoKeyEncrypter",          # named collections, management service account
    "roles/cloudkms.cryptoKeyDecrypter",          # named collections, ClickHouse server service account
  ]

  # ClickHouse names each infra's key rings <infra-name>-tde and <infra-name>-snc, with one key each.
  clickhouse_kms_key_suffixes = [
    "-tde/cryptoKeys/tde-default-kek",
    "-snc/cryptoKeys/snc-kek",
  ]

  clickhouse_project_iam_grant_condition = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${join(", ", formatlist("'%s'", local.clickhouse_grantable_project_roles))}])"

  clickhouse_service_account_iam_grant_condition = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${join(", ", formatlist("'%s'", local.clickhouse_grantable_service_account_roles))}])"

  clickhouse_storage_iam_grant_condition = join(" && ", [
    "resource.type == 'storage.googleapis.com/Bucket'",
    "(${join(" || ", formatlist("resource.name.endsWith('%s')", local.clickhouse_bucket_suffixes))})",
    "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${join(", ", formatlist("'%s'", local.clickhouse_grantable_bucket_roles))}])",
  ])

  clickhouse_kms_iam_grant_condition = join(" && ", [
    "resource.type == 'cloudkms.googleapis.com/CryptoKey'",
    "(${join(" || ", formatlist("resource.name.endsWith('%s')", local.clickhouse_kms_key_suffixes))})",
    "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${join(", ", formatlist("'%s'", local.clickhouse_grantable_kms_roles))}])",
  ])

  clickhouse_crossplane_sa_map = {
    "production" = [
      # asia-ne1 = asia-northeast1 (Tokyo); this region's SAs use the short cell naming scheme
      "serviceAccount:asia-ne1-gke-crossplane@dataplane-production.iam.gserviceaccount.com",
      "serviceAccount:asia-southeast1-gke-crossplane@dataplane-production.iam.gserviceaccount.com",
      "serviceAccount:europe-west4-gke-crossplane@dataplane-production.iam.gserviceaccount.com",
      "serviceAccount:us-central1-gke-crossplane@dataplane-production.iam.gserviceaccount.com",
      "serviceAccount:us-east1-gke-crossplane@dataplane-production.iam.gserviceaccount.com",
    ]
    "staging" = [
      "serviceAccount:us-central1-gke-crossplane@dataplane-staging.iam.gserviceaccount.com",
    ]
    "development" = [
      "serviceAccount:us-east1-gke-crossplane@dataplane-development.iam.gserviceaccount.com",
    ]
  }
}
