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
| maintenance_mode | (Optional) Set to `true` after ClickHouse has provisioned every infra in `maintenance_infras`. ClickHouse then gets only a minimal set of roles on the resources of each infra. See [Maintenance mode](#maintenance-mode) | bool | `false` | no |
| maintenance_infras | (Optional) The spoken names of every BYOC infra in this subscription, provided by ClickHouse. Required with `maintenance_mode = true` | list(string) | `[]` | no |
| include_tde_permissions | (Optional) Whether to let ClickHouse provision the BYOC+TDE shared resources in this subscription: one TDE delegate managed identity and one default Key Vault + RSA key (KEK) per infra. Grants no vault/key delete or purge and no cryptographic use of the keys — ClickHouse can never destroy or use your key material with this role. Set to `true` before enabling TDE for an infra | bool | `false` | no |

## Maintenance mode

ClickHouse needs the full permissions of this module only to create or delete an infra, or to enable a feature on it. After that, you can limit the permissions to a minimal set to operate the infras:

1. Apply this module with the default settings.
2. Tell ClickHouse to create the infra. Wait until the infra is ready.
3. Set `maintenance_mode = true`. Set `maintenance_infras` to the spoken names of all infras in the subscription. Apply.

```hcl
module "clickhouse_onboarding" {
  source = "github.com/ClickHouse/terraform-byoc-onboarding.git//modules/azure?ref=<version>"

  maintenance_mode   = true
  maintenance_infras = ["<spoken-name-provided-by-clickhouse>"]
}
```

> [!IMPORTANT]
> Add every infra of the subscription to `maintenance_infras`. An infra that is not in the list has no permissions, and ClickHouse cannot operate it.

In maintenance mode, ClickHouse can do these operations:

- Update and upgrade the AKS cluster and its node pools, with AKS admin access.
- Add new ClickHouse services to an infra.
- Enable customer private link on an infra.
- Make the AKS API server of an infra private.

Private link and a private API server need the `pl` and `apiserver` subnets in the virtual network of the infra. Infras created since 2026-09-25 have both subnets. For an older infra, ClickHouse must add a subnet first, and maintenance mode does not allow that.

> [!IMPORTANT]
> Set `maintenance_mode = false` before you do one of these operations. Keep it until ClickHouse completes the operation:
>
> - Create a new infra in the subscription.
> - Delete an infra.
> - Enable TDE, autoscaling or named collections on an infra.
> - Add a subnet to an infra, for example the `pl` or `apiserver` subnet of an older infra.
>
> If you do not, the operation stops with authorization errors.

The plan fails if the AKS cluster, the NSG or the virtual network of an infra does not exist. Maintenance mode is not available yet with `include_iam_write_permissions = false` or `include_vpc_write_permissions = false`.

In maintenance mode, the ClickHouse BYOC Provisioner role on the subscription keeps only `Microsoft.Resources/subscriptions/providers/read`. The role assignment stays, so 1 apply with `maintenance_mode = false` adds the full permissions again.

The module assigns these roles to the ClickHouse service principal for each infra. Each role is assigned on the resources in the Scope column only. A role on a resource also applies to its child resources, for example the subnets of a virtual network or the containers of a storage account.

| Role | Scope | Actions |
|------|-------|---------|
| ClickHouse BYOC Maintenance Resource Group | `clickhouse-cloud-<spoken_name>-default` and `clickhouse-cloud-<spoken_name>-storage` | Read the resource group, role definitions and role assignments |
| ClickHouse BYOC Maintenance AKS | The AKS cluster `clickhouse-cloud-<spoken_name>` | Read and update the cluster (Kubernetes version upgrades), reset its service principal secret, get the cluster credentials, and read, create, update and delete node pools. No cluster delete |
| ClickHouse BYOC Maintenance NSG | The NSG `<spoken_name>-nsg` | Read and update the NSG, and read, create, update and delete its security rules |
| ClickHouse BYOC Maintenance Virtual Network | The virtual network `<spoken_name>` | Read the virtual network and its subnets, and join the existing subnets. No virtual network or subnet write |
| ClickHouse BYOC Maintenance Network Reader | Each NAT gateway and public IP address `<spoken_name>-<zone>` | Read |
| ClickHouse BYOC Maintenance Storage Account | Each storage account of the infra in `clickhouse-cloud-<spoken_name>-storage` | Read the account, get its keys, and read, create and update containers. No storage account or container delete |
| ClickHouse BYOC Maintenance Identity | Each managed identity `<spoken_name>-*` | Read the identity and its federated identity credentials |
| ClickHouse BYOC Maintenance Key Vault | Each key vault `<spoken_name>-*` | Read the vault and the key metadata. No cryptographic use of the keys |
| ClickHouse BYOC Maintenance Private Link Service | `clickhouse-cloud-<spoken_name>-default` | Read, create and update Private Link Services, for the private API server. The Private Link Service does not exist before ClickHouse makes the API server private, so this role is on the resource group. No delete |
| ClickHouse BYOC Maintenance Load Balancer Join | The `kube-apiserver` load balancer in `MC_<spoken_name>_<region>`, if it exists | Put a Private Link Service in front of the load balancer |

The module finds the NAT gateways, public IP addresses, identities, key vaults and storage accounts on each apply. If ClickHouse adds one of these resources while maintenance mode is off, the next apply with `maintenance_mode = true` assigns its role.

In maintenance mode, ClickHouse cannot do these operations:

- Create, change or delete resource groups, virtual networks, subnets, NAT gateways, public IP addresses, storage accounts, key vaults or AKS clusters.
- Delete any resource, except node pools and NSG rules.
- Create, change or delete managed identities, federated identity credentials, role definitions or role assignments. So ClickHouse cannot grant a role to any principal.
- Register resource providers.
- Use the keys in the key vaults for cryptographic operations.

Maintenance mode does not change the roles of the infra identities (for example `<spoken_name>-data-plane-mgmt`), which ClickHouse assigned during provisioning. It also does not change the Microsoft Graph permission `Application.ReadWrite.OwnedBy`.

## Bring your own IAM (BYO-IAM)

With the default `include_iam_write_permissions = true`, ClickHouse creates the managed identities, custom role definitions and role assignments of each BYOC infra. To keep these in your control, do these steps:

1. Set `include_iam_write_permissions = false` on this module.
2. Apply the [`azure-per-infra-iam`](../azure-per-infra-iam/) module for each infra, before ClickHouse creates the infra. Set its `onboarding` input to the `byo_iam` output of this module.
3. Send the `data_plane_management_identity_client_id` output of that module to ClickHouse.

With `include_iam_write_permissions = false`, the provisioner role does not get these actions:

- `Microsoft.ManagedIdentity/userAssignedIdentities/write` and `/delete`
- `Microsoft.Authorization/roleDefinitions/write` and `/delete`
- `Microsoft.Authorization/roleAssignments/write` and `/delete`
- `Microsoft.Resources/subscriptions/resourceGroups/write` and `/delete`. You create the resource groups of each infra with `azure-per-infra-iam`.

### Resource group scope

With BYO-IAM, the provisioner role that this module assigns on the subscription keeps only the subscription-level actions. All other provisioner actions are in the ClickHouse BYOC Resource Group Provisioner role. The `azure-per-infra-iam` module assigns that role on the 2 resource groups of each infra. So ClickHouse cannot change resources in other resource groups of the subscription.

| Role | Assigned by | Scope |
|------|-------------|-------|
| ClickHouse BYOC Resource Group Provisioner | `azure-per-infra-iam` | `clickhouse-cloud-<spoken_name>-default` and `clickhouse-cloud-<spoken_name>-storage` |
| ClickHouse BYOC Role Assignment Delegate | `azure-per-infra-iam` | `clickhouse-cloud-<spoken_name>-default` |
| ClickHouse BYOC Network User (BYO-VPC only) | `azure-per-infra-iam` | The resource group of your virtual network (`vnet_resource_group_name`) |
| ClickHouse BYOC Provisioner (subscription-level actions only) | This module | The subscription |

With BYO-IAM, the ClickHouse BYOC Provisioner role has only the actions that Azure does not allow at resource group scope:

- `Microsoft.Network/register/action`, `Microsoft.ContainerService/register/action`, `Microsoft.ManagedIdentity/register/action` and `Microsoft.Storage/register/action`.
- `Microsoft.Network/loadBalancers/frontendIPConfigurations/join/action`. For a private API server, ClickHouse puts a Private Link Service in front of the AKS-managed load balancer. That load balancer is in the AKS node resource group (`MC_...`), which AKS creates together with the cluster. This action has no effect without `privateLinkServices/write`, which ClickHouse has only in the infra resource groups.
- With `include_tde_permissions = true`: `Microsoft.KeyVault/register/action`, `Microsoft.KeyVault/checkNameAvailability/read` and `Microsoft.KeyVault/locations/deletedVaults/read`.

The ClickHouse BYOC Network User role exists only with `include_vpc_write_permissions = false`. It has read access to the virtual network, subnets, public IPs and NAT gateways, and `Microsoft.Network/virtualNetworks/subnets/join/action`.

> [!IMPORTANT]
> Before you destroy the `azure-per-infra-iam` module of an infra, make sure that ClickHouse deleted the infra. If you remove the role assignments first, ClickHouse cannot delete the infra resources.

ClickHouse keeps these actions in both modes:

- Read access to managed identities, role definitions and role assignments.
- `Microsoft.ManagedIdentity/userAssignedIdentities/assign/action`.
- Read, write and delete of federated identity credentials. Each credential binds 1 of your identities to a Kubernetes service account. The issuer of most credentials is the AKS cluster that ClickHouse creates, so you cannot create them in advance. ClickHouse also adds 1 credential for each ClickHouse instance.

Some role assignments have a scope or a principal that ClickHouse creates during provisioning. For these, the module adds the `ClickHouse BYOC Role Assignment Delegate` role. The `azure-per-infra-iam` module assigns it on the default resource group of each infra, with an [ABAC condition](https://learn.microsoft.com/en-us/azure/role-based-access-control/delegate-role-assignments-overview). The condition lets ClickHouse create and delete a role assignment only if the role and the principal match 1 of these rows:

| Role | Allowed principal | Scope that ClickHouse uses |
|------|-------------------|----------------------------|
| Network Contributor | Any principal except the ClickHouse service principal. ClickHouse uses it for the AKS cluster service principal, which it creates | The infra's default resource group |
| Azure Kubernetes Service Cluster Admin Role | The data-plane-mgmt identity | The AKS cluster |
| Azure Kubernetes Service Cluster User Role | The data-plane-mgmt identity | The AKS cluster (only with autoscaling) |
| Azure Kubernetes Service RBAC Cluster Admin | The data-plane-mgmt identity | The AKS cluster (only with autoscaling) |
| Key Vault Crypto User | The TDE delegate, data-plane-mgmt and ClickHouse pod identities | The TDE and named-collections key vaults |

ClickHouse cannot assign any other role, so it cannot grant Owner, Contributor, User Access Administrator or a custom role. ClickHouse also cannot give these roles to its own service principal, so it cannot get cryptographic use of your TDE key. A role assignment condition cannot limit the scope, so each row applies to the whole default resource group of the infra and the resources in it.

The Microsoft Graph permission `Application.ReadWrite.OwnedBy` stays in both modes. ClickHouse uses it to create the Entra application of the AKS cluster. The application is multitenant, because the cluster also uses it to pull images from the ClickHouse container registry.

## Outputs

| Name | Description |
|------|-------------|
| tenant_id | The Azure AD tenant ID |
| subscription_id | The Azure subscription ID |
| service_principal_client_id | The application (client) ID of the service principal |
| byo_iam | BYO-IAM only. The service principal object ID and the IDs of the ClickHouse BYOC role definitions. Set the `onboarding` input of each `azure-per-infra-iam` module to this value. `null` when `include_iam_write_permissions = true` |

## Resources

| Name | Description |
|------|------|
| azuread_service_principal.this | Service Principal for ClickHouse BYOC application |
| azurerm_role_definition.clickhouse_byoc_provisioner | Custom role for ClickHouse to provision Azure BYOC infrastructure resources |
| azurerm_role_assignment.this | Assigns 'ClickHouse BYOC Provisioner' role to the service principal on the subscription. With BYO-IAM the role has only the subscription-level actions |
| azuread_app_role_assignment.graph_permissions["Application.ReadWrite.OwnedBy"] | Grants Application.ReadWrite.OwnedBy Microsoft Graph permission |
| azurerm_role_definition.clickhouse_byoc_role_assignment_delegate | BYO-IAM only. Custom role with the role assignment actions. Assigned by `azure-per-infra-iam` |
| azurerm_role_definition.clickhouse_byoc_resource_group_provisioner | BYO-IAM only. Custom role with the provisioner actions that work at resource group scope. Assigned by `azure-per-infra-iam` on the infra resource groups |
| azurerm_role_definition.clickhouse_byoc_maintenance | Maintenance mode only. 1 custom role for each type of infra resource, with the minimal actions to operate a provisioned infra |
| azurerm_role_assignment.clickhouse_byoc_maintenance | Maintenance mode only. Assigns the maintenance roles on the resource groups and resources of each infra in `maintenance_infras` |
| azurerm_role_definition.clickhouse_byoc_network_user | BYO-IAM with `include_vpc_write_permissions = false` only. Custom role with read and join access to your virtual network. Assigned by `azure-per-infra-iam` |

## Requirements

| Name | Version |
|------|---------|
| terraform | >=1.3 |
| azuread provider | >=2.0 |
| azurerm provider | >=3.0 |
