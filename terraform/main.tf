# =============================================================================
# MAIN TERRAFORM CONFIGURATION
# =============================================================================
# This file wires together all the individual modules/resources.
# Think of it as the "entry point" that orchestrates everything.
# =============================================================================

# Tell Terraform which providers (cloud APIs) we need
terraform {
  required_version = ">= 1.5" # Minimum Terraform version

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Use AWS provider v5.x
    }
  }

  # IMPORTANT: Store Terraform state remotely so your team can collaborate.
  # Uncomment and configure this once you create the S3 bucket.
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "replication-api/terraform.tfstate"
  #   region = "ap-southeast-1"
  # }
}

# Configure the AWS provider — this tells Terraform which region to use
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  # Tag every resource automatically so you can track costs
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# =============================================================================
# DATA SOURCES
# =============================================================================
# Data sources let you look up existing AWS resources (they don't create anything).
# =============================================================================

# Get the default VPC — every AWS account has one. Using it avoids creating
# networking from scratch (saves cost and complexity for learning).
data "aws_vpc" "default" {
  default = true
}

# Get all subnets in the default VPC. Subnets are in different Availability
# Zones (AZs), which gives us fault tolerance — if one AZ goes down, the
# other keeps running.
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get current AWS account ID (used in IAM policies)
data "aws_caller_identity" "current" {}
