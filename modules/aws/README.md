# ClickHouse BYOC AWS Onboarding — Management Role

> **GENERATED MODULE — do not edit.**
> This module is generated and published automatically by ClickHouse.
> Manual edits will be overwritten by the next sync.

This Terraform module provisions the `ClickHouseManagementRole` IAM role and its
policies in your AWS account. ClickHouse Cloud assumes this role to manage the
BYOC (Bring Your Own Cloud) infrastructure on your behalf. It grants the same
permission set as the CloudFormation onboarding template.

> [!IMPORTANT]
> Keep `byoc_env = "production"` (this is the default). Do **not** change it.
> `production` is the only supported value for customer onboarding. Setting any
> other value points the trust policy at a non-production ClickHouse account and
> will break onboarding.

## Usage

```hcl
module "clickhouse_onboarding" {
  source = "github.com/ClickHouse/terraform-byoc-onboarding.git//modules/aws?ref=<version>"

  # Required — provided by ClickHouse during BYOC onboarding
  external_id = "<external-id-provided-by-clickhouse>"
}

output "clickhouse_management_role_arn" {
  value = module.clickhouse_onboarding.clickhouse_management_role_arn
}
```

Replace `<version>` with the latest tag from the module's
[releases page](https://github.com/ClickHouse/terraform-byoc-onboarding/releases)
— always use the latest release.

The module is also published as a tarball at
`https://s3.us-east-2.amazonaws.com/clickhouse-public-resources.clickhouse.cloud/tf/byoc.tar.gz`,
which can be used as `source` directly; the GitHub module above is the
recommended source.

Report the `clickhouse_management_role_arn` output back to ClickHouse to
complete onboarding.

## Inputs

| Name                            | Description                                                                                                | Type     | Default                      | Required |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------- | -------- | ---------------------------- | :------: |
| `external_id`                   | Unique identifier for role assumption, provided by ClickHouse.                                              | `string` | n/a                          |   yes    |
| `role_name`                     | Name of the IAM role to create.                                                                              | `string` | `"ClickHouseManagementRole"` |    no    |
| `include_vpc_write_permissions` | Grant VPC create/delete permissions. Set `false` for bring-your-own-VPC onboarding.                          | `bool`   | `true`                       |    no    |
| `include_iam_write_permissions` | Grant IAM role/policy write permissions. Set `false` for bring-your-own-IAM onboarding.                      | `bool`   | `true`                       |    no    |
| `include_kms_permissions`       | Grant KMS permissions for EKS secret envelope encryption. Set `true` only if instructed to use ClickHouse-managed KMS keys. | `bool`   | `false`                      |    no    |
| `include_tde_permissions`       | Grant KMS permissions for provisioning the BYOC+TDE shared resources (one delegate IAM role + one default KMS key per infra, tag-scoped, no key use). Set `true` before enabling TDE for an infra. | `bool`   | `false`                      |    no    |

> `byoc_env` exists for internal ClickHouse use only. Leave it at its default
> (`production`). See the note above.

## Outputs

| Name                             | Description                                                        |
| -------------------------------- | ------------------------------------------------------------------ |
| `clickhouse_management_role_arn` | ARN of the created management role — report back to ClickHouse.    |
