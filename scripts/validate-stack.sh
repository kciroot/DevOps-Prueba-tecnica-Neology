#!/usr/bin/env bash
# Valida el stack de Docker Compose de punta a punta. Lo usan tanto el pipeline como una persona.
#
#   ./scripts/validate-stack.sh             # construye las imágenes y valida
#   ./scripts/validate-stack.sh --no-build  # usa imágenes ya construidas (CI)
#   KEEP_RUNNING=1 ./scripts/validate-stack.sh   # no apaga el stack al terminar
#   FRONTEND_PORT=4280 ./scripts/validate-stack.sh  # si tu stack de trabajo ya usa el 4200
#
# Usa un proyecto de Compose propio (parking-validate): sus contenedores y su volumen
# son independientes del stack de trabajo, así que al terminar se borran sin tocar tus datos.
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
export COMPOSE_PROJECT_NAME="parking-validate"

build_flag="--build"
[[ "${1:-}" == "--no-build" ]] && build_flag="--no-build"

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
# Puerto real publicado (respeta FRONTEND_PORT de .env)
base_url="http://$(docker compose port frontend 8080 | sed 's/0.0.0.0/localhost/')"
echo "    Frontend en $base_url"

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

# `docker compose port` responde ":0" (exit 0) para puertos expuestos pero NO publicados:
# solo un puerto de host distinto de 0 significa que el servicio es accesible desde fuera.
published_port() { docker compose port "$1" "$2" 2>/dev/null | grep -E ':[1-9][0-9]*$' || true; }

[[ -z "$(published_port database 5432)" ]] || fail "PostgreSQL está publicado en el host"
echo "    PostgreSQL no está publicado en el host"

for port in 8080 8081; do
  [[ -z "$(published_port backend "$port")" ]] || fail "el backend ($port) está publicado en el host"
done
echo "    Backend (8080 y 8081) no está publicado en el host"

# nginx responde index.html (SPA) a rutas desconocidas: lo que importa es que NO llegue a Actuator
actuator_body="$(curl -s "$base_url/actuator/health")"
if grep -q '"status"' <<<"$actuator_body"; then
  fail "Actuator es accesible desde el frontend público"
fi
echo "    /actuator no es accesible públicamente (nginx no lo reenvía al backend)"

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
