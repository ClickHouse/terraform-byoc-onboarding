output "tenant_id" {
  description = "The Azure AD tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "The Azure subscription ID"
  value       = data.azurerm_client_config.current.subscription_id
}

output "service_principal_client_id" {
  description = "The application (client) ID of the service principal"
  value       = azuread_service_principal.this.client_id
}

output "byo_iam" {
  description = "BYO-IAM only (`include_iam_write_permissions = false`): pass this to the `onboarding` input of the `azure-per-infra-iam` module of each infra, which assigns these roles on the infra resource groups. `null` otherwise."
  value = local.byo_iam ? {
    service_principal_object_id                   = azuread_service_principal.this.object_id
    resource_group_provisioner_role_definition_id = azurerm_role_definition.clickhouse_byoc_resource_group_provisioner[0].role_definition_resource_id
    role_assignment_delegate_role_definition_id   = azurerm_role_definition.clickhouse_byoc_role_assignment_delegate[0].role_definition_resource_id
    network_user_role_definition_id               = one(azurerm_role_definition.clickhouse_byoc_network_user[*].role_definition_resource_id)
  } : null
}
