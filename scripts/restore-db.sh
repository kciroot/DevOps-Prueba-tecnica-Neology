#!/usr/bin/env bash
# Restauración de PostgreSQL desde un respaldo de backup-db.sh.
#
#   ./scripts/restore-db.sh backups/parking-X.dump            # PRUEBA: restaura en una BD temporal
#                                                              # y compara conteos con la BD viva
#   ./scripts/restore-db.sh backups/parking-X.dump --in-place  # RECUPERACIÓN: reemplaza la BD viva
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
file="${1:?uso: $0 <archivo.dump> [--in-place]}"
mode="${2:-verify}"
check_db="parking_restore_check"

[[ -s "$file" ]] || { echo "ERROR: no existe o está vacío: $file" >&2; exit 1; }
if [[ -f "$file.sha256" ]]; then
  (sha256sum -c "$file.sha256" 2>/dev/null || shasum -a 256 -c "$file.sha256") >/dev/null \
    || { echo "ERROR: checksum inválido, el respaldo está corrupto" >&2; exit 1; }
  echo "Checksum verificado."
fi

# $POSTGRES_USER / $POSTGRES_DB se expanden DENTRO del contenedor (por eso van entre comillas simples)
# shellcheck disable=SC2016
psql_in_db() { docker compose exec -T database sh -c "psql -v ON_ERROR_STOP=1 -U \"\$POSTGRES_USER\" -d $1 -At -c \"$2\""; }
row_counts() {
  psql_in_db "$1" "SELECT 'vehicles=' || (SELECT count(*) FROM vehicles) || ' stays=' || (SELECT count(*) FROM parking_stays)"
}

if [[ "$mode" == "--in-place" ]]; then
  read -r -p "Esto REEMPLAZA los datos actuales de la BD. Escribe 'restaurar' para continuar: " answer
  [[ "$answer" == "restaurar" ]] || { echo "Cancelado."; exit 1; }
  start=$(date +%s)
  echo "1/4 Deteniendo backend (evita escrituras durante la restauración)..."
  docker compose stop backend
  echo "2/4 Restaurando..."
  docker compose exec -T database sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner --exit-on-error' < "$file"
  echo "3/4 Iniciando backend..."
  docker compose up --detach --wait backend
  # shellcheck disable=SC2016
  echo "4/4 Conteos tras restaurar: $(row_counts '"$POSTGRES_DB"')"
  echo "RESTAURACIÓN COMPLETA en $(( $(date +%s) - start )) s (dato para el RTO)."
  exit 0
fi

echo "1/3 Restaurando en BD temporal '$check_db'..."
psql_in_db postgres "DROP DATABASE IF EXISTS $check_db" >/dev/null
psql_in_db postgres "CREATE DATABASE $check_db" >/dev/null
docker compose exec -T database sh -c "pg_restore -U \"\$POSTGRES_USER\" -d $check_db --no-owner --exit-on-error" < "$file"

echo "2/3 Comparando conteos..."
restored="$(row_counts "$check_db")"
# shellcheck disable=SC2016
live="$(row_counts '"$POSTGRES_DB"')"
echo "    respaldo : $restored"
echo "    BD viva  : $live   (puede tener más filas si hubo actividad después del respaldo)"

echo "3/3 Eliminando BD temporal..."
psql_in_db postgres "DROP DATABASE $check_db" >/dev/null
echo "PRUEBA DE RESTAURACIÓN CORRECTA: el respaldo es legible y contiene datos."
