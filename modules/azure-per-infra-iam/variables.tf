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
