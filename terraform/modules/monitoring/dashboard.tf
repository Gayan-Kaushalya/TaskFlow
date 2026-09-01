resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "taskflow-application-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", "app/taskflow-alb/653356053", { "stat" = "Average", "label" = "Avg Response Time (s)" }],
            ["...", { "stat" = "p95", "label" = "p95 Response Time (s)" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "Request Latency (ALB Target Response Time)"
          period  = 60
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", "taskflow-cluster", "ServiceName", "taskflow-service", { "stat" = "Average", "label" = "Running Tasks" }],
            ["AWS/ECS", "CPUUtilization", "ClusterName", "taskflow-cluster", "ServiceName", "taskflow-service", { "stat" = "Average", "visible" = false }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "ECS Running Task Count"
          period  = 60
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", "taskflow-cluster", "ServiceName", "taskflow-service", { "stat" = "Average", "label" = "CPU Utilization (%)" }],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", "taskflow-cluster", "ServiceName", "taskflow-service", { "stat" = "Average", "label" = "Memory Utilization (%)" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = "us-east-1"
          title   = "ECS Resource Utilization (CPU & Memory)"
          period  = 60
        }
      }
    ]
  })
}
