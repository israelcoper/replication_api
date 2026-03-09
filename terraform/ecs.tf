# =============================================================================
# ECS — Elastic Container Service
# =============================================================================
# ECS runs your Docker containers in the cloud. Key concepts:
#
#   Cluster   = A logical grouping of tasks/services (like a namespace)
#   Task Def  = A blueprint describing which containers to run and how
#   Service   = Ensures N copies of your task are always running
#   Fargate   = Serverless compute — you don't manage any EC2 instances
#
# We use the SIDECAR PATTERN: railsapi and pgcat run in the same task.
# They share a network namespace, so they talk over localhost (127.0.0.1).
# =============================================================================

# --- ECS Cluster ---
# Just a logical container for your services. No cost by itself.
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  # CloudWatch Container Insights gives you monitoring metrics.
  # Disabled to save cost — enable when you need observability.
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

# --- CloudWatch Log Groups ---
# ECS sends container stdout/stderr to CloudWatch Logs.
# This is how you view your app's logs in AWS.
resource "aws_cloudwatch_log_group" "railsapi" {
  name              = "/ecs/${var.project_name}/railsapi"
  retention_in_days = 7 # Keep logs for 7 days (saves cost)
}

resource "aws_cloudwatch_log_group" "pgcat" {
  name              = "/ecs/${var.project_name}/pgcat"
  retention_in_days = 7
}

# --- IAM Role: Task Execution Role ---
# This role is used by ECS itself (not your app) to:
#   - Pull images from ECR
#   - Send logs to CloudWatch
#   - Read secrets from SSM/Secrets Manager
resource "aws_iam_role" "ecs_execution" {
  name = "${var.project_name}-ecs-execution-role"

  # "Assume role policy" = WHO can use this role.
  # Here, only the ECS service can assume it.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Attach the AWS-managed policy that grants ECR pull + CloudWatch logs
resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- IAM Role: Task Role ---
# This role is used by YOUR APP at runtime (e.g., if your Rails code
# needs to call other AWS services like S3).
# For now it's empty, but you can add policies later.
resource "aws_iam_role" "ecs_task" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# --- ECS Task Definition ---
# This is the blueprint for your containers.
# It defines WHAT runs, HOW MUCH resources each gets, and HOW they connect.
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-task"
  requires_compatibilities = ["FARGATE"]   # Run on Fargate (serverless)
  network_mode             = "awsvpc"      # Each task gets its own ENI (IP)
  cpu                      = var.task_cpu   # CPU for the ENTIRE task
  memory                   = var.task_memory # Memory for the ENTIRE task
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  # The container definitions describe each container in the task.
  # Both containers share the same network (localhost).
  container_definitions = jsonencode([
    # --- PgCat Sidecar Container ---
    # This MUST start before Rails because Rails depends on PgCat for DB access.
    {
      name      = "pgcat"
      image     = var.pgcat_image
      essential = true  # If pgcat crashes, the whole task is restarted

      # Port mapping (within the task's network)
      portMappings = [
        {
          containerPort = var.pgcat_container_port
          protocol      = "tcp"
        }
      ]

      # PgCat config is injected via environment variable.
      # We dynamically build the TOML config using RDS endpoints.
      environment = [
        {
          name = "PGCAT_CONFIG"
          value = templatefile("${path.module}/templates/pgcat.toml.tftpl", {
            db_name          = var.db_name
            db_username      = var.db_username
            db_password      = var.db_password
            primary_host     = aws_db_instance.primary.address
            replica_host     = aws_db_instance.replica.address
            primary_port     = aws_db_instance.primary.port
            replica_port     = aws_db_instance.replica.port
          })
        }
      ]

      # Override the entrypoint to write the config and start PgCat
      entryPoint = ["/bin/sh", "-c"]
      command    = ["echo \"$PGCAT_CONFIG\" > /etc/pgcat/pgcat.toml && pgcat /etc/pgcat/pgcat.toml"]

      # Resource limits for this container (must fit within task limits)
      cpu    = 64   # 0.0625 vCPU — PgCat is lightweight
      memory = 128  # 128 MB

      # Logging configuration
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.pgcat.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "pgcat"
        }
      }
    },

    # --- Rails API Container ---
    {
      name      = "railsapi"
      image     = var.rails_image
      essential = true  # If Rails crashes, the whole task is restarted

      portMappings = [
        {
          containerPort = var.rails_container_port
          protocol      = "tcp"
        }
      ]

      # Environment variables for your Rails app
      environment = [
        {
          name  = "RAILS_ENV"
          value = "production"
        },
        {
          # Rails connects to PgCat on localhost because they're in the same task!
          # PgCat then routes queries to the appropriate RDS instance.
          name  = "DATABASE_URL"
          value = "postgres://${var.db_username}:${var.db_password}@127.0.0.1:${var.pgcat_container_port}/${var.db_name}"
        },
        {
          name  = "RAILS_LOG_TO_STDOUT"
          value = "true"
        },
        {
          # Required for Rails production — generate with: rails secret
          name  = "SECRET_KEY_BASE"
          value = var.secret_key_base
        }
      ]

      # Resource limits for this container
      cpu    = 192  # Remaining CPU after PgCat
      memory = 384  # Remaining memory after PgCat

      # Wait for PgCat to be ready before starting Rails.
      # This is the ECS way to express container startup ordering.
      dependsOn = [
        {
          containerName = "pgcat"
          condition     = "START"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.railsapi.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "railsapi"
        }
      }
    }
  ])
}

# --- ECS Service ---
# The service ensures your desired number of tasks are always running.
# If a task crashes, the service automatically starts a new one.
# It also registers tasks with the ALB for load balancing.
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count  # How many copies to run
  launch_type     = "FARGATE"

  # Network configuration for Fargate tasks
  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true  # Needed in default VPC to pull images from ECR
  }

  # Connect the service to the ALB target group
  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "railsapi"             # Which container receives traffic
    container_port   = var.rails_container_port
  }

  # Don't try to create the service until the ALB listener exists
  depends_on = [aws_lb_listener.http]

  # When deploying a new version, ECS will:
  #   1. Start new tasks with the new image
  #   2. Wait for them to pass health checks
  #   3. Drain and stop old tasks
  # This gives you zero-downtime deployments!
  deployment_minimum_healthy_percent = 50   # Keep at least 50% running during deploy
  deployment_maximum_percent         = 200  # Can temporarily run 200% during deploy
}
