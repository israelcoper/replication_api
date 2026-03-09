# =============================================================================
# GITHUB OIDC — Secure CI/CD Authentication
# =============================================================================
# OIDC (OpenID Connect) lets GitHub Actions assume an AWS IAM role WITHOUT
# storing long-lived AWS access keys as secrets. Here's how it works:
#
#   1. GitHub Actions requests a short-lived OIDC token from GitHub
#   2. GitHub Actions presents this token to AWS STS (Security Token Service)
#   3. AWS verifies the token came from GitHub and matches our conditions
#   4. AWS gives GitHub Actions temporary credentials (valid ~1 hour)
#
# This is much more secure than storing AWS_ACCESS_KEY_ID/SECRET in GitHub!
# =============================================================================

# --- OIDC Identity Provider ---
# This tells AWS to trust GitHub as an identity provider.
# You only need ONE of these per AWS account (not per repo).
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  # The "audience" must match what GitHub Actions sends
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC thumbprint (this is a well-known, stable value)
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"]
}

# --- IAM Role for GitHub Actions ---
# This role defines WHAT GitHub Actions can do in your AWS account.
resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions-role"

  # WHO can assume this role: only GitHub Actions, and only from YOUR repo
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            # Only allow the "sts.amazonaws.com" audience
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            # Only allow workflows from YOUR repo's production branch
            # The "*" at the end allows any workflow/job in that branch
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/production"
          }
        }
      }
    ]
  })
}

# --- Policy: ECR Access ---
# GitHub Actions needs to push Docker images to ECR
resource "aws_iam_role_policy" "github_ecr" {
  name = "${var.project_name}-github-ecr-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAuth"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"  # Needed to log in to ECR
        ]
        Resource = "*"  # GetAuthorizationToken doesn't support resource-level perms
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        # Restrict to only YOUR repository (least privilege)
        Resource = aws_ecr_repository.railsapi.arn
      }
    ]
  })
}

# --- Policy: ECS Deployment ---
# GitHub Actions needs to update the ECS service to trigger a new deployment
resource "aws_iam_role_policy" "github_ecs" {
  name = "${var.project_name}-github-ecs-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSUpdateService"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",           # Trigger a new deployment
          "ecs:DescribeServices",        # Check deployment status
          "ecs:DescribeTaskDefinition",  # Read current task definition
          "ecs:RegisterTaskDefinition",  # Create new task definition revision
          "ecs:ListTasks",               # List running tasks
          "ecs:DescribeTasks"            # Check task status
        ]
        Resource = "*"
        # NOTE: For tighter security, you could restrict to specific cluster/service ARNs
      },
      {
        Sid    = "PassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        # ECS needs to "pass" execution and task roles when registering a new task def
        Resource = [
          aws_iam_role.ecs_execution.arn,
          aws_iam_role.ecs_task.arn
        ]
      }
    ]
  })
}
