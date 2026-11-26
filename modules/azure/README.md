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

## Bring your own virtual network (BYO-VNet)

If you pre-create and manage the virtual network yourself, set `include_vpc_write_permissions = false`. ClickHouse then does **not** get permissions to create, delete, or modify the network topology (the virtual network, its subnets, and the NAT egress path — public IPs and NAT gateways), but keeps read access to it and `Microsoft.Network/virtualNetworks/subnets/join/action` so AKS can join your subnets. ClickHouse still creates and manages the resources it owns inside your network — the AKS cluster, and the Private Link Service that fronts it — so PrivateLink and load balancers keep working. (Under BYO-IAM, this read-and-join access is the `ClickHouse BYOC Network User` role, assigned by [`azure-per-infra-iam`](../azure-per-infra-iam/) on your virtual network's resource group — see [Bring your own IAM](#bring-your-own-iam-byo-iam).)

```hcl
module "clickhouse_onboarding" {
  source                        = "github.com/ClickHouse/terraform-byoc-onboarding.git//modules/azure?ref=<version>"
  include_vpc_write_permissions = false
}
```

### The subnets you create

Create one virtual network with the subnets below. ClickHouse validates their shape up front (a preflight check) and fails fast with the specific reason if one is wrong, so it is worth getting these exactly right before you hand them over.

| Subnet | Minimum size | Delegation | Also required |
|--------|--------------|------------|---------------|
| **node** | `/27` (a /27 or larger range, e.g. /24 — a /28 is too small) | **none** | The AKS egress path for your `outboundType` — see below. |
| **pod** | `/25` | `Microsoft.ContainerService/managedClusters` | Azure CNI gives every pod a real VNet IP, so size this for your target pod count. |
| **apiserver** (optional, for a private API server) | `/28` | `Microsoft.ContainerService/managedClusters` | Used only for [API Server VNet Integration](https://learn.microsoft.com/en-us/azure/aks/api-server-vnet-integration); nothing else joins it. |
| **privatelink** (optional, for PrivateLink) | `/28` | **none** | `privateLinkServiceNetworkPolicies = Disabled`, so the istio-ingress Private Link Service can be created. |

All subnets must belong to the virtual network you bring. Sizes are minimums — larger ranges are fine and recommended for the node and pod subnets.

### Egress (`outboundType`)

Unlike EKS and GKE, AKS needs its egress mode stated explicitly, so you choose how the nodes reach the internet and prepare the node subnet to match:

- **`userAssignedNATGateway`** (the default when you set nothing): attach a **NAT gateway** to the node subnet. Create a Standard public IP and a NAT gateway (zone-redundant is recommended), and associate the NAT gateway with the node subnet.
- **`userDefinedRouting`**: attach a **route table** to the node subnet with a `0.0.0.0/0` route to your firewall or NVA (for example Azure Firewall). Use this when all egress must go through your own inspection point.

### AKS service CIDR

The AKS service CIDR (the in-cluster `ClusterIP` range, default `10.0.0.0/16`) **must not overlap** your virtual network or any of its subnets, or in-cluster service IPs collide with pod and node IPs. If your network uses `10.0.0.0/16`, set a non-overlapping service CIDR when you create the infra.

### Handing the network to ClickHouse

When you create the BYOC infra, give ClickHouse the virtual network resource ID and the subnet resource IDs (node, pod, and — if used — API-server and PrivateLink), your `outboundType`, and a non-overlapping service CIDR. ClickHouse observes the network at those IDs instead of creating one.

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
| byo_iam | BYO-IAM only. The service principal object ID, the role definition IDs and the ABAC condition. Set the `onboarding` input of each `azure-per-infra-iam` module to this value. `null` when `include_iam_write_permissions = true` |

## Resources

| Name | Description |
|------|------|
| azuread_service_principal.this | Service Principal for ClickHouse BYOC application |
| azurerm_role_definition.clickhouse_byoc_provisioner | Custom role for ClickHouse to provision Azure BYOC infrastructure resources |
| azurerm_role_assignment.this | Assigns 'ClickHouse BYOC Provisioner' role to the service principal on the subscription. With BYO-IAM the role has only the subscription-level actions |
| azuread_app_role_assignment.graph_permissions["Application.ReadWrite.OwnedBy"] | Grants Application.ReadWrite.OwnedBy Microsoft Graph permission |
| azurerm_role_definition.clickhouse_byoc_role_assignment_delegate | BYO-IAM only. Custom role with the role assignment actions. Assigned by `azure-per-infra-iam` |
| azurerm_role_definition.clickhouse_byoc_resource_group_provisioner | BYO-IAM only. Custom role with the provisioner actions that work at resource group scope. Assigned by `azure-per-infra-iam` on the infra resource groups |
| azurerm_role_definition.clickhouse_byoc_network_user | BYO-IAM with `include_vpc_write_permissions = false` only. Custom role with read and join access to your virtual network. Assigned by `azure-per-infra-iam` |

## Requirements

| Name | Version |
|------|---------|
| terraform | >=1.3 |
| azuread provider | >=2.0 |
| azurerm provider | >=3.0 |
