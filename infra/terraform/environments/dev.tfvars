# Ambiente DEV: mínimo costo, una réplica, sin Multi-AZ.
# image_tag e image_repository los define el pipeline (-var).
environment = "dev"
aws_region  = "us-east-1"
vpc_cidr    = "10.20.0.0/16"

nat_gateway_per_az = false # un solo NAT (ahorro)
certificate_arn    = null  # HTTP en dev; en producción es obligatorio HTTPS

backend  = { cpu = 512, memory = 1024, desired_count = 1 }
frontend = { cpu = 256, memory = 512, desired_count = 1 }

db_pool_size       = 10
log_level          = "INFO"
log_retention_days = 14

db = {
  instance_class        = "db.t4g.micro"
  allocated_storage     = 20
  max_allocated_storage = 50
  multi_az              = false
  backup_retention_days = 7
  deletion_protection   = false
}

alarm_email       = null
github_repository = null # p. ej. "usuario/DevOps-Prueba-tecnica-Neology"
tf_state_bucket   = null
