output "alb_dns_name" {
  value       = module.ecs.alb_dns_name
  description = "Public ALB URL for smoke tests"
}

output "ecr_repository_url" {
  value       = module.ecs.ecr_repository_url
  description = "ECR Repository URL for Docker pushes"
}
