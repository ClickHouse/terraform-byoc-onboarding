variable "environment" {
  type        = string
  description = "(Optional) Environment. Default is `production`. The other values are reserved for internal use"
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be one of: production, staging, development"
  }
}

variable "include_vpc_write_permissions" {
  type        = bool
  description = "(Optional) Whether to let ClickHouse create and delete the virtual network, its subnets and the NAT egress path (public IPs and NAT gateways) in this subscription. Set to `false` when you bring your own virtual network (BYO-VPC); ClickHouse then only reads it and joins its subnets. Defaults to true."
  default     = true
}

variable "include_tde_permissions" {
  type        = bool
  description = "(Optional) Whether to let ClickHouse provision the BYOC+TDE shared resources in this subscription: one TDE delegate managed identity and one default Key Vault + RSA key (KEK) per infra, wrapping the data-encryption keys of TDE-enabled ClickHouse instances. Deliberately grants no vault/key delete or purge and no cryptographic use of the keys — ClickHouse can never destroy or use your key material with this role. Defaults to false; enable before turning on TDE for an infra."
  default     = false
}
