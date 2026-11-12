# Bring your own IAM (BYO-IAM). These roles are created in both modes and grant nothing alone.
# Only the gcp-per-infra-iam module binds them, to the service accounts of one BYOC infra, so the
# role IDs below are a contract with that module. Do not rename them.

# Project-level permissions of the per-infra data-plane-management service account
# (<spoken>-dp-mgmt). Bound at project level, without a condition.
resource "google_project_iam_custom_role" "clickhouse_dp_mgmt_role" {
  role_id     = "clickhouseDpMgmtRole"
  title       = "ClickHouse Data Plane Management Role"
  description = "Project-level permissions of the ClickHouse data plane management service account of a BYOC infra. Holds no permission to grant roles. Bound by the gcp-per-infra-iam module."
  permissions = [
    # Status reads of the private load balancer forwarding rule (PrivateLink).
    "compute.forwardingRules.get",

    # GKE cluster and node pool reads, and the GKE DNS-based control plane endpoint.
    "container.clusters.get",
    "container.clusters.connect",

    # Bucket create is checked on the project, so an IAM Condition on the bucket name cannot
    # limit it. List is used by the cleaner, by label.
    "storage.buckets.create",
    "storage.buckets.list",

    # Service account reads.
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.list",
  ]
}

# Bucket-level permissions of the per-infra data-plane-management service account. The
# gcp-per-infra-iam module binds it at project level with an IAM Condition on the bucket name
# prefix of the infra, so it applies only to the buckets of that infra.
resource "google_project_iam_custom_role" "clickhouse_dp_mgmt_bucket_role" {
  role_id     = "clickhouseDpMgmtBucketRole"
  title       = "ClickHouse Data Plane Management Bucket Role"
  description = "Bucket permissions of the ClickHouse data plane management service account of a BYOC infra, bound with a condition on the bucket name prefix of the infra. Holds no permission to grant roles. Bound by the gcp-per-infra-iam module."
  permissions = [
    "storage.buckets.get",
    "storage.buckets.update",
    "storage.buckets.delete",
    "storage.objects.list",
    "storage.objects.delete",
  ]
}

# The one IAM write that ClickHouse keeps when you bring your own IAM. The gcp-per-infra-iam
# module grants it on 4 service accounts of the infra only, never at project level. ClickHouse
# uses it to add Workload Identity members, which name Kubernetes service accounts in a GKE
# cluster that does not exist when you apply the module.
resource "google_project_iam_custom_role" "clickhouse_workload_identity_binder_role" {
  role_id     = "clickhouseWorkloadIdentityBinderRole"
  title       = "ClickHouse Workload Identity Binder Role"
  description = "Lets ClickHouse add Workload Identity members on a service account of a BYOC infra. Granted on single service accounts by the gcp-per-infra-iam module."
  permissions = [
    "iam.serviceAccounts.get",
    "iam.serviceAccounts.getIamPolicy",
    "iam.serviceAccounts.setIamPolicy",
  ]
}
