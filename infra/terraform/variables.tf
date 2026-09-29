# ---------------------------------------------------------------------------
# Generales
# ---------------------------------------------------------------------------
variable "project" {
  description = "Prefijo de nombres y etiqueta Project"
  type        = string
  default     = "parking"
}

variable "environment" {
  description = "Ambiente: dev o production"
  type        = string

  validation {
    condition     = contains(["dev", "production"], var.environment)
    error_message = "environment debe ser 'dev' o 'production'."
  }
}

variable "aws_region" {
  description = "Región de AWS"
  type        = string
  default     = "us-east-1"
}

# ---------------------------------------------------------------------------
# Red
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "Rango de la VPC. Se divide en subredes públicas, de aplicación y de datos"
  type        = string
  default     = "10.20.0.0/16"
}

variable "nat_gateway_per_az" {
  description = "true = un NAT por zona (alta disponibilidad, prod); false = uno solo (costo, dev)"
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ARN de un certificado ACM. Si se define, el ALB sirve HTTPS y redirige HTTP->HTTPS"
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Imágenes y cómputo (ECS Fargate)
# ---------------------------------------------------------------------------
variable "image_repository" {
  description = "Repositorio de imágenes, p. ej. ghcr.io/usuario/devops-prueba-tecnica-neology"
  type        = string
}

variable "image_tag" {
  description = "Tag inmutable a desplegar (sha-<commit>). Lo define el pipeline"
  type        = string
}

variable "registry_credentials_secret_arn" {
  description = "Secreto de Secrets Manager con usuario/token de GHCR (null si las imágenes son públicas)"
  type        = string
  default     = null
}

variable "backend" {
  description = "Tamaño y réplicas del backend"
  type = object({
    cpu           = number
    memory        = number
    desired_count = number
  })
}

variable "frontend" {
  description = "Tamaño y réplicas del frontend"
  type = object({
    cpu           = number
    memory        = number
    desired_count = number
  })
}

variable "db_pool_size" {
  description = "Conexiones por tarea del backend. Total = desired_count x db_pool_size"
  type        = number
  default     = 10
}

variable "log_level" {
  description = "Nivel de log de la aplicación"
  type        = string
  default     = "INFO"
}

variable "log_retention_days" {
  description = "Días de retención de logs en CloudWatch"
  type        = number
  default     = 30
}

# ---------------------------------------------------------------------------
# Base de datos (RDS PostgreSQL)
# ---------------------------------------------------------------------------
variable "db" {
  description = "Configuración de RDS PostgreSQL"
  type = object({
    instance_class        = string
    allocated_storage     = number
    max_allocated_storage = number
    multi_az              = bool
    backup_retention_days = number
    deletion_protection   = bool
  })
}

# ---------------------------------------------------------------------------
# Alertas y CI/CD
# ---------------------------------------------------------------------------
variable "alarm_email" {
  description = "Correo que recibe las alarmas (null = sin suscripción)"
  type        = string
  default     = null
}

variable "github_repository" {
  description = "owner/repo autorizado a desplegar vía OIDC (null = no crear el rol)"
  type        = string
  default     = null
}

variable "create_github_oidc_provider" {
  description = "Crear el proveedor OIDC de GitHub (false si ya existe en la cuenta)"
  type        = bool
  default     = true
}

variable "tf_state_bucket" {
  description = "Bucket S3 del state (el rol de despliegue necesita leer/escribir su state)"
  type        = string
  default     = null
}
