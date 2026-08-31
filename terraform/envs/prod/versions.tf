terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    bucket         = "taskflow-tfstate-bucket-gayankk"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "taskflow-tfstate-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "TaskFlow"
      Environment = "Production"
      ManagedBy   = "Terraform"
    }
  }
}
