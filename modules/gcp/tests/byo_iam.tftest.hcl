# Plan-only tests with a mocked Google provider. They need no credentials and make no API call.
# Run them with: terraform init -backend=false && terraform test

mock_provider "google" {}

variables {
  project_id = "byoc-test-project"
}

# Default mode must not change: the permission lists of the gated roles are the same as before
# include_iam_write_permissions was added.
run "default_mode_is_unchanged" {
  command = plan

  variables {
    include_tde_permissions = true
  }

  assert {
    condition = toset(google_project_iam_custom_role.clickhouse_iam_role.permissions) == toset([
      "resourcemanager.projects.setIamPolicy",
      "resourcemanager.projects.getIamPolicy",
      "iam.serviceAccounts.create",
      "iam.serviceAccounts.createTagBinding",
      "iam.serviceAccounts.delete",
      "iam.serviceAccounts.deleteTagBinding",
      "iam.serviceAccounts.disable",
      "iam.serviceAccounts.enable",
      "iam.serviceAccounts.get",
      "iam.serviceAccounts.getIamPolicy",
      "iam.serviceAccounts.list",
      "iam.serviceAccounts.listEffectiveTags",
      "iam.serviceAccounts.listTagBindings",
      "iam.serviceAccounts.setIamPolicy",
      "iam.serviceAccounts.undelete",
      "iam.serviceAccounts.update",
      "iam.roles.create",
      "iam.roles.delete",
      "iam.roles.get",
      "iam.roles.list",
      "iam.roles.undelete",
      "iam.roles.update",
    ])
    error_message = "clickhouseIamRole changed in default mode"
  }

  assert {
    condition = toset(google_project_iam_custom_role.clickhouse_storage_role.permissions) == toset([
      "storage.buckets.create",
      "storage.buckets.createTagBinding",
      "storage.buckets.delete",
      "storage.buckets.deleteTagBinding",
      "storage.buckets.enableObjectRetention",
      "storage.buckets.get",
      "storage.buckets.getIamPolicy",
      "storage.buckets.getIpFilter",
      "storage.buckets.getObjectInsights",
      "storage.buckets.list",
      "storage.buckets.listEffectiveTags",
      "storage.buckets.listTagBindings",
      "storage.buckets.relocate",
      "storage.buckets.restore",
      "storage.buckets.setIamPolicy",
      "storage.buckets.setIpFilter",
      "storage.buckets.update",
      "storage.anywhereCaches.list",
    ])
    error_message = "clickhouseStorageRole changed in default mode"
  }

  assert {
    condition = toset(google_project_iam_custom_role.clickhouse_tde_role[0].permissions) == toset([
      "cloudkms.keyRings.create",
      "cloudkms.keyRings.get",
      "cloudkms.keyRings.list",
      "cloudkms.cryptoKeys.create",
      "cloudkms.cryptoKeys.get",
      "cloudkms.cryptoKeys.list",
      "cloudkms.cryptoKeys.update",
      "cloudkms.cryptoKeys.getIamPolicy",
      "cloudkms.cryptoKeys.setIamPolicy",
    ])
    error_message = "clickhouseTdeRole changed in default mode"
  }

  assert {
    condition = toset(google_project_iam_custom_role.clickhouse_vpc_write_role[0].permissions) == toset([
      "compute.networks.addPeering",
      "compute.networks.create",
      "compute.networks.createTagBinding",
      "compute.networks.delete",
      "compute.networks.deleteTagBinding",
      "compute.networks.mirror",
      "compute.networks.removePeering",
      "compute.networks.setFirewallPolicy",
      "compute.networks.switchToCustomMode",
      "compute.networks.update",
      "compute.networks.updatePeering",
      "compute.subnetworks.create",
      "compute.subnetworks.createTagBinding",
      "compute.subnetworks.delete",
      "compute.subnetworks.deleteTagBinding",
      "compute.subnetworks.expandIpCidrRange",
      "compute.subnetworks.mirror",
      "compute.subnetworks.setIamPolicy",
      "compute.subnetworks.setPrivateIpGoogleAccess",
      "compute.subnetworks.update",
      "compute.routes.create",
      "compute.routes.createTagBinding",
      "compute.routes.delete",
      "compute.routes.deleteTagBinding",
      "compute.routers.create",
      "compute.routers.createTagBinding",
      "compute.routers.delete",
      "compute.routers.deleteRoutePolicy",
      "compute.routers.deleteTagBinding",
      "compute.routers.update",
      "compute.routers.updateRoutePolicy",
      "compute.addresses.createTagBinding",
      "compute.addresses.deleteTagBinding",
    ])
    error_message = "clickhouseVPCWriteRole changed in default mode"
  }

  assert {
    condition     = google_project_iam_custom_role.clickhouse_iam_role.description == "Role to allow ClickHouse Cloud to manage IAM resources in your project"
    error_message = "clickhouseIamRole description changed in default mode"
  }

  assert {
    condition     = length(google_project_iam_member.clickhouse_sa_roles) == 7
    error_message = "the set of role bindings of clickhouse-management changed in default mode"
  }
}

# Bring your own IAM: no role bound to clickhouse-management can create service accounts or
# roles, or set an IAM policy.
run "byo_iam_removes_iam_writes" {
  command = plan

  variables {
    include_iam_write_permissions = false
    include_tde_permissions       = true
  }

  assert {
    condition = alltrue([
      for p in flatten([
        google_project_iam_custom_role.clickhouse_common_role.permissions,
        google_project_iam_custom_role.clickhouse_vpc_role.permissions,
        google_project_iam_custom_role.clickhouse_vpc_write_role[0].permissions,
        google_project_iam_custom_role.clickhouse_cluster_role.permissions,
        google_project_iam_custom_role.clickhouse_storage_role.permissions,
        google_project_iam_custom_role.clickhouse_storage_objects_role.permissions,
        google_project_iam_custom_role.clickhouse_iam_role.permissions,
        google_project_iam_custom_role.clickhouse_tde_role[0].permissions,
      ]) : !endswith(p, ".setIamPolicy") && !startswith(p, "iam.roles.create") && !startswith(p, "iam.roles.update") && !startswith(p, "iam.roles.delete") && p != "iam.serviceAccounts.create" && p != "iam.serviceAccounts.delete"
    ])
    error_message = "a role bound to clickhouse-management still holds an IAM write permission"
  }

  assert {
    condition = toset(google_project_iam_custom_role.clickhouse_iam_role.permissions) == toset([
      "resourcemanager.projects.getIamPolicy",
      "iam.serviceAccounts.get",
      "iam.serviceAccounts.getIamPolicy",
      "iam.serviceAccounts.list",
      "iam.roles.get",
      "iam.roles.list",
    ])
    error_message = "clickhouseIamRole must keep only the IAM read permissions"
  }

  # The role keeps its ID and binding, so a change of the variable changes no binding.
  assert {
    condition     = google_project_iam_custom_role.clickhouse_iam_role.role_id == "clickhouseIamRole" && contains(keys(google_project_iam_member.clickhouse_sa_roles), "iam_role")
    error_message = "clickhouseIamRole must stay bound to clickhouse-management"
  }

  # actAs stays: GKE node pools run as the customer-created node service account.
  assert {
    condition     = contains(google_project_iam_custom_role.clickhouse_common_role.permissions, "iam.serviceAccounts.actAs")
    error_message = "clickhouseCommonRole must keep iam.serviceAccounts.actAs"
  }
}

# The roles that gcp-per-infra-iam binds exist in both modes, with fixed IDs, and none of them
# can grant a project or bucket role.
run "byo_iam_roles_are_created_in_both_modes" {
  command = plan

  assert {
    condition = (
      google_project_iam_custom_role.clickhouse_dp_mgmt_role.role_id == "clickhouseDpMgmtRole" &&
      google_project_iam_custom_role.clickhouse_dp_mgmt_bucket_role.role_id == "clickhouseDpMgmtBucketRole" &&
      google_project_iam_custom_role.clickhouse_workload_identity_binder_role.role_id == "clickhouseWorkloadIdentityBinderRole"
    )
    error_message = "the BYO-IAM role IDs are a contract with gcp-per-infra-iam and must not change"
  }

  assert {
    condition = alltrue([
      for p in setunion(
        google_project_iam_custom_role.clickhouse_dp_mgmt_role.permissions,
        google_project_iam_custom_role.clickhouse_dp_mgmt_bucket_role.permissions,
      ) : !endswith(p, ".setIamPolicy") && !startswith(p, "iam.roles.")
    ])
    error_message = "the dp-mgmt roles must hold no permission to grant roles"
  }

  assert {
    condition = !anytrue([
      for p in setunion(
        google_project_iam_custom_role.clickhouse_dp_mgmt_role.permissions,
        google_project_iam_custom_role.clickhouse_dp_mgmt_bucket_role.permissions,
      ) : contains(["storage.objects.create", "storage.objects.get"], p)
    ])
    error_message = "dp-mgmt does not read or write objects on BYOC (remote settings do not run on BYOC)"
  }

  assert {
    condition = toset(google_project_iam_custom_role.clickhouse_workload_identity_binder_role.permissions) == toset([
      "iam.serviceAccounts.get",
      "iam.serviceAccounts.getIamPolicy",
      "iam.serviceAccounts.setIamPolicy",
    ])
    error_message = "the binder role must hold only the service account IAM policy permissions"
  }
}
