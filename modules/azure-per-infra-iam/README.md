# ClickHouse BYOC Azure Onboarding — Per-Infra IAM

This Terraform module creates the IAM resources of 1 ClickHouse BYOC infra in your Azure subscription. Use it for bring-your-own-IAM (BYO-IAM) onboarding. It creates the managed identities, the custom role definitions and the role assignments that ClickHouse otherwise creates when it provisions the infra.

Use this module together with the [`azure`](../azure/) onboarding module, applied with `include_iam_write_permissions = false`. See [Bring your own IAM](../azure/README.md#bring-your-own-iam-byo-iam) for the permissions that ClickHouse keeps.

> [!IMPORTANT]
> Apply this module **before** ClickHouse creates the infra. ClickHouse finds the resources by name. Do not rename them.

> [!IMPORTANT]
> ClickHouse can add identities and permissions to this module in a new release. Always use the **latest release**. Apply the module again when ClickHouse tells you about an update. If you do not, provisioning and upgrades of the infra can fail.

## Usage

```hcl
provider "azurerm" {
  resource_provider_registrations = "none"

  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
  features {}
}

module "clickhouse_per_infra_iam" {
  source = "github.com/ClickHouse/terraform-byoc-onboarding.git//modules/azure-per-infra-iam?ref=<version>"

  # Required — provided by ClickHouse
  spoken_name = "<spoken-name-provided-by-clickhouse>"
  region      = "eastus2"
}

output "data_plane_management_identity_client_id" {
  value = module.clickhouse_per_infra_iam.data_plane_management_identity_client_id
}
```

Replace `<version>` with the latest tag from the module's
[releases page](https://github.com/ClickHouse/terraform-byoc-onboarding/releases)
— always use the latest release.

Send the `data_plane_management_identity_client_id` output to ClickHouse.

## What the module creates

The module creates the 2 resource groups of the infra, because the identities and the role assignment scopes are in them. ClickHouse creates all other infra resources in these resource groups.

| Identity | Role | Scope |
|----------|------|-------|
| `<spoken_name>-data-plane-mgmt` | Storage Account Contributor | `clickhouse-cloud-<spoken_name>-storage` |
| `<spoken_name>-data-plane-mgmt` | Storage Blob Data Contributor | `clickhouse-cloud-<spoken_name>-storage` |
| `<spoken_name>-data-plane-mgmt` | Managed Identity Contributor | `clickhouse-cloud-<spoken_name>-default` |
| `<spoken_name>-data-plane-mgmt` | `<spoken_name>-data-plane-mgmt-pls-reader` (custom) | `clickhouse-cloud-<spoken_name>-default` |
| `<spoken_name>-clickhouse-byoc` | `<spoken_name>-clickhouse-byoc` (custom, blob data access) | `clickhouse-cloud-<spoken_name>-storage` |
| `<spoken_name>-monitoring` | `<spoken_name>-monitoring` (custom, blob data access) | `clickhouse-cloud-<spoken_name>-storage` |
| `<spoken_name>-tde-delegate` (only if `include_tde = true`) | None. ClickHouse assigns Key Vault Crypto User on the TDE vault | — |

All identities are in the `clickhouse-cloud-<spoken_name>-default` resource group.

The module does not create these resources, because they depend on resources that ClickHouse creates during provisioning:

- The federated identity credentials on the identities. Their issuer is the OIDC issuer of the AKS cluster, or of the ClickHouse management cluster.
- The Entra application and service principal of the AKS cluster, and its Network Contributor role assignment.
- The Azure Kubernetes Service Cluster Admin Role assignment of `<spoken_name>-data-plane-mgmt` on the AKS cluster.
- The Key Vault Crypto User role assignments on the TDE and named-collections key vaults.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| spoken_name | The spoken name of the BYOC infra, provided by ClickHouse | string | n/a | yes |
| region | The Azure region (location) of the BYOC infra, for example `eastus2` | string | n/a | yes |
| include_tde | Whether to create the BYOC+TDE delegate identity. Set to `true` before you enable TDE for the infra, together with `include_tde_permissions` on the onboarding module | bool | `false` | no |
| tags | Tags to add to every resource that this module creates | map(string) | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| data_plane_management_identity_client_id | Client ID of the data-plane-mgmt identity. Send it to ClickHouse |
| clickhouse_identity_client_id | Client ID of the identity of the ClickHouse pods |
| monitoring_identity_client_id | Client ID of the monitoring identity |
| tde_delegate_identity_client_id | Client ID of the TDE delegate identity, or `null` when `include_tde` is `false` |
| default_resource_group_name | Name of the default resource group of the infra |
| storage_resource_group_name | Name of the storage resource group of the infra |

## Requirements

| Name | Version |
|------|---------|
| terraform | >=1.3 |
| azurerm provider | >=3.0 |
