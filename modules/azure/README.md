# ClickHouse BYOC Azure Onboarding Terraform Module

This repository contains Terraform module to bootstrap a BYOC Azure tenant & subscription for ClickHouse Cloud.

In accordance with Azure guidance for cross-tenant authentication, the module provisions the multitenant application as an Enterprise Application (service principal) in the target tenant and assigns it the required permissions scoped to the target subscription. This allows the ClickHouse provisioner to create Azure resources in the target subscription.

## Usage

```hcl
terraform {
  required_providers {
    azuread = {
      source = "hashicorp/azuread"
    }
    azurerm = {
      source = "hashicorp/azurerm"
    }
  }
}

variable "tenant_id" {
  type        = string
  description = "The Azure tenant ID"
}

variable "subscription_id" {
  type        = string
  description = "The Azure subscription ID to onboard"
}

provider "azuread" {
  tenant_id = var.tenant_id
}

provider "azurerm" {
  resource_provider_registrations = "none"

  tenant_id       = var.tenant_id
  subscription_id = var.subscription_id
  features {}
}

module "clickhouse_onboarding" {
  source = "github.com/ClickHouse/terraform-byoc-onboarding.git//modules/azure?ref=<version>"
}

output "tenant_id" {
  value = module.clickhouse_onboarding.tenant_id
}

output "subscription_id" {
  value = module.clickhouse_onboarding.subscription_id
}

output "service_principal_client_id" {
  value = module.clickhouse_onboarding.service_principal_client_id
}
```

Replace `<version>` with the latest tag from the module's
[releases page](https://github.com/ClickHouse/terraform-byoc-onboarding/releases)
— always use the latest release.

## Role assignments ClickHouse can make

ClickHouse creates a few managed identities per infra and assigns them roles on the infra's own resource groups, AKS cluster and Key Vaults. The module does not let ClickHouse create or change role definitions: the two custom roles ClickHouse assigns are created here. Role assignment rights sit in a separate role, `ClickHouse BYOC Role Assignments`, whose assignment carries an [Azure ABAC condition](https://learn.microsoft.com/en-us/azure/role-based-access-control/delegate-role-assignments-overview):

- **Create:** only these roles, and never to the ClickHouse service principal itself:
  - Network Contributor
  - Azure Kubernetes Service Cluster Admin Role
  - Storage Account Contributor
  - Storage Blob Data Contributor
  - Managed Identity Contributor
  - Key Vault Crypto User
  - ClickHouse BYOC Storage Data
  - ClickHouse BYOC Private Link Approver
- **Delete:** any assignment except Owner, Contributor, User Access Administrator and Role Based Access Control Administrator. This lets ClickHouse remove the assignments it made when it tears an infra down, including those of infras created with earlier module versions.

Azure conditions cannot restrict where an assignment is made, so we recommend a subscription dedicated to ClickHouse BYOC.

## Upgrading from v2.x

Applying this version updates the `ClickHouse BYOC Provisioner` role in place and adds the role assignment role, its conditioned assignment and the two custom roles. The service principal and its Microsoft Graph permission do not change. Infras created with v2.x keep working: their role assignments and per-infra role definitions stay in place, and ClickHouse can still tear them down.

The provisioner role loses these actions:

- `Microsoft.Authorization/roleDefinitions/write` and unconditioned `roleAssignments/write` and `roleAssignments/delete`
- `Microsoft.ManagedIdentity/userAssignedIdentities/assign/action`
- `Microsoft.Network/dnszones/*`: ClickHouse manages BYOC DNS outside your subscription
- `Microsoft.Storage/storageAccounts/delete` and `blobServices/containers/delete`: ClickHouse leaves storage in place on teardown

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | (Optional) Environment. Default is `production`. The other values are reserved for internal use" | string | production | no |
| include_tde_permissions | (Optional) Whether to let ClickHouse provision the BYOC+TDE shared resources in this subscription: one TDE delegate managed identity and one default Key Vault + RSA key (KEK) per infra. Grants no vault/key delete or purge and no cryptographic use of the keys — ClickHouse can never destroy or use your key material with this role. Set to `true` before enabling TDE for an infra | bool | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| tenant_id | The Azure AD tenant ID |
| subscription_id | The Azure subscription ID |
| service_principal_client_id | The application (client) ID of the service principal |

## Resources

| Name | Description |
|------|------|
| azuread_service_principal.this | Service Principal for ClickHouse BYOC application |
| azurerm_role_definition.clickhouse_byoc_provisioner | Custom role for ClickHouse to provision Azure BYOC infrastructure resources; holds no permission to create role definitions or role assignments |
| azurerm_role_assignment.this | Assigns 'ClickHouse BYOC Provisioner' role to the service principal |
| azurerm_role_definition.clickhouse_byoc_role_assignments | Custom role holding `roleAssignments/write` and `roleAssignments/delete` |
| azurerm_role_assignment.role_assignments | Assigns 'ClickHouse BYOC Role Assignments' to the service principal with a condition that limits which roles it can assign (see below) |
| azurerm_role_definition.clickhouse_byoc_storage_data | Custom role ClickHouse assigns to its own per-infra identities for blob read/write on the infra's storage resource group |
| azurerm_role_definition.clickhouse_byoc_private_link_approver | Custom role ClickHouse assigns to its own per-infra management identity to read its Private Link Services and approve their private endpoint connections |
| azuread_app_role_assignment.graph_permissions["Application.ReadWrite.OwnedBy"] | Grants Application.ReadWrite.OwnedBy Microsoft Graph permission |

## Requirements

| Name | Version |
|------|---------|
| terraform | >=1.3 |
| azuread provider | >=2.0 |
| azurerm provider | >=3.0 |
