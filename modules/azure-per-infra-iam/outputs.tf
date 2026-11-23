output "data_plane_management_identity_client_id" {
  description = "Client ID of the data-plane-mgmt managed identity. Report back to ClickHouse."
  value       = azurerm_user_assigned_identity.data_plane_mgmt.client_id
}

output "clickhouse_identity_client_id" {
  description = "Client ID of the managed identity of the ClickHouse pods."
  value       = azurerm_user_assigned_identity.clickhouse.client_id
}

output "monitoring_identity_client_id" {
  description = "Client ID of the monitoring managed identity."
  value       = azurerm_user_assigned_identity.monitoring.client_id
}

output "tde_delegate_identity_client_id" {
  description = "Client ID of the BYOC+TDE delegate managed identity, or null when `include_tde` is false."
  value       = one(azurerm_user_assigned_identity.tde_delegate[*].client_id)
}

output "default_resource_group_name" {
  description = "Name of the infra's default resource group."
  value       = azurerm_resource_group.default.name
}

output "storage_resource_group_name" {
  description = "Name of the infra's storage resource group."
  value       = azurerm_resource_group.storage.name
}
