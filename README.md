Инструкция по подготовке инфраструктуры для Kubernetes кластера (AWS EKS) с использованием Terraform

Инструкция по подготовке инфраструктуры для Kubernetes кластера (AWS EKS) с использованием Terraform
Цель
Подготовить инфраструктуру для Kubernetes (AWS EKS service) кластера для окружения dev. Задачи включают:
Создание VPC, подсетей, маршрутов и шлюзов.
Создание ECR репозитория для хранения Docker образов.
Создание EKS кластера с двумя нодами EC2 типа t2.micro.
Хранение состояния Terraform в S3 с блокировкой состояния через DynamoDB.
Настройка CI/CD, чтобы запускать Terraform при каждом push в репозиторий.

Шаг 1. Установка и настройка инструментов
1.1. Установите Terraform
Скачайте и установите Terraform с официального сайта: https://www.terraform.io/downloads.html.
Убедитесь, что Terraform установлен корректно, выполнив:
terraform --version

1.2. Настройте AWS CLI
Установите AWS CLI, если еще не установили: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html.
Настройте AWS CLI:

aws configure
Введите ваш AWS Access Key ID, Secret Access Key, регион (например, us-east-1) и формат вывода (например, json).
Шаг 2. Создание файлов Terraform

2.1. main.tf — Основной файл инфраструктуры
Создайте файл main.tf с следующим содержимым:

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}

# Настройка S3 backend для хранения состояния
terraform {
  backend "s3" {
    bucket         = "alekseyk-terraform-state-bucket-unique-1234567890"
    key            = "dev/terraform.tfstate"
    region         = var.region
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

# Создание VPC
resource "aws_vpc" "dev_vpc" {
  cidr_block = var.vpc_cidr
}

# Публичные подсети
resource "aws_subnet" "public_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.dev_vpc.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true
}

# Приватные подсети
resource "aws_subnet" "private_subnet" {
  count             = 2
  vpc_id            = aws_vpc.dev_vpc.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = element(data.aws_availability_zones.available.names, count.index)
}

# Интернет-шлюз
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.dev_vpc.id
}

# NAT Gateway и EIP
resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet[0].id
}

# Маршрутные таблицы
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.dev_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_association" {
  count          = 2
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.dev_vpc.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
}

resource "aws_route_table_association" "private_association" {
  count          = 2
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# ECR репозиторий
resource "aws_ecr_repository" "dev_ecr" {
  name = "dev-ecr-repo"
}

# Использование IAM роли для EKS
data "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"
}

resource "aws_eks_cluster" "eks_cluster" {
  name     = var.eks_cluster_name
  role_arn = data.aws_iam_role.eks_cluster_role.arn
  vpc_config {
    subnet_ids = aws_subnet.private_subnet[*].id
  }
}

data "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"
}

resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "dev-node-group"
  node_role_arn   = data.aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.private_subnet[*].id
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.desired_capacity
    max_size     = var.max_size
    min_size     = var.min_size
  }
}
2.2. variables.tf — Определение переменных
Создайте файл variables.tf для хранения переменных:

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "Private subnet CIDRs"
  type        = list(string)
  default     = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "eks_cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "dev-eks-cluster"
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t2.micro"
}

variable "desired_capacity" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 3
}

variable "min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}
2.3. outputs.tf — Определение выводов
Создайте файл outputs.tf, чтобы экспортировать ключевые значения:

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

Шаг 3. Инициализация и запуск Terraform
3.1. Инициализация Terraform
Выполните команду для инициализации Terraform и скачивания необходимых плагинов:

terraform init

3.2. Просмотр изменений
Чтобы увидеть, какие ресурсы будут созданы, выполните:

terraform plan

3.3. Применение изменений
Для создания ресурсов выполните:

terraform apply

Шаг 4. Настройка CI/CD
Для автоматического запуска Terraform при каждом пуше в репозиторий, используйте любой CI-инструмент. Пример конфигурации для GitHub Actions:
4.1. Создание файла .github/workflows/terraform.yml:
yaml
Копировать код
name: Terraform

on:
  push:
    branches:
      - main

jobs:
  terraform:
    runs-on: ubuntu-latest

    steps:
    - name: Checkout repository
      uses: actions/checkout@v2

    - name: Set up Terraform
      uses: hashicorp/setup-terraform@v1

    - name: Terraform Init
      run: terraform init

    - name: Terraform Plan
      run: terraform plan

    - name: Terraform Apply
      if: github.event_name == 'push'
      run: terraform apply -auto-approve
Шаг 5. Проверка работы
Выполните git push в ваш репоз





