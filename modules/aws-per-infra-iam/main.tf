# GENERATED FILE — DO NOT EDIT.
# This module is generated and published automatically by ClickHouse.
# Manual edits will be overwritten by the next sync.


locals {
  byoc_account_map = {
    dev        = 851725629656
    staging    = 767397831528
    production = 381492293576
  }
  data_plane_management_role_map = {
    dev        = "arn:aws:iam::662591887723:role/development-non-prod-mgmt-DataPlaneMgmtRole"
    staging    = "arn:aws:iam::463754717262:role/non-prod-staging-${var.region}-mgmt-DataPlaneMgmtRole"
    production = "arn:aws:iam::426924874929:role/prod-production-${var.region}-mgmt-DataPlaneMgmtRole"
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

variable "spoken_name" {
  description = "The spoken name of the byoc infra"
  type        = string
}

variable "region" {
  description = "The AWS region to deploy the BYOC infra"
  type        = string
}

variable "external_id" {
  description = "Unique identifier used to enhance security and prevent unauthorised role assumptions"
  type        = string
}
data "aws_caller_identity" "caller" {
}
data "aws_iam_policy_document" "eks_pod_identity_assume_policy" {
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    effect = "Allow"
    sid    = "AllowEksAuthToAssumeRoleForPodIdentity"
    condition {
      test = "StringEquals"
      values = [
        "${data.aws_caller_identity.caller.account_id}"
      ]
      variable = "aws:SourceAccount"
    }
    condition {
      test = "ArnEquals"
      values = [
        "arn:aws:eks:${var.region}:${data.aws_caller_identity.caller.account_id}:cluster/clickhouse-cloud-${var.spoken_name}"
      ]
      variable = "aws:SourceArn"
    }
    principals {
      identifiers = [
        "pods.eks.amazonaws.com"
      ]
      type = "Service"
    }
  }
}
data "aws_iam_policy_document" "assume_role_policy_k8s_control_plane" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]
    effect = "Allow"
    principals {
      identifiers = [
        "eks.amazonaws.com"
      ]
      type = "Service"
    }
  }
}
resource "aws_iam_role" "role_k8s_control_plane" {
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy_k8s_control_plane.json
  name               = "${var.spoken_name}-${var.region}-k8s-control-plane"
  tags = {
    clickhouse-byoc = "true"
    version         = "2.0.324-f7637fc"
  }
}
resource "aws_iam_role_policy_attachment" "managed_policy_k8s_control_plane_amazon_eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.role_k8s_control_plane.name
}
resource "aws_iam_role_policy_attachment" "managed_policy_k8s_control_plane_amazon_eks_service_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.role_k8s_control_plane.name
}
resource "aws_iam_role_policy_attachment" "managed_policy_k8s_control_plane_amazon_eksvpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.role_k8s_control_plane.name
}
data "aws_iam_policy_document" "eks_encryption_policy" {
  statement {
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:CreateGrant",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:ListGrants",
      "kms:DescribeKey"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:kms:us-west-2:${local.byoc_account_map[var.byoc_env]}:key/*"
    ]
  }
}
resource "aws_iam_role_policy" "role_policy_k8s_control_plane_eks_encryption" {
  name   = "EKSEncryption"
  policy = data.aws_iam_policy_document.eks_encryption_policy.json
  role   = aws_iam_role.role_k8s_control_plane.name
}
data "aws_iam_policy_document" "assume_role_policy_k8s_worker" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]
    effect = "Allow"
    principals {
      identifiers = [
        "ec2.amazonaws.com"
      ]
      type = "Service"
    }
  }
}
resource "aws_iam_role" "role_k8s_worker" {
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy_k8s_worker.json
  name               = "${var.spoken_name}-${var.region}-k8s-worker"
  tags = {
    clickhouse-byoc = "true"
    version         = "2.0.324-f7637fc"
  }
}
resource "aws_iam_role_policy_attachment" "managed_policy_k8s_worker_amazon_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.role_k8s_worker.name
}
resource "aws_iam_role_policy_attachment" "managed_policy_k8s_worker_amazon_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.role_k8s_worker.name
}
resource "aws_iam_role_policy_attachment" "managed_policy_k8s_worker_amazon_ec_2_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.role_k8s_worker.name
}
data "aws_iam_policy_document" "ecr_puller_policy" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::654654567411:role/${var.spoken_name}-${var.region}-ecr-puller"
    ]
  }
}
resource "aws_iam_role_policy" "role_policy_k8s_worker_ecr_puller" {
  name   = "K8SWorkerECRPuller"
  policy = data.aws_iam_policy_document.ecr_puller_policy.json
  role   = aws_iam_role.role_k8s_worker.name
}
resource "aws_iam_role" "role_load_balancer_controller" {
  assume_role_policy = data.aws_iam_policy_document.eks_pod_identity_assume_policy.json
  name               = "${var.spoken_name}-${var.region}-load-balancer-controller"
  tags = {
    clickhouse-byoc = "true"
    version         = "2.0.324-f7637fc"
  }
}
data "aws_iam_policy_document" "inline_policy_load_balancer_controller_lb_controller_iam_policy" {
  statement {
    actions = [
      "iam:CreateServiceLinkedRole"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "elasticloadbalancing.amazonaws.com"
      ]
      variable = "iam:AWSServiceName"
    }
  }
  statement {
    actions = [
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeVpcPeeringConnections",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:GetCoipPoolUsage",
      "ec2:DescribeCoipPools",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
      "elasticloadbalancing:DescribeTrustStores"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "cognito-idp:DescribeUserPoolClient",
      "acm:ListCertificates",
      "acm:DescribeCertificate",
      "iam:ListServerCertificates",
      "iam:GetServerCertificate",
      "waf-regional:GetWebACL",
      "waf-regional:GetWebACLForResource",
      "waf-regional:AssociateWebACL",
      "waf-regional:DisassociateWebACL",
      "wafv2:GetWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "shield:GetSubscriptionState",
      "shield:DescribeProtection",
      "shield:CreateProtection",
      "shield:DeleteProtection"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "ec2:CreateSecurityGroup"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "ec2:CreateTags"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:security-group/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "CreateSecurityGroup"
      ]
      variable = "ec2:CreateAction"
    }
    condition {
      test = "Null"
      values = [
        "false"
      ]
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
    }
  }
  statement {
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:security-group/*"
    ]
    condition {
      test = "Null"
      values = [
        "true",
        "false"
      ]
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
    }
  }
  statement {
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:DeleteSecurityGroup"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
    condition {
      test = "Null"
      values = [
        "false"
      ]
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
    }
  }
  statement {
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateTargetGroup"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
    condition {
      test = "Null"
      values = [
        "false"
      ]
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
    }
  }
  statement {
    actions = [
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:DeleteRule"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
    ]
    condition {
      test = "Null"
      values = [
        "true",
        "false"
      ]
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
    }
  }
  statement {
    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
      "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
    ]
  }
  statement {
    actions = [
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:DeleteTargetGroup"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
    condition {
      test = "Null"
      values = [
        "false"
      ]
      variable = "aws:ResourceTag/elbv2.k8s.aws/cluster"
    }
  }
  statement {
    actions = [
      "elasticloadbalancing:AddTags"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
      "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "CreateTargetGroup",
        "CreateLoadBalancer"
      ]
      variable = "elasticloadbalancing:CreateAction"
    }
    condition {
      test = "Null"
      values = [
        "false"
      ]
      variable = "aws:RequestTag/elbv2.k8s.aws/cluster"
    }
  }
  statement {
    actions = [
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
    ]
  }
  statement {
    actions = [
      "elasticloadbalancing:SetWebAcl",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:AddListenerCertificates",
      "elasticloadbalancing:RemoveListenerCertificates",
      "elasticloadbalancing:ModifyRule"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
}
resource "aws_iam_role_policy" "role_policy_load_balancer_controller_lb_controller_iam_policy" {
  name   = "LBControllerIAMPolicy"
  policy = data.aws_iam_policy_document.inline_policy_load_balancer_controller_lb_controller_iam_policy.json
  role   = aws_iam_role.role_load_balancer_controller.name
}
resource "aws_iam_role" "role_ebs_csi_driver" {
  assume_role_policy = data.aws_iam_policy_document.eks_pod_identity_assume_policy.json
  name               = "${var.spoken_name}-${var.region}-ebs-csi-driver"
  tags = {
    clickhouse-byoc = "true"
    version         = "2.0.324-f7637fc"
  }
}
data "aws_iam_policy_document" "inline_policy_ebs_csi_driver_ebscsi_driver_policy" {
  statement {
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInstances",
      "ec2:DescribeSnapshots",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:DescribeVolumesModifications",
      "ec2:DescribeVolumeStatus"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "ec2:CreateSnapshot",
      "ec2:ModifyVolume"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:volume/*"
    ]
  }
  statement {
    actions = [
      "ec2:AttachVolume",
      "ec2:DetachVolume"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:volume/*",
      "arn:aws:ec2:*:*:instance/*"
    ]
  }
  statement {
    actions = [
      "ec2:CreateVolume",
      "ec2:EnableFastSnapshotRestores"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:snapshot/*"
    ]
  }
  statement {
    actions = [
      "ec2:CreateTags"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:volume/*",
      "arn:aws:ec2:*:*:snapshot/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "CreateVolume",
        "CreateSnapshot"
      ]
      variable = "ec2:CreateAction"
    }
  }
  statement {
    actions = [
      "ec2:DeleteTags"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:volume/*",
      "arn:aws:ec2:*:*:snapshot/*"
    ]
  }
  statement {
    actions = [
      "ec2:CreateVolume"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:volume/*"
    ]
    condition {
      test = "StringLike"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/ebs.csi.aws.com/cluster"
    }
  }
  statement {
    actions = [
      "ec2:CreateVolume"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:volume/*"
    ]
    condition {
      test = "StringLike"
      values = [
        "*"
      ]
      variable = "aws:RequestTag/CSIVolumeName"
    }
  }
  statement {
    actions = [
      "ec2:CreateVolume"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:volume/*"
    ]
    condition {
      test = "StringLike"
      values = [
        "owned"
      ]
      variable = "aws:RequestTag/kubernetes.io/cluster/*"
    }
  }
  statement {
    actions = [
      "ec2:DeleteVolume"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:volume/*"
    ]
    condition {
      test = "StringLike"
      values = [
        "true"
      ]
      variable = "ec2:ResourceTag/ebs.csi.aws.com/cluster"
    }
  }
  statement {
    actions = [
      "ec2:DeleteVolume"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:volume/*"
    ]
    condition {
      test = "StringLike"
      values = [
        "*"
      ]
      variable = "ec2:ResourceTag/CSIVolumeName"
    }
  }
  statement {
    actions = [
      "ec2:DeleteVolume"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:volume/*"
    ]
    condition {
      test = "StringLike"
      values = [
        "*"
      ]
      variable = "ec2:ResourceTag/kubernetes.io/created-for/pvc/name"
    }
  }
  statement {
    actions = [
      "ec2:DeleteVolume"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:volume/*"
    ]
    condition {
      test = "StringLike"
      values = [
        "owned"
      ]
      variable = "ec2:ResourceTag/kubernetes.io/cluster/*"
    }
  }
  statement {
    actions = [
      "ec2:CreateSnapshot"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:snapshot/*"
    ]
    condition {
      test = "StringLike"
      values = [
        "*"
      ]
      variable = "aws:RequestTag/CSIVolumeSnapshotName"
    }
  }
  statement {
    actions = [
      "ec2:CreateSnapshot"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:snapshot/*"
    ]
    condition {
      test = "StringLike"
      values = [
        "true"
      ]
      variable = "aws:RequestTag/ebs.csi.aws.com/cluster"
    }
  }
  statement {
    actions = [
      "ec2:DeleteSnapshot"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:snapshot/*"
    ]
    condition {
      test = "StringLike"
      values = [
        "*"
      ]
      variable = "ec2:ResourceTag/CSIVolumeSnapshotName"
    }
  }
  statement {
    actions = [
      "ec2:DeleteSnapshot"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:*:*:snapshot/*"
    ]
    condition {
      test = "StringLike"
      values = [
        "true"
      ]
      variable = "ec2:ResourceTag/ebs.csi.aws.com/cluster"
    }
  }
}
resource "aws_iam_role_policy" "role_policy_ebs_csi_driver_ebscsi_driver_policy" {
  name   = "EBSCSIDriverPolicy"
  policy = data.aws_iam_policy_document.inline_policy_ebs_csi_driver_ebscsi_driver_policy.json
  role   = aws_iam_role.role_ebs_csi_driver.name
}
resource "aws_iam_role" "role_cluster_autoscaler" {
  assume_role_policy = data.aws_iam_policy_document.eks_pod_identity_assume_policy.json
  name               = "${var.spoken_name}-${var.region}-cluster-autoscaler"
  tags = {
    clickhouse-byoc = "true"
    version         = "2.0.324-f7637fc"
  }
}
data "aws_iam_policy_document" "inline_policy_cluster_autoscaler_eks_autoscaler_policy" {
  statement {
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeTags",
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeInstanceTypes",
      "eks:DescribeNodegroup"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
}
resource "aws_iam_role_policy" "role_policy_cluster_autoscaler_eks_autoscaler_policy" {
  name   = "EKSAutoscalerPolicy"
  policy = data.aws_iam_policy_document.inline_policy_cluster_autoscaler_eks_autoscaler_policy.json
  role   = aws_iam_role.role_cluster_autoscaler.name
}
resource "aws_iam_role" "role_karpenter_controller" {
  assume_role_policy = data.aws_iam_policy_document.eks_pod_identity_assume_policy.json
  name               = "${var.spoken_name}-${var.region}-karpenter-controller"
  tags = {
    clickhouse-byoc = "true"
    version         = "2.0.324-f7637fc"
  }
}
data "aws_iam_policy_document" "inline_policy_karpenter_controller_karpenter_controller_policy" {
  statement {
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:${var.region}::image/*",
      "arn:aws:ec2:${var.region}::snapshot/*",
      "arn:aws:ec2:${var.region}:${data.aws_caller_identity.caller.account_id}:spot-instances-request/*",
      "arn:aws:ec2:${var.region}:${data.aws_caller_identity.caller.account_id}:security-group/*",
      "arn:aws:ec2:${var.region}:${data.aws_caller_identity.caller.account_id}:subnet/*",
      "arn:aws:ec2:${var.region}:${data.aws_caller_identity.caller.account_id}:capacity-reservation/*",
      "arn:aws:ec2:${var.region}:${data.aws_caller_identity.caller.account_id}:placement-group/*"
    ]
  }
  statement {
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:${var.region}:*:launch-template/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "owned"
      ]
      variable = "aws:ResourceTag/kubernetes.io/cluster/clickhouse-cloud-${var.spoken_name}"
    }
    condition {
      test = "StringLike"
      values = [
        "*"
      ]
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
    }
  }
  statement {
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:${var.region}:*:fleet/*",
      "arn:aws:ec2:${var.region}:*:instance/*",
      "arn:aws:ec2:${var.region}:*:volume/*",
      "arn:aws:ec2:${var.region}:*:network-interface/*",
      "arn:aws:ec2:${var.region}:*:launch-template/*",
      "arn:aws:ec2:${var.region}:*:spot-instances-request/*",
      "arn:aws:ec2:${var.region}:*:capacity-reservation/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "owned",
        "clickhouse-cloud-${var.spoken_name}"
      ]
      variable = "aws:RequestTag/kubernetes.io/cluster/clickhouse-cloud-${var.spoken_name}"
    }
    condition {
      test = "StringLike"
      values = [
        "*"
      ]
      variable = "aws:RequestTag/karpenter.sh/nodepool"
    }
  }
  statement {
    actions = [
      "ec2:CreateTags"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:${var.region}:*:fleet/*",
      "arn:aws:ec2:${var.region}:*:instance/*",
      "arn:aws:ec2:${var.region}:*:volume/*",
      "arn:aws:ec2:${var.region}:*:network-interface/*",
      "arn:aws:ec2:${var.region}:*:launch-template/*",
      "arn:aws:ec2:${var.region}:*:spot-instances-request/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "owned",
        "clickhouse-cloud-${var.spoken_name}"
      ]
      variable = "aws:RequestTag/kubernetes.io/cluster/clickhouse-cloud-${var.spoken_name}"
    }
    condition {
      test = "StringLike"
      values = [
        "*"
      ]
      variable = "aws:RequestTag/karpenter.sh/nodepool"
    }
    condition {
      test = "ForAnyValue:StringEquals"
      values = [
        "RunInstances",
        "CreateFleet",
        "CreateLaunchTemplate"
      ]
      variable = "ec2:CreateAction"
    }
  }
  statement {
    actions = [
      "ec2:CreateTags"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:${var.region}:*:instance/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "owned"
      ]
      variable = "aws:ResourceTag/kubernetes.io/cluster/clickhouse-cloud-${var.spoken_name}"
    }
    condition {
      test = "StringLike"
      values = [
        "*"
      ]
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
    }
    condition {
      test = "StringEqualsIfExists"
      values = [
        "clickhouse-cloud-${var.spoken_name}"
      ]
      variable = "aws:RequestTag/eks:eks-cluster-name"
    }
    condition {
      test = "ForAllValues:StringEquals"
      values = [
        "eks:eks-cluster-name",
        "karpenter.sh/nodeclaim",
        "Name"
      ]
      variable = "aws:TagKeys"
    }
  }
  statement {
    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ec2:${var.region}:*:instance/*",
      "arn:aws:ec2:${var.region}:*:launch-template/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "owned"
      ]
      variable = "aws:ResourceTag/kubernetes.io/cluster/clickhouse-cloud-${var.spoken_name}"
    }
    condition {
      test = "StringLike"
      values = [
        "*"
      ]
      variable = "aws:ResourceTag/karpenter.sh/nodepool"
    }
  }
  statement {
    actions = [
      "ec2:DescribeCapacityReservations",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceStatus",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribePlacementGroups",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "${var.region}"
      ]
      variable = "aws:RequestedRegion"
    }
  }
  statement {
    actions = [
      "iam:CreateInstanceProfile"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.caller.account_id}:instance-profile/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "owned",
        "clickhouse-cloud-${var.spoken_name}",
        "${var.region}"
      ]
      variable = "aws:RequestTag/kubernetes.io/cluster/clickhouse-cloud-${var.spoken_name}"
    }
    condition {
      test = "StringLike"
      values = [
        "*"
      ]
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"
    }
  }
  statement {
    actions = [
      "iam:TagInstanceProfile"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.caller.account_id}:instance-profile/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "owned",
        "${var.region}",
        "owned",
        "clickhouse-cloud-${var.spoken_name}"
      ]
      variable = "aws:ResourceTag/kubernetes.io/cluster/clickhouse-cloud-${var.spoken_name}"
    }
    condition {
      test = "StringLike"
      values = [
        "*",
        "*"
      ]
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
    }
  }
  statement {
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.caller.account_id}:instance-profile/*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "owned",
        "${var.region}"
      ]
      variable = "aws:ResourceTag/kubernetes.io/cluster/clickhouse-cloud-${var.spoken_name}"
    }
    condition {
      test = "StringLike"
      values = [
        "*"
      ]
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"
    }
  }
  statement {
    actions = [
      "iam:PassRole"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.caller.account_id}:role/${var.spoken_name}-${var.region}-karpenter-node"
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
      "pricing:GetProducts"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
  statement {
    actions = [
      "ssm:GetParameter"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:ssm:${var.region}::parameter/aws/service/eks/optimized-ami/*"
    ]
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
  statement {
    actions = [
      "eks:DescribeCluster"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:eks:${var.region}:${data.aws_caller_identity.caller.account_id}:cluster/clickhouse-cloud-${var.spoken_name}"
    ]
  }
  statement {
    actions = [
      "arc-zonal-shift:GetManagedResource"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
    condition {
      test = "StringEquals"
      values = [
        "arn:aws:eks:${var.region}:${data.aws_caller_identity.caller.account_id}:cluster/clickhouse-cloud-${var.spoken_name}"
      ]
      variable = "arc-zonal-shift:ResourceIdentifier"
    }
  }
}
resource "aws_iam_role_policy" "role_policy_karpenter_controller_karpenter_controller_policy" {
  name   = "KarpenterControllerPolicy"
  policy = data.aws_iam_policy_document.inline_policy_karpenter_controller_karpenter_controller_policy.json
  role   = aws_iam_role.role_karpenter_controller.name
}
data "aws_iam_policy_document" "assume_role_policy_karpenter_node" {
  statement {
    actions = [
      "sts:AssumeRole"
    ]
    effect = "Allow"
    principals {
      identifiers = [
        "ec2.amazonaws.com"
      ]
      type = "Service"
    }
  }
}
resource "aws_iam_role" "role_karpenter_node" {
  assume_role_policy = data.aws_iam_policy_document.assume_role_policy_karpenter_node.json
  name               = "${var.spoken_name}-${var.region}-karpenter-node"
  tags = {
    clickhouse-byoc = "true"
    version         = "2.0.324-f7637fc"
  }
}
resource "aws_iam_role_policy_attachment" "managed_policy_karpenter_node_amazon_eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.role_karpenter_node.name
}
resource "aws_iam_role_policy_attachment" "managed_policy_karpenter_node_amazon_eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.role_karpenter_node.name
}
resource "aws_iam_role_policy_attachment" "managed_policy_karpenter_node_amazon_ec_2_container_registry_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.role_karpenter_node.name
}
resource "aws_iam_role_policy_attachment" "managed_policy_karpenter_node_amazon_ssm_managed_instance_core" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.role_karpenter_node.name
}
resource "aws_iam_role" "role_state_exporter" {
  assume_role_policy = data.aws_iam_policy_document.eks_pod_identity_assume_policy.json
  name               = "${var.spoken_name}-${var.region}-state-exporter"
  tags = {
    clickhouse-byoc = "true"
    version         = "2.0.324-f7637fc"
  }
}
data "aws_iam_policy_document" "inline_policy_state_exporter_state_exporter_policy" {
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::${local.byoc_account_map[var.byoc_env]}:role/*"
    ]
  }
}
resource "aws_iam_role_policy" "role_policy_state_exporter_state_exporter_policy" {
  name   = "StateExporterPolicy"
  policy = data.aws_iam_policy_document.inline_policy_state_exporter_state_exporter_policy.json
  role   = aws_iam_role.role_state_exporter.name
}
resource "aws_iam_role" "role_thanos" {
  assume_role_policy = data.aws_iam_policy_document.eks_pod_identity_assume_policy.json
  name               = "${var.spoken_name}-${var.region}-thanos"
  tags = {
    clickhouse-byoc = "true"
    version         = "2.0.324-f7637fc"
  }
}
data "aws_iam_policy_document" "inline_policy_thanos_thanos_policy" {
  statement {
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:s3:::*.cloud-monitoring/*",
      "arn:aws:s3:::*.cloud-monitoring"
    ]
  }
}
resource "aws_iam_role_policy" "role_policy_thanos_thanos_policy" {
  name   = "ThanosPolicy"
  policy = data.aws_iam_policy_document.inline_policy_thanos_thanos_policy.json
  role   = aws_iam_role.role_thanos.name
}
resource "aws_iam_role" "role_clickhouse_scraper" {
  assume_role_policy = data.aws_iam_policy_document.eks_pod_identity_assume_policy.json
  name               = "${var.spoken_name}-${var.region}-clickhouse-scraper"
  tags = {
    clickhouse-byoc = "true"
    version         = "2.0.324-f7637fc"
  }
}
data "aws_iam_policy_document" "inline_policy_clickhouse_scraper_scraper_billing_bucket_assume_role_policy" {
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::${local.byoc_account_map[var.byoc_env]}:role/*"
    ]
  }
}
resource "aws_iam_role_policy" "role_policy_clickhouse_scraper_scraper_billing_bucket_assume_role_policy" {
  name   = "ScraperBillingBucketAssumeRolePolicy"
  policy = data.aws_iam_policy_document.inline_policy_clickhouse_scraper_scraper_billing_bucket_assume_role_policy.json
  role   = aws_iam_role.role_clickhouse_scraper.name
}
resource "aws_iam_role" "role_kube_metric_forwarder_asc" {
  assume_role_policy = data.aws_iam_policy_document.eks_pod_identity_assume_policy.json
  name               = "${var.spoken_name}-${var.region}-kube-metric-forwarder-asc"
  tags = {
    clickhouse-byoc = "true"
    version         = "2.0.324-f7637fc"
  }
}
data "aws_iam_policy_document" "inline_policy_kube_metric_forwarder_asc_kube_metric_forwarder_autoscale_bucket_assume_role_policy" {
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::${local.byoc_account_map[var.byoc_env]}:role/*"
    ]
  }
}
resource "aws_iam_role_policy" "role_policy_kube_metric_forwarder_asc_kube_metric_forwarder_autoscale_bucket_assume_role_policy" {
  name   = "KubeMetricForwarderAutoscaleBucketAssumeRolePolicy"
  policy = data.aws_iam_policy_document.inline_policy_kube_metric_forwarder_asc_kube_metric_forwarder_autoscale_bucket_assume_role_policy.json
  role   = aws_iam_role.role_kube_metric_forwarder_asc.name
}
resource "aws_iam_role" "role_clickhouse_s3_access" {
  assume_role_policy = data.aws_iam_policy_document.eks_pod_identity_assume_policy.json
  name               = "${var.spoken_name}-${var.region}-CH-S3-Role"
  tags = {
    clickhouse-byoc = "true"
    version         = "2.0.324-f7637fc"
  }
}
data "aws_iam_policy_document" "billing_bucket_assume_role_policy" {
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::${local.byoc_account_map[var.byoc_env]}:role/*",
      "arn:aws:iam::*:role/ClickHouseAccessRole-*"
    ]
    sid = "AllowAssumeroleRemote"
  }
}
resource "aws_iam_role_policy" "role_policy_clickhouse_s3_access_billing_bucket_assume_role" {
  name   = "BillingBucketAssumeRolePolicy"
  policy = data.aws_iam_policy_document.billing_bucket_assume_role_policy.json
  role   = aws_iam_role.role_clickhouse_s3_access.name
}
data "aws_iam_policy_document" "ch_s3_tde_delegate_assume_policy" {
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:role/${var.spoken_name}-${var.region}-tde-delegate"
    ]
    sid = "ByocTDEAssumeDelegate"
  }
}
resource "aws_iam_role_policy" "role_policy_clickhouse_s3_access_tde_delegate_assume" {
  name   = "ByocTDEDelegateAssumePolicy"
  policy = data.aws_iam_policy_document.ch_s3_tde_delegate_assume_policy.json
  role   = aws_iam_role.role_clickhouse_s3_access.name
}
data "aws_iam_policy_document" "s3_full_access_policy" {
  statement {
    actions = [
      "s3:*"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:s3:::*.${var.region}.aws.clickhouse.cloud-backup/ch-s3-*/*",
      "arn:aws:s3:::*.${var.region}.aws.clickhouse.cloud-shared/ch-s3-*/*",
      "arn:aws:s3:::*.${var.region}.aws.clickhouse.cloud-shared/*/udf/*"
    ]
  }
  statement {
    actions = [
      "s3:ListBucket"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:s3:::*.${var.region}.aws.clickhouse.cloud-backup",
      "arn:aws:s3:::*.${var.region}.aws.clickhouse.cloud-shared"
    ]
    condition {
      test = "StringLike"
      values = [
        "ch-s3-*/*",
        "*/udf/*"
      ]
      variable = "s3:prefix"
    }
  }
}
resource "aws_iam_role_policy" "role_policy_clickhouse_s3_access_s3_full_access" {
  name   = "S3FullAccessPolicy"
  policy = data.aws_iam_policy_document.s3_full_access_policy.json
  role   = aws_iam_role.role_clickhouse_s3_access.name
}
data "aws_iam_policy_document" "data_plane_management_assume_role_policy" {
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    effect = "Allow"
    condition {
      test = "StringEquals"
      values = [
        "${var.external_id}"
      ]
      variable = "sts:ExternalId"
    }
    principals {
      identifiers = [
        "${local.data_plane_management_role_map[var.byoc_env]}"
      ]
      type = "AWS"
    }
  }
}
resource "aws_iam_role" "role_data_plane_management" {
  assume_role_policy = data.aws_iam_policy_document.data_plane_management_assume_role_policy.json
  name               = "${var.spoken_name}-${var.region}-data-plane-mgmt"
  tags = {
    clickhouse-byoc = "true"
    version         = "2.0.324-f7637fc"
  }
}
data "aws_iam_policy_document" "data_plane_management_policy" {
  statement {
    actions = [
      "eks:Describe*",
      "eks:List*"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:eks:${var.region}:*:*"
    ]
  }
  statement {
    actions = [
      "s3:ListAllMyBuckets"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:s3:::*"
    ]
  }
  statement {
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:PutEncryptionConfiguration",
      "s3:PutMetricsConfiguration",
      "s3:PutBucketVersioning",
      "s3:PutLifecycleConfiguration",
      "s3:ListBucketVersions"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:s3:::*.*.aws.clickhouse.cloud-shared",
      "arn:aws:s3:::*.*.aws.clickhouse.cloud-backup",
      "arn:aws:s3:::*.*.aws.clickhouse.cloud-monitoring",
      "arn:aws:s3:::*.*.aws.clickhouse.cloud-shared/*",
      "arn:aws:s3:::*.*.aws.clickhouse.cloud-backup/*",
      "arn:aws:s3:::*.*.aws.clickhouse.cloud-monitoring/*"
    ]
  }
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    effect = "Allow"
    resources = [
      "arn:aws:iam::*:role/${var.spoken_name}-${var.region}-tde-delegate"
    ]
    sid = "ByocTDEDelegate"
  }
  statement {
    actions = [
      "sts:GetCallerIdentity",
      "elasticloadbalancing:DescribeLoadBalancers",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeScalingActivities"
    ]
    effect = "Allow"
    resources = [
      "*"
    ]
  }
}
resource "aws_iam_role_policy" "role_policy_data_plane_mgmt" {
  name   = "DataPlaneManagement"
  policy = data.aws_iam_policy_document.data_plane_management_policy.json
  role   = aws_iam_role.role_data_plane_management.name
}
data "aws_iam_policy_document" "tde_delegate_assume_role_policy" {
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    effect = "Allow"
    sid    = "ByocTDEDataPlaneMgmt"
    condition {
      test = "StringEquals"
      values = [
        "${var.external_id}"
      ]
      variable = "sts:ExternalId"
    }
    principals {
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.caller.account_id}:role/${var.spoken_name}-${var.region}-data-plane-mgmt"
      ]
      type = "AWS"
    }
  }
  statement {
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    effect = "Allow"
    sid    = "ByocTDESharedPodRole"
    principals {
      identifiers = [
        "arn:aws:iam::${data.aws_caller_identity.caller.account_id}:role/${var.spoken_name}-${var.region}-CH-S3-Role"
      ]
      type = "AWS"
    }
  }
}
resource "aws_iam_role" "role_tde_delegate" {
  assume_role_policy = data.aws_iam_policy_document.tde_delegate_assume_role_policy.json
  name               = "${var.spoken_name}-${var.region}-tde-delegate"
  tags = {
    clickhouse-byoc = "true"
    version         = "2.0.324-f7637fc"
  }
  depends_on = [
    "aws_iam_role.role_data_plane_management",
    "aws_iam_role.role_clickhouse_s3_access",
  ]
}

output "data_plane_management_role_arn" {
  value = aws_iam_role.role_data_plane_management.arn
}

output "ch_s3_role_arn" {
  value = aws_iam_role.role_clickhouse_s3_access.arn
}

output "tde_delegate_role_arn" {
  value = aws_iam_role.role_tde_delegate.arn
}