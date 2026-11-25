# Maintenance mode (var.maintenance_mode = true): minimal roles to operate the provisioned infras
# in var.maintenance_infras.
#
# Azure role assignment scopes must exist, so before an infra is provisioned ClickHouse can only
# get its roles on the subscription. Once the infras exist, maintenance mode looks up their
# resources and assigns each role on the resources it is for, with only the actions that the BYOC
# Crossplane compositions (crossplane-xrd templates/azure) need to keep observing an infra and to
# do these operations:
# - Updates and upgrades of the AKS cluster and its node pools, with AKS admin access.
# - New ClickHouse services. data-plane-mgmt creates their storage and federated identity
#   credentials with the infra's data-plane-mgmt identity, so they need nothing here beyond new
#   node groups (node pools in the existing subnets).
# - Customer private link. The AKS cloud provider creates its Private Link Service with the
#   cluster's own service principal; ClickHouse only adds an NSG rule.
# - Private API server. ClickHouse creates a Private Link Service in front of the AKS-managed
#   kube-apiserver load balancer and adds an NSG rule.
# Private link and the private API server need the pl and apiserver subnets. The default Azure
# subnets include both for infras created since 2026-09-25; adding a subnet to an older infra
# needs maintenance_mode = false (no subnets/write here).
#
# Read-only, so maintenance_mode must be false to change them:
# - Managed identities, federated identity credentials, role definitions and role assignments.
#   ClickHouse cannot grant any role to anybody.
# - Key vaults and keys: TDE and named collections cannot be enabled in maintenance mode.
# - Resource groups, virtual networks, subnets, NAT gateways, public IPs and storage accounts.
# Nothing here can delete a resource, except node pools.
#
# The roles of the infra identities (data-plane-mgmt, ClickHouse pods, monitoring) and the
# Microsoft Graph permission do not change.

locals {
  maintenance_infras = local.provisioning ? toset([]) : toset(var.maintenance_infras)

  # Actions of each maintenance role. Each role is assigned only on the scopes named in its
  # comment (see local.maintenance_assignments). An assignment on a resource also covers its child
  # resources (subnets, security rules, node pools, containers, federated credentials, keys).
  maintenance_roles = {
    # Infra resource groups (-default, -storage). Must stay at resource group scope: some role
    # assignments Crossplane observes are on the resource group itself, and a role definition is
    # not an assignment scope.
    resource_group = {
      name        = "Resource Group"
      description = "Read the resource groups, role definitions and role assignments of a provisioned BYOC infrastructure."
      actions = [
        "Microsoft.Resources/subscriptions/resourceGroups/read",
        "Microsoft.Authorization/roleDefinitions/read",
        "Microsoft.Authorization/roleAssignments/read",
      ]
      data_actions = []
    }

    # The AKS cluster: Kubernetes version upgrades, node pool changes (scaling limits, node pool
    # rotation through temporaryNameForRotation, new node groups), the AKS service principal
    # secret, and the kubeconfig that Crossplane uses to manage the in-cluster objects. No cluster
    # delete.
    aks = {
      name        = "AKS"
      description = "Upgrade the AKS cluster of a provisioned BYOC infrastructure, manage its node pools and get its credentials. No cluster delete."
      actions = [
        "Microsoft.ContainerService/managedClusters/read",
        "Microsoft.ContainerService/managedClusters/write",
        "Microsoft.ContainerService/managedClusters/resetServicePrincipalProfile/action",
        "Microsoft.ContainerService/managedClusters/listClusterAdminCredential/action",
        "Microsoft.ContainerService/managedClusters/listClusterUserCredential/action",
        "Microsoft.ContainerService/managedClusters/agentPools/read",
        "Microsoft.ContainerService/managedClusters/agentPools/write",
        "Microsoft.ContainerService/managedClusters/agentPools/delete",
      ]
      data_actions = []
    }

    # The NSG: security rule changes (private link, private API server).
    nsg = {
      name        = "NSG"
      description = "Change the NSG and NSG rules of a provisioned BYOC infrastructure."
      actions = [
        "Microsoft.Network/networkSecurityGroups/read",
        "Microsoft.Network/networkSecurityGroups/write",
        "Microsoft.Network/networkSecurityGroups/securityRules/read",
        "Microsoft.Network/networkSecurityGroups/securityRules/write",
        "Microsoft.Network/networkSecurityGroups/securityRules/delete",
      ]
      data_actions = []
    }

    # The virtual network: read it, and join its existing subnets (node pools, Private Link
    # Service NAT IP). No virtual network or subnet write.
    vnet = {
      name        = "Virtual Network"
      description = "Read the virtual network of a provisioned BYOC infrastructure and join its existing subnets."
      actions = [
        "Microsoft.Network/virtualNetworks/read",
        "Microsoft.Network/virtualNetworks/subnets/read",
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
      data_actions = []
    }

    # Each NAT gateway and public IP of the egress path.
    network_reader = {
      name        = "Network Reader"
      description = "Read the NAT gateways and public IP addresses of a provisioned BYOC infrastructure."
      actions = [
        "Microsoft.Network/natGateways/read",
        "Microsoft.Network/publicIPAddresses/read",
      ]
      data_actions = []
    }

    # Each storage account. Observing an account reads its keys, and Crossplane keeps its
    # containers in sync. No storage account write or delete, and no container delete.
    storage_account = {
      name        = "Storage Account"
      description = "Read the storage accounts of a provisioned BYOC infrastructure and keep their containers in sync. No storage account or container delete."
      actions = [
        "Microsoft.Storage/storageAccounts/read",
        "Microsoft.Storage/storageAccounts/listkeys/action",
        "Microsoft.Storage/storageAccounts/blobServices/read",
        "Microsoft.Storage/storageAccounts/blobServices/containers/read",
        "Microsoft.Storage/storageAccounts/blobServices/containers/write",
        "Microsoft.Storage/storageAccounts/fileServices/read",
      ]
      data_actions = []
    }

    # Each managed identity of the infra, and its federated identity credentials.
    identity = {
      name        = "Identity"
      description = "Read the managed identities and federated identity credentials of a provisioned BYOC infrastructure."
      actions = [
        "Microsoft.ManagedIdentity/userAssignedIdentities/read",
        "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials/read",
      ]
      data_actions = []
    }

    # Each key vault (TDE, named collections). Key metadata only, no cryptographic use.
    key_vault = {
      name        = "Key Vault"
      description = "Read the key vaults and key metadata of a provisioned BYOC infrastructure. No cryptographic use of the keys."
      actions = [
        "Microsoft.KeyVault/vaults/read",
      ]
      data_actions = [
        "Microsoft.KeyVault/vaults/keys/read",
        "Microsoft.KeyVault/vaults/keyrotationpolicies/read",
      ]
    }

    # The -default resource group: the private API server Private Link Service. It does not exist
    # before ClickHouse makes the API server private, so it cannot be assigned on the resource.
    private_link_service = {
      name        = "Private Link Service"
      description = "Create and update the private API server Private Link Service of a provisioned BYOC infrastructure. No delete."
      actions = [
        "Microsoft.Network/privateLinkServices/read",
        "Microsoft.Network/privateLinkServices/write",
      ]
      data_actions = []
    }

    # The AKS-managed kube-apiserver load balancer in the node resource group: put the private API
    # server Private Link Service in front of its frontend IP configuration.
    load_balancer_join = {
      name        = "Load Balancer Join"
      description = "Put a Private Link Service in front of the AKS-managed kube-apiserver load balancer of a provisioned BYOC infrastructure."
      actions = [
        "Microsoft.Network/loadBalancers/frontendIPConfigurations/join/action",
      ]
      data_actions = []
    }
  }
}

# ---------------------------------------------------------------------------------------------
# Existing infra resources, named as in the crossplane-xrd Azure compositions. A lookup of a
# resource that every infra has fails the plan if the resource does not exist, so enable
# maintenance mode only after ClickHouse has provisioned the infras. azurerm_resources is used for
# the cluster instead of azurerm_kubernetes_cluster, which would put the cluster credentials into
# the Terraform state.
# ---------------------------------------------------------------------------------------------

data "azurerm_resource_group" "maintenance_default" {
  for_each = local.maintenance_infras

  name = "clickhouse-cloud-${each.key}-default"
}

data "azurerm_resource_group" "maintenance_storage" {
  for_each = local.maintenance_infras

  name = "clickhouse-cloud-${each.key}-storage"
}

data "azurerm_resources" "maintenance_aks_cluster" {
  for_each = local.maintenance_infras

  name                = "clickhouse-cloud-${each.key}"
  resource_group_name = data.azurerm_resource_group.maintenance_default[each.key].name
  type                = "Microsoft.ContainerService/managedClusters"

  lifecycle {
    postcondition {
      condition     = length(self.resources) == 1
      error_message = "AKS cluster clickhouse-cloud-${each.key} not found in clickhouse-cloud-${each.key}-default. Enable maintenance mode only after ClickHouse has provisioned the infra."
    }
  }
}

data "azurerm_resources" "maintenance_nsg" {
  for_each = local.maintenance_infras

  name                = "${each.key}-nsg"
  resource_group_name = data.azurerm_resource_group.maintenance_default[each.key].name
  type                = "Microsoft.Network/networkSecurityGroups"

  lifecycle {
    postcondition {
      condition     = length(self.resources) == 1
      error_message = "Network security group ${each.key}-nsg not found in clickhouse-cloud-${each.key}-default. Enable maintenance mode only after ClickHouse has provisioned the infra."
    }
  }
}

data "azurerm_resources" "maintenance_vnet" {
  for_each = local.maintenance_infras

  name                = each.key
  resource_group_name = data.azurerm_resource_group.maintenance_default[each.key].name
  type                = "Microsoft.Network/virtualNetworks"

  lifecycle {
    postcondition {
      condition     = length(self.resources) == 1
      error_message = "Virtual network ${each.key} not found in clickhouse-cloud-${each.key}-default. Enable maintenance mode only after ClickHouse has provisioned the infra."
    }
  }
}

# Resources whose number depends on the infra (1 NAT gateway and public IP for each zone, 1
# storage account for each bucket) or on its features (key vaults). Listed by type and filtered by
# the infra name prefix below.
data "azurerm_resources" "maintenance_nat_gateways" {
  for_each = local.maintenance_infras

  resource_group_name = data.azurerm_resource_group.maintenance_default[each.key].name
  type                = "Microsoft.Network/natGateways"
}

data "azurerm_resources" "maintenance_public_ips" {
  for_each = local.maintenance_infras

  resource_group_name = data.azurerm_resource_group.maintenance_default[each.key].name
  type                = "Microsoft.Network/publicIPAddresses"
}

data "azurerm_resources" "maintenance_identities" {
  for_each = local.maintenance_infras

  resource_group_name = data.azurerm_resource_group.maintenance_default[each.key].name
  type                = "Microsoft.ManagedIdentity/userAssignedIdentities"
}

data "azurerm_resources" "maintenance_key_vaults" {
  for_each = local.maintenance_infras

  resource_group_name = data.azurerm_resource_group.maintenance_default[each.key].name
  type                = "Microsoft.KeyVault/vaults"
}

data "azurerm_resources" "maintenance_storage_accounts" {
  for_each = local.maintenance_infras

  resource_group_name = data.azurerm_resource_group.maintenance_storage[each.key].name
  type                = "Microsoft.Storage/storageAccounts"
}

# The AKS-managed kube-apiserver load balancer. AKS creates it with API Server VNet Integration,
# which the composition enables when the infra has an apiserver subnet. The composition pins the
# node resource group to MC_<spoken_name>_<region>. No load balancer means no private API server
# support for the infra, so no assignment.
data "azurerm_resources" "maintenance_apiserver_lb" {
  for_each = local.maintenance_infras

  name                = "kube-apiserver"
  resource_group_name = "MC_${each.key}_${data.azurerm_resource_group.maintenance_default[each.key].location}"
  type                = "Microsoft.Network/loadBalancers"
}

locals {
  # One entry for each role assignment: key => { role, scope }. Keys use the infra and resource
  # names, so adding or removing an infra or a resource only changes its own assignments.
  maintenance_assignments = merge([
    for n in local.maintenance_infras : merge(
      {
        "${n}/resource_group/default" = { role = "resource_group", scope = data.azurerm_resource_group.maintenance_default[n].id }
        "${n}/resource_group/storage" = { role = "resource_group", scope = data.azurerm_resource_group.maintenance_storage[n].id }
        "${n}/aks"                    = { role = "aks", scope = data.azurerm_resources.maintenance_aks_cluster[n].resources[0].id }
        "${n}/nsg"                    = { role = "nsg", scope = data.azurerm_resources.maintenance_nsg[n].resources[0].id }
        "${n}/vnet"                   = { role = "vnet", scope = data.azurerm_resources.maintenance_vnet[n].resources[0].id }
        "${n}/private_link_service"   = { role = "private_link_service", scope = data.azurerm_resource_group.maintenance_default[n].id }
      },
      # NAT gateways and public IPs: both <spoken_name>-<zone>, so the type is part of the key.
      {
        for r in data.azurerm_resources.maintenance_nat_gateways[n].resources :
        "${n}/network_reader/nat_gateway/${r.name}" => { role = "network_reader", scope = r.id }
        if length(regexall("^${n}-", r.name)) > 0
      },
      {
        for r in data.azurerm_resources.maintenance_public_ips[n].resources :
        "${n}/network_reader/public_ip/${r.name}" => { role = "network_reader", scope = r.id }
        if length(regexall("^${n}-", r.name)) > 0
      },
      # Identities: <spoken_name>-data-plane-mgmt, -clickhouse-byoc, -monitoring, -tde-delegate.
      {
        for r in data.azurerm_resources.maintenance_identities[n].resources :
        "${n}/identity/${r.name}" => { role = "identity", scope = r.id }
        if length(regexall("^${n}-", r.name)) > 0
      },
      # Key vaults: <spoken_name>-tde, <spoken_name>-snc (truncated to 24 characters).
      {
        for r in data.azurerm_resources.maintenance_key_vaults[n].resources :
        "${n}/key_vault/${r.name}" => { role = "key_vault", scope = r.id }
        if length(regexall("^${n}-", r.name)) > 0
      },
      # Storage accounts: <spoken_name><bucket_name> without - and _, truncated to 24 characters.
      {
        for r in data.azurerm_resources.maintenance_storage_accounts[n].resources :
        "${n}/storage_account/${r.name}" => { role = "storage_account", scope = r.id }
        if length(regexall("^${replace(n, "-", "")}", r.name)) > 0
      },
      {
        for r in data.azurerm_resources.maintenance_apiserver_lb[n].resources :
        "${n}/load_balancer_join" => { role = "load_balancer_join", scope = r.id }
      },
    )
  ]...)
}

# ---------------------------------------------------------------------------------------------
# Role definitions, shared by all infras. Assignable on the subscription; every assignment below
# is on a resource group or a resource of one infra.
# ---------------------------------------------------------------------------------------------

resource "azurerm_role_definition" "clickhouse_byoc_maintenance" {
  for_each = local.provisioning ? {} : local.maintenance_roles

  name        = "ClickHouse BYOC Maintenance ${each.value.name} (${var.environment})"
  scope       = data.azurerm_subscription.current.id
  description = each.value.description

  permissions {
    actions          = each.value.actions
    not_actions      = []
    data_actions     = each.value.data_actions
    not_data_actions = []
  }

  assignable_scopes = [data.azurerm_subscription.current.id]
}

resource "azurerm_role_assignment" "clickhouse_byoc_maintenance" {
  for_each = local.maintenance_assignments

  scope              = each.value.scope
  role_definition_id = azurerm_role_definition.clickhouse_byoc_maintenance[each.value.role].role_definition_resource_id
  principal_id       = azuread_service_principal.this.object_id
  principal_type     = "ServicePrincipal"
}
