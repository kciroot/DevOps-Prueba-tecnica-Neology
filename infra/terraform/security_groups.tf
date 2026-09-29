# Segmentación por Security Groups (mínimo privilegio en red):
#   Internet --80/443--> ALB --8080--> frontend
#                        ALB --8080/8081--> backend --5432--> RDS
# Cada capa solo acepta tráfico de la capa anterior (referencia entre SGs, no por IP).

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "ALB publico: HTTP/HTTPS desde internet"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "frontend" {
  name        = "${local.name}-frontend"
  description = "Tareas frontend: solo desde el ALB"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "backend" {
  name        = "${local.name}-backend"
  description = "Tareas backend: solo desde el ALB"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "db" {
  name        = "${local.name}-db"
  description = "RDS PostgreSQL: solo desde el backend"
  vpc_id      = aws_vpc.main.id
}

# --- ALB ---
#trivy:ignore:AVD-AWS-0107 El ALB es el punto de entrada público de una aplicación web.
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP publico (redirige a HTTPS si hay certificado)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

#trivy:ignore:AVD-AWS-0107 El ALB es el punto de entrada público de una aplicación web.
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS publico"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "alb_to_frontend" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Hacia tareas frontend"
  referenced_security_group_id = aws_security_group.frontend.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

resource "aws_vpc_security_group_egress_rule" "alb_to_backend" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Hacia tareas backend (API 8080 y health 8081)"
  referenced_security_group_id = aws_security_group.backend.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8081
}

# --- Frontend ---
resource "aws_vpc_security_group_ingress_rule" "frontend_from_alb" {
  security_group_id            = aws_security_group.frontend.id
  description                  = "HTTP desde el ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

# --- Backend ---
resource "aws_vpc_security_group_ingress_rule" "backend_from_alb" {
  security_group_id            = aws_security_group.backend.id
  description                  = "API y health check desde el ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8081
}

resource "aws_vpc_security_group_egress_rule" "backend_to_db" {
  security_group_id            = aws_security_group.backend.id
  description                  = "PostgreSQL"
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# --- Salida HTTPS de las tareas (descargar imágenes de GHCR, Secrets Manager, CloudWatch) ---
# Riesgo aceptado y documentado: en un entorno empresarial se reemplaza por ECR + VPC endpoints.
#trivy:ignore:AVD-AWS-0104 Las tareas necesitan HTTPS saliente para GHCR y APIs de AWS vía NAT.
resource "aws_vpc_security_group_egress_rule" "frontend_https_out" {
  security_group_id = aws_security_group.frontend.id
  description       = "HTTPS saliente via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

#trivy:ignore:AVD-AWS-0104 Las tareas necesitan HTTPS saliente para GHCR y APIs de AWS vía NAT.
resource "aws_vpc_security_group_egress_rule" "backend_https_out" {
  security_group_id = aws_security_group.backend.id
  description       = "HTTPS saliente via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# --- Base de datos ---
resource "aws_vpc_security_group_ingress_rule" "db_from_backend" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL solo desde el backend"
  referenced_security_group_id = aws_security_group.backend.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
