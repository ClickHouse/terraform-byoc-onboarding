# ClickHouse BYOC GCP Onboarding Terraform Module

This repository contains Terraform module to bootstrap a BYOC GCP project for ClickHouse Cloud.

## Usage

```hcl
provider "google" {
  project = "replace-with-your-clickhouse-byoc-project-id"
}

module "clickhouse_onboarding" {
  source     = "github.com/ClickHouse/terraform-byoc-onboarding.git//modules/gcp?ref=<version>"
  project_id = "replace-with-your-clickhouse-byoc-project-id"
}
```

Replace `<version>` with the latest tag from the module's
[releases page](https://github.com/ClickHouse/terraform-byoc-onboarding/releases)
— always use the latest release.

### Bring your own VPC (same project)

If you pre-create and manage the VPC network, routes, and Cloud NAT yourself within the BYOC project, set `include_vpc_write_permissions = false`. ClickHouse then does **not** get permissions to create, delete, or modify the network topology (networks, routes, Cloud Routers, subnets), but retains read and use access to it. ClickHouse still creates and manages the resources it owns inside your VPC — the PrivateLink (PSC) service attachment, and ingress/static IP addresses — so PrivateLink and load balancers keep working.

When you bring your own VPC, the PrivateLink PSC NAT subnet is **yours to create**: ClickHouse observes and uses it, and has no permission to create, modify, or delete subnets in your project. Create it with `purpose = PRIVATE_SERVICE_CONNECT` in the same region and network, with a primary range of at least /29, and give ClickHouse its name when you enable PrivateLink. (On a ClickHouse-managed VPC, ClickHouse creates this subnet for you.)

```hcl
module "clickhouse_onboarding" {
  source                        = "github.com/ClickHouse/terraform-byoc-onboarding.git//modules/gcp?ref=<version>"
  project_id                    = "replace-with-your-clickhouse-byoc-project-id"
  include_vpc_write_permissions = false
}
```

Replace `<version>` with the latest tag from the module's
[releases page](https://github.com/ClickHouse/terraform-byoc-onboarding/releases)
— always use the latest release.

If the VPC you bring instead lives in a **different** project, use the Shared VPC setup below.

### Shared VPC (bring a VPC from a different project)

If the VPC you bring lives in a **different** GCP project (the Shared VPC *host* project) than the BYOC *service* project where ClickHouse runs GKE, set `shared_vpc_host_project_id` (plus the host subnet's `shared_vpc_host_subnet_region` and `shared_vpc_host_private_subnet_id`). The module then grants the network and GKE Shared VPC permissions in the host project, in addition to the standard service-project setup.

```hcl
module "clickhouse_onboarding" {
  source                            = "github.com/ClickHouse/terraform-byoc-onboarding.git//modules/gcp?ref=<version>"
  project_id                        = "replace-with-your-clickhouse-byoc-service-project-id"
  shared_vpc_host_project_id        = "replace-with-your-shared-vpc-host-project-id"
  shared_vpc_host_subnet_region     = "us-central1"
  shared_vpc_host_private_subnet_id = "replace-with-your-host-subnet-name"
}
```

Replace `<version>` with the latest tag from the module's
[releases page](https://github.com/ClickHouse/terraform-byoc-onboarding/releases)
— always use the latest release.

The ClickHouse management SA's custom host role is read and use only: it observes the brought network and subnet, and uses the PrivateLink PSC NAT subnet you pre-create there (`compute.subnetworks.use`), allowing the service attachment in the service project to reference it. Separate grants let GKE consume the host node subnet and manage the firewall rules described below.

Because a GKE cluster on a Shared VPC has its network in the host project, GKE also creates its firewall rules there — the master→node rule (kubelet/webhook ports) and the load-balancer health-check rules. The module therefore enables the Container API on the host project (so the host project's GKE service agent exists) and grants the service project's GKE service agent a scoped firewall role (`compute.firewalls.*` + `compute.networks.updatePolicy`) in the host project. Without this, admission webhooks and metrics-server degrade and internal load balancers (including the PrivateLink PSC ingress) never become healthy.

**Prerequisites for Shared VPC:**

- The host project must already be enabled as a [Shared VPC host](https://cloud.google.com/vpc/docs/provisioning-shared-vpc) and the service project (`project_id`) attached to it. This is an org-level operation (`compute.xpnAdmin`) and is **not** performed by this module.
- The credentials running this module must have IAM admin on **both** the service project (`project_id`) and the host project (`shared_vpc_host_project_id`).
- If you will use ClickHouse Private Service Connect (PrivateLink), create the PSC NAT subnet in the host project yourself, in the same region and network as the node subnet, with `purpose = PRIVATE_SERVICE_CONNECT` and a primary range of at least /29. ClickHouse only reads and uses it; it will not create it for you. Give its name to ClickHouse when you enable PrivateLink.

### Object access is limited to ClickHouse monitoring buckets

ClickHouse needs `storage.objects.list` and `storage.objects.delete` only to empty the ClickHouse-managed monitoring bucket before deleting it during infra teardown. These permissions are in `clickhouseStorageObjectsRole`, bound with an IAM Condition that matches only buckets whose name ends in `_gcp_clickhouse_cloud-monitoring` (ClickHouse names each infra's monitoring bucket `<infra-name>_<region-short>_gcp_clickhouse_cloud-monitoring`) and the objects inside them. ClickHouse has no object access to any other bucket in the project, and nothing needs updating when infras are added or removed.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_id | (Required) The GCP project ID where resources will be provisioned | string | n/a | yes |
| environment | (Optional) Environment. Default is `production`. The other values are reserved for internal use | string | `production` | no |
| include_vpc_write_permissions | (Optional) Whether to grant permissions to manage your VPC network topology (create/delete/modify of networks, routes, Cloud Routers, and subnets). Set to `false` for bring-your-own-VPC onboarding. ClickHouse always retains read and use access to the VPC and manages the resources it owns inside it (PrivateLink/PSC service attachment, ingress/static IP addresses). When you bring your own VPC you also pre-create the PSC NAT subnet; ClickHouse only observes and uses it | bool | `true` | no |
| shared_vpc_host_project_id | (Optional) The GCP project ID of the Shared VPC host project, when the VPC you bring lives in a different project than `project_id`. Leave empty for the standard same-project setup. When set, `shared_vpc_host_subnet_region` and `shared_vpc_host_private_subnet_id` are required | string | `""` | no |
| shared_vpc_host_subnet_region | (Optional) The region of the Shared VPC host subnet. Required only when `shared_vpc_host_project_id` is set | string | `""` | no |
| shared_vpc_host_private_subnet_id | (Optional) The name of the existing Shared VPC host subnet used for GKE nodes. Required only when `shared_vpc_host_project_id` is set | string | `""` | no |
| include_tde_permissions | (Optional) Whether to let ClickHouse provision the BYOC+TDE shared resources in this project: one TDE delegate service account and one default Cloud KMS key (KEK) per infra. Grants Cloud KMS key management without any destroy permission — ClickHouse can never destroy key material. Set to `true` before enabling TDE for an infra | bool | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| clickhouse_management_sa_name | The name of the ClickHouse Management Service Account | string |
| clickhouse_management_sa_roles | List of role IDs assigned to the ClickHouse Management Service Account, including `clickhouseStorageObjectsRole`, which is conditioned on ClickHouse monitoring buckets | list(string) |
| shared_vpc_enabled | Whether Shared VPC host-project resources were provisioned (true when `shared_vpc_host_project_id` is set) | bool |
| shared_vpc_host_role | The ID of the ClickHouse Shared VPC host role granted in the host project, or null when Shared VPC is not used | string |
| gke_service_agent_member | The service project's GKE service agent granted access to the Shared VPC host project, or null when Shared VPC is not used | string |
| gke_shared_vpc_firewall_role | The ID of the firewall role granted to the GKE service agent in the host project, or null when Shared VPC is not used | string |

## Resources

| Name | Description |
|------|------|
| google_service_account.clickhouse_management_sa | Service Account to manage ClickHouse resources in BYOC project |
| google_project_service.cloud_resource_manager | Enables Cloud Resource Manager service API |
| google_project_service.service_usage | Enables the Service Usage API so ClickHouse onboarding checks can read which APIs are enabled in your project |
| google_project_service.compute_engine | Enables the Compute Engine API |
| google_project_service.network_connectivity_api | Enables the Network Connectivity API |
| google_project_service.iam_api | Enables the Identity and Access Management (IAM) API |
| google_project_service.container_api | Enables the Kubernetes Engine API (also provisions the GKE service agent used by the Shared VPC grants) |
| google_project_service.cloudkms_api | Enables the Cloud KMS API; created only when `include_tde_permissions` is true |
| google_project_iam_custom_role.clickhouse_common_role | Role to allow ClickHouse Cloud common operations |
| google_project_iam_custom_role.clickhouse_vpc_role | Role to allow ClickHouse Cloud to read and use VPC resources, and to create/manage the ClickHouse-owned addresses and PrivateLink (PSC) service attachment it provisions within the VPC |
| google_project_iam_custom_role.clickhouse_vpc_write_role | Role to allow ClickHouse Cloud to create/delete/modify the VPC network topology (networks, routes, Cloud Routers, subnets); created only when `include_vpc_write_permissions` is true |
| google_project_iam_custom_role.clickhouse_cluster_role | Role to allow ClickHouse Cloud to manage cluster resources in your project |
| google_project_iam_custom_role.clickhouse_storage_role | Role to allow ClickHouse Cloud to manage Object Storage buckets in your project; holds no object-level permissions |
| google_project_iam_custom_role.clickhouse_storage_objects_role | Role holding `storage.objects.list/delete` (no object reads), used only to empty ClickHouse monitoring buckets during infra teardown |
| google_project_iam_custom_role.clickhouse_iam_role | Role to allow ClickHouse Cloud to manage IAM resources in your project |
| google_project_iam_custom_role.clickhouse_tde_role | Role to allow ClickHouse Cloud to manage the BYOC+TDE key ring, default KEK and key IAM bindings (no destroy permissions); created only when `include_tde_permissions` is true |
| google_project_iam_member.clickhouse_sa_roles["common_role"] | Grants `clickhouseCommonRole` to ClickHouse Management Service Account |
| google_project_iam_member.clickhouse_sa_roles["vpc_role"] | Grants `clickhouseVPCRole` to ClickHouse Management Service Account |
| google_project_iam_member.clickhouse_sa_roles["vpc_write_role"] | Grants `clickhouseVPCWriteRole` to ClickHouse Management Service Account; present only when `include_vpc_write_permissions` is true |
| google_project_iam_member.clickhouse_sa_roles["tde_role"] | Grants `clickhouseTdeRole` to ClickHouse Management Service Account; present only when `include_tde_permissions` is true |
| google_project_iam_member.clickhouse_sa_roles["cluster_role"] | Grants `clickhouseClusterRole` to ClickHouse Management Service Account |
| google_project_iam_member.clickhouse_sa_roles["storage_role"] | Grants `clickhouseStorageRole` to ClickHouse Management Service Account |
| google_project_iam_member.clickhouse_sa_roles["iam_role"] | Grants `clickhouseIamRole` to ClickHouse Management Service Account |
| google_project_iam_member.clickhouse_sa_storage_objects_role | Grants `clickhouseStorageObjectsRole` to ClickHouse Management Service Account, conditioned on buckets ending in `_gcp_clickhouse_cloud-monitoring`, and their objects |
| google_service_account_iam_binding.impersonation_binding | Allows ClickHouse Crossplane Service Account to impersonate ClickHouse Management Service Account |
| google_project_iam_custom_role.clickhouse_shared_vpc_host_role | [Shared VPC] Role to observe the host network/subnet and use the customer-provided PrivateLink PSC NAT subnet (read + use only) |
| google_project_iam_member.clickhouse_sa_shared_vpc_host_role | [Shared VPC] Grants `clickhouseSharedVPCHostRole` to ClickHouse Management Service Account in the host project |
| google_project_iam_member.gke_host_service_agent_user | [Shared VPC] Grants `roles/container.hostServiceAgentUser` to the service project's GKE service agent on the host project |
| google_compute_subnetwork_iam_member.network_user | [Shared VPC] Grants `roles/compute.networkUser` on the host subnet to the GKE service agent, Google APIs SA, and ClickHouse Management Service Account |
| google_project_service.container_host | [Shared VPC] Enables the Container API on the host project so its GKE service agent exists (creates cluster-lifecycle firewall rules in the host network) |
| google_project_iam_custom_role.clickhouse_gke_shared_vpc_firewall_role | [Shared VPC] Role allowing the GKE service agent to manage cluster/load-balancer firewall rules in the host project |
| google_project_iam_member.gke_shared_vpc_firewall | [Shared VPC] Grants `clickhouseGKESharedVPCFirewallRole` to the service project's GKE service agent in the host project |

## Requirements

| Name | Version |
|------|---------|
| terraform | >=1.3 |
| google provider | >=6.38.0, <7 |
