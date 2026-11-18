variable "spoken_name" {
  type        = string
  description = "(Required) The spoken name of the BYOC infra, provided by ClickHouse (for example `infra-ab-123`)."

  validation {
    # dp-mgmt caps the infra name at 16 characters; resource names below are derived from it.
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,15}$", var.spoken_name))
    error_message = "spoken_name must be the lowercase spoken name provided by ClickHouse (at most 16 characters of a-z, 0-9 and -)."
  }
}

variable "region" {
  type        = string
  description = "(Required) The Azure region (location) of the BYOC infra, for example `eastus2`."
}

variable "onboarding" {
  type = object({
    service_principal_object_id                   = string
    resource_group_provisioner_role_definition_id = string
    role_assignment_delegate_role_definition_id   = string
    assignable_role_ids = object({
      network_contributor    = string
      aks_cluster_admin      = string
      aks_cluster_user       = string
      aks_rbac_cluster_admin = string
      key_vault_crypto_user  = string
    })
    network_user_role_definition_id = optional(string)
  })
  nullable    = false
  description = "(Required) The `byo_iam` output of the `azure` onboarding module, applied with `include_iam_write_permissions = false`. This module assigns the ClickHouse provisioner and role assignment delegate roles on the resource groups of this infra only."
}

variable "vnet_resource_group_name" {
  type        = string
  description = "(Optional) BYO-VPC only: the name of the resource group of your own virtual network. ClickHouse gets read access to the virtual network, its subnets, public IPs and NAT gateways there, and can join its subnets. Requires `include_vpc_write_permissions = false` on the onboarding module. Defaults to `null` (ClickHouse creates the virtual network in the default resource group of the infra)."
  default     = null
}

variable "include_tde" {
  type        = bool
  description = "(Optional) Whether to create the BYOC+TDE delegate managed identity for this infra. Set to `true` before enabling TDE for the infra (together with `include_tde_permissions` on the onboarding module). Defaults to false."
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "(Optional) Tags to add to every resource this module creates."
  default     = {}
}
