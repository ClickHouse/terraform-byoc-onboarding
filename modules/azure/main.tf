data "azuread_client_config" "current" {}
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {
  subscription_id = data.azurerm_client_config.current.subscription_id
}
data "azuread_service_principal" "microsoft_graph" {
  client_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
}

# Create a service principle of the BYOC application
resource "azuread_service_principal" "this" {
  client_id = local.clickhouse_byoc_app_registration_map[var.environment]
  # it's recommended to always set owner of service principal (using current user here)
  owners = [data.azuread_client_config.current.object_id]
}

# Assign proper role definitions to the service principle
resource "azurerm_role_assignment" "this" {
  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.clickhouse_byoc_provisioner.role_definition_resource_id
  principal_id       = azuread_service_principal.this.object_id
}

# Let the service principal assign only the roles ClickHouse's BYOC identities need
resource "azurerm_role_assignment" "role_assignments" {
  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.clickhouse_byoc_role_assignments.role_definition_resource_id
  principal_id       = azuread_service_principal.this.object_id
  principal_type     = "ServicePrincipal"
  description        = "ClickHouse may assign only the roles its BYOC identities need, and never to itself"
  condition_version  = "2.0"
  condition          = local.clickhouse_role_assignment_condition
}

# Grant Microsoft Graph permissions to the service principal
resource "azuread_app_role_assignment" "graph_permissions" {
  for_each            = local.graph_permissions
  app_role_id         = each.value
  principal_object_id = azuread_service_principal.this.object_id
  resource_object_id  = data.azuread_service_principal.microsoft_graph.object_id
}
