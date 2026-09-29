output "service_name" {
  description = "Nombre del servicio ECS"
  value       = aws_ecs_service.this.name
}

output "task_definition_arn" {
  description = "Revisión de task definition desplegada (útil para rollback)"
  value       = aws_ecs_task_definition.this.arn
}

output "task_definition_json" {
  description = "Definición de contenedores renderizada (usada por las pruebas de terraform test)"
  value       = aws_ecs_task_definition.this.container_definitions
}
