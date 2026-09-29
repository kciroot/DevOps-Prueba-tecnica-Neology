#!/usr/bin/env bash
# Valida el stack de Docker Compose de punta a punta. Lo usan tanto el pipeline como una persona.
#
#   ./scripts/validate-stack.sh             # construye las imágenes y valida
#   ./scripts/validate-stack.sh --no-build  # usa imágenes ya construidas (CI)
#   KEEP_RUNNING=1 ./scripts/validate-stack.sh   # no apaga el stack al terminar
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

build_flag="--build"
[[ "${1:-}" == "--no-build" ]] && build_flag="--no-build"
frontend_port="${FRONTEND_PORT:-4200}"
base_url="http://localhost:${frontend_port}"

step() { printf '\n==> %s\n' "$*"; }
fail() { echo "ERROR: $*" >&2; exit 1; }

cleanup() {
  local status=$?
  if [[ $status -ne 0 ]]; then
    echo "---- Estado y logs para diagnóstico ----" >&2
    docker compose ps >&2 || true
    docker compose logs --tail=80 >&2 || true
  fi
  if [[ "${KEEP_RUNNING:-0}" != "1" ]]; then
    docker compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

[[ -f .env ]] || fail "falta .env (cp .env.example .env y definir POSTGRES_PASSWORD)"

step "1. Configuración de Compose válida"
docker compose config --quiet

step "2. Levantar el stack y esperar a que todos los servicios estén healthy"
docker compose up --detach $build_flag --wait --wait-timeout 180
docker compose ps

step "3. Health de Actuator (puerto de gestión interno 8081)"
health="$(docker compose exec -T backend curl -fsS http://127.0.0.1:8081/actuator/health)"
echo "    $health"
grep -q '"status":"UP"' <<<"$health" || fail "backend no está UP"
readiness="$(docker compose exec -T backend curl -fsS http://127.0.0.1:8081/actuator/health/readiness)"
grep -q '"status":"UP"' <<<"$readiness" || fail "backend no está listo (readiness)"

step "4. Controles de seguridad del runtime"
backend_uid="$(docker compose exec -T backend id -u)"
frontend_uid="$(docker compose exec -T frontend id -u)"
echo "    UID backend=$backend_uid frontend=$frontend_uid"
[[ "$backend_uid" != "0" && "$frontend_uid" != "0" ]] || fail "un contenedor corre como root"

if docker compose port database 5432 >/dev/null 2>&1; then
  fail "PostgreSQL está publicado en el host"
fi
echo "    PostgreSQL no está publicado en el host"

if docker compose port backend 8080 >/dev/null 2>&1; then
  fail "el backend está publicado en el host"
fi
echo "    Backend no está publicado en el host"

actuator_status="$(curl -s -o /dev/null -w '%{http_code}' "$base_url/actuator/health")"
[[ "$actuator_status" != "200" ]] || fail "Actuator es accesible desde el frontend público"
echo "    /actuator no es accesible públicamente (HTTP $actuator_status)"

if docker compose exec -T backend sh -c 'touch /app/probe' 2>/dev/null; then
  fail "el sistema de archivos del backend es escribible"
fi
echo "    Sistema de archivos de solo lectura"

step "5. Métricas Prometheus disponibles en el puerto de gestión"
metrics="$(docker compose exec -T backend curl -fsS http://127.0.0.1:8081/actuator/prometheus)"
grep -q '^hikaricp_connections_max' <<<"$metrics" || fail "no hay métricas del pool de conexiones"
echo "    OK (hikaricp_*, http_server_requests_*, jvm_*)"

step "6. Prueba funcional (smoke test) a través del frontend"
BASE_URL="$base_url" "$project_dir/scripts/smoke-test.sh"

step "7. Correlación frontend -> backend por X-Request-ID"
request_id="$(curl -fsS -D - -o /dev/null "$base_url/neo/vehiculos" \
  | tr -d '\r' | awk -F': ' '!found && tolower($1)=="x-request-id"{print $2; found=1}')"
sleep 1
frontend_logs="$(docker compose logs --no-log-prefix frontend)"
backend_logs="$(docker compose logs --no-log-prefix backend)"
grep -q "$request_id" <<<"$frontend_logs" || fail "request_id $request_id no aparece en logs de nginx"
grep -q "$request_id" <<<"$backend_logs" || fail "request_id $request_id no aparece en logs del backend"
echo "    request_id=$request_id presente en nginx y en backend"
grep -F "$request_id" <<<"$backend_logs" | tail -1

printf '\nVALIDACIÓN DEL STACK CORRECTA\n'
