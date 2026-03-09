# =============================================================================
# OUTPUTS
# =============================================================================
# Outputs display important values after "terraform apply" completes.
# They're also accessible to other Terraform configurations.
# =============================================================================

output "alb_dns_name" {
  description = "The URL to access your Rails API (via the load balancer)"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ecr_repository_url" {
  description = "The ECR repository URL — use this in your CI/CD to push images"
  value       = aws_ecr_repository.railsapi.repository_url
}

output "rds_primary_endpoint" {
  description = "The RDS primary instance endpoint (for debugging)"
  value       = aws_db_instance.primary.endpoint
}

output "rds_replica_endpoint" {
  description = "The RDS replica instance endpoint (for debugging)"
  value       = aws_db_instance.replica.endpoint
}

output "ecs_cluster_name" {
  description = "The ECS cluster name (used in CI/CD)"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "The ECS service name (used in CI/CD)"
  value       = aws_ecs_service.app.name
}

output "github_actions_role_arn" {
  description = "The IAM role ARN that GitHub Actions assumes via OIDC"
  value       = aws_iam_role.github_actions.arn
}
