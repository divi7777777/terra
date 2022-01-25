provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

#####
# VPC and subnets
#####
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.48.0"

  name = "Cloudforte-Devsecops-vpc"

  cidr = "10.0.0.0/20"

  azs              = data.aws_availability_zones.available.names
  private_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets   = ["10.0.6.0/24", "10.0.7.0/24", "10.0.8.0/24"]
  database_subnets = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  database_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  enable_dns_hostnames   = true
  enable_dns_support     = true
  enable_nat_gateway     = true
  enable_vpn_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  tags = {
    "kubernetes.io/cluster/eks" = "shared",
    Environment                 = "test"
  }
}

#####
# EKS Cluster
#####

resource "aws_eks_cluster" "cluster" {
  enabled_cluster_log_types = []
  name                      = var.cluster_name
  role_arn                  = aws_iam_role.cluster.arn
  version                   = "1.17"

  vpc_config {
    subnet_ids              = flatten([module.vpc.public_subnets, module.vpc.private_subnets, module.vpc.database_subnets])
    security_group_ids      = []
    endpoint_private_access = "true"
    endpoint_public_access  = "true"
  }
}

resource "aws_iam_role" "cluster" {
  name = join("-", ["eks-cluster-role", var.cluster_name])

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSServicePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  role       = aws_iam_role.cluster.name
}

#####
# EKS Node Group per availability zone
# If you are running a stateful application across multiple Availability Zones that is backed by Amazon EBS volumes and using the Kubernetes Cluster Autoscaler,
# you should configure multiple node groups, each scoped to a single Availability Zone. In addition, you should enable the --balance-similar-node-groups feature.
#
# In this setup you can configure a single IAM Role that is attached to multiple node groups.
#####

resource "aws_iam_role" "main" {
  name = join("-", ["eks-managed-group-node-role", var.cluster_name])

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "main_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.main.name
}

resource "aws_iam_role_policy_attachment" "main_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.main.name
}

resource "aws_iam_role_policy_attachment" "main_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.main.name
}

module "eks-node-group-app" {
  source          = "./modules/node_group"
  node_group_name = join("-", [aws_eks_cluster.cluster.name, "app"])
  create_iam_role = false
  region          = var.region

  cluster_name  = aws_eks_cluster.cluster.id
  node_role_arn = aws_iam_role.main.arn
  subnet_ids    = [module.vpc.private_subnets[0], module.vpc.private_subnets[1], module.vpc.private_subnets[2]]

  desired_size = 1
  min_size     = 1
  max_size     = 1

  instance_types = ["t3.small"]

  ec2_ssh_key = var.ec2_ssh_key

  kubernetes_labels = {
    lifecycle = "OnDemand"
    tier      = "app"
    # az        = data.aws_availability_zones.available.names[0]
  }

  tags = {
    Environment = "test"
  }
}

module "eks-node-group-data" {
  source          = "./modules/node_group"
  node_group_name = join("-", [aws_eks_cluster.cluster.name, "data"])
  create_iam_role = false
  region          = var.region

  cluster_name  = aws_eks_cluster.cluster.id
  node_role_arn = aws_iam_role.main.arn
  subnet_ids    = [module.vpc.database_subnets[0], module.vpc.database_subnets[1], module.vpc.database_subnets[2]]

  desired_size = 1
  min_size     = 1
  max_size     = 1

  instance_types = ["t2.small"]

  ec2_ssh_key = var.ec2_ssh_key

  kubernetes_labels = {
    lifecycle = "OnDemand"
    tier      = "data"
    # az        = data.aws_availability_zones.available.names[1]
  }

  tags = {
    Environment = "test"
  }
}

module "eks-node-group-web" {
  source          = "./modules/node_group"
  node_group_name = join("-", [aws_eks_cluster.cluster.name, "web"])
  create_iam_role = false
  region          = var.region

  cluster_name  = aws_eks_cluster.cluster.id
  node_role_arn = aws_iam_role.main.arn
  subnet_ids    = [module.vpc.public_subnets[0], module.vpc.public_subnets[1], module.vpc.public_subnets[2]]

  desired_size = 1
  min_size     = 1
  max_size     = 1

  ec2_ssh_key = var.ec2_ssh_key

  kubernetes_labels = {
    lifecycle = "OnDemand"
    tier      = "web"
    # az        = data.aws_availability_zones.available.names[2]
  }

  tags = {
    Environment = "test"
  }
}
