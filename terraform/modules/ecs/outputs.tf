output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "ecs_instances_security_group_id" {
  value = aws_security_group.ecs_instances.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}
