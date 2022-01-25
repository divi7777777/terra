variable "region" {
  type        = string
  default     = "us-east-2"
  description = "The name of region"
}

variable "ec2_ssh_key" {
  type        = string
  description = "SSH key name that should be used to access the worker nodes"
  default     = "jenkins"
}

variable "cluster_name" {
  type        = string
  default     = "Cloudforte-Devsecops"
  description = "The name of the EKS cluster"
}
