# Cómputo: ECS Fargate (contenedores gestionados, sin servidores que parchear).

resource "aws_ecs_cluster" "main" {
  name = local.name

  # Container Insights: CPU, memoria, reinicios y tareas por servicio en CloudWatch
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "app" {
  for_each          = toset(["backend", "frontend"])
  name              = "/ecs/${local.name}/${each.key}"
  retention_in_days = var.log_retention_days
}

# --- IAM: dos roles con propósitos distintos (mínimo privilegio) ---
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# Rol de EJECUCIÓN: lo usa el agente de ECS (descargar imagen, leer secretos, escribir logs)
resource "aws_iam_role" "execution" {
  name               = "${local.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_base" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_secrets" {
  statement {
    sid       = "ReadOnlyTheSecretsThisAppNeeds"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = compact([local.db_secret_arn, var.registry_credentials_secret_arn])
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  name   = "read-app-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secrets.json
}

# Rol de TAREA: identidad de la aplicación. No llama a APIs de AWS, así que no tiene permisos.
resource "aws_iam_role" "task" {
  name               = "${local.name}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# --- Servicios ---
module "backend" {
  source = "./modules/ecs-service"

  name          = "${local.name}-backend"
  cluster_id    = aws_ecs_cluster.main.id
  image         = "${var.image_repository}/parking-backend:${var.image_tag}"
  cpu           = var.backend.cpu
  memory        = var.backend.memory
  desired_count = var.backend.desired_count

  container_port = 8080
  extra_ports    = [8081]

  # Configuración por ambiente (no sensible)
  environment = {
    SPRING_PROFILES_ACTIVE = "postgres"
    APP_ENV                = var.environment
    APP_VERSION            = var.image_tag
    DB_URL                 = "jdbc:postgresql://${aws_db_instance.main.address}:${aws_db_instance.main.port}/${aws_db_instance.main.db_name}?sslmode=require&ApplicationName=parking-api-${var.image_tag}"
    DB_POOL_SIZE           = tostring(var.db_pool_size)
    LOG_LEVEL              = var.log_level
  }

  # Credenciales: ECS las lee de Secrets Manager al iniciar la tarea (nunca en texto plano)
  secrets = {
    DB_USERNAME = "${local.db_secret_arn}:username::"
    DB_PASSWORD = "${local.db_secret_arn}:password::"
  }

  health_check_command = ["CMD-SHELL", "curl -fsS http://127.0.0.1:8081/actuator/health/liveness || exit 1"]

  subnet_ids                        = aws_subnet.app[*].id
  security_group_ids                = [aws_security_group.backend.id]
  target_group_arn                  = aws_lb_target_group.backend.arn
  execution_role_arn                = aws_iam_role.execution.arn
  task_role_arn                     = aws_iam_role.task.arn
  log_group_name                    = aws_cloudwatch_log_group.app["backend"].name
  aws_region                        = var.aws_region
  registry_credentials_secret_arn   = var.registry_credentials_secret_arn
  health_check_grace_period_seconds = 90

  depends_on = [aws_lb_listener_rule.api, aws_secretsmanager_secret_version.db]
}

module "frontend" {
  source = "./modules/ecs-service"

  name          = "${local.name}-frontend"
  cluster_id    = aws_ecs_cluster.main.id
  image         = "${var.image_repository}/parking-frontend:${var.image_tag}"
  cpu           = var.frontend.cpu
  memory        = var.frontend.memory
  desired_count = var.frontend.desired_count

  container_port = 8080

  # En AWS el ALB enruta /neo/* directo al backend; nginx solo sirve la SPA.
  environment = {
    BACKEND_URL = "http://127.0.0.1:8080"
  }

  health_check_command = ["CMD-SHELL", "wget -q --spider http://127.0.0.1:8080/healthz || exit 1"]

  subnet_ids                      = aws_subnet.app[*].id
  security_group_ids              = [aws_security_group.frontend.id]
  target_group_arn                = aws_lb_target_group.frontend.arn
  execution_role_arn              = aws_iam_role.execution.arn
  task_role_arn                   = aws_iam_role.task.arn
  log_group_name                  = aws_cloudwatch_log_group.app["frontend"].name
  aws_region                      = var.aws_region
  registry_credentials_secret_arn = var.registry_credentials_secret_arn

  depends_on = [aws_lb_listener.http]
}
