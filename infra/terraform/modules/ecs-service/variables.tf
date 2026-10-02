variable "name" {
  description = "Nombre del servicio (p. ej. parking-dev-backend)"
  type        = string
}

variable "cluster_id" {
  description = "ID del cluster ECS"
  type        = string
}

variable "image" {
  description = "Imagen completa con tag inmutable"
  type        = string
}

variable "cpu" {
  description = "CPU de la tarea (unidades Fargate: 256 = 0.25 vCPU)"
  type        = number
}

variable "memory" {
  description = "Memoria de la tarea en MiB"
  type        = number
}

variable "desired_count" {
  description = "Número de tareas"
  type        = number
}

variable "container_port" {
  description = "Puerto de tráfico registrado en el target group"
  type        = number
}

variable "extra_ports" {
  description = "Puertos adicionales del contenedor (p. ej. 8081 de gestión)"
  type        = list(number)
  default     = []
}

variable "environment" {
  description = "Variables de entorno NO sensibles"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Variables sensibles: nombre -> ARN de Secrets Manager (ECS las inyecta al iniciar)"
  type        = map(string)
  default     = {}
}

variable "health_check_command" {
  description = "Comando de health check del contenedor"
  type        = list(string)
}

variable "subnet_ids" {
  description = "Subredes privadas donde corren las tareas"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security groups de las tareas"
  type        = list(string)
}

variable "target_group_arn" {
  description = "Target group del ALB"
  type        = string
}

variable "execution_role_arn" {
  description = "Rol que usa ECS para descargar la imagen, leer secretos y escribir logs"
  type        = string
}

variable "task_role_arn" {
  description = "Rol de la aplicación en tiempo de ejecución (sin permisos si no llama a AWS)"
  type        = string
}

variable "log_group_name" {
  description = "Grupo de logs de CloudWatch"
  type        = string
}

variable "aws_region" {
  description = "Región para el driver awslogs"
  type        = string
}

variable "registry_credentials_secret_arn" {
  description = "Credenciales del registro privado (null para imágenes públicas)"
  type        = string
  default     = null
}

variable "health_check_grace_period_seconds" {
  description = "Tiempo de arranque antes de evaluar el health check del ALB"
  type        = number
  default     = 60
}
