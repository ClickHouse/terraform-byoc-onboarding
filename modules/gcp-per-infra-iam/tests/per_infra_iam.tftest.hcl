# Plan-only tests with a mocked Google provider. They need no credentials and make no API call.
# Run them with: terraform init -backend=false && terraform test

mock_provider "google" {
  # The service account email and member are known after apply. Give the mock the same shape as
  # the real values, so that the plan-time assertions can read them.
  override_resource {
    target = google_service_account.this
    values = {
      member = "serviceAccount:mock@byoc-test-project.iam.gserviceaccount.com"
    }
  }
}

variables {
  project_id  = "byoc-test-project"
  spoken_name = "acme-prod"
  region      = "us-east1"
}

# The names are the contract with the crossplane-xrd chart
# (helm-charts/crossplane-xrd/files/gcp/byo-iam-names.yaml in data-plane-application).
run "creates_the_7_service_accounts_with_fixed_names" {
  command = plan

  assert {
    condition = toset([for sa in google_service_account.this : sa.account_id]) == toset([
      "acme-prod-clickhouse",
      "acme-prod-scraper",
      "acme-prod-kmf",
      "acme-prod-gke-node",
      "acme-prod-monitoring",
      "acme-prod-dp-mgmt",
      "acme-prod-tde-delegate",
    ])
    error_message = "service account names do not match the contract"
  }

  assert {
    condition     = alltrue([for sa in google_service_account.this : strcontains(sa.description, "clickhouse-byo-iam-version=1")])
    error_message = "every service account must carry the version stamp"
  }
}

# The prefix must equal the value that data-plane-management computes. The
# data-plane-management unit tests assert the same values.
run "bucket_prefix_matches_dpm" {
  command = plan

  assert {
    condition     = output.bucket_prefix == "ch_acme-prod_us-east1_"
    error_message = "bucket prefix for acme-prod in us-east1 must be ch_acme-prod_us-east1_"
  }

  assert {
    condition     = google_project_iam_member.dp_mgmt_bucket_role.condition[0].expression == "resource.name.startsWith(\"projects/_/buckets/ch_acme-prod_us-east1_\")"
    error_message = "dp-mgmt bucket role must be conditioned on the infra bucket prefix"
  }

  assert {
    condition = alltrue([
      for m in google_project_iam_member.clickhouse_buckets : m.condition[0].expression == "resource.name.startsWith(\"projects/_/buckets/ch_acme-prod_us-east1_\")"
    ])
    error_message = "ClickHouse server bucket roles must be conditioned on the infra bucket prefix"
  }
}

# Longest production region plus a 17-character spoken name. The condition still uses the
# underscore delimiter, so it stays unique.
run "bucket_prefix_longest_region" {
  command = plan

  variables {
    spoken_name = "abcdefghijklmnopq"
    region      = "northamerica-northeast2"
  }

  assert {
    condition     = output.bucket_prefix == "ch_abcdefghijklmnopq_northamerica-northeast2_"
    error_message = "bucket prefix for a 17-character spoken name in northamerica-northeast2 must include the region"
  }

  assert {
    condition     = google_project_iam_member.dp_mgmt_bucket_role.condition[0].expression == "resource.name.startsWith(\"projects/_/buckets/ch_abcdefghijklmnopq_northamerica-northeast2_\")"
    error_message = "dp-mgmt bucket role must be conditioned on the longest-region prefix"
  }
}

run "restore_sources_get_read_only_grants" {
  command = plan

  variables {
    restore_source_spoken_names = ["lemon-ab-12", "x9"]
  }

  assert {
    condition     = length(google_project_iam_member.clickhouse_restore_sources) == 4
    error_message = "each restore source needs objectViewer and clickhouseBucketReaderRole"
  }

  assert {
    condition     = google_project_iam_member.clickhouse_restore_sources["lemon-ab-12/roles/storage.objectViewer"].condition[0].expression == "resource.name.startsWith(\"projects/_/buckets/ch_lemon-ab-12_\")"
    error_message = "restore source grant must use the prefix of the source infra"
  }

  assert {
    condition     = google_project_iam_member.clickhouse_restore_sources["x9/projects/byoc-test-project/roles/clickhouseBucketReaderRole"].condition[0].expression == "resource.name.startsWith(\"projects/_/buckets/ch_x9_\")"
    error_message = "restore source grant must use the prefix of the source infra"
  }

  assert {
    condition     = alltrue([for m in google_project_iam_member.clickhouse_restore_sources : contains(["roles/storage.objectViewer", "projects/byoc-test-project/roles/clickhouseBucketReaderRole"], m.role)])
    error_message = "restore source grants must be read only"
  }
}

# The binder is granted on 4 service accounts only, never at project level.
run "binder_is_granted_on_4_service_accounts" {
  command = plan

  assert {
    condition     = toset(keys(google_service_account_iam_member.workload_identity_binder)) == toset(["clickhouse", "scraper", "kmf", "monitoring"])
    error_message = "binder must be granted on clickhouse, scraper, kmf and monitoring only"
  }

  assert {
    condition     = google_service_account_iam_member.workload_identity_binder["clickhouse"].member == "serviceAccount:acme-prod-dp-mgmt@byoc-test-project.iam.gserviceaccount.com"
    error_message = "dp-mgmt adds the per-instance Workload Identity members on the ClickHouse server service account"
  }

  assert {
    condition = alltrue([
      for k in ["scraper", "kmf", "monitoring"] :
      google_service_account_iam_member.workload_identity_binder[k].member == "serviceAccount:clickhouse-management@byoc-test-project.iam.gserviceaccount.com"
    ])
    error_message = "Crossplane adds the static Workload Identity members as clickhouse-management"
  }

  assert {
    condition     = alltrue([for m in google_service_account_iam_member.workload_identity_binder : m.role == "projects/byoc-test-project/roles/clickhouseWorkloadIdentityBinderRole"])
    error_message = "binder grants must use the role defined by the gcp onboarding module"
  }
}

# No grant of this module gives a ClickHouse principal a role that can change IAM, except the
# binder on single service accounts.
run "no_project_level_iam_write" {
  command = plan

  assert {
    condition = alltrue(flatten([
      [for m in google_project_iam_member.cluster_viewer : m.role == "roles/container.clusterViewer"],
      [google_project_iam_member.dp_mgmt_role.role == "projects/byoc-test-project/roles/clickhouseDpMgmtRole"],
      [google_project_iam_member.dp_mgmt_bucket_role.role == "projects/byoc-test-project/roles/clickhouseDpMgmtBucketRole"],
      [google_project_iam_member.gke_node_default_node_sa.role == "roles/container.defaultNodeServiceAccount"],
    ]))
    error_message = "unexpected project role"
  }
}

run "kms_grants_are_scoped_to_the_infra_keys" {
  command = plan

  assert {
    condition = alltrue([
      for m in google_project_iam_member.tde_delegate_kek :
      m.condition[0].expression == "resource.name == \"projects/byoc-test-project/locations/us-east1/keyRings/acme-prod-tde/cryptoKeys/tde-default-kek\" || resource.name.startsWith(\"projects/byoc-test-project/locations/us-east1/keyRings/acme-prod-tde/cryptoKeys/tde-default-kek/\")"
    ])
    error_message = "TDE grants must be scoped to the infra TDE key"
  }

  assert {
    condition = alltrue([
      for m in google_project_iam_member.snc_kek :
      strcontains(m.condition[0].expression, "keyRings/acme-prod-snc/cryptoKeys/snc-kek")
    ])
    error_message = "named collections grants must be scoped to the infra key"
  }
}

run "environment_selects_the_clickhouse_identities" {
  command = plan

  variables {
    environment = "development"
  }

  assert {
    condition     = toset(keys(google_service_account_iam_member.dp_mgmt_token_creator)) == toset(["serviceAccount:us-east1-gke-mgmt@dataplane-development.iam.gserviceaccount.com"])
    error_message = "development must trust the development mgmt identity only"
  }

  assert {
    condition = toset(keys(google_project_iam_member.cluster_viewer)) == toset([
      "serviceAccount:us-east1-gke-mgmt@dataplane-development.iam.gserviceaccount.com",
      "serviceAccount:us-east1-byoc-argocd@dataplane-development.iam.gserviceaccount.com",
    ])
    error_message = "development must grant clusterViewer to the development mgmt and ArgoCD identities"
  }
}

run "rejects_a_spoken_name_longer_than_17_characters" {
  command = plan

  variables {
    spoken_name = "abcdefghijklmnopqr"
  }

  expect_failures = [var.spoken_name]
}
