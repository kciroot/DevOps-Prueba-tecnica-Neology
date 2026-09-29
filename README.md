# Parking — prueba técnica DevOps

Aplicación de estacionamiento (Angular 18 + Spring Boot 3 + PostgreSQL) preparada para ejecutarse de forma **segura, reproducible y observable**, desde una laptop hasta AWS.

> La lógica de negocio es la aplicación base (tag `app-base-v1.0.0`). Esta rama agrega contenedores endurecidos, CI/CD con quality gates, infraestructura como código, seguridad, observabilidad y recuperación.

| Documento | Contenido |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Arquitectura, decisiones técnicas (A/B), CI/CD, versionado, branching |
| [docs/SECURITY.md](docs/SECURITY.md) | Controles, checklist, riesgos detectados y pendientes |
| [docs/OPERATIONS.md](docs/OPERATIONS.md) | Observabilidad, SLI/SLO, alertas, backup/restore, rollback, runbook del incidente |
| [docs/VALIDATION.md](docs/VALIDATION.md) | Evidencia de las validaciones ejecutadas y pendientes |

---

## 1. Arquitectura en una imagen

```text
                 LOCAL (Docker Compose)                          AWS (Terraform)
 Navegador ──:4200──► frontend (nginx, UID 101)          Internet ──► ALB (HTTPS)
                         │  /neo/*  (red "edge")                       ├─ /neo/* ─► ECS Fargate backend  ─┐
                         ▼                                             └─ /*     ─► ECS Fargate frontend  │
                      backend (Spring Boot, UID 10001)                                                   ▼
                         │  :8080 API · :8081 Actuator (interno)                         RDS PostgreSQL (subred sin internet)
                         ▼  (red "data", sin internet)                Secrets Manager · CloudWatch (logs, métricas, alarmas → SNS)
                      database (PostgreSQL 16, sin puertos al host)
```

Solo el frontend es público. El backend, Actuator y PostgreSQL quedan en redes internas.

## 2. Requisitos

| Para | Necesitas |
|---|---|
| Levantar el stack | Docker Desktop o Docker Engine con Compose v2, `make`, `openssl`, `curl` |
| Desarrollo sin Docker (opcional) | Java 17+, Maven 3.9+, Node.js 22 LTS |
| Terraform (opcional) | Terraform ≥ 1.11 |

Puerto libre en el host: `4200`.

## 3. Inicio rápido (3 comandos)

```bash
make env        # crea .env con un password aleatorio (no se versiona)
make up         # construye las imágenes y espera a que todo esté healthy
make ps         # los tres servicios deben aparecer como (healthy)
```

Abrir <http://localhost:4200>. Detener con `make down` (los datos se conservan en el volumen `pgdata`).

<details>
<summary>Lo mismo sin make</summary>

```bash
cp .env.example .env                       # y reemplazar POSTGRES_PASSWORD (openssl rand -hex 24)
docker compose up --build --detach --wait
docker compose ps
```
</details>

## 4. Comandos

| Comando | Qué hace |
|---|---|
| `make help` | Lista todos los comandos |
| `make test` | Tests del backend y build del frontend sin Docker (`scripts/verify.sh`) |
| `make validate` | Valida el stack completo en un proyecto aislado: health, controles de seguridad, métricas, smoke test y correlación nginx ↔ backend (`scripts/validate-stack.sh`) |
| `make scan` / `make scan-images` | Trivy sobre el repo / y sobre las imágenes locales |
| `make drills` | Simulacros: errores HTTP, BD caída, backend caído, estado de contenedores |
| `make backup` / `make restore-check` | Respaldo de PostgreSQL / prueba de restauración en una BD temporal |
| `make observability` | Prometheus en <http://localhost:9090> con las reglas de alerta |
| `make tf-check` | `terraform fmt`, `validate` y `test` (sin credenciales AWS) |
| `make tf-plan` | `terraform plan` real (requiere credenciales AWS; no aplica nada) |

### Verificación de la guía de evaluación

```bash
./scripts/verify.sh
docker compose config
docker compose build --no-cache
docker compose up --detach          # termina cuando el backend ya está healthy
docker compose ps
./scripts/smoke-test.sh             # usa http://localhost:4200 (todo pasa por nginx)
docker compose logs --tail=150 backend frontend database
docker compose down
```

El health check del backend ya no se publica en `localhost:8080`. Está en el puerto de gestión interno:

```bash
docker compose exec backend curl -s http://127.0.0.1:8081/actuator/health
```

## 5. Estructura

```text
.
├── .github/
│   ├── workflows/pipeline.yml   CI → Security → Build → Release → Deploy
│   ├── dependabot.yml           actualización semanal de dependencias
│   └── pull_request_template.md
├── backend/                     Spring Boot 3.5 + Java 17 (Dockerfile, .dockerignore)
├── frontend/                    Angular 18 + nginx (Dockerfile, nginx/)
├── infra/terraform/             AWS: VPC, ALB, ECS Fargate, RDS, alarmas, OIDC
│   ├── modules/ecs-service/     módulo reutilizado por frontend y backend
│   ├── environments/            dev.tfvars, production.tfvars
│   └── tests/                   terraform test con provider simulado
├── observability/prometheus/    scrape, reglas de alerta y sus pruebas
├── scripts/                     verify, validate-stack, smoke-test, drills, backup/restore, scan
├── docs/                        arquitectura, seguridad, operación, validación
├── docker-compose.yml
├── .env.example                 plantilla sin secretos
├── trivy.yaml                   configuración única de Trivy (local y CI)
└── Makefile
```

## 6. Configuración por ambiente

| Dónde | Qué | Cómo se inyecta |
|---|---|---|
| Local | `.env` (fuera de Git) a partir de `.env.example` | Docker Compose → variables de entorno |
| CI | Password efímero generado en el runner | Nunca se imprime ni se guarda |
| AWS | `environments/<env>.tfvars` (no sensible) + Secrets Manager (password) | ECS: `environment` y `secrets` en la task definition |

Variables principales del backend: `SPRING_PROFILES_ACTIVE`, `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, `DB_POOL_SIZE`, `LOG_LEVEL`, `APP_ENV`, `APP_VERSION`.

## 7. CI/CD en resumen

```text
push/PR ─► CI (backend · frontend · terraform) + Security (Trivy) ─► Build (imágenes, Trivy, E2E) ─► Release (GHCR) ─► Deploy (AWS)
```

- Cualquier fallo detiene lo que sigue: **no se publica ni se despliega nada sin pasar los quality gates**.
- La imagen publicada es **la misma** que pasó Trivy y el E2E (release no reconstruye).
- Tags: `sha-<commit>` (inmutable, el que se despliega), `X.Y.Z` en releases y `main`.
- Deploy: `main` → dev automático; tag `vX.Y.Z` → production con aprobación. Queda apagado hasta definir `DEPLOY_ENABLED=true`.

Detalle y configuración de GitHub (branch protection, environments, variables): [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#cicd).

## 8. Terraform (AWS)

```bash
cd infra/terraform
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
terraform test                       # plan con AWS simulado: verifica controles de seguridad
```

`terraform plan` real necesita credenciales AWS y un backend. Sin bucket S3: `make tf-plan` (state local, no aplica). Con bucket, por ambiente:

```bash
terraform init -backend-config=environments/backend-dev.hcl      # copia de backend.hcl.example
terraform plan -var-file=environments/dev.tfvars \
  -var image_repository=ghcr.io/<owner>/<repo> -var image_tag=sha-<commit>
```

No es necesario aplicar la infraestructura para evaluar la prueba.

## 9. Desarrollo sin Docker (H2 en memoria)

```bash
cd backend && mvn spring-boot:run          # API :8080, Actuator :8081, consola H2 /h2-console
cd frontend && npm ci && npm start         # http://localhost:4200 (proxy /neo -> :8080)
./scripts/verify-local-stack.sh            # levanta ambos, ejecuta el smoke test y los detiene
```

## 10. API

| Método | Ruta | Objetivo |
|---|---|---|
| `GET` | `/neo/vehiculos` | Listar vehículos |
| `GET` | `/neo/vehiculos/{placa}` | Consultar vehículo y estancias |
| `POST` | `/neo/vehiculos/oficiales` · `/residentes` · `/no-residentes` | Alta de vehículo |
| `POST` | `/neo/estancias/entrada` · `/salida` | Registrar entrada / salida y cobro |
| `GET` | `/neo/residentes/pagos` | Reporte de residentes |
| `POST` | `/neo/mes/iniciar` | Reiniciar el mes |
| `GET` | `:8081/actuator/health` · `/health/liveness` · `/health/readiness` · `/prometheus` | Operación (solo red interna) |

Reglas de negocio (sin cambios): residentes `$0.05`/min acumulado, no residentes `$0.50`/min al salir, oficiales sin cobro; cada minuto iniciado cuenta completo.

## 11. Flujo de trabajo Git

`main` protegido · ramas `feature/*` · Pull Request con el pipeline obligatorio en verde · squash merge · tags `vX.Y.Z` para releases. La entrega de la prueba está en la rama `candidato/ricardo-palacios`.
