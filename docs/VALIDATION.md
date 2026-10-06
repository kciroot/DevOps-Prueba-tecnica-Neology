# Evidencia de validación

Fecha: 29-sep-2026. Nada se marca como validado sin haberlo ejecutado.

## 1. Ejecución real en macOS (Apple Silicon, Docker Desktop)

| Validación | Comando | Resultado |
|---|---|---|
| Tests del backend | `make test` (`mvn test`) | **7 tests, 0 fallas**: `ParkingServiceTest` 4/4 (originales) y `RequestIdFilterTest` 3/3 (nuevos) |
| Build del frontend | `make test` (`npm ci` + `npm run build`) | Bundle de producción generado en `frontend/dist/` |
| Imágenes | `docker compose build` | `parking-backend` y `parking-frontend` construidas (multi-arquitectura: corrieron en arm64) |
| Stack completo | `make validate` | **`VALIDACIÓN DEL STACK CORRECTA`** (ver abajo) |
| Respaldo | `make backup` | `backups/parking-20260929-165314.dump` + `.sha256` |
| Restauración | `make restore-check` | Restauración en BD temporal y comparación de conteos |
| Simulacros | `make drills` | Errores HTTP, BD caída, backend caído, estado de contenedores |
| Terraform | `terraform providers lock` | `.terraform.lock.hcl` generado para `linux_amd64` y `darwin_arm64` (Terraform real) |

### Salida de `make validate` (resumen)

```text
==> 2. Levantar el stack y esperar a que todos los servicios estén healthy
 ✔ Container parking-validate-database-1 Healthy
 ✔ Container parking-validate-backend-1  Healthy
 ✔ Container parking-validate-frontend-1 Healthy
==> 3. Health de Actuator (puerto de gestión interno 8081)
    {"status":"UP","groups":["liveness","readiness"],"components":{"db":{"status":"UP"},...}}
==> 4. Controles de seguridad del runtime
    UID backend=10001 frontend=101
    PostgreSQL no está publicado en el host
    Backend (8080 y 8081) no está publicado en el host
    /actuator no es accesible públicamente (nginx no lo reenvía al backend)
    Sistema de archivos de solo lectura
==> 5. Métricas Prometheus disponibles en el puerto de gestión
    OK (hikaricp_*, http_server_requests_*, jvm_*)
==> 6. Prueba funcional (smoke test) a través del frontend
    X-Request-ID=eb188af1d90dd084c5657d035c9e1bf8
    SMOKE TEST CORRECTO para la placa SMK-104650.
==> 7. Correlación frontend -> backend por X-Request-ID
    request_id=29b06f55cc8aa1315089a2a0d2e05904 presente en nginx y en backend
    {"log":{"level":"INFO","logger":"mx.neology.parking.config.RequestIdFilter"},
     "message":"GET /neo/vehiculos -> 200 (36 ms)","request_id":"29b06f55cc8aa1315089a2a0d2e05904",
     "http_status":200,"duration_ms":36, ...}
VALIDACIÓN DEL STACK CORRECTA
```

## 2. Errores encontrados por la validación y corregidos

La validación real encontró 4 problemas que la revisión estática no detectó. Cada uno está en su propio commit.

| # | Síntoma | Causa | Corrección | Commit |
|---|---|---|---|---|
| 1 | `npm ci` falla dentro de la imagen: *lock file's chokidar@4.0.3 does not satisfy chokidar@3.6.0* | El `package-lock.json` de la app base se generó con el npm de Node 20. El npm de Node 22 valida el peer opcional `chokidar ^3.5.2` de `@angular-devkit/core` | Árbol de dependencias reubicado (chokidar 3.6.0 en la raíz y 4.0.3 anidado en `@angular/compiler-cli`), con las mismas versiones e integridades. `package.json` sin cambios | `fix(frontend): package-lock.json compatible con el npm de Node 22` |
| 2 | Frontend `unhealthy`: *`/etc/nginx/conf.d` is not writable* | El tmpfs se creaba propiedad de root y nginx corre como UID 101; arrancaba sin el bloque `server` | `tmpfs` con `mode=1777` en frontend y backend | `fix(compose): tmpfs escribibles para usuarios sin privilegios` |
| 3 | Falso positivo: *PostgreSQL está publicado en el host* | `docker compose port` devuelve `:0` con exit 0 para puertos expuestos pero no publicados | Solo cuenta como publicado un puerto de host distinto de 0 | `fix(scripts): detectar puertos publicados correctamente` |
| 4 | (Habría fallado a continuación) Control de Actuator | nginx responde `index.html` con 200 a rutas desconocidas (SPA) | Se verifica el contenido, no el código HTTP | mismo commit que el #3 |

Los errores 1 y 2 también habrían fallado en GitHub Actions: la validación local los adelantó.

### Primera ejecución en GitHub Actions

`CI · backend` y `CI · frontend` pasaron a la primera (confirman en CI las correcciones #1 y #2). Fallaron dos jobs, y Build, Release y Deploy no corrieron: el quality gate funcionó.

| # | Job | Causa | Corrección |
|---|---|---|---|
| 5 | `CI · terraform` | *Unknown condition value*: Terraform genera los valores simulados en el apply, así que dos aserciones sobre atributos calculados no se podían evaluar en un `plan`. OpenTofu, usado para validar sin acceso a HashiCorp, sí los genera en el plan: por eso aquí pasaba | Las aserciones verifican valores conocidos en el plan: nombres de variables secretas y en texto plano (`secret_variable_names`, `plain_variable_names`). Mismo resultado en Terraform y OpenTofu |
| 6 | `Security · Trivy` | Maven Central respondió *429 Too Many Requests* mientras Trivy resolvía los BOM del `pom.xml` (4 ejecuciones simultáneas desde runners compartidos) | Escaneo del repositorio sin red (`TRIVY_OFFLINE_SCAN`). Las dependencias Java se escanean con versiones exactas sobre la imagen. Además, las ramas de trabajo se validan solo en su Pull Request: menos ejecuciones duplicadas |
| 7 | `Security · Trivy` (segundo run) | Con el escaneo ya funcionando, Trivy encontró 15 hallazgos HIGH (12 CVE) en Angular 18.2.13. Angular 18 no tiene soporte y ninguno tiene parche en la línea 18.x | Excepciones documentadas en `.trivyignore`, una por CVE, con el motivo por el que la app no está expuesta y caducidad `exp:2026-12-31` (al vencer, el gate vuelve a fallar). La migración a Angular 20.3.32+ queda como riesgo en `docs/SECURITY.md` |
| 8 | `Build` · Trivy de la imagen backend | El escaneo de la imagen (versiones exactas de los JAR) encontró 5 hallazgos con parche: Tomcat 10.1.55 (3 CRITICAL), Jackson 2.21.4 (1 HIGH) y pgjdbc 42.7.11 (1 HIGH). El SO de la imagen (Ubuntu 24.04) salió limpio. El gate bloqueó la imagen antes del E2E y de publicar | Se fijan en `pom.xml` las versiones de parche dentro de la misma línea (`jackson-bom.version` 2.21.6, `postgresql.version` 42.7.12), con comentario para quitarlas cuando Spring Boot las incluya. Además, el escaneo del frontend ahora corre aunque falle el del backend, para ver ambas imágenes en un solo run |
| 9 | `CI · backend` | Al fijar también `tomcat.version` 10.1.58 (la versión de parche que reporta Trivy), Maven no la encontró: el advisory ya se publicó, pero el artefacto todavía no está en Maven Central | Tomcat se queda en 10.1.55 con excepción temporal en `.trivyignore` (caduca el 2026-10-31) tras revisar la exposición: la app no usa autenticación ni security constraints de Tomcat. Lección: una versión de parche no se fija hasta confirmar que está publicada |
| 10 | `Security · Trivy` | La base de datos de Trivy se actualiza a diario: el 1-oct-2026 apareció un CVE nuevo en `@angular/router` 18.2.13 (CVE-2026-101896, DoS en SSR), sin parche en la línea 18.x. El código no cambió: cambió lo que se sabe de él | Misma revisión de exposición que el #7 (la app no usa SSR) y misma caducidad. Es el comportamiento esperado del gate: avisa de riesgos nuevos aunque nadie toque el repositorio |
| 11 | `Build` · Trivy de la imagen backend | Ya pasaron Tomcat (excepción) y pgjdbc (corregido). Aparecieron hallazgos nuevos del día: OpenSSL 3.0.13-0ubuntu3.15 en el SO (parche ya publicado por Ubuntu) y 2 CVE en Jackson 2.21.6 cuyo parche (2.21.7) aún no se publica | SO: `apt-get upgrade` en la etapa runtime, para aplicar parches publicados después de la imagen base. Jackson: excepción temporal (caduca el 2026-10-31) tras comprobar en el código que no usa deserialización polimórfica ni `@JsonIdentityInfo` |

### Resultado final en GitHub Actions

Con el commit `8db345a` (2-oct-2026), el pipeline del [Pull Request #2](https://github.com/kciroot/DevOps-Prueba-tecnica-Neology/pull/2) quedó en verde: `CI · backend` (35 s), `CI · frontend` (22 s), `CI · terraform` (25 s), `Security · Trivy` (24 s) y `Build · imágenes + escaneo + E2E` (3 min 5 s: escaneo de ambas imágenes, stack completo con `validate-stack.sh` y pruebas de alertas). `Release` y `Deploy` se omiten a propósito en un Pull Request: solo corren en `main` o en tags `vX.Y.Z`, y el deploy además requiere `DEPLOY_ENABLED`.

## 3. Validación estática (entorno de desarrollo, sin Docker ni registros)

| Validación | Resultado |
|---|---|
| `git ls-files` sin `.env`, `.pem` ni llaves (control de la GUIA) | Ninguno |
| `docker compose config` / sin `POSTGRES_PASSWORD` | OK / falla con mensaje claro |
| `shellcheck -S style scripts/*.sh` | Sin hallazgos |
| `actionlint` sobre `pipeline.yml` | Sin hallazgos |
| `promtool check rules` y `promtool test rules alerts.test.yml` | 6 reglas / SUCCESS |
| `trivy fs --scanners secret,misconfig` | 0 secretos; 0 misconfiguraciones HIGH/CRITICAL |

## 4. Pendiente

| Validación | Dónde |
|---|---|
| `terraform plan` real | Requiere credenciales AWS (`make tf-plan`) |
| Comportamiento en ECS Fargate | Requiere cuenta AWS (deploy a `dev`) |
