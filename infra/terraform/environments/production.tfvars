# Ambiente PRODUCTION: alta disponibilidad (2 AZ), HTTPS, Multi-AZ y protección contra borrado.
# Recomendado: cuenta de AWS separada de dev.
environment = "production"
aws_region  = "us-east-1"
vpc_cidr    = "10.30.0.0/16"

nat_gateway_per_az = true
certificate_arn    = "arn:aws:acm:us-east-1:111111111111:certificate/REEMPLAZAR"

backend  = { cpu = 1024, memory = 2048, desired_count = 2 }
frontend = { cpu = 256, memory = 512, desired_count = 2 }

db_pool_size       = 10
log_level          = "INFO"
log_retention_days = 90

db = {
  instance_class        = "db.t4g.small"
  allocated_storage     = 50
  max_allocated_storage = 200
  multi_az              = true
  backup_retention_days = 14
  deletion_protection   = true
}

alarm_email       = "oncall@example.com"
github_repository = null # p. ej. "usuario/DevOps-Prueba-tecnica-Neology"
tf_state_bucket   = null
