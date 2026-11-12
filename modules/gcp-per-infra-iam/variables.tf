variable "project_id" {
  type        = string
  description = "(Required) The ID of the GCP project that is dedicated to ClickHouse BYOC. Apply the `gcp` onboarding module to it first, with `include_iam_write_permissions = false`."
}

variable "spoken_name" {
  type        = string
  description = "(Required) The spoken name of the BYOC infra, provided by ClickHouse."

  validation {
    # Service account IDs are at most 30 characters, and the longest one is <spoken>-tde-delegate.
    condition     = can(regex("^[a-z][a-z0-9-]{0,15}[a-z0-9]$", var.spoken_name))
    error_message = "spoken_name must be 2 to 17 characters: lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
}

variable "region" {
  type        = string
  description = "(Required) The GCP region of the BYOC infra, for example `us-east1`."
}

variable "environment" {
  type        = string
  description = "(Optional) Environment. Default is `production`. The other values are reserved for internal use."
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "Environment must be one of: production, staging, development"
  }
}

variable "restore_source_spoken_names" {
  type        = list(string)
  description = "(Optional) The spoken names of other BYOC infras in this project whose backups this infra can restore. The module gives the ClickHouse service account of this infra read access to the buckets of those infras."
  default     = []
}
