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

# Grant Microsoft Graph permissions to the service principal
resource "azuread_app_role_assignment" "graph_permissions" {
  for_each            = local.graph_permissions
  app_role_id         = each.value
  principal_object_id = azuread_service_principal.this.object_id
  resource_object_id  = data.azuread_service_principal.microsoft_graph.object_id
}

# BYO-IAM only: constrained role assignment rights (see roles.tf)
resource "azurerm_role_assignment" "role_assignment_delegate" {
  count = var.include_iam_write_permissions ? 0 : 1

  scope              = data.azurerm_subscription.current.id
  role_definition_id = azurerm_role_definition.clickhouse_byoc_role_assignment_delegate[0].role_definition_resource_id
  principal_id       = azuread_service_principal.this.object_id
  condition          = local.byo_iam_role_assignment_condition
  condition_version  = "2.0"
}
