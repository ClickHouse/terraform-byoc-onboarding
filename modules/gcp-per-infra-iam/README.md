# ClickHouse BYOC GCP Onboarding — Per-Infra IAM (bring your own IAM)

This Terraform module creates the IAM of one ClickHouse BYOC infra in your GCP project: the 7 service accounts of the infra and all their grants. Use it when you bring your own IAM (BYO-IAM). ClickHouse then cannot create service accounts or custom roles, or change IAM policies in your project, except one narrow grant (the binder, see below).

Use this module together with the [`gcp`](../gcp/) onboarding module, applied with `include_iam_write_permissions = false`. See [Bring your own IAM](../gcp/README.md#bring-your-own-iam-byo-iam).

> [!IMPORTANT]
> Keep `environment = "production"` (this is the default). Do **not** change it. The other values are for internal ClickHouse use only.

> [!IMPORTANT]
> ClickHouse periodically adds identities and permissions to this module. Always use the **latest release**, and re-apply the module when ClickHouse tells you of an update. ClickHouse reads the version stamp `clickhouse-byo-iam-version=<n>` in the description of each service account, and the infra preflight fails when it is too old.

## Usage

Apply the module once for each infra, **before** ClickHouse creates the infra. ClickHouse gives you the spoken name of the infra.

```hcl
module "clickhouse_onboarding" {
  source                        = "github.com/ClickHouse/terraform-byoc-onboarding.git//modules/gcp?ref=<version>"
  project_id                    = "replace-with-your-clickhouse-byoc-project-id"
  include_iam_write_permissions = false
}

module "clickhouse_per_infra_iam" {
  source = "github.com/ClickHouse/terraform-byoc-onboarding.git//modules/gcp-per-infra-iam?ref=<version>"

  project_id  = "replace-with-your-clickhouse-byoc-project-id"
  spoken_name = "<spoken-name-provided-by-clickhouse>"
  region      = "us-east1"

  depends_on = [module.clickhouse_onboarding]
}
```

Replace `<version>` with the latest tag from the module's [releases page](https://github.com/ClickHouse/terraform-byoc-onboarding/releases).

The roles that this module binds (`clickhouseDpMgmtRole`, `clickhouseDpMgmtBucketRole`, `clickhouseBucketReaderRole`, `clickhouseWorkloadIdentityBinderRole`) are defined by the `gcp` module. Apply the `gcp` module first.

## What the module creates

| Service account | Used by | Grants |
|-----------------|---------|--------|
| `<spoken>-clickhouse` | ClickHouse server | `roles/storage.objectUser` and `clickhouseBucketReaderRole` (`storage.buckets.get`) on the instance buckets of the infra (name prefix condition). `roles/cloudkms.cryptoKeyDecrypter` on the named collections key. Token creator on `<spoken>-tde-delegate` |
| `<spoken>-scraper` | ClickHouse scraper | None in your project |
| `<spoken>-kmf` | Kube metric forwarder (autoscaling) | None in your project |
| `<spoken>-gke-node` | GKE nodes | `roles/container.defaultNodeServiceAccount` on the project |
| `<spoken>-monitoring` | Thanos and Prometheus | `roles/storage.objectAdmin` on the monitoring bucket of the infra only (bucket name condition) |
| `<spoken>-dp-mgmt` | ClickHouse data plane management | `clickhouseDpMgmtRole` on the project. `clickhouseDpMgmtBucketRole` on the instance buckets of the infra (name prefix condition). `roles/cloudkms.cryptoKeyEncrypter` on the named collections key. Token creator on `<spoken>-tde-delegate` |
| `<spoken>-tde-delegate` | BYOC+TDE | `roles/cloudkms.cryptoKeyEncrypterDecrypter` and `roles/cloudkms.viewer` on the TDE key of the infra only (key name condition) |

The module also grants:

- `roles/iam.serviceAccountTokenCreator` on `<spoken>-dp-mgmt` to the ClickHouse data plane management identities of `environment`. This is how ClickHouse acts as `<spoken>-dp-mgmt`.
- `roles/container.clusterViewer` on the project to the ClickHouse data plane management and ArgoCD identities. They connect to the GKE control plane over the DNS-based endpoint.

The module has no feature toggles. It always creates all service accounts and grants. A service account that is not used, or a grant on a key that does not exist, gives no access.

### Bucket names

ClickHouse names the instance buckets of a BYO-IAM infra with a prefix token: the first 5 hex characters of `sha256(spoken_name)`. The grants above use this token in an IAM Condition, so they apply only to the buckets of this infra. The `bucket_token` output shows the value.

### The binder: the one IAM write that ClickHouse keeps

A Workload Identity member names a Kubernetes service account in the GKE cluster of the infra. The cluster does not exist when you apply this module, and ClickHouse adds one member for each ClickHouse instance. So ClickHouse keeps `clickhouseWorkloadIdentityBinderRole` (`iam.serviceAccounts.get`, `getIamPolicy`, `setIamPolicy`) on these 4 service accounts only, never on the project:

| Service account | Grantee |
|-----------------|---------|
| `<spoken>-clickhouse` | `<spoken>-dp-mgmt` |
| `<spoken>-scraper` | `clickhouse-management` |
| `<spoken>-kmf` | `clickhouse-management` |
| `<spoken>-monitoring` | `clickhouse-management` |

GCP IAM cannot limit which member the binder adds. We recommend the organization policy `iam.disableServiceAccountKeyCreation` on the project.

### Restore from another infra

To restore backups of another BYOC infra in the same project, add its spoken name to `restore_source_spoken_names`. The ClickHouse server of this infra then gets read access (`roles/storage.objectViewer` and `clickhouseBucketReaderRole`) to the buckets of that infra.

### Terminate an infra

Tell ClickHouse to terminate the infra first. Then destroy this module for that infra. ClickHouse never deletes the service accounts that you create.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_id | The ID of the GCP project that is dedicated to ClickHouse BYOC | `string` | n/a | yes |
| spoken_name | The spoken name of the BYOC infra, provided by ClickHouse. At most 17 characters | `string` | n/a | yes |
| region | The GCP region of the BYOC infra | `string` | n/a | yes |
| environment | Environment. Leave at `production` | `string` | `production` | no |
| restore_source_spoken_names | Spoken names of other BYOC infras in this project whose backups this infra can restore | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| service_account_emails | The emails of the 7 service accounts of the infra, by purpose |
| bucket_token | The name prefix of the instance buckets of the infra |
| byo_iam_version | The version of this module's IAM contract |

## Requirements

| Name | Version |
|------|---------|
| terraform | >=1.3 |
| google provider | >=6.38.0, <8 |

## AWS equivalent

This module is the GCP form of [`aws-per-infra-iam`](../aws-per-infra-iam/).

| `aws-per-infra-iam` | `gcp-per-infra-iam` |
|---------------------|---------------------|
| `spoken_name` | `spoken_name` |
| `region` | `region` |
| `byoc_env` | `environment` |
| `external_id` | none: ClickHouse acts as `<spoken>-dp-mgmt` by service account impersonation |
| `permissions_boundary` | none: use a principal access boundary or a deny policy at organization level if you need one |
| (account from the provider) | `project_id` |
| none | `restore_source_spoken_names` |
