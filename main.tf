provider "aws" {
  region = "us-east-1"
}

# Получение доступных зон
data "aws_availability_zones" "available" {}

# Включение версионирования для существующего S3 бакета
resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = "alekseyk-terraform-state-bucket-unique-1234567890"  # Укажите вручную существующий бакет

  versioning_configuration {
    status = "Enabled"
  }
}

# Настройка backend S3 для хранения состояния Terraform
terraform {
  backend "s3" {
    bucket         = "alekseyk-terraform-state-bucket-unique-1234567890"  # Укажите существующий бакет вручную
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"  # Укажите существующую таблицу вручную
    encrypt        = true
  }
}

# Использование существующей таблицы DynamoDB для блокировок (таблица уже создана вручную)
# Удален блок создания ресурса aws_dynamodb_table

# Создание VPC
resource "aws_vpc" "dev_vpc" {
  cidr_block = "10.0.0.0/16"
}

# Публичные подсети
resource "aws_subnet" "public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.dev_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.dev_vpc.cidr_block, 8, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
}

# Приватные подсети
resource "aws_subnet" "private_subnet" {
  count             = 2
  vpc_id            = aws_vpc.dev_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.dev_vpc.cidr_block, 8, count.index + 2)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
}

# Интернет-шлюз
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.dev_vpc.id
}

# NAT Gateway и EIP для доступа из приватных подсетей
resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet[0].id
}

# Маршрутная таблица для публичных подсетей
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.dev_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

# Привязка маршрутной таблицы к публичным подсетям
resource "aws_route_table_association" "public_association" {
  count          = 2
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# Маршрутная таблица для приватных подсетей с NAT Gateway
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.dev_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
}

# Привязка маршрутной таблицы к приватным подсетям
resource "aws_route_table_association" "private_association" {
  count          = 2
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# Создание ECR репозитория для хранения Docker образов
resource "aws_ecr_repository" "dev_ecr" {
  name = "dev-ecr-repo"
}

# Использование существующей IAM роли для EKS кластера
data "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"  # Укажите существующую роль вручную
}

# Создание EKS кластера с использованием существующей роли
resource "aws_eks_cluster" "eks_cluster" {
  name     = "dev-eks-cluster"
  role_arn = data.aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = aws_subnet.private_subnet[*].id
  }
}

# Использование существующей IAM роли для узлов EKS (роль уже существует)
data "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"  # Укажите существующую роль вручную
}

# Привязка политик к существующей роли узлов
resource "aws_iam_role_policy_attachment" "eks_node_policy" {
  role       = data.aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = data.aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_read_access" {
  role       = data.aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ec2_container_instance" {
  role       = data.aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Создание группы узлов EKS в приватных подсетях
resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "dev-node-group"
  node_role_arn   = data.aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.private_subnet[*].id
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }
}
