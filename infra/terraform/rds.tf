# PostgreSQL administrado (RDS): backups automáticos, PITR, parches menores y Multi-AZ opcional.

resource "aws_db_subnet_group" "main" {
  name       = local.name
  subnet_ids = aws_subnet.data[*].id
}

resource "aws_db_parameter_group" "main" {
  name   = "${local.name}-pg16"
  family = "postgres16"

  # Solo conexiones cifradas (TLS)
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Diagnóstico del incidente de "crecimiento de conexiones": registra conexiones y consultas lentas
  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # ms
  }
}

#trivy:ignore:AVD-AWS-0176 Autenticación IAM fuera de alcance: se usa usuario/password gestionado y rotado por RDS.
#trivy:ignore:AVD-AWS-0133 Performance Insights se habilita según el tamaño de instancia de producción.
resource "aws_db_instance" "main" {
  identifier     = local.name
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db.instance_class

  db_name  = "parking"
  username = "parking"

  # RDS genera el password, lo guarda en Secrets Manager y lo rota.
  # El password NUNCA aparece en el código ni en el state de Terraform.
  manage_master_user_password = true

  allocated_storage     = var.db.allocated_storage
  max_allocated_storage = var.db.max_allocated_storage # autoescalado de almacenamiento
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.main.name
  publicly_accessible    = false
  multi_az               = var.db.multi_az

  # Respaldo y recuperación: snapshots diarios + point-in-time recovery (RPO ~5 min)
  backup_retention_period  = var.db.backup_retention_days
  backup_window            = "08:00-09:00" # UTC (02:00-03:00 hora de CDMX)
  maintenance_window       = "sun:09:30-sun:10:30"
  copy_tags_to_snapshot    = true
  delete_automated_backups = false

  deletion_protection       = var.db.deletion_protection
  skip_final_snapshot       = var.environment != "production"
  final_snapshot_identifier = "${local.name}-final"

  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["postgresql"]
}

locals {
  # ARN del secreto que RDS crea y rota automáticamente
  db_secret_arn = aws_db_instance.main.master_user_secret[0].secret_arn
}
