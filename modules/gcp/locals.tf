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
