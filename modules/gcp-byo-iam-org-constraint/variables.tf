variable "organization_id" {
  type        = string
  description = "(Required) The numeric ID of your Google Cloud organization. The custom constraints are created under organizations/ORGANIZATION_ID."

  validation {
    condition     = can(regex("^[0-9]+$", var.organization_id))
    error_message = "organization_id must be the numeric organization ID."
  }
}

variable "project_id" {
  type        = string
  description = "(Required) The ID of the GCP project where ClickHouse BYOC runs. The constraints allow only Workload Identity members of this project."
}

variable "project_number" {
  type        = string
  description = "(Required) The numeric project number of `project_id`. It is part of the principal:// Workload Identity members."

  validation {
    condition     = can(regex("^[0-9]+$", var.project_number))
    error_message = "project_number must be the numeric project number."
  }
}

variable "policy_parent" {
  type        = string
  description = "(Required) The resource where the organization policies are set: `projects/PROJECT_ID`, `projects/PROJECT_NUMBER`, or `folders/FOLDER_ID`. Use the BYOC project. The rules name the Workload Identity pool of `project_id` only, so a folder applies them to every project in it: use a folder only when it holds only this BYOC project."

  validation {
    condition     = can(regex("^(projects/[a-z0-9-]+|folders/[0-9]+)$", var.policy_parent))
    error_message = "policy_parent must be projects/PROJECT_ID, projects/PROJECT_NUMBER, or folders/FOLDER_ID."
  }
}

variable "live_enforce" {
  type        = bool
  description = "(Optional) When `false`, the policies run in dry-run mode only: violations are logged and not denied. Set to `true` only after you review the dry-run logs."
  default     = false
}

variable "workload_identity_namespace_prefix" {
  type        = string
  description = "(Optional) A Kubernetes namespace prefix that Workload Identity members must also match, for example `ns-`. Empty allows every namespace of the project Workload Identity pool. A prefix narrows the members, but any namespace that starts with the prefix still matches."
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9-]*$", var.workload_identity_namespace_prefix))
    error_message = "workload_identity_namespace_prefix can contain only lowercase letters, digits, and hyphens."
  }
}

variable "enable_storage_member_rule" {
  type        = bool
  description = "(Optional) UNVERIFIED. Also restrict who can receive Cloud Storage roles in `policy_parent`. Keep `false` until the ClickHouse bucket tests pass. When `true`, every member of a `roles/storage.*` role, or of a role in `storage_custom_roles`, must be a Workload Identity member of the project or a member in `storage_allowed_members`. `allUsers` and `allAuthenticatedUsers` are then denied. This rule applies to all grants in `policy_parent`, also grants by your administrators."
  default     = false
}

variable "storage_allowed_members" {
  type        = list(string)
  description = "(Optional) Exact member strings that can receive Cloud Storage roles when `enable_storage_member_rule` is `true`, for example `serviceAccount:SPOKEN-clickhouse@PROJECT_ID.iam.gserviceaccount.com` or `group:storage-admins@example.com`. List every principal that you grant storage roles to. Do not list the ClickHouse data plane management service account (SPOKEN-dp-mgmt)."
  default     = []
}

variable "storage_custom_roles" {
  type        = list(string)
  description = "(Optional) Full names of custom roles that also give bucket access and are covered by the storage member rule, for example `projects/PROJECT_ID/roles/clickhouseBucketReaderRole`."
  default     = []
}

variable "storage_policy_admin_roles" {
  type        = list(string)
  description = "(Optional) Roles that can change bucket allow policies. When `enable_storage_member_rule` is `true`, these roles cannot be granted to a Workload Identity member, so a pod cannot change bucket allow policies."
  default     = ["roles/storage.admin", "roles/storage.legacyBucketOwner"]
}

variable "enforce_public_access_prevention" {
  type        = bool
  description = "(Optional) Enforce the managed `storage.publicAccessPrevention` constraint on `policy_parent`. Then no bucket in scope can be made public. This policy has no dry-run in this module: it is enforced when `true`."
  default     = false
}
