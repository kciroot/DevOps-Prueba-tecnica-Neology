# Seguridad

## 1. Controles implementados

| Capa | Control | Dónde |
|---|---|---|
| Código | Sin secretos en Git: `.gitignore` bloquea `.env`, llaves, tfstate; `.env.example` sin valores reales | `.gitignore`, `.env.example` |
| Código | Escaneo de secretos, dependencias y misconfiguración como quality gate | `trivy.yaml`, job `security` |
| Dependencias | Versiones exactas (`package-lock.json`, BOM de Spring Boot, providers de Terraform, imágenes base con parche) + Dependabot semanal | `.github/dependabot.yml` |
| Imágenes | Multi-stage (sin JDK/Node/código fuente en runtime), usuario sin privilegios con UID fijo, archivos de la app de solo lectura para el proceso | `*/Dockerfile` |
| Imágenes | Escaneo de la imagen final antes de publicar; se publica exactamente la imagen escaneada | job `build` / `release` |
| Contenedores | `read_only`, `cap_drop: ALL`, `no-new-privileges`, límites de CPU/memoria | `docker-compose.yml` |
| Red local | Solo el frontend publica puerto; red `data` interna sin salida a internet; PostgreSQL sin puertos | `docker-compose.yml` |
| Aplicación | Actuator en puerto de gestión 8081, nunca expuesto; nginx solo reenvía `/neo/*` | `application.yml`, `nginx/` |
| Aplicación | Fail fast: sin password por defecto (Compose y perfil `postgres`) | `docker-compose.yml`, `application-postgres.yml` |
| HTTP | CSP, `X-Frame-Options`, `nosniff`, `Referrer-Policy`, `Permissions-Policy`, `server_tokens off`; HSTS en el ALB | `nginx/security-headers.conf`, `alb.tf` |
| Logs | `X-Request-ID` validado (regex) antes de entrar al log → sin log injection | `RequestIdFilter.java` |
| CI/CD | Permisos mínimos por job, actions fijadas por SHA, `persist-credentials: false`, OIDC a AWS (sin llaves), deploy a producción con aprobación | `pipeline.yml` |
| AWS red | Subredes privadas para tareas; RDS sin ruta a internet; SGs encadenados por referencia; SG por defecto sin reglas | `network.tf`, `security_groups.tf` |
| AWS datos | RDS cifrado, `publicly_accessible = false`, `rds.force_ssl = 1`, backups + PITR, deletion protection y snapshot final en producción | `rds.tf` |
| AWS secretos | Password efímero escrito como write-only en RDS y Secrets Manager (no queda en el state); ECS lo inyecta en `secrets` (no en `environment`) | `rds.tf`, `ecs.tf` |
| AWS IAM | Rol de ejecución solo lee su secreto; rol de tarea sin permisos; rol de deploy solo registra task definitions, actualiza sus servicios y pasa sus roles | `ecs.tf`, `iam_github.tf` |

## 2. Checklist de seguridad

- [x] Ningún password, token ni llave en el repositorio (Trivy `secret` en cada push)
- [x] `.env` fuera de Git; `.env.example` sin secretos
- [x] Compose no arranca sin `POSTGRES_PASSWORD`
- [x] Contenedores de la app sin root (UID 10001 y 101), sin capabilities, FS de solo lectura
- [x] PostgreSQL sin exposición al host ni a internet
- [x] Actuator no accesible públicamente (verificado por `validate-stack.sh`)
- [x] Escaneo de dependencias, IaC e imágenes como quality gate
- [x] Credenciales de CI temporales (OIDC) y permisos mínimos
- [x] Secretos de AWS fuera del código y del state de Terraform
- [x] TLS hacia RDS y HTTPS con HSTS en producción

## 3. Riesgos detectados en la aplicación base y su tratamiento

| # | Riesgo | Impacto | Tratamiento |
|---|---|---|---|
| 1 | Password por defecto `parking_dev_password` en Compose y en el perfil `postgres` | Cualquiera con el repo conoce la credencial | Eliminado; Compose y la app fallan si falta |
| 2 | Backend y `/actuator` expuestos (puerto 8080 publicado y proxy `/actuator/` en nginx) | Superficie pública para endpoints operativos | Actuator en 8081 interno; backend sin puerto publicado |
| 3 | Sin `.gitignore` ni `.dockerignore` | `.env` al repo; `node_modules`/`target` en el build context | Agregados (allow-list en `.dockerignore`) |
| 4 | Spring Boot 3.3.5, Node 20 y nginx 1.27 fuera de soporte | CVEs sin parche | Boot 3.5.16, Node 22 LTS, nginx 1.30 stable |
| 5 | `curl` instalado con `apt-get` en runtime y UID no fijo | Más superficie; UID impredecible | Base que ya incluye `curl`; UID/GID 10001 |

Encontrados durante la auditoría de esta solución y corregidos: rotación automática del secreto de RDS que habría tumbado el backend cada 7 días; release que reconstruía (lo publicado ≠ lo escaneado); HSTS documentado pero no configurado.

Encontrados por el escaneo de imágenes en CI y corregidos: Tomcat, Jackson y pgjdbc con CVE con parche (3 CRITICAL, 2 HIGH); se fijan las versiones de parche en `pom.xml` sin cambiar de línea menor.

## 4. Riesgos pendientes (conscientemente fuera de alcance)

| Riesgo | Clasificación | Recomendación |
|---|---|---|
| La app usa el usuario master de PostgreSQL | Importante | Usuario de aplicación con permisos DML y `CONNECTION LIMIT`, creado en el aprovisionamiento |
| `ddl-auto: update` sin migraciones versionadas | Importante | Flyway: esquema versionado y rollback predecible |
| Spring Boot 3.x sin soporte OSS | Importante | Migrar a Spring Boot 4.x (cambio de aplicación) |
| Angular 18 fuera de soporte: 12 CVE HIGH (15 hallazgos) sin parche en la línea 18.x, aceptados temporalmente en `.trivyignore` tras revisar la exposición (sin SSR, sin i18n, sin innerHTML, formatos fijos, URLs relativas); caducan el 2026-12-31 | Importante | Migrar a Angular 20.3.27 o posterior (cambio de aplicación) |
| Solo lectura del FS en Fargate | Mejora | Declarar `VOLUME /tmp` en las imágenes y validar en Fargate |
| Imágenes desde GHCR vía NAT | Mejora | ECR + VPC endpoints (sin salida a internet) + escaneo de ECR |
| Sin firma de imágenes ni SBOM publicado | Mejora | cosign + SBOM (CycloneDX) adjunto a la imagen |
| Sin WAF, logs de acceso del ALB ni VPC Flow Logs | Mejora | Activarlos en producción |
| Rotación del password requiere reiniciar tareas | Mejora | AWS Advanced JDBC Wrapper con plugin de Secrets Manager |
| CSP no validada en navegador | Mejora | Revisar la consola del navegador tras el primer despliegue |
| Imagen base Ubuntu (~270 MB) | Mejora | distroless / jlink |

## 5. Rotar un secreto sin reconstruir nada

- **Local:** cambiar `POSTGRES_PASSWORD` en `.env` y actualizarlo en la BD (`ALTER USER parking PASSWORD '...'`); luego `docker compose up -d backend`.
- **AWS:** subir `db_password_version` en el `tfvars` → `terraform apply` (escribe el nuevo password en RDS y en Secrets Manager) → `aws ecs update-service --cluster <c> --service <backend> --force-new-deployment`. Las tareas nuevas leen el secreto nuevo; no se reconstruye ninguna imagen.
