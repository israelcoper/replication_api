# =============================================================================
# ECR — Elastic Container Registry
# =============================================================================
# ECR is AWS's Docker Hub. It stores your Docker images privately.
# Your CI/CD pipeline will push images here, and ECS will pull from here.
# =============================================================================

resource "aws_ecr_repository" "railsapi" {
  name = "${var.project_name}/railsapi"

  # "MUTABLE" means you can overwrite tags (e.g., push a new "latest").
  # "IMMUTABLE" would prevent overwriting — safer but less convenient.
  image_tag_mutability = "MUTABLE"

  # Scan images for known vulnerabilities on push (free and useful!)
  image_scanning_configuration {
    scan_on_push = true
  }

  # Delete the repository even if it has images (for easy teardown during learning)
  force_delete = true
}

# Lifecycle policy: Auto-delete old images to save storage costs.
# This keeps only the 10 most recent images.
resource "aws_ecr_lifecycle_policy" "railsapi" {
  repository = aws_ecr_repository.railsapi.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the 10 most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
