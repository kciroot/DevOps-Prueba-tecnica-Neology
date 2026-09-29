#!/usr/bin/env bash
# Respaldo lógico de PostgreSQL (pg_dump, formato custom comprimido) desde el contenedor.
# Las credenciales se toman del propio contenedor: no se pasan por la línea de comandos.
#
#   ./scripts/backup-db.sh                 # genera backups/parking-AAAAMMDD-HHMMSS.dump
#   RETENTION=14 ./scripts/backup-db.sh    # conserva los últimos 14 respaldos (por defecto 7)
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
backup_dir="${BACKUP_DIR:-backups}"
retention="${RETENTION:-7}"
file="$backup_dir/parking-$(date -u +%Y%m%d-%H%M%S).dump"

mkdir -p "$backup_dir"
chmod 700 "$backup_dir"      # los respaldos contienen datos de negocio

echo "Generando respaldo en $file ..."
docker compose exec -T database sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner' > "$file"

# Verificación mínima: el archivo no está vacío y pg_restore puede leer su índice
[[ -s "$file" ]] || { echo "ERROR: respaldo vacío" >&2; rm -f "$file"; exit 1; }
docker compose exec -T database pg_restore --list < "$file" >/dev/null
sha256sum "$file" > "$file.sha256" 2>/dev/null || shasum -a 256 "$file" > "$file.sha256"

echo "Respaldo correcto: $file ($(du -h "$file" | cut -f1))"

# Retención: elimina los respaldos más antiguos (nombres generados por este script)
# shellcheck disable=SC2012
ls -1t "$backup_dir"/parking-*.dump 2>/dev/null | tail -n +"$((retention + 1))" | while read -r old; do
  rm -f "$old" "$old.sha256"
  echo "Eliminado por retención: $old"
done
