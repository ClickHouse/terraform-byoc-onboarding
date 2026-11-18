# Bring-your-own-IAM (BYO-IAM) resources for one Azure BYOC infra.
#
# Every name below must match what the ClickHouse BYOC composition (crossplane-xrd
# templates/azure/composition-xbridgeiamrole.tpl and composition-xbyocinfras.tpl) and
# data-plane-management look up: ClickHouse observes these resources by name instead of creating
# them when the infra is created with skipIAMCreation.
#
# Not created here, because they depend on resources ClickHouse creates during provisioning:
# - Federated identity credentials: their issuer is the OIDC issuer of the AKS cluster ClickHouse
#   creates (or the ClickHouse management cluster), and data-plane-management adds one per
#   ClickHouse instance at runtime.
# - The AKS cluster's Entra application/service principal and its Network Contributor assignment,
#   the data-plane-mgmt Azure Kubernetes Service Cluster Admin Role assignment on the cluster, and
#   the Key Vault Crypto User assignments on the TDE / named-collections vaults. ClickHouse makes
#   these through the constrained role assignment delegate of the onboarding module, which this
#   module assigns on the default resource group.

locals {
  default_resource_group_name = "clickhouse-cloud-${var.spoken_name}-default"
  storage_resource_group_name = "clickhouse-cloud-${var.spoken_name}-storage"

  # Data access the ClickHouse pods and the monitoring stack (Thanos, Prometheus) need on the
  # infra's storage accounts. Same permissions as the composition's custom roles.
  storage_container_actions = [
    "Microsoft.Storage/storageAccounts/blobServices/containers/read",
    "Microsoft.Storage/storageAccounts/blobServices/containers/write",
  ]
  storage_blob_data_actions = [
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/move/action",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action",
  ]

  tags = merge(var.tags, { clickhouse-byoc = "true" })

  # ABAC condition on the role assignment delegate. ClickHouse can create and delete a role
  # assignment only when the role and the principal match 1 of these pairs, which are the
  # assignments the crossplane-xrd composition makes under skipIAMCreation:
  # - Network Contributor, for any principal except the ClickHouse service principal itself. The
  #   principal is the AKS cluster service principal, which ClickHouse creates later, so it
  #   cannot be listed here.
  # - The AKS Cluster Admin, Cluster User and RBAC Cluster Admin roles, for data-plane-mgmt only.
  # - Key Vault Crypto User, for the TDE delegate, data-plane-mgmt and ClickHouse pod identities
  #   only. So ClickHouse can never give its own identity cryptographic use of the TDE key.
  # Role assignment conditions cannot test the scope, so each pair applies anywhere in the
  # default resource group, which is the scope of the delegate assignment.
  # https://learn.microsoft.com/en-us/azure/role-based-access-control/delegate-role-assignments-examples
  role_ids = var.onboarding.assignable_role_ids

  key_vault_crypto_user_principal_ids = flatten([
    azurerm_user_assigned_identity.data_plane_mgmt.principal_id,
    azurerm_user_assigned_identity.clickhouse.principal_id,
    azurerm_user_assigned_identity.tde_delegate[*].principal_id,
  ])

  # @ATTR is @Request for a new assignment (write) and @Resource for an existing one (delete).
  role_assignment_rule = <<-EOT
    (
     (
      @ATTR[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.role_ids.network_contributor}}
      AND
      @ATTR[Microsoft.Authorization/roleAssignments:PrincipalId] ForAnyOfAllValues:GuidNotEquals {${var.onboarding.service_principal_object_id}}
     )
     OR
     (
      @ATTR[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.role_ids.aks_cluster_admin}, ${local.role_ids.aks_cluster_user}, ${local.role_ids.aks_rbac_cluster_admin}}
      AND
      @ATTR[Microsoft.Authorization/roleAssignments:PrincipalId] ForAnyOfAnyValues:GuidEquals {${azurerm_user_assigned_identity.data_plane_mgmt.principal_id}}
     )
     OR
     (
      @ATTR[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.role_ids.key_vault_crypto_user}}
      AND
      @ATTR[Microsoft.Authorization/roleAssignments:PrincipalId] ForAnyOfAnyValues:GuidEquals {${join(", ", local.key_vault_crypto_user_principal_ids)}}
     )
    )
  EOT

  role_assignment_delegate_condition = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     ${trimspace(replace(local.role_assignment_rule, "@ATTR", "@Request"))}
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     ${trimspace(replace(local.role_assignment_rule, "@ATTR", "@Resource"))}
    )
  EOT
}

# ---------------------------------------------------------------------------------------------
# Resource groups. The identities and the role assignment scopes live in them, so they must
# exist before the infra is created. ClickHouse observes them under skipIAMCreation.
# ---------------------------------------------------------------------------------------------

resource "azurerm_resource_group" "default" {
  name     = local.default_resource_group_name
  location = var.region
  tags     = local.tags
}

resource "azurerm_resource_group" "storage" {
  name     = local.storage_resource_group_name
  location = var.region
  tags     = local.tags
}

# ---------------------------------------------------------------------------------------------
# ClickHouse provisioner (the BYOC service principal of the onboarding module). Under BYO-IAM
# its roles are scoped to the resource groups of the infra instead of the subscription. Only the
# subscription-level actions (resource provider registration, the AKS node resource group load
# balancer join, the Key Vault name checks) stay in the ClickHouse BYOC Provisioner role that the
# onboarding module assigns on the subscription.
# ---------------------------------------------------------------------------------------------

resource "azurerm_role_assignment" "clickhouse_provisioner" {
  for_each = {
    default = azurerm_resource_group.default.id
    storage = azurerm_resource_group.storage.id
  }

  scope              = each.value
  role_definition_id = var.onboarding.resource_group_provisioner_role_definition_id
  principal_id       = var.onboarding.service_principal_object_id
  principal_type     = "ServicePrincipal"
}

# Every role assignment ClickHouse still makes under BYO-IAM is in the default resource group:
# Network Contributor on the resource group itself, the AKS roles on the AKS cluster, and Key
# Vault Crypto User on the TDE and named-collections vaults. The ABAC condition
# (local.role_assignment_delegate_condition) limits it to those roles and their principals.
resource "azurerm_role_assignment" "clickhouse_role_assignment_delegate" {
  scope              = azurerm_resource_group.default.id
  role_definition_id = var.onboarding.role_assignment_delegate_role_definition_id
  principal_id       = var.onboarding.service_principal_object_id
  principal_type     = "ServicePrincipal"
  condition          = local.role_assignment_delegate_condition
  condition_version  = "2.0"
}

data "azurerm_resource_group" "vnet" {
  count = var.vnet_resource_group_name == null ? 0 : 1

  name = var.vnet_resource_group_name
}

resource "azurerm_role_assignment" "clickhouse_network_user" {
  count = var.vnet_resource_group_name == null ? 0 : 1

  scope              = data.azurerm_resource_group.vnet[0].id
  role_definition_id = var.onboarding.network_user_role_definition_id
  principal_id       = var.onboarding.service_principal_object_id
  principal_type     = "ServicePrincipal"

  lifecycle {
    precondition {
      condition     = var.onboarding.network_user_role_definition_id != null
      error_message = "vnet_resource_group_name requires include_vpc_write_permissions = false on the azure onboarding module."
    }
  }
}

# ---------------------------------------------------------------------------------------------
# data-plane-mgmt: the identity the ClickHouse management plane federates into to manage the
# infra (instance storage, private endpoint approval, per-instance federated credentials).
# ---------------------------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "data_plane_mgmt" {
  name                = "${var.spoken_name}-data-plane-mgmt"
  resource_group_name = azurerm_resource_group.default.name
  location            = var.region
  tags                = local.tags
}

resource "azurerm_role_assignment" "data_plane_mgmt_storage" {
  scope                = azurerm_resource_group.storage.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_user_assigned_identity.data_plane_mgmt.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "data_plane_mgmt_storage_blob_data" {
  scope                = azurerm_resource_group.storage.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.data_plane_mgmt.principal_id
  principal_type       = "ServicePrincipal"
}

# Lets data-plane-mgmt add and remove the per-instance federated identity credentials on the
# identities in the default resource group (ClickHouse pods, TDE delegate).
resource "azurerm_role_assignment" "data_plane_mgmt_identity" {
  scope                = azurerm_resource_group.default.id
  role_definition_name = "Managed Identity Contributor"
  principal_id         = azurerm_user_assigned_identity.data_plane_mgmt.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_definition" "data_plane_mgmt_pls_reader" {
  name        = "${var.spoken_name}-data-plane-mgmt-pls-reader"
  scope       = azurerm_resource_group.default.id
  description = "Access to Private Link Service properties and private endpoint connection approval used by data-plane-mgmt"

  permissions {
    actions = [
      "Microsoft.Network/privateLinkServices/read",
      "Microsoft.Network/privateLinkServices/privateEndpointConnections/read",
      "Microsoft.Network/privateLinkServices/privateEndpointConnections/write",
    ]
    not_actions = []
  }

  assignable_scopes = [azurerm_resource_group.default.id]
}

resource "azurerm_role_assignment" "data_plane_mgmt_pls_reader" {
  scope              = azurerm_resource_group.default.id
  role_definition_id = azurerm_role_definition.data_plane_mgmt_pls_reader.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.data_plane_mgmt.principal_id
  principal_type     = "ServicePrincipal"
}

# ---------------------------------------------------------------------------------------------
# ClickHouse pods: shared identity for all ClickHouse instances of the infra.
# ---------------------------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "clickhouse" {
  name                = "${var.spoken_name}-clickhouse-byoc"
  resource_group_name = azurerm_resource_group.default.name
  location            = var.region
  tags                = local.tags
}

resource "azurerm_role_definition" "clickhouse" {
  name        = "${var.spoken_name}-clickhouse-byoc"
  scope       = azurerm_resource_group.storage.id
  description = "This is a role for ClickHouse pods to access storage accounts"

  permissions {
    actions          = local.storage_container_actions
    data_actions     = local.storage_blob_data_actions
    not_actions      = []
    not_data_actions = []
  }

  assignable_scopes = [azurerm_resource_group.storage.id]
}

resource "azurerm_role_assignment" "clickhouse" {
  scope              = azurerm_resource_group.storage.id
  role_definition_id = azurerm_role_definition.clickhouse.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.clickhouse.principal_id
  principal_type     = "ServicePrincipal"
}

# ---------------------------------------------------------------------------------------------
# Monitoring (Thanos, Prometheus): metrics storage.
# ---------------------------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "monitoring" {
  name                = "${var.spoken_name}-monitoring"
  resource_group_name = azurerm_resource_group.default.name
  location            = var.region
  tags                = local.tags
}

resource "azurerm_role_definition" "monitoring" {
  name        = "${var.spoken_name}-monitoring"
  scope       = azurerm_resource_group.storage.id
  description = "This is a role for Monitoring storage access"

  permissions {
    actions          = local.storage_container_actions
    data_actions     = local.storage_blob_data_actions
    not_actions      = []
    not_data_actions = []
  }

  assignable_scopes = [azurerm_resource_group.storage.id]
}

resource "azurerm_role_assignment" "monitoring" {
  scope              = azurerm_resource_group.storage.id
  role_definition_id = azurerm_role_definition.monitoring.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.monitoring.principal_id
  principal_type     = "ServicePrincipal"
}

# ---------------------------------------------------------------------------------------------
# BYOC+TDE delegate. ClickHouse grants it Key Vault Crypto User on the TDE vault it creates.
# ---------------------------------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "tde_delegate" {
  count = var.include_tde ? 1 : 0

  name                = "${var.spoken_name}-tde-delegate"
  resource_group_name = azurerm_resource_group.default.name
  location            = var.region
  tags                = local.tags
}
