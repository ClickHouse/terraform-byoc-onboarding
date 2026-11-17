locals {
  # Workload Identity members of the project pool. The legacy form is the one that ClickHouse
  # writes today. The principal:// form is the official federated form.
  # https://docs.cloud.google.com/iam/docs/principal-identifiers
  wi_pool          = "${var.project_id}.svc.id.goog"
  wi_principal     = "principal://iam.googleapis.com/projects/${var.project_number}/locations/global/workloadIdentityPools/${local.wi_pool}/subject/ns/"
  wi_member_legacy = "serviceAccount:${local.wi_pool}[${var.workload_identity_namespace_prefix}"
  wi_member_new    = "${local.wi_principal}${var.workload_identity_namespace_prefix}"

  # Constraint names are unique in the organization, so they carry the project number.
  # Names: custom. followed by letters and digits only, at most 70 characters after custom.
  # https://docs.cloud.google.com/organization-policy/create-custom-constraints
  wi_constraint_name      = "custom.clickhouseByocWiMembers${var.project_number}"
  storage_constraint_name = "custom.clickhouseByocStorageMembers${var.project_number}"
  storage_admin_name      = "custom.clickhouseByocStorageAdmin${var.project_number}"

  # Supported CEL functions: https://docs.cloud.google.com/iam/docs/org-policy-custom-constraints
  # UNVERIFIED: that page shows && and ||, and does not show !. Confirm that the API accepts
  # !RoleNameMatches(...) before you enforce.
  wi_condition = "resource.bindings.all(binding, !RoleNameMatches(binding.role, ['roles/iam.workloadIdentityUser']) || binding.members.all(member, MemberSubjectStartsWith(member, ['${local.wi_member_legacy}', '${local.wi_member_new}'])))"

  storage_role_match = length(var.storage_custom_roles) == 0 ? "RoleNameStartsWith(binding.role, ['roles/storage.'])" : "(RoleNameStartsWith(binding.role, ['roles/storage.']) || RoleNameMatches(binding.role, [${join(", ", formatlist("'%s'", var.storage_custom_roles))}]))"

  storage_member_match = length(var.storage_allowed_members) == 0 ? "MemberSubjectStartsWith(member, ['${local.wi_member_new}'])" : "(MemberSubjectStartsWith(member, ['${local.wi_member_new}']) || MemberSubjectMatches(member, [${join(", ", formatlist("'%s'", var.storage_allowed_members))}]))"

  # UNVERIFIED (pending the TC-BUCKET tests): that the constraint applies to bucket allow
  # policies, and that this condition shape is accepted.
  storage_condition = "resource.bindings.all(binding, !${local.storage_role_match} || binding.members.all(member, ${local.storage_member_match}))"

  storage_admin_condition = "resource.bindings.all(binding, !RoleNameMatches(binding.role, [${join(", ", formatlist("'%s'", var.storage_policy_admin_roles))}]) || binding.members.all(member, !MemberSubjectStartsWith(member, ['principal://'])))"

  constraints = merge(
    {
      wi = {
        name         = local.wi_constraint_name
        display_name = "ClickHouse BYOC: Workload Identity members only"
        description  = "roles/iam.workloadIdentityUser members must be Kubernetes service accounts of the Workload Identity pool of project ${var.project_id}. Service account emails, users, groups, and principalSet identifiers are denied on that role."
        condition    = local.wi_condition
      }
    },
    var.enable_storage_member_rule ? {
      storage = {
        name         = local.storage_constraint_name
        display_name = "ClickHouse BYOC: storage role members (unverified)"
        description  = "Members of Cloud Storage roles must be Kubernetes service accounts of the Workload Identity pool of project ${var.project_id}, or listed members. allUsers and allAuthenticatedUsers are denied."
        condition    = local.storage_condition
      }
      storage_admin = {
        name         = local.storage_admin_name
        display_name = "ClickHouse BYOC: no bucket policy admin for workloads (unverified)"
        description  = "Roles that can change bucket allow policies cannot be granted to principal:// members."
        condition    = local.storage_admin_condition
      }
    } : {},
  )
}
