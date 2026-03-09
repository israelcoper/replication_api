# =============================================================================
# SECURITY GROUPS
# =============================================================================
# Security groups are like firewalls. They control what traffic can flow
# in and out of your resources. Each resource gets its own security group
# with the minimum permissions needed (principle of least privilege).
# =============================================================================

# --- ALB Security Group ---
# The ALB is the only thing exposed to the internet.
# It accepts HTTP traffic on port 80.
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP traffic from the internet to the ALB"
  vpc_id      = data.aws_vpc.default.id

  # Inbound: Allow HTTP from anywhere
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 0.0.0.0/0 = anywhere on the internet
  }

  # Outbound: Allow all (ALB needs to reach ECS tasks)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # -1 = all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- ECS Security Group ---
# ECS tasks should ONLY accept traffic from the ALB, not directly from internet.
resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-ecs-sg"
  description = "Allow traffic from ALB to ECS tasks"
  vpc_id      = data.aws_vpc.default.id

  # Inbound: Only allow traffic from the ALB on the Rails port
  ingress {
    description     = "Traffic from ALB"
    from_port       = var.rails_container_port
    to_port         = var.rails_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id] # Only from ALB!
  }

  # Outbound: Allow all (tasks need to reach RDS, ECR, etc.)
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- RDS Security Group ---
# The database should ONLY be reachable from ECS tasks, never from internet.
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow PostgreSQL traffic from ECS tasks only"
  vpc_id      = data.aws_vpc.default.id

  # Inbound: Only allow PostgreSQL port from ECS tasks
  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id] # Only from ECS!
  }

  # Outbound: Allow all
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
