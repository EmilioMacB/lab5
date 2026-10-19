terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Obtener cuenta actual de AWS de forma dinamica
data "aws_caller_identity" "current" {}

# En Learner Lab NO se pueden crear roles IAM nuevos. Reutilizamos LabRole:
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}
