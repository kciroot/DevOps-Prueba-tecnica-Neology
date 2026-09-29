#!/usr/bin/env bash
# Simulacros de falla: demuestra CÓMO se detecta cada problema con las señales disponibles.
# Requiere el stack levantado:  docker compose up -d --wait
#
#   ./scripts/failure-drills.sh            # ejecuta todos los simulacros
#   ./scripts/failure-drills.sh http|db|app|container
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
base_url="http://localhost:${FRONTEND_PORT:-4200}"

title() { printf '\n==================== %s ====================\n' "$*"; }
health() { docker compose exec -T backend curl -s -w ' [HTTP %{http_code}]' http://127.0.0.1:8081/actuator/health || true; echo; }
code()   { curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$@" || true; }

drill_http() {
  title "1) Errores HTTP"
  echo "Petición inválida (placa con símbolos) -> $(code -X POST "$base_url/neo/vehiculos/residentes" \
    -H 'Content-Type: application/json' -d '{"placa":"$$$"}')"
  echo "Vehículo inexistente                   -> $(code "$base_url/neo/vehiculos/NOEXISTE")"
  echo
  echo "Señal 1 - log JSON de nginx (status por petición):"
  docker compose logs --no-log-prefix --tail=3 frontend | grep '"status"' || true
  echo
  echo "Señal 2 - métrica http_server_requests_seconds_count por status:"
  docker compose exec -T backend curl -s http://127.0.0.1:8081/actuator/prometheus \
    | grep '^http_server_requests_seconds_count' | grep -E 'status="(4|5)' || true
  echo "Alerta asociada: HighErrorRate (observability/prometheus/alerts.yml)"
}

drill_db() {
  title "2) Base de datos caída"
  docker compose stop database
  echo "Health del backend (espera 503 y db DOWN):"
  health
  echo "API durante la caída -> HTTP $(code "$base_url/neo/vehiculos")  (falla en ~5 s por connection-timeout)"
  echo "Estado de contenedores:"
  docker compose ps database backend
  echo
  echo "Recuperación: docker compose start database"
  docker compose start database
  docker compose up --detach --wait database backend >/dev/null
  sleep 3
  echo "Health después de recuperar:"
  health
  echo "Alertas asociadas: DatabaseConnectionFailures, HighErrorRate"
}

drill_app() {
  title "3) Aplicación (backend) caída"
  docker compose stop backend
  echo "El frontend sigue sano: /healthz -> $(code "$base_url/healthz")"
  echo "Pero la API responde                -> $(code "$base_url/neo/vehiculos")  (502/504 = backend inaccesible)"
  docker compose ps backend
  echo
  echo "Recuperación: docker compose up -d --wait backend"
  docker compose up --detach --wait backend >/dev/null
  echo "API después de recuperar -> $(code "$base_url/neo/vehiculos")"
  echo "Alerta asociada: BackendDown (up == 0) · en AWS: UnHealthyHostCount del ALB"
}

drill_container() {
  title "4) Problemas de contenedor"
  echo "Estado de salud, reinicios y OOM por contenedor:"
  for id in $(docker compose ps -q); do
    docker inspect --format '{{.Name}}  health={{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}  restarts={{.RestartCount}}  oom_killed={{.State.OOMKilled}}  exit={{.State.ExitCode}}' "$id"
  done
  echo
  echo "Consumo de recursos (límites definidos en docker-compose.yml):"
  docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'
  echo
  echo "Últimos resultados del HEALTHCHECK del backend:"
  docker inspect --format '{{range .State.Health.Log}}{{.End}} exit={{.ExitCode}}{{"\n"}}{{end}}' \
    "$(docker compose ps -q backend)" | tail -3
}

case "${1:-all}" in
  http) drill_http ;;
  db) drill_db ;;
  app) drill_app ;;
  container) drill_container ;;
  all) drill_http; drill_db; drill_app; drill_container ;;
  *) echo "uso: $0 [http|db|app|container|all]" >&2; exit 2 ;;
esac
