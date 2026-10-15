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
