variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "private_subnet_ids" { type = list(string) }
variable "ecs_instance_profile_arn" { type = string }
variable "ecs_execution_role_arn" { type = string }
variable "ecs_task_role_arn" { type = string }
variable "db_secret_arn" { type = string }
variable "app_image" {
  type    = string
  default = "nginx:alpine"
}
variable "app_port" {
  type    = number
  default = 8000
}
