# Optional organization policy controls for GCP bring your own IAM (BYO IAM). Highly recommended.
# ClickHouse does not apply this module. Your organization policy administrator applies it.
#
# The constraints limit who can be added to IAM allow policies. When ClickHouse binds a
# Kubernetes service account at runtime, these rules make sure that only Kubernetes service
# accounts of the BYOC project can be added, not service account emails, users, or groups.
#
# Apply with live_enforce = false first (dry-run). Review the logs. Then set live_enforce = true.
# https://docs.cloud.google.com/organization-policy/test-policies

resource "google_org_policy_custom_constraint" "this" {
  for_each = local.constraints

  name   = each.value.name
  parent = "organizations/${var.organization_id}"

  display_name = each.value.display_name
  description  = each.value.description

  action_type    = "ALLOW"
  method_types   = ["CREATE", "UPDATE"]
  resource_types = ["iam.googleapis.com/AllowPolicy"]
  condition      = each.value.condition

  lifecycle {
    precondition {
      condition     = length(each.value.condition) <= 1500
      error_message = "The CEL condition is longer than 1500 characters (https://docs.cloud.google.com/organization-policy/create-custom-constraints). Use fewer storage_allowed_members or storage_custom_roles."
    }
  }
}

# The policy has a dry-run spec that is always on, and a live spec that follows live_enforce.
# enforce must be the string "TRUE" or "FALSE".
resource "google_org_policy_policy" "this" {
  for_each = google_org_policy_custom_constraint.this

  name   = "${var.policy_parent}/policies/${each.value.name}"
  parent = var.policy_parent

  dry_run_spec {
    rules {
      enforce = "TRUE"
    }
  }

  spec {
    rules {
      enforce = var.live_enforce ? "TRUE" : "FALSE"
    }
  }
}

# Managed constraint: no bucket in policy_parent can be made public.
# https://docs.cloud.google.com/storage/docs/public-access-prevention
resource "google_org_policy_policy" "public_access_prevention" {
  count = var.enforce_public_access_prevention ? 1 : 0

  name   = "${var.policy_parent}/policies/storage.publicAccessPrevention"
  parent = var.policy_parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}
