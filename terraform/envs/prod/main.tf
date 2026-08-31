module "vpc" {
  source = "../../modules/vpc"
}

module "iam" {
  source = "../../modules/iam"
}

module "ecs" {
  source                   = "../../modules/ecs"
  vpc_id                   = module.vpc.vpc_id
  public_subnet_ids        = module.vpc.public_subnet_ids
  private_subnet_ids       = module.vpc.private_subnet_ids
  ecs_instance_profile_arn = module.iam.ecs_instance_profile_arn
  ecs_execution_role_arn   = module.iam.ecs_execution_role_arn
  ecs_task_role_arn        = module.iam.ecs_task_role_arn
  db_secret_arn            = module.rds.db_secret_arn
  app_image                = var.app_image
}

module "rds" {
  source                = "../../modules/rds"
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  ecs_security_group_id = module.ecs.ecs_instances_security_group_id
}

module "vertical_scaling" {
  source           = "../../modules/vertical_scaling"
  ecs_cluster_name = module.ecs.ecs_cluster_name
  ecs_service_name = module.ecs.ecs_service_name
}
