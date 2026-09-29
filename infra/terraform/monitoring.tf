# Alertas mínimas en CloudWatch (métricas nativas del ALB, ECS y RDS; sin agentes extra).
# Cada alarma responde una pregunta: ¿está caída?, ¿da errores?, ¿está lenta?, ¿la BD está saturada?

resource "aws_sns_topic" "alerts" {
  name              = "${local.name}-alerts"
  kms_master_key_id = aws_kms_key.main.arn # CMK: ver kms.tf
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email == null ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

locals {
  alarm_actions = [aws_sns_topic.alerts.arn]
  alb_dimension = aws_lb.main.arn_suffix
}

# ¿Aplicación caída? Tareas del backend que no pasan el health check del ALB
resource "aws_cloudwatch_metric_alarm" "backend_unhealthy" {
  alarm_name          = "${local.name}-backend-unhealthy-hosts"
  alarm_description   = "Hay tareas del backend fallando el health check (readiness). Ver RUNBOOK: aplicacion-caida"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  dimensions = {
    LoadBalancer = local.alb_dimension
    TargetGroup  = aws_lb_target_group.backend.arn_suffix
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
}

# ¿Errores HTTP? SLI de disponibilidad: % de respuestas 5xx del backend (SLO 99.5 %)
resource "aws_cloudwatch_metric_alarm" "api_5xx_rate" {
  alarm_name          = "${local.name}-api-5xx-rate"
  alarm_description   = "Más del 5 % de respuestas 5xx en la API durante 5 minutos (consumo rápido del presupuesto de error)"
  evaluation_periods  = 5
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  metric_query {
    id          = "error_rate"
    expression  = "100 * errors / MAX([requests, 1])"
    label       = "Porcentaje de 5xx"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 60
      stat        = "Sum"
      dimensions = {
        LoadBalancer = local.alb_dimension
        TargetGroup  = aws_lb_target_group.backend.arn_suffix
      }
    }
  }

  metric_query {
    id = "requests"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      period      = 60
      stat        = "Sum"
      dimensions = {
        LoadBalancer = local.alb_dimension
        TargetGroup  = aws_lb_target_group.backend.arn_suffix
      }
    }
  }
}

# ¿Está lenta? Latencia p95 del backend
resource "aws_cloudwatch_metric_alarm" "api_latency_p95" {
  alarm_name          = "${local.name}-api-latency-p95"
  alarm_description   = "Latencia p95 de la API superior a 500 ms durante 10 minutos"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 10
  threshold           = 0.5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    LoadBalancer = local.alb_dimension
    TargetGroup  = aws_lb_target_group.backend.arn_suffix
  }
  alarm_actions = local.alarm_actions
}

# ¿Crecimiento anormal de conexiones? (escenario del incidente simulado)
# Umbral = tareas x pool x 2 (durante un despliegue rolling conviven tareas viejas y nuevas: 200 %)
#          + 10 % de margen. Si se supera, hay fuga de conexiones o réplicas de más.
resource "aws_cloudwatch_metric_alarm" "db_connections" {
  alarm_name          = "${local.name}-db-connections-high"
  alarm_description   = "Conexiones a PostgreSQL por encima de lo esperado (tareas x DB_POOL_SIZE). Ver RUNBOOK: incidente"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = ceil(var.backend.desired_count * var.db_pool_size * 2.2)
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.main.identifier }
  alarm_actions       = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "db_cpu" {
  alarm_name          = "${local.name}-db-cpu-high"
  alarm_description   = "CPU de RDS > 80 % durante 10 minutos"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 10
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.main.identifier }
  alarm_actions       = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "db_storage" {
  alarm_name          = "${local.name}-db-free-storage-low"
  alarm_description   = "Menos de 2 GB libres en RDS"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 2147483648
  comparison_operator = "LessThanThreshold"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.main.identifier }
  alarm_actions       = local.alarm_actions
}

# Errores de aplicación en logs (líneas con nivel ERROR en el JSON del backend)
resource "aws_cloudwatch_log_metric_filter" "backend_errors" {
  name           = "${local.name}-backend-errors"
  log_group_name = aws_cloudwatch_log_group.app["backend"].name
  pattern        = "ERROR"

  metric_transformation {
    name          = "BackendErrorLogs"
    namespace     = "Parking/${var.environment}"
    value         = "1"
    default_value = "0"
  }
}
