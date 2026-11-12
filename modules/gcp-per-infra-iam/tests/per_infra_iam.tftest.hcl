# Plan-only tests with a mocked Google provider. They need no credentials and make no API call.
# mock_provider requires Terraform 1.7 or later. CI runs Terraform 1.9.8.
# Run them with: terraform init -backend=false && terraform test

mock_provider "google" {
  # The service account email and member are known after apply. Give each key its
  # own member so a grant wired to the wrong service account fails the test.
  override_resource {
    target          = google_service_account.this["clickhouse"]
    override_during = plan
    values = {
      member = "serviceAccount:acme-prod-clickhouse@byoc-test-project.iam.gserviceaccount.com"
      email  = "acme-prod-clickhouse@byoc-test-project.iam.gserviceaccount.com"
      name   = "projects/byoc-test-project/serviceAccounts/acme-prod-clickhouse@byoc-test-project.iam.gserviceaccount.com"
    }
  }

  override_resource {
    target          = google_service_account.this["scraper"]
    override_during = plan
    values = {
      member = "serviceAccount:acme-prod-scraper@byoc-test-project.iam.gserviceaccount.com"
      email  = "acme-prod-scraper@byoc-test-project.iam.gserviceaccount.com"
      name   = "projects/byoc-test-project/serviceAccounts/acme-prod-scraper@byoc-test-project.iam.gserviceaccount.com"
    }
  }

  override_resource {
    target          = google_service_account.this["kmf"]
    override_during = plan
    values = {
      member = "serviceAccount:acme-prod-kmf@byoc-test-project.iam.gserviceaccount.com"
      email  = "acme-prod-kmf@byoc-test-project.iam.gserviceaccount.com"
      name   = "projects/byoc-test-project/serviceAccounts/acme-prod-kmf@byoc-test-project.iam.gserviceaccount.com"
    }
  }

  override_resource {
    target          = google_service_account.this["gke_node"]
    override_during = plan
    values = {
      member = "serviceAccount:acme-prod-gke-node@byoc-test-project.iam.gserviceaccount.com"
      email  = "acme-prod-gke-node@byoc-test-project.iam.gserviceaccount.com"
      name   = "projects/byoc-test-project/serviceAccounts/acme-prod-gke-node@byoc-test-project.iam.gserviceaccount.com"
    }
  }

  override_resource {
    target          = google_service_account.this["monitoring"]
    override_during = plan
    values = {
      member = "serviceAccount:acme-prod-monitoring@byoc-test-project.iam.gserviceaccount.com"
      email  = "acme-prod-monitoring@byoc-test-project.iam.gserviceaccount.com"
      name   = "projects/byoc-test-project/serviceAccounts/acme-prod-monitoring@byoc-test-project.iam.gserviceaccount.com"
    }
  }

  override_resource {
    target          = google_service_account.this["dp_mgmt"]
    override_during = plan
    values = {
      member = "serviceAccount:acme-prod-dp-mgmt@byoc-test-project.iam.gserviceaccount.com"
      email  = "acme-prod-dp-mgmt@byoc-test-project.iam.gserviceaccount.com"
      name   = "projects/byoc-test-project/serviceAccounts/acme-prod-dp-mgmt@byoc-test-project.iam.gserviceaccount.com"
    }
  }

  override_resource {
    target          = google_service_account.this["tde_delegate"]
    override_during = plan
    values = {
      member = "serviceAccount:acme-prod-tde-delegate@byoc-test-project.iam.gserviceaccount.com"
      email  = "acme-prod-tde-delegate@byoc-test-project.iam.gserviceaccount.com"
      name   = "projects/byoc-test-project/serviceAccounts/acme-prod-tde-delegate@byoc-test-project.iam.gserviceaccount.com"
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

  variables {
    restore_source_spoken_names = ["lemon-ab-12"]
  }

  assert {
    condition = alltrue([
      for m in flatten([
        [google_project_iam_member.dp_mgmt_role],
        [google_project_iam_member.dp_mgmt_bucket_role],
        [google_project_iam_member.gke_node_default_node_sa],
        values(google_project_iam_member.cluster_viewer),
        values(google_project_iam_member.clickhouse_buckets),
        values(google_project_iam_member.clickhouse_restore_sources),
        [google_project_iam_member.monitoring_bucket],
        values(google_project_iam_member.tde_delegate_kek),
        values(google_project_iam_member.snc_kek),
        ]) : contains([
        "projects/byoc-test-project/roles/clickhouseDpMgmtRole",
        "projects/byoc-test-project/roles/clickhouseDpMgmtBucketRole",
        "projects/byoc-test-project/roles/clickhouseBucketReaderRole",
        "roles/container.defaultNodeServiceAccount",
        "roles/container.clusterViewer",
        "roles/storage.objectUser",
        "roles/storage.objectViewer",
        "roles/storage.objectAdmin",
        "roles/cloudkms.cryptoKeyEncrypterDecrypter",
        "roles/cloudkms.viewer",
        "roles/cloudkms.cryptoKeyEncrypter",
        "roles/cloudkms.cryptoKeyDecrypter",
      ], m.role)
    ])
    error_message = "unexpected project role"
  }

  assert {
    condition     = google_project_iam_member.monitoring_bucket.member == google_service_account.this["monitoring"].member
    error_message = "the monitoring bucket grant must go to the monitoring service account"
  }

  assert {
    condition = alltrue([
      for m in values(google_project_iam_member.clickhouse_buckets) : m.member == google_service_account.this["clickhouse"].member
    ])
    error_message = "instance bucket grants must go to the ClickHouse server service account"
  }

  assert {
    condition = alltrue([
      for m in values(google_project_iam_member.tde_delegate_kek) : m.member == google_service_account.this["tde_delegate"].member
    ])
    error_message = "TDE key grants must go to the TDE delegate service account"
  }

  assert {
    condition = alltrue([
      for k, m in google_project_iam_member.snc_kek :
      (k == "dp_mgmt_encrypter" && m.member == google_service_account.this["dp_mgmt"].member) ||
      (k == "clickhouse_decrypter" && m.member == google_service_account.this["clickhouse"].member)
    ])
    error_message = "named collections grants must go to dp-mgmt and the ClickHouse server"
  }

  assert {
    condition     = google_project_iam_member.gke_node_default_node_sa.member == google_service_account.this["gke_node"].member
    error_message = "the default node service account role must go to the GKE node service account"
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

run "monitoring_bucket_condition_matches_the_infra_name" {
  command = plan

  assert {
    condition = google_project_iam_member.monitoring_bucket.condition[0].expression == join(" || ", [
      "(resource.name.startsWith(\"projects/_/buckets/acme-prod_\") && resource.name.extract(\"projects/_/buckets/{bucket}/objects/\") == \"\" && resource.name.endsWith(\"_gcp_clickhouse_cloud-monitoring\"))",
      "(resource.name.extract(\"projects/_/buckets/{bucket}/objects/\").startsWith(\"acme-prod_\") && resource.name.extract(\"projects/_/buckets/{bucket}/objects/\").endsWith(\"_gcp_clickhouse_cloud-monitoring\"))",
    ])
    error_message = "monitoring bucket condition must match only this infra's monitoring bucket"
  }
}

run "accepts_a_spoken_name_of_17_characters" {
  command = plan

  variables {
    spoken_name = "abcdefghijklmnopq"
  }

  assert {
    condition     = google_service_account.this["tde_delegate"].account_id == "abcdefghijklmnopq-tde-delegate"
    error_message = "a 17-character spoken name must be accepted"
  }
}

run "rejects_an_invalid_region" {
  command = plan

  variables {
    region = "US-EAST-1"
  }

  expect_failures = [var.region]
}

run "rejects_an_invalid_restore_source_spoken_name" {
  command = plan

  variables {
    restore_source_spoken_names = ["Acme"]
  }

  expect_failures = [var.restore_source_spoken_names]
}

