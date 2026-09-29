output "service_name" {
  description = "Nombre del servicio ECS"
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "Revisión de task definition desplegada (útil para rollback)"
  value       = aws_ecs_task_definition.this.arn
}

output "secret_variable_names" {
  description = "Variables inyectadas desde Secrets Manager (verificado por terraform test)"
  value       = keys(var.secrets)
}

output "plain_variable_names" {
  description = "Variables de entorno en texto plano (verificado por terraform test)"
  value       = keys(var.environment)
}
