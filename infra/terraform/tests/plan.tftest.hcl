# Pruebas de la infraestructura SIN credenciales ni costos: provider de AWS simulado (mock).
#   terraform test
# Verifican las decisiones de seguridad más importantes sobre el plan.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  # Los ARN simulados deben tener formato válido: el provider los valida en el plan
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:us-east-1:111111111111:parking-alerts" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:loadbalancer/app/parking/abc" }
  }
  mock_resource "aws_lb_listener" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:listener/app/parking/abc/def" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:111111111111:targetgroup/parking/abc" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/parking" }
  }
  mock_resource "aws_db_instance" {
    defaults = {
      address = "parking-dev.abc.us-east-1.rds.amazonaws.com"
      port    = 5432
    }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:us-east-1:111111111111:secret:parking-dev/db-credentials" }
  }
}

variables {
  image_repository = "ghcr.io/example/devops-prueba-tecnica-neology"
  image_tag        = "sha-abc1234"
}

run "dev_es_seguro_por_defecto" {
  command = plan

  variables {
    environment = "dev"
    backend     = { cpu = 512, memory = 1024, desired_count = 1 }
    frontend    = { cpu = 256, memory = 512, desired_count = 1 }
    db = {
      instance_class        = "db.t4g.micro"
      allocated_storage     = 20
      max_allocated_storage = 50
      multi_az              = false
      backup_retention_days = 7
      deletion_protection   = false
    }
  }

  assert {
    condition     = aws_db_instance.main.publicly_accessible == false
    error_message = "RDS no debe ser accesible públicamente"
  }

  assert {
    condition     = aws_db_instance.main.storage_encrypted
    error_message = "RDS debe cifrar el almacenamiento"
  }

  assert {
    condition     = aws_db_instance.main.password == null && aws_db_instance.main.password_wo_version == 1
    error_message = "El password de RDS solo se escribe como write-only (nunca en el state)"
  }

  assert {
    condition     = aws_db_instance.main.backup_retention_period >= 7
    error_message = "Se requieren al menos 7 días de backups (PITR)"
  }

  assert {
    condition     = length(aws_subnet.app) == 2 && length(aws_nat_gateway.main) == 1
    error_message = "dev: 2 subredes de aplicación y un solo NAT"
  }

  assert {
    condition     = strcontains(module.backend.task_definition_json, "\"drop\":[\"ALL\"]")
    error_message = "El backend debe correr sin capabilities de Linux"
  }

  assert {
    condition = (
      strcontains(module.backend.task_definition_json, "\"DB_PASSWORD\",\"valueFrom\":") &&
      !strcontains(module.backend.task_definition_json, "\"DB_PASSWORD\",\"value\":")
    )
    error_message = "El password de la BD debe venir de Secrets Manager, nunca en texto plano"
  }

  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "forward"
    error_message = "Sin certificado, el listener HTTP reenvía al frontend"
  }
}

run "produccion_exige_https_y_alta_disponibilidad" {
  command = plan

  variables {
    environment        = "production"
    nat_gateway_per_az = true
    certificate_arn    = "arn:aws:acm:us-east-1:111111111111:certificate/test"
    backend            = { cpu = 1024, memory = 2048, desired_count = 2 }
    frontend           = { cpu = 256, memory = 512, desired_count = 2 }
    db = {
      instance_class        = "db.t4g.small"
      allocated_storage     = 50
      max_allocated_storage = 200
      multi_az              = true
      backup_retention_days = 14
      deletion_protection   = true
    }
  }

  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "redirect"
    error_message = "Con certificado, HTTP debe redirigir a HTTPS"
  }

  assert {
    condition     = aws_db_instance.main.multi_az && aws_db_instance.main.deletion_protection
    error_message = "Producción requiere Multi-AZ y protección contra borrado"
  }

  assert {
    condition     = aws_db_instance.main.skip_final_snapshot == false
    error_message = "Producción debe tomar un snapshot final antes de borrar la BD"
  }

  assert {
    condition     = length(aws_nat_gateway.main) == 2
    error_message = "Producción usa un NAT por zona"
  }
}

run "rechaza_ambientes_desconocidos" {
  command = plan

  variables {
    environment = "qa"
    backend     = { cpu = 256, memory = 512, desired_count = 1 }
    frontend    = { cpu = 256, memory = 512, desired_count = 1 }
    db = {
      instance_class        = "db.t4g.micro"
      allocated_storage     = 20
      max_allocated_storage = 20
      multi_az              = false
      backup_retention_days = 1
      deletion_protection   = false
    }
  }

  expect_failures = [var.environment]
}
