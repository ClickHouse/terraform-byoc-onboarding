locals {
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

  # BYO-IAM: built-in roles ClickHouse may still assign. Each covers an assignment whose scope or
  # principal is created by ClickHouse during provisioning, so the customer cannot create it in
  # advance:
  # - Network Contributor: the AKS cluster service principal (an Entra app ClickHouse creates,
  #   multitenant so it can also pull from the ClickHouse container registry) on the infra's
  #   default resource group.
  # - Azure Kubernetes Service Cluster Admin Role: the data-plane-mgmt identity on the AKS cluster.
  # - Key Vault Crypto User: the TDE delegate identity on the TDE vault, and the data-plane-mgmt
  #   and ClickHouse pod identities on the named-collections vault.
  byo_iam_assignable_role_names = [
    "Network Contributor",
    "Azure Kubernetes Service Cluster Admin Role",
    "Key Vault Crypto User",
  ]

  byo_iam_assignable_role_ids = join(", ", [
    for role in data.azurerm_role_definition.byo_iam_assignable : basename(role.role_definition_id)
  ])

  # ABAC condition on the BYO-IAM role assignment delegate: ClickHouse can create and delete role
  # assignments only for the roles above, so it can never grant Owner, Contributor, User Access
  # Administrator or any custom role.
  # https://learn.microsoft.com/en-us/azure/role-based-access-control/delegate-role-assignments-examples
  byo_iam_role_assignment_condition = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.byo_iam_assignable_role_ids}}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.byo_iam_assignable_role_ids}}
     )
    )
  EOT

  # Private API server actions: ClickHouse fronts the private AKS API server's internal load
  # balancer with a Private Link Service so the ClickHouse management plane can reach it without a
  # public endpoint. The join action authorizes referencing the AKS-managed kube-apiserver frontend
  # (by its deterministic ID) when creating the PLS; no load balancer read is needed.
  # Always granted, like the AWS PrivateLink/Lattice and GCP PSC permissions: private API server
  # mode is a per-infra setting, so gating it would break a later private infra until re-apply.
  # The validator still probes these under GroupPrivateAPIServer only for private infras, so
  # subscriptions onboarded before they were added keep validating for public infras.
  private_api_server_actions = [
    "Microsoft.Network/privateLinkServices/read",
    "Microsoft.Network/privateLinkServices/write",
    "Microsoft.Network/privateLinkServices/delete",
    "Microsoft.Network/loadBalancers/frontendIPConfigurations/join/action",
  ]
}

resource "azurerm_role_definition" "clickhouse_byoc_provisioner" {
  name        = "ClickHouse BYOC Provisioner (${var.environment})"
  scope       = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
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
      ],
      var.include_vpc_write_permissions ? local.vpc_write_actions : [],
      var.include_iam_write_permissions ? local.iam_write_actions : [],
      local.private_api_server_actions,
      var.include_tde_permissions ? local.tde_keyvault_actions : [],
    )

    not_actions = []

    data_actions = var.include_tde_permissions ? local.tde_keyvault_data_actions : []
  }

  assignable_scopes = [
    "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  ]
}

data "azurerm_role_definition" "byo_iam_assignable" {
  for_each = var.include_iam_write_permissions ? toset([]) : toset(local.byo_iam_assignable_role_names)

  name  = each.value
  scope = data.azurerm_subscription.current.id
}

# BYO-IAM only: lets ClickHouse create and delete role assignments, restricted by
# local.byo_iam_role_assignment_condition (set on the assignment in main.tf) to the built-in
# roles in local.byo_iam_assignable_role_names. Kept separate from the provisioner role so the
# condition constrains nothing else.
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
