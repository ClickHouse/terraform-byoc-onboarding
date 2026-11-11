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

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| environment | (Optional) Environment. Default is `production`. The other values are reserved for internal use" | string | production | no |
| include_vpc_write_permissions | (Optional) Whether to let ClickHouse create and delete the virtual network, its subnets and the NAT egress path (public IPs and NAT gateways). Set to `false` when you bring your own virtual network (BYO-VPC); ClickHouse then only reads it and joins its subnets | bool | `true` | no |
| include_iam_write_permissions | (Optional) Whether to let ClickHouse create and delete the per-infra managed identities, custom role definitions and role assignments. Set to `false` when you bring your own IAM (BYO-IAM). See [Bring your own IAM](#bring-your-own-iam-byo-iam) | bool | `true` | no |
| include_tde_permissions | (Optional) Whether to let ClickHouse provision the BYOC+TDE shared resources in this subscription: one TDE delegate managed identity and one default Key Vault + RSA key (KEK) per infra. Grants no vault/key delete or purge and no cryptographic use of the keys — ClickHouse can never destroy or use your key material with this role. Set to `true` before enabling TDE for an infra | bool | `false` | no |

## Bring your own IAM (BYO-IAM)

With the default `include_iam_write_permissions = true`, ClickHouse creates the managed identities, custom role definitions and role assignments of each BYOC infra. To keep these in your control, do these steps:

1. Set `include_iam_write_permissions = false` on this module.
2. Apply the [`azure-per-infra-iam`](../azure-per-infra-iam/) module for each infra, before ClickHouse creates the infra.
3. Send the `data_plane_management_identity_client_id` output of that module to ClickHouse.

With `include_iam_write_permissions = false`, the provisioner role does not get these actions:

- `Microsoft.ManagedIdentity/userAssignedIdentities/write` and `/delete`
- `Microsoft.Authorization/roleDefinitions/write` and `/delete`
- `Microsoft.Authorization/roleAssignments/write` and `/delete`

ClickHouse keeps these actions in both modes:

- Read access to managed identities, role definitions and role assignments.
- `Microsoft.ManagedIdentity/userAssignedIdentities/assign/action`.
- Read, write and delete of federated identity credentials. Each credential binds 1 of your identities to a Kubernetes service account. The issuer of most credentials is the AKS cluster that ClickHouse creates, so you cannot create them in advance. ClickHouse also adds 1 credential for each ClickHouse instance.

Some role assignments have a scope or a principal that ClickHouse creates during provisioning. For these, the module adds the `ClickHouse BYOC Role Assignment Delegate` role. An [ABAC condition](https://learn.microsoft.com/en-us/azure/role-based-access-control/delegate-role-assignments-overview) on that assignment lets ClickHouse create and delete role assignments only for these built-in roles:

| Role | Principal | Scope |
|------|-----------|-------|
| Network Contributor | The AKS cluster service principal | The infra's default resource group |
| Azure Kubernetes Service Cluster Admin Role | The data-plane-mgmt identity | The AKS cluster |
| Key Vault Crypto User | The TDE delegate, data-plane-mgmt and ClickHouse pod identities | The TDE and named-collections key vaults |

ClickHouse cannot assign any other role, so it cannot grant Owner, Contributor, User Access Administrator or a custom role. The condition does not limit the scope or the principal of these 3 roles. The role assignment is at subscription scope, because the infra resource groups do not exist when you apply this module.

The Microsoft Graph permission `Application.ReadWrite.OwnedBy` stays in both modes. ClickHouse uses it to create the Entra application of the AKS cluster. The application is multitenant, because the cluster also uses it to pull images from the ClickHouse container registry.

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
| azurerm_role_definition.clickhouse_byoc_provisioner | Custom role for ClickHouse to provision Azure BYOC infrastructure resources |
| azurerm_role_assignment.this | Assigns 'ClickHouse BYOC Provisioner' role to the service principal |
| azuread_app_role_assignment.graph_permissions["Application.ReadWrite.OwnedBy"] | Grants Application.ReadWrite.OwnedBy Microsoft Graph permission |
| azurerm_role_definition.clickhouse_byoc_role_assignment_delegate | BYO-IAM only. Custom role with the role assignment actions |
| azurerm_role_assignment.role_assignment_delegate | BYO-IAM only. Assigns the delegate role to the service principal, with a condition that allows only the built-in roles listed in [Bring your own IAM](#bring-your-own-iam-byo-iam) |

## Requirements

| Name | Version |
|------|---------|
| terraform | >=1.3 |
| azuread provider | >=2.0 |
| azurerm provider | >=3.0 |
