output "app_url" {
  description = "URL pública de la aplicación"
  value       = "${local.https_enabled ? "https" : "http"}://${aws_lb.main.dns_name}"
}

output "alb_dns_name" {
  description = "DNS del ALB (para un registro CNAME/ALIAS propio)"
  value       = aws_lb.main.dns_name
}

output "ecs_cluster_name" {
  description = "Cluster ECS"
  value       = aws_ecs_cluster.main.name
}

output "ecs_services" {
  description = "Servicios ECS (para aws ecs update-service / describe-services)"
  value = {
    backend  = module.backend.service_name
    frontend = module.frontend.service_name
  }
}

output "deployed_image_tag" {
  description = "Versión desplegada actualmente (rollback = volver a aplicar el tag anterior)"
  value       = var.image_tag
}

output "db_endpoint" {
  description = "Endpoint privado de RDS (solo accesible desde el backend)"
  value       = aws_db_instance.main.address
}

output "db_secret_arn" {
  description = "Secreto con las credenciales de la BD (gestionado y rotado por RDS)"
  value       = local.db_secret_arn
}

output "log_groups" {
  description = "Grupos de logs de CloudWatch"
  value       = { for key, group in aws_cloudwatch_log_group.app : key => group.name }
}

output "alerts_topic_arn" {
  description = "Tema SNS de alertas"
  value       = aws_sns_topic.alerts.arn
}

output "github_deploy_role_arn" {
  description = "Rol a configurar como variable AWS_DEPLOY_ROLE_ARN en el Environment de GitHub"
  value       = local.create_github_role ? aws_iam_role.github_deploy[0].arn : null
}
