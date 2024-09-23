output "vpc_id" {
  value = aws_vpc.dev_vpc.id
}

output "public_subnets" {
  value = aws_subnet.public_subnet[*].id
}

output "private_subnets" {
  value = aws_subnet.private_subnet[*].id
}

output "eks_cluster_id" {
  value = aws_eks_cluster.eks_cluster.id
}
