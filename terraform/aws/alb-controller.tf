# Role for the AWS Load Balancer Controller running in an EKS cluster. 
# The Load Balancer Controller requires specific IAM permissions to manage AWS resources such as Application Load Balancers (ALBs) 
# and Network Load Balancers (NLBs) on behalf of the Kubernetes services running in the EKS cluster.
module "lb_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.2.1" # module versions cannot be variable. aws provider ~5.0 requires versions 5.x

  name                                   = "aws-lb-controller-${data.aws_caller_identity.current.account_id}"
  attach_load_balancer_controller_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}


# Deploy the ALB/NLB controller Pod using helm chart
# This controller will create ALBs/NLBs depending on the Ingress resources and Service resources created.
resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  values = [
    yamlencode({
      clusterName = var.eks_cluster_name
      vpcId       = module.vpc.vpc_id
      region      = data.aws_region.current.name
      image = {
        repository = "602401143452.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/amazon/aws-load-balancer-controller"
      }
      replicaCount = 1
      serviceAccount = {
        name = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = module.lb_role.arn
        }
      }
    })
  ]

  depends_on = [
    module.eks
  ]
}


# Attach the custom EC2 policy to the ALB controller role
resource "aws_iam_role_policy_attachment" "alb_controller_ec2" {
  role       = module.lb_role.name
  policy_arn = aws_iam_policy.alb_controller_ec2.arn
}

# Custom policy for ALB controller to access EC2 resources
resource "aws_iam_policy" "alb_controller_ec2" {
  name        = "alb-controller-ec2-policy"
  description = "Policy for ALB controller to access EC2 & Shield resources"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeRouteTables",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs",
          "shield:GetSubscriptionState",
          "shield:DescribeProtection"
        ]
        Resource = "*"
      }
    ]
  })
}