locals {
  # BYO-IAM (include_iam_write_permissions = false): the provisioner role and the role assignment
  # delegate are not assigned on the subscription. The azure-per-infra-iam module assigns them on
  # the resource groups of each infra, which it creates. Only the actions that Azure does not
  # allow at resource group scope stay on the subscription, in the subscription provisioner role.
  byo_iam = !var.include_iam_write_permissions

  # Subscription-level operations: a resource group scope cannot grant them.
  resource_provider_registration_actions = [
    "Microsoft.Network/register/action",
    "Microsoft.ContainerService/register/action",
    "Microsoft.ManagedIdentity/register/action",
    "Microsoft.Storage/register/action",
  ]

  # Resource groups only exist at subscription scope. Under BYO-IAM the customer creates them with
  # azure-per-infra-iam and ClickHouse only reads them (the resource group provisioner role keeps
  # resourceGroups/read on its own).
  resource_group_actions = [
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/subscriptions/resourceGroups/write",
    "Microsoft.Resources/subscriptions/resourceGroups/delete",
  ]

  # BYOC+TDE control-plane actions: create and read the infra's default Key Vault (RBAC mode)
  # holding the shared KEK. Deliberately NO vaults/delete and NO deletedVaults purge — key
  # material must never be destroyable by ClickHouse's identity (the vault is orphaned on infra
  # teardown and remains the customer's).
  # Split in 2: provider registration, the vault name check and the deleted-vault lookup are
  # subscription-level operations.
  tde_keyvault_subscription_actions = [
    "Microsoft.KeyVault/register/action",
    "Microsoft.KeyVault/checkNameAvailability/read",
    "Microsoft.KeyVault/locations/deletedVaults/read",
  ]
  tde_keyvault_actions = [
    "Microsoft.KeyVault/vaults/read",
    "Microsoft.KeyVault/vaults/write",
  ]

  # BYOC+TDE data-plane actions: manage the KEK inside the vault (keys are created through the
  # Key Vault data plane, so control-plane actions alone are not enough). Deliberately NO
  # keys/delete, NO keys/purge and NO cryptographic actions (encrypt/decrypt/wrap/unwrap) — only
  # the TDE delegate identity gets Key Vault Crypto User on the key.
  tde_keyvault_data_actions = [
    "Microsoft.KeyVault/vaults/keys/read",
    "Microsoft.KeyVault/vaults/keys/create/action",
    "Microsoft.KeyVault/vaults/keys/update/action",
    "Microsoft.KeyVault/vaults/keyrotationpolicies/read",
  ]

  # Managed-VNet actions: ClickHouse creates and deletes the VNet, its subnets and the NAT egress
  # path (public IPs + NAT gateways). Not needed when the customer brings their own VNet (BYO-VPC).
  # The read and join actions on the same resources stay in the always-granted set, because a
  # BYO-VPC deployment still reads the customer VNet and joins its subnets.
  # Mirrors GroupVPCWrite in the data-plane-management onboarding validator.
  vpc_write_actions = [
    "Microsoft.Network/virtualNetworks/write",
    "Microsoft.Network/virtualNetworks/delete",
    "Microsoft.Network/virtualNetworks/subnets/write",
    "Microsoft.Network/virtualNetworks/subnets/delete",
    "Microsoft.Network/publicIPAddresses/write",
    "Microsoft.Network/publicIPAddresses/delete",
    "Microsoft.Network/publicIPAddresses/join/action",
    "Microsoft.Network/natGateways/write",
    "Microsoft.Network/natGateways/delete",
    "Microsoft.Network/natGateways/join/action",
  ]

  # ClickHouse-managed IAM actions: ClickHouse creates and deletes the per-infra user-assigned
  # managed identities, custom role definitions and role assignments. Not needed when the customer
  # brings their own IAM (BYO-IAM) through the azure-per-infra-iam module. Mirrors the AWS
  # IncludeIAMWritePermissions / ClickHouse-IAM-Extended-Policy split.
  # The read actions, userAssignedIdentities/assign/action (the Azure equivalent of iam:PassRole)
  # and the federated identity credential actions stay in the always-granted set: a BYO-IAM
  # deployment still observes the customer identities, and ClickHouse still federates them to the
  # workloads of the AKS cluster it creates (the cluster OIDC issuer is unknown before that, like
  # the EKS pod identity associations ClickHouse keeps managing under AWS BYO-IAM).
  iam_write_actions = [
    "Microsoft.ManagedIdentity/userAssignedIdentities/write",
    "Microsoft.ManagedIdentity/userAssignedIdentities/delete",
    "Microsoft.Authorization/roleDefinitions/write",
    "Microsoft.Authorization/roleDefinitions/delete",
    "Microsoft.Authorization/roleAssignments/write",
    "Microsoft.Authorization/roleAssignments/delete",
  ]

  # BYO-IAM: built-in roles ClickHouse may still assign. Each covers an assignment that the
  # crossplane-xrd composition (composition-xbridgeiamrole.tpl, composition-xk8sclusters.tpl)
  # makes in the customer subscription also under skipIAMCreation, because its scope or principal
  # only exists once ClickHouse creates it:
  # - Network Contributor: the AKS cluster service principal (an Entra app ClickHouse creates,
  #   multitenant so it can also pull from the ClickHouse container registry) on the infra's
  #   default resource group.
  # - Azure Kubernetes Service Cluster Admin Role: the data-plane-mgmt identity on the AKS cluster.
  # - Azure Kubernetes Service Cluster User Role and Azure Kubernetes Service RBAC Cluster Admin:
  #   the data-plane-mgmt identity on the AKS cluster, for the clickhouse-recommender when
  #   autoscaling is enabled.
  # - Key Vault Crypto User: the TDE delegate identity on the TDE vault, and the data-plane-mgmt
  #   and ClickHouse pod identities on the named-collections vault.
  # The ABAC condition that pairs each role with its allowed principals is built per infra by
  # azure-per-infra-iam, which creates those identities.
  byo_iam_assignable_roles = {
    network_contributor    = "Network Contributor"
    aks_cluster_admin      = "Azure Kubernetes Service Cluster Admin Role"
    aks_cluster_user       = "Azure Kubernetes Service Cluster User Role"
    aks_rbac_cluster_admin = "Azure Kubernetes Service RBAC Cluster Admin"
    key_vault_crypto_user  = "Key Vault Crypto User"
  }

  # Private API server actions: ClickHouse fronts the private AKS API server's internal load
  # balancer with a Private Link Service so the ClickHouse management plane can reach it without a
  # public endpoint. The join action authorizes referencing the AKS-managed kube-apiserver frontend
  # (by its deterministic ID) when creating the PLS; no load balancer read is needed.
  # Always granted, like the AWS PrivateLink/Lattice and GCP PSC permissions: private API server
  # mode is a per-infra setting, so gating it would break a later private infra until re-apply.
  # The validator still probes these under GroupPrivateAPIServer only for private infras, so
  # subscriptions onboarded before they were added keep validating for public infras.
  private_link_service_actions = [
    "Microsoft.Network/privateLinkServices/read",
    "Microsoft.Network/privateLinkServices/write",
    "Microsoft.Network/privateLinkServices/delete",
  ]
  # The AKS-managed kube-apiserver load balancer is in the AKS node resource group (MC_...), which
  # AKS creates together with the cluster. Under BYO-IAM no resource-group-scoped assignment can
  # cover it in advance, so this action stays in the subscription-assigned provisioner role. It is only usable
  # together with privateLinkServices/write, which is limited to the infra resource groups.
  node_resource_group_actions = [
    "Microsoft.Network/loadBalancers/frontendIPConfigurations/join/action",
  ]

  # Infra resource actions, granted in both IAM modes. In the subscription-scoped flow they are in
  # the provisioner role; under BYO-IAM they are in the resource group provisioner role, which
  # azure-per-infra-iam assigns on the infra resource groups only.
  infra_actions = [
    # Virtual Networks & Subnets (read + join in both VNet modes; write/delete in vpc_write_actions)
    "Microsoft.Network/virtualNetworks/read",
    "Microsoft.Network/virtualNetworks/subnets/read",
    "Microsoft.Network/virtualNetworks/subnets/join/action",

    # Public IPs & NAT Gateways (read in both VNet modes; write/delete/join in vpc_write_actions)
    "Microsoft.Network/publicIPAddresses/read",
    "Microsoft.Network/natGateways/read",

    # NSG (managed by ClickHouse in both VNet modes)
    "Microsoft.Network/networkSecurityGroups/read",
    "Microsoft.Network/networkSecurityGroups/write",
    "Microsoft.Network/networkSecurityGroups/delete",
    "Microsoft.Network/networkSecurityGroups/join/action",
    "Microsoft.Network/networkSecurityGroups/securityRules/read",
    "Microsoft.Network/networkSecurityGroups/securityRules/write",
    "Microsoft.Network/networkSecurityGroups/securityRules/delete",

    # Storage Accounts & Containers. No delete actions: ClickHouse never deletes the storage
    # accounts or containers holding your data (they are orphaned on infra teardown).
    "Microsoft.Storage/storageAccounts/read",
    "Microsoft.Storage/storageAccounts/write",
    "Microsoft.Storage/storageAccounts/listkeys/action",
    "Microsoft.Storage/storageAccounts/blobServices/read",
    "Microsoft.Storage/storageAccounts/blobServices/write",
    "Microsoft.Storage/storageAccounts/blobServices/containers/read",
    "Microsoft.Storage/storageAccounts/blobServices/containers/write",
    "Microsoft.Storage/storageAccounts/fileServices/read",

    # AKS Clusters & Node Pools
    "Microsoft.ContainerService/managedClusters/read",
    "Microsoft.ContainerService/managedClusters/write",
    "Microsoft.ContainerService/managedClusters/delete",
    "Microsoft.ContainerService/managedClusters/agentPools/read",
    "Microsoft.ContainerService/managedClusters/agentPools/write",
    "Microsoft.ContainerService/managedClusters/agentPools/delete",
    "Microsoft.ContainerService/managedClusters/listClusterAdminCredential/action",
    "Microsoft.ContainerService/managedClusters/listClusterUserCredential/action",

    # Managed Identities & Federated Credentials (read, assign and federation in both IAM modes;
    # identity write/delete in iam_write_actions)
    "Microsoft.ManagedIdentity/userAssignedIdentities/read",
    "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action",
    "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/read",
    "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/write",
    "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/delete",

    # Role Definitions & Assignments (read in both IAM modes; write/delete in iam_write_actions,
    # or the constrained clickhouse_byoc_role_assignment_delegate role under BYO-IAM)
    "Microsoft.Authorization/roleDefinitions/read",
    "Microsoft.Authorization/roleAssignments/read",
  ]

  # BYO-IAM with BYO-VPC: read the customer VNet and join its subnets. Assigned by
  # azure-per-infra-iam on the resource group of the customer VNet.
  network_user_actions = [
    "Microsoft.Network/virtualNetworks/read",
    "Microsoft.Network/virtualNetworks/subnets/read",
    "Microsoft.Network/virtualNetworks/subnets/join/action",
    "Microsoft.Network/publicIPAddresses/read",
    "Microsoft.Network/natGateways/read",
  ]
}

# Always assigned on the subscription (main.tf).
# Subscription-scoped flow: every provisioner action. The action order is unchanged from earlier
# releases, so existing onboardings plan no diff.
# BYO-IAM: only the actions that Azure does not allow at resource group scope, or that target the
# AKS node resource group. Everything else is in clickhouse_byoc_resource_group_provisioner.
resource "azurerm_role_definition" "clickhouse_byoc_provisioner" {
  name        = "ClickHouse BYOC Provisioner (${var.environment})"
  scope       = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  description = "Least-privilege custom role for ClickHouse to provision Azure BYOC infrastructure resources"

  permissions {
    actions = concat(
      local.resource_provider_registration_actions,
      local.byo_iam ? [] : concat(
        local.resource_group_actions,
        local.infra_actions,
        var.include_vpc_write_permissions ? local.vpc_write_actions : [],
        local.iam_write_actions,
        local.private_link_service_actions,
      ),
      local.node_resource_group_actions,
      var.include_tde_permissions ? local.tde_keyvault_subscription_actions : [],
      var.include_tde_permissions && !local.byo_iam ? local.tde_keyvault_actions : [],
    )

    not_actions = []

    data_actions = var.include_tde_permissions && !local.byo_iam ? local.tde_keyvault_data_actions : []
  }

  assignable_scopes = [
    "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  ]
}

data "azurerm_role_definition" "byo_iam_assignable" {
  for_each = local.byo_iam ? local.byo_iam_assignable_roles : {}

  name  = each.value
  scope = data.azurerm_subscription.current.id
}

# BYO-IAM only: the provisioner actions that work at resource group scope. Assigned by
# azure-per-infra-iam on the default and storage resource groups of each infra, so ClickHouse
# cannot change resources in other resource groups. No resource group write/delete: the customer
# creates the resource groups with azure-per-infra-iam.
resource "azurerm_role_definition" "clickhouse_byoc_resource_group_provisioner" {
  count = local.byo_iam ? 1 : 0

  name        = "ClickHouse BYOC Resource Group Provisioner (${var.environment})"
  scope       = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  description = "Custom role for ClickHouse to provision the resources of a bring-your-own-IAM BYOC infrastructure, assigned on the resource groups of the infrastructure only"

  permissions {
    actions = concat(
      ["Microsoft.Resources/subscriptions/resourceGroups/read"],
      local.infra_actions,
      var.include_vpc_write_permissions ? local.vpc_write_actions : [],
      local.private_link_service_actions,
      var.include_tde_permissions ? local.tde_keyvault_actions : [],
    )

    not_actions = []

    data_actions = var.include_tde_permissions ? local.tde_keyvault_data_actions : []
  }

  assignable_scopes = [
    "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  ]
}

# BYO-IAM with BYO-VPC only: read and join access to the customer VNet. Assigned by
# azure-per-infra-iam on the resource group of the VNet.
resource "azurerm_role_definition" "clickhouse_byoc_network_user" {
  count = local.byo_iam && !var.include_vpc_write_permissions ? 1 : 0

  name        = "ClickHouse BYOC Network User (${var.environment})"
  scope       = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  description = "Read access to a customer-managed virtual network and permission to join its subnets, for a bring-your-own-IAM BYOC infrastructure."

  permissions {
    actions     = local.network_user_actions
    not_actions = []
  }

  assignable_scopes = [
    "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  ]
}

# BYO-IAM only: lets ClickHouse create and delete role assignments. azure-per-infra-iam assigns it
# on the infra's default resource group with an ABAC condition that allows only the built-in
# roles in local.byo_iam_assignable_roles, each for its expected principals. Kept separate from
# the provisioner role so the condition constrains nothing else.
resource "azurerm_role_definition" "clickhouse_byoc_role_assignment_delegate" {
  count = var.include_iam_write_permissions ? 0 : 1

  name        = "ClickHouse BYOC Role Assignment Delegate (${var.environment})"
  scope       = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  description = "Lets ClickHouse assign a fixed set of built-in roles on resources it creates for a bring-your-own-IAM BYOC infrastructure. Constrained by an ABAC condition on the role assignment."

  permissions {
    actions = [
      "Microsoft.Authorization/roleAssignments/read",
      "Microsoft.Authorization/roleAssignments/write",
      "Microsoft.Authorization/roleAssignments/delete",
    ]
    not_actions = []
  }

  assignable_scopes = [
    "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  ]
}
