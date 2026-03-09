# =============================================================================
# VARIABLES
# =============================================================================
# Variables let you parameterize your config so you don't hardcode values.
# You can override them via terraform.tfvars, CLI flags, or environment vars.
# =============================================================================

variable "aws_profile" {
  description = "The AWS CLI profile to use for authentication (from ~/.aws/credentials)"
  type        = string
  default     = "default"
}

variable "aws_region" {
  description = "The AWS region where all resources will be created"
  type        = string
  default     = "ap-southeast-1" # Singapore — pick the region closest to you
}

variable "project_name" {
  description = "A short name used to prefix/tag all resources (keeps things organized)"
  type        = string
  default     = "replication-api"
}

variable "environment" {
  description = "Deployment environment (e.g., production, staging)"
  type        = string
  default     = "production"
}

# -----------------------------------------------------------------------------
# Database settings
# -----------------------------------------------------------------------------

variable "db_name" {
  description = "Name of the PostgreSQL database to create in RDS"
  type        = string
  default     = "replication_api_production"
}

variable "db_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "Master password for the RDS instance (keep this secret!)"
  type        = string
  sensitive   = true # Terraform won't print this in logs
}

# -----------------------------------------------------------------------------
# Container settings
# -----------------------------------------------------------------------------

variable "rails_image" {
  description = "Docker image URI for the Rails API (from ECR)"
  type        = string
  # This will be set during CI/CD — no default needed
}

variable "pgcat_image" {
  description = "Docker image URI for PgCat"
  type        = string
  default     = "ghcr.io/postgresml/pgcat:latest"
}

variable "rails_container_port" {
  description = "Port the Rails app listens on inside the container"
  type        = number
  default     = 3000
}

variable "pgcat_container_port" {
  description = "Port PgCat listens on inside the container"
  type        = number
  default     = 6432
}

# -----------------------------------------------------------------------------
# ECS settings
# -----------------------------------------------------------------------------

variable "task_cpu" {
  description = "CPU units for the ECS task (256 = 0.25 vCPU — cheapest option)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memory in MB for the ECS task (512 MB — cheapest option)"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "How many copies of your task to run (2 = high availability)"
  type        = number
  default     = 2
}

# -----------------------------------------------------------------------------
# GitHub OIDC (for CI/CD)
# -----------------------------------------------------------------------------

variable "secret_key_base" {
  description = "Rails SECRET_KEY_BASE for production (generate with: rails secret)"
  type        = string
  sensitive   = true # Terraform won't print this in logs
}

variable "github_org" {
  description = "Your GitHub username or organization name"
  type        = string
  default     = "israelcoper"
}

variable "github_repo" {
  description = "Your GitHub repository name"
  type        = string
  default     = "replication_api"
}
