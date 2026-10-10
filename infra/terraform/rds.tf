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

# --- Credenciales ---
# El password se genera como valor EFÍMERO en cada apply y se escribe con atributos write-only
# en RDS y en Secrets Manager: no queda en el código, ni en el plan, ni en el state.
# Solo se reescribe cuando cambia db_password_version (rotación deliberada, ver docs/OPERATIONS.md).
# Se evita la rotación automática de RDS (cada 7 días) porque ECS inyecta el secreto solo al
# arrancar la tarea: tras rotar, las conexiones nuevas del pool fallarían sin un reinicio.
locals {
  db_username   = "parking"
  db_secret_arn = aws_secretsmanager_secret.db.arn
}

ephemeral "random_password" "db" {
  length  = 32
  special = false # sin caracteres que haya que escapar en JDBC
}

#trivy:ignore:AVD-AWS-0098 Cifrado con la llave administrada de Secrets Manager (suficiente para este alcance).
resource "aws_secretsmanager_secret" "db" {
  name                    = "${local.name}/db-credentials"
  description             = "Usuario y password de PostgreSQL para el backend"
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string_wo = jsonencode({
    username = local.db_username
    password = ephemeral.random_password.db.result
  })
  secret_string_wo_version = var.db_password_version
}

#trivy:ignore:AVD-AWS-0176 Autenticación IAM fuera de alcance: usuario/password en Secrets Manager.
#trivy:ignore:AVD-AWS-0133 Performance Insights se habilita según el tamaño de instancia de producción.
resource "aws_db_instance" "main" {
  identifier     = local.name
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db.instance_class

  db_name             = "parking"
  username            = local.db_username
  password_wo         = ephemeral.random_password.db.result
  password_wo_version = var.db_password_version

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
