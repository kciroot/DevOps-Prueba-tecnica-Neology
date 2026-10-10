# Operación: observabilidad, recuperación e incidentes

## 1. Señales disponibles

| Señal | Local | AWS |
|---|---|---|
| Salud | `HEALTHCHECK` de cada contenedor (`docker compose ps`); Actuator `:8081/actuator/health` (incluye `db`) | Health checks del ALB (`/healthz`, `/actuator/health/readiness`) y de ECS (liveness) |
| Métricas | `/actuator/prometheus` → Prometheus (perfil `observability`) | ALB, ECS (Container Insights), RDS en CloudWatch |
| Logs | JSON en stdout: nginx (acceso) y backend (formato ECS) | CloudWatch Logs `/ecs/parking-<env>/{backend,frontend}` |
| Correlación | `request_id` = `X-Request-ID` generado por nginx | `request_id` = `Root` de `X-Amzn-Trace-Id` generado por el ALB |
| Alertas | `observability/prometheus/alerts.yml` | `infra/terraform/monitoring.tf` → SNS |

**Liveness y readiness:** *liveness* responde "¿el proceso vive?"; si falla, se reinicia el contenedor. *Readiness* incluye la BD y responde "¿puede atender?"; si falla, el ALB deja de enviarle tráfico. Por eso una caída de PostgreSQL **no** provoca reinicios en cadena del backend.

### Correlacionar una petición del frontend con el backend
1. El navegador recibe `X-Request-ID` en cada respuesta de `/neo/*` (visible en DevTools → Network).
2. `docker compose logs frontend | grep <id>` muestra la línea de nginx: `status`, `upstream_status`, `request_time`.
3. `docker compose logs backend | grep <id>` muestra la línea del backend: método, ruta, estado, `duration_ms` y, si falló, el stack trace con el mismo `request_id`.

`scripts/validate-stack.sh` comprueba automáticamente que el mismo ID aparece en ambos logs.

## 2. SLI y SLO

| SLI | Definición | SLO (30 días) |
|---|---|---|
| Disponibilidad de la API | Peticiones `/neo/**` sin 5xx ÷ peticiones `/neo/**` | **99.5 %** (presupuesto de error: 0.5 % ≈ 3 h 36 min/mes) |
| Latencia de la API | Peticiones `/neo/**` con respuesta < 500 ms | 95 % |

En AWS el numerador de errores suma `HTTPCode_Target_5XX` (errores del backend) y `HTTPCode_ELB_5XX` (502/503/504 cuando el backend está caído o no responde).

### Consultas de ejemplo (PromQL)

```promql
# SLI de disponibilidad (regla de grabación, ventana 5 min)
sli:api_availability:ratio_rate5m

# Disponibilidad de los últimos 30 días
1 - sum(increase(http_server_requests_seconds_count{uri=~"/neo.*",status=~"5.."}[30d]))
  / sum(increase(http_server_requests_seconds_count{uri=~"/neo.*"}[30d]))

# Latencia p95
histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{uri=~"/neo.*"}[5m])))

# Errores por endpoint
sum by (uri, status) (rate(http_server_requests_seconds_count{status=~"5.."}[5m]))

# Pool de conexiones: activas, en espera y timeouts
hikaricp_connections_active
hikaricp_connections_pending
increase(hikaricp_connections_timeout_total[5m])
```

### Consulta de ejemplo (CloudWatch Logs Insights)
```text
fields @timestamp, request_id, message
| filter `log.level` = "ERROR"
| sort @timestamp desc
| limit 50
```

## 3. Alertas

| Alerta (Prometheus / CloudWatch) | Detecta | Severidad |
|---|---|---|
| `BackendDown` / `backend-unhealthy-hosts` | Backend caído | Crítica |
| — / `frontend-unhealthy-hosts` | Frontend caído (en local: `docker compose ps` → `unhealthy`) | Crítica |
| `HighErrorRate` / `api-5xx-rate` | > 5 % de 5xx durante 5 min (consumo rápido del presupuesto de error) | Crítica |
| `HighLatencyP95` / `api-latency-p95` | p95 > 500 ms durante 10 min | Advertencia |
| `DatabaseConnectionFailures` | El backend no obtiene conexiones (BD caída o pool agotado) | Crítica |
| `DbPoolSaturation` / `db-connections-high` | Pool > 90 % o conexiones en RDS > tareas × pool × 2.2 | Advertencia |
| — / `db-free-storage-low` | Menos de 2 GB libres en RDS | Advertencia |

Las reglas de Prometheus tienen pruebas unitarias (`promtool test rules alerts.test.yml`) que se ejecutan en el pipeline.

### Cómo se detecta cada falla (`make drills` lo demuestra en local)

| Falla | Qué se ve |
|---|---|
| Frontend caído | Contenedor `unhealthy`/`exited`; ALB `UnHealthyHostCount` del frontend |
| Backend caído | `/neo/*` responde 502 (`upstream_status` vacío en nginx); `BackendDown`; `docker compose ps` |
| Errores HTTP | `status` en el log de nginx; `http_server_requests_seconds_count{status="5xx"}`; `HighErrorRate` |
| Latencia | `request_time` (nginx) y `duration_ms` (backend); `HighLatencyP95` |
| PostgreSQL caído | `/actuator/health` → 503 con `"db":{"status":"DOWN"}`; readiness DOWN; peticiones fallan tras 5 s (`connection-timeout`); `DatabaseConnectionFailures` |
| Aumento de conexiones | `hikaricp_connections_active/pending`; `pg_stat_activity` por `application_name`; RDS `DatabaseConnections` |
| Problemas de contenedor | `docker inspect` → `health`, `RestartCount`, `OOMKilled`; `docker stats`; ECS *stopped reason* |

### Checklist de observabilidad
- [x] Health checks de liveness y readiness (incluye BD)
- [x] Logs estructurados JSON en nginx y backend
- [x] `request_id` de extremo a extremo
- [x] Métricas HTTP (conteo, estado, histograma de latencia), JVM y pool de conexiones
- [x] SLI/SLO definidos con consulta y regla de alerta
- [x] Alertas para caída, errores, latencia, BD y conexiones, con pruebas unitarias
- [x] `application_name` con versión en PostgreSQL para aislar conexiones por versión

## 4. Respaldo y recuperación

| | Local (Compose) | AWS (RDS) |
|---|---|---|
| Respaldo | `make backup` → `pg_dump -Fc` + checksum, retención de 7 | Backups automáticos diarios + logs de transacciones (PITR), retención 7/14 días |
| Prueba de restauración | `make restore-check`: restaura en una BD temporal y compara conteos | Restaurar a una instancia nueva y ejecutar el smoke test contra ella |
| **RPO** | Frecuencia del respaldo (p. ej. diario por cron → **24 h**) | **≈ 5 min**: RDS sube los logs de transacciones cada 5 minutos |
| **RTO** | **≈ 15 min**: restaurar un dump pequeño y reiniciar el backend (`restore-db.sh` imprime el tiempo real) | **≈ 1 h**: crear la instancia restaurada (~15–30 min), validarla y apuntar la app |

### Si PostgreSQL falla
1. Confirmar: alerta `DatabaseConnectionFailures`, health con `db: DOWN`, `docker compose ps database` o eventos de RDS.
2. **Si el proceso cayó pero los datos están bien:** `docker compose start database` (local). En RDS Multi-AZ el failover es automático (1–2 min); el backend se reconecta solo.
3. **Si hay corrupción o borrado de datos:**
   - Local: `./scripts/restore-db.sh backups/<archivo>.dump --in-place` (detiene el backend, restaura y lo levanta).
   - AWS: `aws rds restore-db-instance-to-point-in-time --source-db-instance-identifier parking-<env> --target-db-instance-identifier parking-<env>-restore --restore-time <UTC antes del daño>` → validar → renombrar la instancia original y darle su identificador a la restaurada (el endpoint se conserva) → `aws ecs update-service --force-new-deployment` → `terraform plan` para reconciliar.

### Si un despliegue rompe la aplicación (rollback de aplicación)
- **Automático:** el circuit breaker de ECS devuelve el servicio a la versión anterior si las tareas nuevas no pasan los health checks.
- **Manual (≈ 5 min):** en GitHub Actions, *Re-run* del job `deploy` del último run sano (despliega su `sha-<commit>`), o `terraform apply -var image_tag=sha-<anterior> -var-file=environments/<env>.tfvars`.
- **Local:** `IMAGE_REGISTRY=ghcr.io/<owner>/<repo> IMAGE_TAG=sha-<anterior> docker compose up -d --no-build`.
- Cuidado: `ddl-auto: update` solo agrega columnas y tablas; una versión anterior suele tolerarlas, pero no hay rollback de esquema (riesgo documentado: Flyway).

### Rollback de configuración
Toda la configuración no sensible está en Git (`.env.example`, `docker-compose.yml`, `environments/*.tfvars`): `git revert` del cambio → pipeline → mismo proceso de deploy. Los secretos se rotan como se describe en [SECURITY.md](SECURITY.md#5-rotar-un-secreto-sin-reconstruir-nada).

## 5. Runbook del incidente simulado

> Después de un despliegue, el frontend responde, pero una parte de las solicitudes al backend devuelve error y la latencia aumenta. PostgreSQL reporta un crecimiento repentino de conexiones.

### Ruta de investigación
```text
Alerta ─► Métrica ─► Petición ─► Log ─► Backend ─► PostgreSQL ─► Causa ─► Contención ─► Recuperación
```

| Paso | Qué revisar | Cómo |
|---|---|---|
| 1. Alerta | `HighErrorRate`, `HighLatencyP95`, `DbPoolSaturation` / `db-connections-high` | Prometheus *Alerts* / CloudWatch + SNS |
| 2. Métricas | ¿Qué endpoints fallan y desde cuándo? ¿Coincide con el deploy? | `sum by (uri,status)(rate(...{status=~"5.."}[5m]))`; `hikaricp_connections_active` en el máximo, `pending > 0`, `timeout_total` creciendo |
| 3. Petición | Tomar un `request_id` fallido | Log de nginx: `status` 500/502/504, `upstream_response_time` alto |
| 4. Log | Error del backend para ese `request_id` | `Connection is not available, request timed out after 5000ms` = pool agotado; `too many clients` = límite de PostgreSQL |
| 5. Backend | Versión y réplicas en ejecución | `service.version` en los logs; `aws ecs describe-services` (¿despliegue atascado con tareas viejas y nuevas?) |
| 6. PostgreSQL | ¿Quién tiene las conexiones? | Consultas de abajo |

```sql
-- Conexiones por aplicación/versión y estado
SELECT application_name, state, count(*) FROM pg_stat_activity
WHERE datname = 'parking' GROUP BY 1, 2 ORDER BY 3 DESC;

-- Transacciones abiertas que retienen conexiones
SELECT pid, application_name, now() - state_change AS duracion, left(query, 80)
FROM pg_stat_activity WHERE state = 'idle in transaction' ORDER BY duracion DESC;

SHOW max_connections;
```
Local: `docker compose exec database psql -U parking -d parking -c "<consulta>"`.

### Hipótesis (de más a menos probable tras un deploy)
1. **La nueva versión no devuelve conexiones al pool** (fuga, transacción sin cerrar): muchas `idle in transaction` con `application_name` de la versión nueva.
2. **Cambio de configuración**: `DB_POOL_SIZE` o réplicas aumentados → conexiones = réplicas × pool > `max_connections`.
3. **Despliegue rolling atascado**: tareas viejas y nuevas conviven (hasta 200 %) y duplican conexiones.
4. **Consulta lenta o bloqueos**: cada petición retiene su conexión más tiempo → pool saturado → latencia. Revisar `log_min_duration_statement` (RDS) y `pg_locks`.
5. **Tormenta de reintentos** de clientes que amplifica la carga.

### Contención (primero reducir el impacto, después entender)
1. Si coincide con el deploy: **rollback** al `sha-` anterior (sección 4). Es la acción más segura y rápida.
2. Si no hay deploy que revertir: bajar `DB_POOL_SIZE` o el número de réplicas para quedar bajo `max_connections`.
3. Si hay sesiones colgadas: `SELECT pg_terminate_backend(pid)` sobre las `idle in transaction` de más de 5 minutos.
4. No reiniciar PostgreSQL como primera acción: corta todas las conexiones sanas y no corrige la causa.

### Recuperación y verificación
- Error rate y p95 vuelven al SLO; `hikaricp_connections_pending = 0`; conexiones en RDS en su nivel normal.
- `./scripts/smoke-test.sh` contra el ambiente.

### Comunicación
- Al detectar: *"Degradación en la API de estacionamiento desde HH:MM. Parte de las operaciones falla. Investigando. Próxima actualización en 30 min."*
- Al contener: qué se hizo (p. ej. rollback a `sha-abc1234`) y el estado actual.
- Al cerrar: duración, impacto (presupuesto de error consumido) y enlace al postmortem.
- Roles: un responsable del incidente (decide) y uno de comunicación; registrar la línea de tiempo de decisiones.

### Acciones preventivas
- `idle_in_transaction_session_timeout` en PostgreSQL y `leakDetectionThreshold` en Hikari.
- Usuario de aplicación con `CONNECTION LIMIT`.
- Dimensionar el pool: réplicas × `DB_POOL_SIZE` × 2 (margen del rolling) < `max_connections`.
- Prueba de carga en el pipeline antes de producción y despliegue canario.
- Mantener la alerta `DbPoolSaturation` como señal temprana.
