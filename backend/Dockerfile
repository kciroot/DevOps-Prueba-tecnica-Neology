# syntax=docker/dockerfile:1

# =============================================================================
# Etapa 1 — build: compila el JAR con Maven + JDK 17
# Imagen Ubuntu "noble" (multi-arquitectura: funciona igual en CI amd64 y Mac arm64)
# =============================================================================
FROM maven:3.9.16-eclipse-temurin-17-noble AS build
WORKDIR /workspace

# 1) Solo pom.xml: la capa de dependencias se reutiliza mientras el pom no cambie
COPY pom.xml ./
RUN mvn --batch-mode --no-transfer-progress dependency:go-offline

# 2) Código fuente. Los tests se ejecutan en el pipeline (job "backend"), no aquí.
COPY src ./src
RUN mvn --batch-mode --no-transfer-progress package -DskipTests \
 && java -Djarmode=tools -jar target/parking-api-*.jar extract \
        --layers --launcher --destination /workspace/extracted

# =============================================================================
# Etapa 2 — runtime: solo JRE (sin Maven, sin JDK, sin código fuente)
# =============================================================================
FROM eclipse-temurin:17.0.20.1_1-jre-noble AS runtime

LABEL org.opencontainers.image.title="parking-api" \
      org.opencontainers.image.description="API Spring Boot del estacionamiento" \
      org.opencontainers.image.source="https://github.com/vmirandaNeo/DevOps-Prueba-tecnica-Neology"

# Parches de seguridad del SO publicados después de la imagen base (p. ej. OpenSSL),
# sin esperar a que se reconstruya el tag de Temurin. Solo actualiza lo ya instalado.
# Usuario sin privilegios con UID/GID fijos (predecible para volúmenes, ECS y Kubernetes)
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/* \
 && groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

# Capas ordenadas de menos a más cambiante: un cambio de código solo invalida la última.
# Los archivos quedan propiedad de root: el proceso (uid 10001) puede leerlos, pero no modificarlos.
COPY --from=build /workspace/extracted/dependencies/ ./
COPY --from=build /workspace/extracted/spring-boot-loader/ ./
COPY --from=build /workspace/extracted/snapshot-dependencies/ ./
COPY --from=build /workspace/extracted/application/ ./

# Logs JSON (ECS) por defecto en contenedor; sin secretos en la imagen.
ENV LOGGING_STRUCTURED_FORMAT_CONSOLE=ecs

USER 10001:10001

# 8080 = API pública (vía nginx/ALB) · 8081 = Actuator (solo red interna)
EXPOSE 8080 8081

# Liveness: ¿el proceso responde? (la disponibilidad de la BD se evalúa en readiness)
# curl ya viene en la imagen base de Temurin; no se instalan paquetes extra.
HEALTHCHECK --interval=15s --timeout=3s --start-period=60s --retries=3 \
  CMD curl --fail --silent --show-error --max-time 2 http://127.0.0.1:8081/actuator/health/liveness || exit 1

# Forma exec: Java es PID 1 y recibe SIGTERM → apagado ordenado (server.shutdown=graceful)
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-XX:+ExitOnOutOfMemoryError", \
            "org.springframework.boot.loader.launch.JarLauncher"]
