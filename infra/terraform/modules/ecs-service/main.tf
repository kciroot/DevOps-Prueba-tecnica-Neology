# Módulo reutilizable: una task definition + un servicio ECS Fargate detrás del ALB.
# Se usa dos veces (frontend y backend) con el mismo endurecimiento.

locals {
  container_name = var.name
  volumes        = { for path in var.writable_paths : replace(trim(path, "/"), "/", "-") => path }
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64" # el pipeline publica imágenes linux/amd64
  }

  # Volúmenes efímeros para las únicas rutas que necesitan escritura
  dynamic "volume" {
    for_each = local.volumes
    content {
      name = volume.key
    }
  }

  container_definitions = jsonencode([{
    name      = local.container_name
    image     = var.image
    essential = true

    portMappings = [for port in concat([var.container_port], var.extra_ports) : {
      containerPort = port
      protocol      = "tcp"
    }]

    environment = [for key, value in var.environment : { name = key, value = value }]
    secrets     = [for key, arn in var.secrets : { name = key, valueFrom = arn }]

    # Endurecimiento del contenedor
    readonlyRootFilesystem = true
    privileged             = false
    linuxParameters = {
      capabilities = { drop = ["ALL"] }
    }
    mountPoints = [for name, path in local.volumes : {
      sourceVolume  = name
      containerPath = path
      readOnly      = false
    }]

    healthCheck = {
      command     = var.health_check_command
      interval    = 15
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }

    stopTimeout = 30 # > timeout de graceful shutdown de la aplicación

    repositoryCredentials = var.registry_credentials_secret_arn == null ? null : {
      credentialsParameter = var.registry_credentials_secret_arn
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = var.log_group_name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Despliegue rolling sin pérdida de capacidad: primero arrancan las tareas nuevas
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds

  # Si las tareas nuevas no quedan sanas, ECS vuelve solo a la versión anterior
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # terraform apply espera a que el despliegue termine: el pipeline falla si no se estabiliza
  wait_for_steady_state = true

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  propagate_tags = "SERVICE"
}
