#!/usr/bin/env bash
# Prueba funcional de punta a punta, igual que un usuario: todo pasa por el frontend (nginx).
#
#   BASE_URL    URL pública del stack           (por defecto http://localhost:4200)
#   HEALTH_URL  opcional: URL de Actuator health (p. ej. http://localhost:8081/actuator/health)
set -euo pipefail

base_url="${BASE_URL:-http://localhost:4200}"
health_url="${HEALTH_URL:-}"
plate="SMK-$(date +%H%M%S)"

fail() { echo "ERROR: $*" >&2; exit 1; }

post_json() {
  curl --fail --silent --show-error --max-time 10 \
    -X POST "$base_url$1" -H 'Content-Type: application/json' --data "$2"
}

echo "[1/7] Frontend sirve la SPA..."
index_html="$(curl --fail --silent --show-error --max-time 10 "$base_url/")"
grep -q '<app-root' <<<"$index_html" || fail "el frontend no devolvió index.html"

if [[ -n "$health_url" ]]; then
  echo "[2/7] Health del backend ($health_url)..."
  health="$(curl --fail --silent --show-error --max-time 5 "$health_url")"
  grep -q '"status":"UP"' <<<"$health" || fail "el backend no reporta UP: $health"
else
  echo "[2/7] Health del backend: omitido (Actuator no se expone públicamente)"
fi

echo "[3/7] API accesible vía proxy y con X-Request-ID..."
headers="$(curl --fail --silent --show-error --max-time 10 -D - -o /dev/null "$base_url/neo/vehiculos")"
request_id="$(printf '%s' "$headers" | tr -d '\r' | awk -F': ' '!found && tolower($1)=="x-request-id"{print $2; found=1}')"
[[ -n "$request_id" ]] || fail "la respuesta no incluye X-Request-ID"
echo "      X-Request-ID=$request_id"

echo "[4/7] Alta de residente $plate..."
post_json "/neo/vehiculos/residentes" "{\"placa\":\"$plate\"}" >/dev/null

echo "[5/7] Registro de entrada..."
post_json "/neo/estancias/entrada" "{\"placa\":\"$plate\"}" >/dev/null

echo "[6/7] Registro de salida..."
post_json "/neo/estancias/salida" "{\"placa\":\"$plate\"}" >/dev/null

echo "[7/7] La placa aparece en el reporte de residentes..."
report="$(curl --fail --silent --show-error --max-time 10 "$base_url/neo/residentes/pagos")"
grep -q "\"placa\":\"$plate\"" <<<"$report" || fail "la placa no aparece en el reporte"

echo "SMOKE TEST CORRECTO para la placa $plate."
