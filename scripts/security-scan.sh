#!/usr/bin/env bash
# Escaneo de seguridad local con Trivy (misma configuración que el pipeline: trivy.yaml).
# Usa el binario "trivy" si está instalado; si no, la imagen oficial de Docker.
#
#   ./scripts/security-scan.sh          # repo: dependencias, secretos y misconfig (Dockerfile, Terraform)
#   ./scripts/security-scan.sh images   # además, imágenes locales del stack
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
trivy_version="0.74.0"
image_tag="${IMAGE_TAG:-dev}"
registry="${IMAGE_REGISTRY:-local}"

trivy() {
  if command -v trivy >/dev/null 2>&1; then
    command trivy "$@"
  else
    docker run --rm \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v "$PWD:/src" -w /src \
      -v "${HOME}/.cache/trivy:/root/.cache/trivy" \
      "aquasec/trivy:${trivy_version}" "$@"
  fi
}

echo "==> Repositorio: vulnerabilidades, secretos y misconfiguración"
trivy fs --config trivy.yaml --scanners vuln,secret,misconfig .

if [[ "${1:-}" == "images" ]]; then
  for service in backend frontend; do
    echo "==> Imagen ${registry}/parking-${service}:${image_tag}"
    trivy image --config trivy.yaml "${registry}/parking-${service}:${image_tag}"
  done
fi

echo "ESCANEO CORRECTO: sin vulnerabilidades HIGH/CRITICAL con parche disponible."
