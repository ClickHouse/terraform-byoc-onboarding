# GENERATED FILE — DO NOT EDIT.
# This module is generated and published automatically by ClickHouse.
# Manual edits will be overwritten by the next sync.


locals {
  byoc_account_map = {
    dev        = 851725629656
    staging    = 767397831528
    production = 381492293576
  }
  clickhouse_account_map = {
    dev        = 662591887723
    staging    = 463754717262
    production = 426924874929
  }
}

variable "byoc_env" {
  default     = "production"
  description = "The ClickHouse BYOC environment. External customers must leave this at \"production\" (the default) and must not change it; dev and staging are for internal ClickHouse use only."
  type        = string
  validation {
    error_message = "byoc_env must be one of: dev, staging, or production"
    condition     = contains(["dev", "staging", "production"], var.byoc_env)
  }
}

variable "role_name" {
  default     = "ClickHouseManagementRole"
  description = "Name of the IAM role to be created"
  type        = string
}

variable "external_id" {
  description = "Unique identifier for role assumption"
  type        = string
}

variable "include_vpc_write_permissions" {
  default     = true
  description = "Whether to include VPC write permissions"
  type        = bool
}

variable "include_iam_write_permissions" {
  default     = true
  description = "Whether to include IAM write permissions"
  type        = bool
}

variable "include_kms_permissions" {
  description = "Whether to include KMS permissions"
  type        = bool
  default     = false
}

variable "include_tde_permissions" {
  description = "Whether to let the ClickHouse Management Role provision the BYOC+TDE shared resources in this account: one TDE delegate IAM role and one default KMS key (KEK) per infra. Runtime Encrypt/Decrypt is NOT granted here — only the TDE delegate role can use the key, via the key policy."
  type        = bool
  default     = false
}
data "aws_iam_policy_document" "assume_role_policy" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]
    effect = "Allow"
    condition {
      test = "StringLike"
      values = [
        "arn:aws:iam::${local.clickhouse_account_map[var.byoc_env]}:role/*-CrossplaneWorkloadRole"
      ]
      variable = "aws:PrincipalArn"
    }
    condition {
      test = "StringEquals"
      values = [
        "${var.external_id}"
      ]
      variable = "sts:ExternalId"
    }
    principals {
      identifiers = [
        "arn:aws:iam::${local.clickhouse_account_map[var.byoc_env]}:root"
      ]
      type = "AWS"
    }
  }
}
resource "aws_iam_role" "clickhouse_management_role" {
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy.json
  description        = "Role to allow ClickHouse Cloud to manage resources in your account"
  name               = var.role_name
  tags = {
    clickhouse-byoc = "true"
    version         = "2.0.324-f7637fc"
  }
}
data "aws_iam_policy_document" "base_policy" {
  statement {
    actions = [
      "sts:GetCallerIdentity"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "servicequotas:GetServiceQuota",
      "servicequotas:GetAWSDefaultServiceQuota"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
}
resource "aws_iam_role_policy" "clickhouse_management_role_policy_base_policy" {
  name   = "BasePolicy"
  policy = data.aws_iam_policy_document.base_policy.json
  role   = aws_iam_role.clickhouse_management_role.name
}
data "aws_iam_policy_document" "iam_base_managed_policy" {
  statement {
    actions = [
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:policy/*"
    ]
  }
  statement {
    actions = [
      "iam:GetRole",
      "iam:ListRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:SimulatePrincipalPolicy"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:role/*"
    ]
  }
  statement {
    actions = [
      "iam:PassRole"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:role/*-k8s-control-plane"
    ]
    condition {
      test = "StringEquals"
      values = [
        "eks.amazonaws.com"
      ]
      variable = "iam:PassedToService"
    }
  }
  statement {
    actions = [
      "iam:PassRole"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:role/*-load-balancer-controller",
      "arn:aws:iam::*:role/*-cluster-autoscaler",
      "arn:aws:iam::*:role/*-clickhouse-*",
      "arn:aws:iam::*:role/clickhouse/*",
      "arn:aws:iam::*:role/*-CH-S3-Role",
      "arn:aws:iam::*:role/*-state-exporter",
      "arn:aws:iam::*:role/*-thanos",
      "arn:aws:iam::*:role/*-ebs-csi-driver",
      "arn:aws:iam::*:role/*-karpenter-controller"
    ]
    condition {
      test = "StringEquals"
      values = [
        "pods.eks.amazonaws.com"
      ]
      variable = "iam:PassedToService"
    }
  }
  statement {
    actions = [
      "iam:PassRole"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:role/*-k8s-worker"
    ]
    condition {
      test = "StringEquals"
      values = [
        "ec2.amazonaws.com",
        "eks.amazonaws.com"
      ]
      variable = "iam:PassedToService"
    }
  }
  statement {
    actions = [
      "iam:PassRole"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:role/*-karpenter-node"
    ]
    condition {
      test = "StringEquals"
      values = [
        "ec2.amazonaws.com"
      ]
      variable = "iam:PassedToService"
    }
  }
  statement {
    actions = [
      "iam:CreateServiceLinkedRole"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:role/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "eks.amazonaws.com",
        "eks-nodegroup.amazonaws.com",
        "vpc-lattice.amazonaws.com"
      ]
      variable = "iam:AWSServiceName"
    }
  }
  statement {
    actions = [
      "iam:GetOpenIDConnectProvider"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:oidc-provider/*"
    ]
  }
  statement {
    actions = [
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:DeleteOpenIDConnectProvider"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:oidc-provider/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:oidc-provider/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "iam:ListInstanceProfilesForRole"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:instance-profile/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "iam:GetInstanceProfile",
      "iam:ListInstanceProfiles"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
}
resource "aws_iam_policy" "clickhouse_management_role_policy_iam_base_managed_policy" {
  description = "Base IAM policy for ClickHouse Management Role"
  name        = "ClickHouse-IAM-Base-Policy"
  policy      = data.aws_iam_policy_document.iam_base_managed_policy.json
}
resource "aws_iam_role_policy_attachment" "clickhouse_management_role_policy_iam_base_managed_policy_attachment" {
  policy_arn = aws_iam_policy.clickhouse_management_role_policy_iam_base_managed_policy.arn
  role       = aws_iam_role.clickhouse_management_role.name
}
data "aws_iam_policy_document" "iam_extended_managed_policy" {
  statement {
    actions = [
      "iam:CreatePolicy",
      "iam:TagPolicy"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:policy/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "iam:DeletePolicy",
      "iam:UntagPolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:policy/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "iam:CreateRole",
      "iam:TagRole"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:role/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:DeleteRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:role/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "iam:RemoveRoleFromInstanceProfile"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:instance-profile/*"
    ]
  }
  statement {
    actions = [
      "iam:CreateInstanceProfile",
      "iam:TagInstanceProfile"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:instance-profile/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:instance-profile/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
}
resource "aws_iam_policy" "clickhouse_management_role_policy_iam_extended_managed_policy" {
  description = "Extended IAM policy for ClickHouse Management Role"
  name        = "ClickHouse-IAM-Extended-Policy"
  policy      = data.aws_iam_policy_document.iam_extended_managed_policy.json
  count       = var.include_iam_write_permissions ? 1 : 0
}
resource "aws_iam_role_policy_attachment" "clickhouse_management_role_policy_iam_extended_managed_policy_attachment" {
  policy_arn = aws_iam_policy.clickhouse_management_role_policy_iam_extended_managed_policy.0.arn
  role       = aws_iam_role.clickhouse_management_role.name
  count      = var.include_iam_write_permissions ? 1 : 0
}
data "aws_iam_policy_document" "s3_managed_policy" {
  statement {
    actions = [
      "s3:GetBucketAcl",
      "s3:GetBucketCors",
      "s3:GetBucketLogging",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetBucketPolicy",
      "s3:GetReplicationConfiguration",
      "s3:GetEncryptionConfiguration",
      "s3:GetBucketRequestPayment",
      "s3:GetBucketTagging",
      "s3:GetBucketVersioning",
      "s3:GetBucketWebsite",
      "s3:GetBucketOwnershipControls",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetAccelerateConfiguration",
      "s3:PutBucketTagging",
      "s3:PutLifecycleConfiguration",
      "s3:PutBucketOwnershipControls",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutEncryptionConfiguration",
      "s3:GetMetricsConfiguration",
      "s3:PutMetricsConfiguration",
      "s3:CreateBucket",
      "s3:ListBucket",
      "s3:GetLifecycleConfiguration"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:s3:::*.*.aws.clickhouse.cloud-shared",
      "arn:aws:s3:::*.*.aws.clickhouse.cloud-backup",
      "arn:aws:s3:::*.*.aws.clickhouse.cloud-monitoring"
    ]
  }
}
resource "aws_iam_policy" "clickhouse_management_role_policy_s3_managed_policy" {
  description = "S3 policy for ClickHouse Management Role"
  name        = "ClickHouse-S3-Policy"
  policy      = data.aws_iam_policy_document.s3_managed_policy.json
}
resource "aws_iam_role_policy_attachment" "clickhouse_management_role_policy_s3_managed_policy_attachment" {
  policy_arn = aws_iam_policy.clickhouse_management_role_policy_s3_managed_policy.arn
  role       = aws_iam_role.clickhouse_management_role.name
}
data "aws_iam_policy_document" "eks_managed_policy" {
  statement {
    actions = [
      "eks:CreateAddon",
      "eks:CreateCluster",
      "eks:DeleteCluster",
      "eks:DeleteAddon",
      "eks:DeleteNodegroup",
      "eks:CreateNodegroup",
      "eks:UpdateAddon",
      "eks:UpdateNodegroupVersion",
      "eks:UpdateNodegroupConfig",
      "eks:UpdateClusterConfig",
      "eks:UpdateClusterVersion",
      "eks:AssociateEncryptionConfig",
      "eks:CreatePodIdentityAssociation",
      "eks:TagResource",
      "eks:UntagResource"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:eks:*:*:cluster/clickhouse-cloud-*",
      "arn:aws:eks:*:*:addon/clickhouse-cloud-*",
      "arn:aws:eks:*:*:nodegroup/clickhouse-cloud-*"
    ]
  }
  statement {
    actions = [
      "eks:DeletePodIdentityAssociation",
      "eks:UpdatePodIdentityAssociation",
      "eks:TagResource",
      "eks:UntagResource"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:eks:*:*:podidentityassociation/clickhouse-cloud-*/*"
    ]
  }
  statement {
    actions = [
      "eks:List*",
      "eks:Describe*"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
}
resource "aws_iam_policy" "clickhouse_management_role_policy_eks_managed_policy" {
  description = "EKS policy for ClickHouse Management Role"
  name        = "ClickHouse-EKS-Policy"
  policy      = data.aws_iam_policy_document.eks_managed_policy.json
}
resource "aws_iam_role_policy_attachment" "clickhouse_management_role_policy_eks_managed_policy_attachment" {
  policy_arn = aws_iam_policy.clickhouse_management_role_policy_eks_managed_policy.arn
  role       = aws_iam_role.clickhouse_management_role.name
}
data "aws_iam_policy_document" "kms_policy" {
  statement {
    actions = [
      "kms:DescribeKey",
      "kms:CreateGrant"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:kms:*:${local.byoc_account_map[var.byoc_env]}:key/*"
    ]
  }
}
resource "aws_iam_policy" "clickhouse_management_role_policy_kms_policy" {
  description = "Enable ClickHouseManagementRole to configure EKS secret envelop encryption with clickhouse managed KMS keys"
  name        = "KMSPolicy"
  policy      = data.aws_iam_policy_document.kms_policy.json
  count       = var.include_kms_permissions ? 1 : 0
}
resource "aws_iam_role_policy_attachment" "clickhouse_management_role_policy_kms_policy_attachment" {
  policy_arn = aws_iam_policy.clickhouse_management_role_policy_kms_policy.0.arn
  role       = aws_iam_role.clickhouse_management_role.name
  count      = var.include_kms_permissions ? 1 : 0
}
data "aws_iam_policy_document" "kms_tde_policy" {
  statement {
    actions = [
      "kms:CreateKey"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "kms:TagResource"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:kms:*:*:key/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:EnableKeyRotation",
      "kms:ListResourceTags",
      "kms:TagResource",
      "kms:UntagResource"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:kms:*:*:key/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
}
resource "aws_iam_policy" "clickhouse_management_role_policy_kms_tde_policy" {
  description = "Enable ClickHouseManagementRole to provision the BYOC+TDE shared default KMS key (KEK) in this account"
  name        = "KMSTDEPolicy"
  policy      = data.aws_iam_policy_document.kms_tde_policy.json
  count       = var.include_tde_permissions ? 1 : 0
}
resource "aws_iam_role_policy_attachment" "clickhouse_management_role_policy_kms_tde_policy_attachment" {
  policy_arn = aws_iam_policy.clickhouse_management_role_policy_kms_tde_policy.0.arn
  role       = aws_iam_role.clickhouse_management_role.name
  count      = var.include_tde_permissions ? 1 : 0
}
data "aws_iam_policy_document" "ec2_managed_policy" {
  statement {
    actions = [
      "ec2:Describe*",
      "ec2:Get*",
      "ec2:RunInstances",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyNetworkInterfaceAttribute",
      "elasticloadbalancing:Describe*",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeScalingActivities"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:CreateTags"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:ModifyVolumeAttribute"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:volume/*"
    ]
  }
  statement {
    actions = [
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DeleteSecurityGroup",
      "ec2:ModifySecurityGroupRules"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:security-group/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DeleteSecurityGroup",
      "ec2:ModifySecurityGroupRules"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:security-group/*"
    ]
    condition {
      test = "StringLike"
      values = [
        "clickhouse-cloud-*"
      ]
      variable = "aws:ResourceTag/aws:eks:cluster-name"
    }
  }
  statement {
    actions = [
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:ModifySecurityGroupRules"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:security-group-rule/*"
    ]
  }
  statement {
    actions = [
      "ec2:CreateSecurityGroup"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:vpc/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:CreateSecurityGroup"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:security-group/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:CreateLaunchTemplate",
      "ec2:CreateLaunchTemplateVersion",
      "ec2:ModifyLaunchTemplate",
      "ec2:DeleteLaunchTemplate"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:launch-template/*"
    ]
  }
  statement {
    actions = [
      "ec2:AllocateAddress"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:elastic-ip/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:ReleaseAddress"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:elastic-ip/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:network-interface/*"
    ]
  }
  statement {
    actions = [
      "ec2:CreateNetworkInterface"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:subnet/*",
      "arn:aws:ec2:*:*:security-group/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
}
resource "aws_iam_policy" "clickhouse_management_role_policy_ec2_managed_policy" {
  description = "EC2 policy for ClickHouse Management Role"
  name        = "ClickHouse-EC2-Policy"
  policy      = data.aws_iam_policy_document.ec2_managed_policy.json
}
resource "aws_iam_role_policy_attachment" "clickhouse_management_role_policy_ec2_managed_policy_attachment" {
  policy_arn = aws_iam_policy.clickhouse_management_role_policy_ec2_managed_policy.arn
  role       = aws_iam_role.clickhouse_management_role.name
}
data "aws_iam_policy_document" "vpc_write_managed_policy" {
  statement {
    actions = [
      "ec2:CreateVpc"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:vpc/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",
      "ec2:CreateSubnet",
      "ec2:CreateRouteTable"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:vpc/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:CreateSubnet"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:subnet/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:DeleteSubnet",
      "ec2:ModifySubnetAttribute"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:subnet/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:CreateNatGateway"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:natgateway/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:CreateNatGateway"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:subnet/*",
      "arn:aws:ec2:*:*:elastic-ip/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:DeleteNatGateway"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:natgateway/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:CreateInternetGateway"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:internet-gateway/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:DeleteInternetGateway"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:internet-gateway/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:AssociateAddress",
      "ec2:DisassociateAddress"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:elastic-ip/*",
      "arn:aws:ec2:*:*:instance/*",
      "arn:aws:ec2:*:*:network-interface/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:internet-gateway/*",
      "arn:aws:ec2:*:*:vpc/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:CreateRouteTable"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:route-table/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:DeleteRouteTable"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:route-table/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:*/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:CreateVpcEndpoint"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:vpc-endpoint/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:CreateVpcEndpoint"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:vpc/*",
      "arn:aws:ec2:*:*:subnet/*",
      "arn:aws:ec2:*:*:security-group/*",
      "arn:aws:ec2:*:*:route-table/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:ModifyVpcEndpoint"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:subnet/*",
      "arn:aws:ec2:*:*:security-group/*",
      "arn:aws:ec2:*:*:route-table/*",
      "arn:aws:ec2:*:*:vpc-endpoint/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:DeleteVpcEndpoints"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:vpc-endpoint/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
}
resource "aws_iam_policy" "clickhouse_management_role_policy_vpc_write_managed_policy" {
  description = "VPC Write policy for ClickHouse Management Role"
  name        = "ClickHouse-VPCWrite-Policy"
  policy      = data.aws_iam_policy_document.vpc_write_managed_policy.json
  count       = var.include_vpc_write_permissions ? 1 : 0
}
resource "aws_iam_role_policy_attachment" "clickhouse_management_role_policy_vpc_write_managed_policy_attachment" {
  policy_arn = aws_iam_policy.clickhouse_management_role_policy_vpc_write_managed_policy.0.arn
  role       = aws_iam_role.clickhouse_management_role.name
  count      = var.include_vpc_write_permissions ? 1 : 0
}
data "aws_iam_policy_document" "vpc_privatelink_managed_policy" {
  statement {
    actions = [
      "ec2:CreateVpcEndpointServiceConfiguration"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:vpc-endpoint-service/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ec2:DeleteVpcEndpointServiceConfigurations",
      "ec2:ModifyVpcEndpointServiceConfiguration",
      "ec2:ModifyVpcEndpointServicePermissions",
      "ec2:StartVpcEndpointServicePrivateDnsVerification"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:vpc-endpoint-service/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
}
resource "aws_iam_policy" "clickhouse_management_role_policy_vpc_privatelink_managed_policy" {
  description = "VPC PrivateLink (Endpoint Service) policy for ClickHouse Management Role"
  name        = "ClickHouse-VPCPrivateLink-Policy"
  policy      = data.aws_iam_policy_document.vpc_privatelink_managed_policy.json
}
resource "aws_iam_role_policy_attachment" "clickhouse_management_role_policy_vpc_privatelink_managed_policy_attachment" {
  policy_arn = aws_iam_policy.clickhouse_management_role_policy_vpc_privatelink_managed_policy.arn
  role       = aws_iam_role.clickhouse_management_role.name
}
data "aws_iam_policy_document" "vpc_lattice_managed_policy" {
  statement {
    actions = [
      "vpc-lattice:GetResourceGateway",
      "vpc-lattice:GetResourceConfiguration",
      "vpc-lattice:GetResourcePolicy",
      "vpc-lattice:ListResourceGateways",
      "vpc-lattice:ListResourceConfigurations",
      "vpc-lattice:ListTagsForResource"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "vpc-lattice:CreateResourceGateway",
      "vpc-lattice:CreateResourceConfiguration"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "vpc-lattice:UpdateResourceGateway",
      "vpc-lattice:DeleteResourceGateway",
      "vpc-lattice:UpdateResourceConfiguration",
      "vpc-lattice:DeleteResourceConfiguration",
      "vpc-lattice:PutResourcePolicy",
      "vpc-lattice:DeleteResourcePolicy",
      "vpc-lattice:TagResource",
      "vpc-lattice:UntagResource"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ram:CreateResourceShare"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "ram:GetResourceShares",
      "ram:GetResourceShareAssociations",
      "ram:ListResources",
      "ram:ListPrincipals",
      "ram:ListResourceSharePermissions",
      "ram:GetPermission",
      "ram:ListPermissions",
      "ram:ListPermissionVersions"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "ram:UpdateResourceShare",
      "ram:DeleteResourceShare",
      "ram:AssociateResourceShare",
      "ram:DisassociateResourceShare",
      "ram:AssociateResourceSharePermission",
      "ram:DisassociateResourceSharePermission",
      "ram:TagResource",
      "ram:UntagResource"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:ResourceTag/clickhouse-byoc"
    }
  }
}
resource "aws_iam_policy" "clickhouse_management_role_policy_vpc_lattice_managed_policy" {
  description = "VPC Lattice + RAM policy for ClickHouse Management Role"
  name        = "ClickHouse-VPCLattice-Policy"
  policy      = data.aws_iam_policy_document.vpc_lattice_managed_policy.json
}
resource "aws_iam_role_policy_attachment" "clickhouse_management_role_policy_vpc_lattice_managed_policy_attachment" {
  policy_arn = aws_iam_policy.clickhouse_management_role_policy_vpc_lattice_managed_policy.arn
  role       = aws_iam_role.clickhouse_management_role.name
}
data "aws_iam_policy_document" "cloudwatch_managed_policy" {
  statement {
    actions = [
      "logs:Get*",
      "logs:Describe*",
      "logs:List*"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "logs:CreateLogGroup"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:logs:*:*:log-group:*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/clickhouse-byoc"
    }
  }
  statement {
    actions = [
      "logs:Tag*",
      "logs:Untag*",
      "logs:PutRetentionPolicy"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:logs:*:*:log-group:/aws/eks/clickhouse-cloud-*"
    ]
  }
}
resource "aws_iam_policy" "clickhouse_management_role_policy_cloudwatch_managed_policy" {
  description = "CloudWatch policy for ClickHouse Management Role"
  name        = "ClickHouse-CloudWatch-Policy"
  policy      = data.aws_iam_policy_document.cloudwatch_managed_policy.json
}
resource "aws_iam_role_policy_attachment" "clickhouse_management_role_policy_cloudwatch_managed_policy_attachment" {
  policy_arn = aws_iam_policy.clickhouse_management_role_policy_cloudwatch_managed_policy.arn
  role       = aws_iam_role.clickhouse_management_role.name
}

output "clickhouse_management_role_arn" {
  value = aws_iam_role.clickhouse_management_role.arn
}