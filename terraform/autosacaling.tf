# =============================================================================
# AUTO SCALING
# =============================================================================
# Auto scaling automatically adjusts the number of running ECS tasks based
# on demand. When CPU usage is high, it adds tasks. When it's low, it
# removes them. This makes your app scalable AND cost-efficient.
# =============================================================================

# Register the ECS service as a scalable target
resource "aws_appautoscaling_target" "ecs" {
  # The resource ID format is: service/<cluster-name>/<service-name>
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"  # What we're scaling
  service_namespace  = "ecs"

  min_capacity = 1   # Never go below 1 task (saves cost)
  max_capacity = 4   # Never exceed 4 tasks (caps cost)
}

# --- Scale based on CPU usage ---
# "Target tracking" is the simplest scaling policy. You set a target CPU %,
# and AWS figures out how many tasks to add/remove to maintain it.
resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.project_name}-cpu-scaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    # Use the built-in ECS CPU metric
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = 70.0  # Try to keep average CPU at 70%
    scale_in_cooldown  = 300   # Wait 5 min after scaling IN before scaling again
    scale_out_cooldown = 60    # Wait 1 min after scaling OUT (react faster to spikes)
  }
}
