# syntax=docker/dockerfile:1

# =============================================================================
# Etapa 1 — build: compila Angular con Node 22 LTS
# =============================================================================
FROM node:22.23.3-alpine3.24 AS build
WORKDIR /app

# 1) Dependencias exactas desde package-lock.json (capa reutilizable mientras no cambie)
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

# 2) Código y build de producción (budgets de tamaño definidos en angular.json)
COPY angular.json tsconfig*.json ./
COPY src ./src
RUN npm run build

# =============================================================================
# Etapa 2 — runtime: nginx sin privilegios (UID 101), variante "slim"
# Solo contiene los estáticos compilados: sin Node, sin node_modules, sin código fuente.
# =============================================================================
FROM nginxinc/nginx-unprivileged:1.30.5-alpine-slim AS runtime

LABEL org.opencontainers.image.title="parking-frontend" \
      org.opencontainers.image.description="SPA Angular servida por nginx" \
      org.opencontainers.image.source="https://github.com/vmirandaNeo/DevOps-Prueba-tecnica-Neology"

# Configuración por variables de entorno (se sustituyen al iniciar el contenedor)
ENV BACKEND_URL=http://backend:8080 \
    NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1

COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY nginx/security-headers.conf /etc/nginx/snippets/security-headers.conf
# Estáticos propiedad de root: nginx (UID 101) puede leerlos, pero no modificarlos
COPY --from=build /app/dist/parking-frontend/browser /usr/share/nginx/html

USER 101
EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD wget --quiet --spider http://127.0.0.1:8080/healthz || exit 1

# nginx maneja SIGQUIT para un apagado ordenado (la imagen base ya lo define)
