# ClickHouse BYOC GCP Bring Your Own IAM Organization Constraint Module

This module is optional. It is highly recommended when you bring your own IAM (BYO IAM) for ClickHouse BYOC on GCP.

With BYO IAM, ClickHouse keeps one IAM write: it adds a Workload Identity member for each new ClickHouse service on a few service accounts of the infra. IAM cannot limit the members that this write adds. This module adds that limit with organization policy custom constraints. Then only Kubernetes service accounts of your BYOC project can be added. Service account emails, users, and groups are denied.

ClickHouse does not apply this module, and ClickHouse does not get organization policy permissions. Your organization policy administrator applies it and controls it.

## What the module creates

- A custom constraint at your organization, on `iam.googleapis.com/AllowPolicy`. Members of `roles/iam.workloadIdentityUser` must start with `serviceAccount:PROJECT_ID.svc.id.goog[` or `principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/PROJECT_ID.svc.id.goog/subject/ns/`. Other roles are not restricted by this constraint.
- A custom constraint that denies `roles/iam.serviceAccountTokenCreator` and `roles/iam.serviceAccountOpenIdTokenCreator` to the ClickHouse service accounts `*-dp-mgmt` and `clickhouse-management` of the project. See "Token role rule."
- An organization policy for each custom constraint on `policy_parent` (a project or a folder). The dry-run spec is always on. The live spec is on only when `live_enforce = true`. Terraform writes these policies one after another.
- Optional, `enable_storage_member_rule`: two more constraints and policies for Cloud Storage roles. See "Storage member rule (unverified)."
- Optional, `enforce_public_access_prevention`: a policy that enforces the managed `storage.publicAccessPrevention` constraint on `policy_parent`.

Constraint names contain the project number, so you can apply the module once for each BYOC project in the same organization. The rules name identities of one project. Set `policy_parent` to that project. If you use a folder, the rules apply to every project in the folder, so use a folder only when it holds only that BYOC project.

## Requirements

- Organization Policy Administrator (`roles/orgpolicy.policyAdmin`) on the organization. A custom constraint can be created only at the organization.
- Billing must be enabled on the project for dry-run.
- The Organization Policy API (`orgpolicy.googleapis.com`) enabled on the project that your Terraform credentials use.
- To read the dry-run logs: Logs Viewer (`roles/logging.viewer`) on the project.

## Usage

```hcl
module "clickhouse_byo_iam_org_constraint" {
  source          = "github.com/ClickHouse/terraform-byoc-onboarding.git//modules/gcp-byo-iam-org-constraint?ref=<version>"
  organization_id = "123456789012"
  project_id      = "replace-with-your-clickhouse-byoc-project-id"
  project_number  = "replace-with-your-clickhouse-byoc-project-number"
  policy_parent   = "projects/replace-with-your-clickhouse-byoc-project-id"

  # Dry-run first. Set to true after you review the logs.
  live_enforce = false
}
```

Replace `<version>` with the latest tag from the
[releases page](https://github.com/ClickHouse/terraform-byoc-onboarding/releases).

## Step 1: dry-run

1. Apply the module with `live_enforce = false`.
2. Wait up to 15 minutes. A new policy can take that long to take effect.
3. Use ClickHouse as usual. Create a ClickHouse service, so that ClickHouse adds a Workload Identity member.
4. Read the policy audit logs:

```sh
gcloud logging read \
  'logName="projects/PROJECT_ID/logs/cloudaudit.googleapis.com%2Fpolicy" AND protoPayload.metadata.dryRunResult="DENIED"' \
  --project=PROJECT_ID --freshness=1d
```

In the Google Cloud console, use Logs Explorer with the same filter.

5. Make sure that no entry is for a ClickHouse member. A ClickHouse member starts with `serviceAccount:PROJECT_ID.svc.id.goog[` or `principal://`. An entry for a grant that you expect, for example by your own administrators, shows that the rule is too strict for your project. Do not enforce until you know the cause.

Note: dry-run logs for `setIamPolicy` can have no `resourceName`, `serviceName`, or `methodName`. If you see no dry-run log, this is not proof that the policy has no effect.

## Step 2: enforce

1. Set `live_enforce = true`.
2. Apply the module again.
3. Wait up to 15 minutes.
4. Create a ClickHouse service. Make sure that it starts.

The dry-run spec stays on after you enforce.

## Roll back

- To go back to dry-run only: set `live_enforce = false` and apply. The constraints stay. No grant is denied.
- To remove all: run `terraform destroy` for this module. Terraform deletes the policies, then the constraints.

A person who can set organization policies on the project can also turn the policy off there. Give `roles/orgpolicy.policyAdmin` only to people you trust. Do not give it to ClickHouse identities.

## Token role rule

The module always creates a second constraint for `roles/iam.serviceAccountTokenCreator` and `roles/iam.serviceAccountOpenIdTokenCreator`. These roles also let a member mint tokens for a service account. The rule denies these roles to the two ClickHouse identities that can change service account allow policies:

- Every `SPOKEN-dp-mgmt` service account of the project (member ends with `-dp-mgmt@PROJECT_ID.iam.gserviceaccount.com`).
- `clickhouse-management@PROJECT_ID.iam.gserviceaccount.com`.

The rule does not limit other members. Grants to your own principals stay your responsibility. The rule needs no change when you add an infra to the project.

## Options

### Namespace prefix

`workload_identity_namespace_prefix = "ns-"` also requires the Kubernetes namespace to start with `ns-`. ClickHouse service namespaces start with `ns-`. This narrows the members. A namespace such as `ns-other` still matches.

### Public access prevention

`enforce_public_access_prevention = true` enforces the managed `storage.publicAccessPrevention` constraint on `policy_parent`. Then no bucket in scope can be made public. This policy has no dry-run in this module. Make sure that no bucket in scope must be public before you set it.

### Storage member rule (unverified)

UNVERIFIED. Keep `enable_storage_member_rule = false`. This option is for a future ClickHouse release that gives each ClickHouse service its own bucket grant. Tests that confirm that the constraint applies to bucket allow policies are pending.

When `true`:

- Every member of a `roles/storage.*` role, or of a role in `storage_custom_roles`, must be a Kubernetes service account of the project Workload Identity pool, or a member in `storage_allowed_members`. `allUsers` and `allAuthenticatedUsers` are denied.
- The roles in `storage_policy_admin_roles` cannot be granted to a `principal://` member.

Read this before you set it:

- The rule applies to all grants in `policy_parent`, also grants by your administrators and by other Terraform. List in `storage_allowed_members` every principal that you grant storage roles to. A project that holds only ClickHouse BYOC is the simple case.
- Do not list the ClickHouse data plane management service account (`SPOKEN-dp-mgmt`).
- A constraint cannot read the permissions of a custom role. Add custom roles that give bucket access to `storage_custom_roles`.
- Each condition can have at most 1,500 characters. Long lists can make it too long. The module then fails before it creates the constraint.

## Limits

- The constraints check only the roles and members that a change adds or removes. Default grants by Cloud Storage and roles that Google Cloud grants by default are not affected.
- The Workload Identity pool is for the project. All GKE clusters in the project share it, and IAM treats the same namespace and Kubernetes service account in two clusters as the same identity.

## References

- Custom constraints for allow policies: https://docs.cloud.google.com/iam/docs/org-policy-custom-constraints
- Create custom constraints: https://docs.cloud.google.com/organization-policy/create-custom-constraints
- Dry-run: https://docs.cloud.google.com/organization-policy/test-policies
- Principal identifiers: https://docs.cloud.google.com/iam/docs/principal-identifiers
- Public access prevention: https://docs.cloud.google.com/storage/docs/public-access-prevention
- Workload Identity Federation for GKE: https://docs.cloud.google.com/kubernetes-engine/docs/concepts/workload-identity

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| organization_id | (Required) The numeric ID of your Google Cloud organization | string | n/a | yes |
| project_id | (Required) The ID of the GCP project where ClickHouse BYOC runs | string | n/a | yes |
| project_number | (Required) The numeric project number of `project_id` | string | n/a | yes |
| policy_parent | (Required) Where the policies are set: `projects/PROJECT_ID`, `projects/PROJECT_NUMBER`, or `folders/FOLDER_ID` | string | n/a | yes |
| live_enforce | (Optional) Enforce the custom constraints live. When `false`, dry-run only | bool | `false` | no |
| workload_identity_namespace_prefix | (Optional) Namespace prefix that Workload Identity members must match, for example `ns-` | string | `""` | no |
| enable_storage_member_rule | (Optional) UNVERIFIED. Restrict who can receive Cloud Storage roles | bool | `false` | no |
| storage_allowed_members | (Optional) Exact members that can receive Cloud Storage roles when the storage rule is on | list(string) | `[]` | no |
| storage_custom_roles | (Optional) Custom roles that the storage rule also covers | list(string) | `[]` | no |
| storage_policy_admin_roles | (Optional) Roles that cannot be granted to `principal://` members when the storage rule is on | list(string) | `["roles/storage.admin", "roles/storage.legacyBucketOwner"]` | no |
| enforce_public_access_prevention | (Optional) Enforce the managed `storage.publicAccessPrevention` constraint | bool | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| custom_constraint_names | The custom constraint names, by key: `wi` and `token`, and `storage` and `storage_admin` when the storage rule is on |
| policy_names | The organization policy names on `policy_parent`, by the same keys |
| live_enforced | Whether the custom constraints are enforced live |
| public_access_prevention_enforced | Whether `storage.publicAccessPrevention` is enforced |
