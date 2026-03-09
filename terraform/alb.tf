# =============================================================================
# ALB — Application Load Balancer
# =============================================================================
# The ALB is the entry point for all HTTP traffic. It:
#   1. Accepts requests from the internet
#   2. Health-checks your ECS tasks
#   3. Distributes traffic across healthy tasks
#   4. Enables zero-downtime deployments (drains old tasks gracefully)
# =============================================================================

# --- The Load Balancer itself ---
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false           # "false" = internet-facing
  load_balancer_type = "application"   # Layer 7 (HTTP/HTTPS)
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids

  # Don't protect against deletion (for easy teardown during learning)
  enable_deletion_protection = false
}

# --- Target Group ---
# A target group is a pool of targets (your ECS tasks) that the ALB
# sends traffic to. It also defines health check settings.
resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = var.rails_container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"  # Fargate requires "ip" target type (not "instance")

  # Health check: ALB periodically hits this endpoint to verify the task is OK.
  # If a task fails health checks, ALB stops sending it traffic.
  health_check {
    path                = "/up"     # Rails 7.2 has a built-in /up health endpoint
    protocol            = "HTTP"
    matcher             = "200"     # Expect HTTP 200 for healthy
    interval            = 30        # Check every 30 seconds
    timeout             = 5         # Timeout after 5 seconds
    healthy_threshold   = 2         # 2 consecutive successes = healthy
    unhealthy_threshold = 3         # 3 consecutive failures = unhealthy
  }

  # Deregistration delay: when removing a task, wait this long for
  # in-flight requests to complete before cutting it off.
  deregistration_delay = 30
}

# --- Listener ---
# A listener defines what port/protocol the ALB accepts and where to
# forward traffic. This listens on port 80 (HTTP) and forwards to the
# target group.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # Default action: forward all traffic to our target group
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  # NOTE: For production, you should:
  #   1. Add an HTTPS listener on port 443 with an ACM certificate
  #   2. Redirect port 80 to 443
  # This is HTTP-only to keep things simple for learning.
}
