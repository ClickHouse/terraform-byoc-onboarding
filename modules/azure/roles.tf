locals {
  subscription_scope = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"

  # BYOC+TDE control-plane actions: create and read the infra's default Key Vault (RBAC mode)
  # holding the shared KEK. Deliberately NO vaults/delete and NO deletedVaults purge — key
  # material must never be destroyable by ClickHouse's identity (the vault is orphaned on infra
  # teardown and remains the customer's).
  tde_keyvault_actions = [
    "Microsoft.KeyVault/register/action",
    "Microsoft.KeyVault/checkNameAvailability/read",
    "Microsoft.KeyVault/locations/deletedVaults/read",
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

  # Built-in roles ClickHouse assigns to the identities it creates for each infra. Together with
  # the custom roles below, these are the only roles ClickHouse can assign.
  clickhouse_assignable_builtin_role_ids = [
    "4d97b98b-1d4f-4787-a291-c67834d212e7", # Network Contributor: AKS cluster principal, on the infra's resource group
    "0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8", # Azure Kubernetes Service Cluster Admin Role: management identity, on the infra's AKS cluster
    "17d1049b-9a84-46fb-8f53-869881c3d3ab", # Storage Account Contributor: management identity, on the infra's storage resource group
    "ba92f5b4-2d11-453d-a403-e96b0029c9fe", # Storage Blob Data Contributor: management identity, on the infra's storage resource group
    "e40ec5ca-96e0-45a2-b4ff-59039f2c2b59", # Managed Identity Contributor: management identity, on the infra's resource group
    "12338af0-0e69-4776-bea7-57ae8d297424", # Key Vault Crypto User: ClickHouse identities, on the infra's Key Vaults
  ]

  clickhouse_assignable_role_ids = concat(local.clickhouse_assignable_builtin_role_ids, [
    azurerm_role_definition.clickhouse_byoc_storage_data.role_definition_id,
    azurerm_role_definition.clickhouse_byoc_private_link_approver.role_definition_id,
  ])

  # Roles whose assignments ClickHouse can never remove. Removal is a denylist rather than an
  # allowlist so that infras created before this module version can still be torn down: their role
  # assignments reference per-infra custom roles whose IDs are not known here.
  privileged_role_ids = [
    "8e3af657-a8ff-443c-a75c-2fe8c4bcb635", # Owner
    "b24988ac-6180-42a0-ab88-20f7382dd24c", # Contributor
    "18d7d88d-d35e-4fb5-a5c3-7773c20a72d9", # User Access Administrator
    "f58310d9-a9f6-439a-9e8d-f62e7b41a168", # Role Based Access Control Administrator
  ]

  # Azure ABAC condition (version 2.0) on the assignment of clickhouse_byoc_role_assignments:
  # - create: only the roles in clickhouse_assignable_role_ids, and never to the ClickHouse
  #   service principal itself
  # - delete: never an assignment of one of privileged_role_ids
  clickhouse_role_assignment_condition = join(" AND ", [
    format(
      "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {%s} AND @Request[Microsoft.Authorization/roleAssignments:PrincipalId] ForAnyOfAllValues:GuidNotEquals {%s}))",
      join(", ", local.clickhouse_assignable_role_ids),
      azuread_service_principal.this.object_id,
    ),
    format(
      "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {%s}))",
      join(", ", local.privileged_role_ids),
    ),
  ])
}

resource "azurerm_role_definition" "clickhouse_byoc_provisioner" {
  name        = "ClickHouse BYOC Provisioner (${var.environment})"
  scope       = local.subscription_scope
  description = "Least-privilege custom role for ClickHouse to provision Azure BYOC infrastructure resources"

  permissions {
    actions = concat([
      # Resource Provider Registration
      "Microsoft.Network/register/action",
      "Microsoft.ContainerService/register/action",
      "Microsoft.ManagedIdentity/register/action",
      "Microsoft.Storage/register/action",

      # Resource Groups
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Resources/subscriptions/resourceGroups/write",
      "Microsoft.Resources/subscriptions/resourceGroups/delete",

      # Virtual Networks & Subnets
      "Microsoft.Network/virtualNetworks/read",
      "Microsoft.Network/virtualNetworks/write",
      "Microsoft.Network/virtualNetworks/delete",
      "Microsoft.Network/virtualNetworks/subnets/read",
      "Microsoft.Network/virtualNetworks/subnets/write",
      "Microsoft.Network/virtualNetworks/subnets/delete",
      "Microsoft.Network/virtualNetworks/subnets/join/action",

      # Public IPs
      "Microsoft.Network/publicIPAddresses/read",
      "Microsoft.Network/publicIPAddresses/write",
      "Microsoft.Network/publicIPAddresses/delete",
      "Microsoft.Network/publicIPAddresses/join/action",

      # NAT Gateways
      "Microsoft.Network/natGateways/read",
      "Microsoft.Network/natGateways/write",
      "Microsoft.Network/natGateways/delete",
      "Microsoft.Network/natGateways/join/action",

      # NSG
      "Microsoft.Network/networkSecurityGroups/read",
      "Microsoft.Network/networkSecurityGroups/write",
      "Microsoft.Network/networkSecurityGroups/delete",
      "Microsoft.Network/networkSecurityGroups/join/action",
      "Microsoft.Network/networkSecurityGroups/securityRules/read",
      "Microsoft.Network/networkSecurityGroups/securityRules/write",
      "Microsoft.Network/networkSecurityGroups/securityRules/delete",

      # Private Link Services & load balancer frontends: ClickHouse fronts the
      # private AKS API server's internal load balancer with a Private Link
      # Service so the ClickHouse management plane can reach it without a
      # public endpoint. The join action authorizes referencing the
      # AKS-managed kube-apiserver frontend when creating the PLS.
      "Microsoft.Network/privateLinkServices/read",
      "Microsoft.Network/privateLinkServices/write",
      "Microsoft.Network/privateLinkServices/delete",
      "Microsoft.Network/loadBalancers/read",
      "Microsoft.Network/loadBalancers/frontendIPConfigurations/read",
      "Microsoft.Network/loadBalancers/frontendIPConfigurations/join/action",

      # Storage Accounts & Containers. No delete: ClickHouse leaves its storage accounts and
      # containers in place when it tears an infra down.
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

      # Managed Identities & Federated Credentials. No assign/action: ClickHouse attaches no
      # user-assigned identity to the resources it creates, so it cannot attach any of yours.
      "Microsoft.ManagedIdentity/userAssignedIdentities/read",
      "Microsoft.ManagedIdentity/userAssignedIdentities/write",
      "Microsoft.ManagedIdentity/userAssignedIdentities/delete",
      "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/read",
      "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/write",
      "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/delete",

      # Role Definitions & Assignments: read only. Role assignments are created through
      # clickhouse_byoc_role_assignments, conditioned to the roles ClickHouse needs, and ClickHouse
      # cannot create or change role definitions. roleDefinitions/delete remains so that infras
      # created before this module version, which own per-infra role definitions, can still be torn
      # down; Azure refuses to delete a role definition that is still assigned.
      "Microsoft.Authorization/roleDefinitions/read",
      "Microsoft.Authorization/roleDefinitions/delete",
      "Microsoft.Authorization/roleAssignments/read",
    ], var.include_tde_permissions ? local.tde_keyvault_actions : [])

    not_actions = []

    data_actions = var.include_tde_permissions ? local.tde_keyvault_data_actions : []
  }

  assignable_scopes = [local.subscription_scope]
}

# Create and delete role assignments. Its assignment to the ClickHouse service principal carries
# clickhouse_role_assignment_condition, which limits the roles ClickHouse can assign.
resource "azurerm_role_definition" "clickhouse_byoc_role_assignments" {
  name        = "ClickHouse BYOC Role Assignments (${var.environment})"
  scope       = local.subscription_scope
  description = "Lets ClickHouse assign the roles its BYOC identities need; the assignment of this role is conditioned to those roles"

  permissions {
    actions = [
      "Microsoft.Authorization/roleAssignments/write",
      "Microsoft.Authorization/roleAssignments/delete",
    ]
    not_actions = []
  }

  assignable_scopes = [local.subscription_scope]
}

# Blob read/write for the identities ClickHouse creates for each infra (monitoring and ClickHouse
# server), assigned on the infra's storage resource group. Pre-created here so that ClickHouse needs
# no permission to create role definitions.
resource "azurerm_role_definition" "clickhouse_byoc_storage_data" {
  name        = "ClickHouse BYOC Storage Data (${var.environment})"
  scope       = local.subscription_scope
  description = "Read and write blobs in ClickHouse-managed storage containers; assigned by ClickHouse to its own per-infra identities"

  permissions {
    actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/write",
    ]
    data_actions = [
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/move/action",
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action",
    ]
    not_actions = []
  }

  assignable_scopes = [local.subscription_scope]
}

# Private Link Service read and private endpoint connection approval for the ClickHouse management
# identity, assigned on the infra's resource group. Pre-created here so that ClickHouse needs no
# permission to create role definitions.
resource "azurerm_role_definition" "clickhouse_byoc_private_link_approver" {
  name        = "ClickHouse BYOC Private Link Approver (${var.environment})"
  scope       = local.subscription_scope
  description = "Read ClickHouse Private Link Services and approve their private endpoint connections; assigned by ClickHouse to its own per-infra management identity"

  permissions {
    actions = [
      "Microsoft.Network/privateLinkServices/read",
      "Microsoft.Network/privateLinkServices/privateEndpointConnections/read",
      "Microsoft.Network/privateLinkServices/privateEndpointConnections/write",
    ]
    not_actions = []
  }

  assignable_scopes = [local.subscription_scope]
}
