# Optional organization policy controls for GCP bring your own IAM (BYO IAM). Highly recommended.
# ClickHouse does not apply this module. Your organization policy administrator applies it.
#
# The constraints limit who can be added to IAM allow policies. When ClickHouse binds a
# Kubernetes service account at runtime, these rules make sure that only Kubernetes service
# accounts of the BYOC project can be added, not service account emails, users, or groups.
# A second constraint denies token-creator roles to the ClickHouse identities that can
# change service account allow policies.
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
#
# Writes of organization policies on one parent return HTTP 409 when they run together,
# so each policy depends on the previous one. Order: wi, token, storage, storage_admin,
# then public access prevention. Constraints stay parallel.

resource "google_org_policy_policy" "wi" {
  name   = "${var.policy_parent}/policies/${google_org_policy_custom_constraint.this["wi"].name}"
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

resource "google_org_policy_policy" "token" {
  depends_on = [google_org_policy_policy.wi]

  name   = "${var.policy_parent}/policies/${google_org_policy_custom_constraint.this["token"].name}"
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

resource "google_org_policy_policy" "storage" {
  count = var.enable_storage_member_rule ? 1 : 0

  depends_on = [
    google_org_policy_custom_constraint.this,
    google_org_policy_policy.token,
  ]

  name   = "${var.policy_parent}/policies/${local.storage_constraint_name}"
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

resource "google_org_policy_policy" "storage_admin" {
  count = var.enable_storage_member_rule ? 1 : 0

  depends_on = [
    google_org_policy_custom_constraint.this,
    google_org_policy_policy.storage,
  ]

  name   = "${var.policy_parent}/policies/${local.storage_admin_name}"
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

  # token always exists. storage_admin exists only when the storage rule is on;
  # depending on the empty resource is a no-op, and storage_admin already waits
  # for storage and token.
  depends_on = [
    google_org_policy_policy.token,
    google_org_policy_policy.storage_admin,
  ]

  name   = "${var.policy_parent}/policies/storage.publicAccessPrevention"
  parent = var.policy_parent

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

moved {
  from = google_org_policy_policy.this["wi"]
  to   = google_org_policy_policy.wi
}

moved {
  from = google_org_policy_policy.this["storage"]
  to   = google_org_policy_policy.storage[0]
}

moved {
  from = google_org_policy_policy.this["storage_admin"]
  to   = google_org_policy_policy.storage_admin[0]
}
