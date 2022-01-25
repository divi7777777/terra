output "iam_role_arn" {
  description = "IAM role ARN used by node group."
  value       = join("", aws_iam_role.main.*.arn)
}

output "iam_role_id" {
  description = "IAM role ID used by node group."
  value       = join("", aws_iam_role.main.*.id)
}

# output "node_group" {
#   description = "Outputs from EKS node group. See `aws_eks_node_group` Terraform documentation for values"
#   value       = join(", ",[module.eks-node-group-app.node_group_name,module.eks-node-group-data.node_group_name,module.eks-node-group-web.node_group_name])
# }
output "region" {
description = " Cluster region"
value	    = var.region
}

output "eks_cluster" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.cluster.name
}
