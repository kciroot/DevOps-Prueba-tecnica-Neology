# Evidencia de validación

Fecha: 29-sep-2026. Esta tabla separa **lo que se ejecutó** de **lo que falta ejecutar**. Nada se marca como validado sin haberlo corrido.

## Entorno donde se trabajó
Contenedor Linux con acceso de red solo a GitHub: Maven Central, el registro de npm, Docker Hub, GHCR y HashiCorp responden 403, y no hay daemon de Docker. Por eso **la compilación, las imágenes y el stack se validan en GitHub Actions** (job `build`) o en una máquina con Docker.

## Ejecutado

| # | Validación | Comando | Resultado |
|---|---|---|---|
| 1 | Sin secretos versionados (GUIA) | `git ls-files \| grep -E '(^\|/)(\.env\|id_rsa\|.*\.pem)$'` | Ninguno |
| 2 | Compose válido | `docker compose config --quiet` | OK |
| 3 | Compose falla sin password | `docker compose config` sin `.env` | `required variable POSTGRES_PASSWORD is missing a value` |
| 4 | Exposición | `docker compose config --format json` | Solo `frontend` publica (`4200`); backend y database sin puertos |
| 5 | Endurecimiento | idem | backend y frontend `read_only: true`, `cap_drop: [ALL]` |
| 6 | Sin `latest`; versiones fijadas | `grep FROM/image` | Todas con versión de parche |
| 7 | Usuario sin privilegios | `grep ^USER */Dockerfile` | `10001:10001` y `101` |
| 8 | Scripts | `shellcheck -S style scripts/*.sh` | Sin hallazgos |
| 9 | Workflow | `actionlint` | Sin hallazgos |
| 10 | Reglas de alerta | `promtool check rules` / `promtool test rules alerts.test.yml` | 6 reglas OK / pruebas SUCCESS |
| 11 | Terraform formato | `tofu fmt -check -recursive` | OK |
| 12 | Terraform init/validate | `tofu init -backend=false` · `tofu validate` | OK |
| 13 | Terraform plan simulado | `tofu test` (3 escenarios: dev, production, ambiente inválido) | 3 passed |
| 14 | Seguridad del repo | `trivy fs --scanners secret,misconfig` (Trivy 0.74.0, checks embebidos) | exit 0: 0 secretos, 0 misconfig HIGH/CRITICAL en Dockerfiles y Terraform |

Terraform se validó con **OpenTofu 1.12.6** y providers idénticos (aws 6.66.0, random 3.9.1) porque `releases.hashicorp.com` no era accesible. El job `terraform` del pipeline ejecuta lo mismo con Terraform 1.16.4.

## No ejecutado aquí (y dónde se ejecuta)

| Validación | Motivo | Dónde |
|---|---|---|
| `./scripts/verify.sh` (mvn test + npm build) | Maven Central y npm → 403 | Jobs `backend` y `frontend`; o local con `make test` |
| `docker compose build --no-cache`, `up`, `ps`, logs | Sin daemon de Docker | Job `build` (`validate-stack.sh`); o local con `make validate` |
| `./scripts/smoke-test.sh` | Requiere el stack | Incluido en `validate-stack.sh` |
| Trivy de vulnerabilidades (dependencias e imágenes) | Base de datos de Trivy en `mirror.gcr.io` → 403 | Jobs `security` y `build` |
| `terraform plan` real | Requiere credenciales AWS | `make tf-plan` con credenciales de solo lectura |
| CSP en navegador | Requiere el stack en un navegador | Abrir <http://localhost:4200> y revisar la consola |
| Comportamiento en ECS Fargate | Requiere cuenta AWS | Deploy a `dev` |

## Pendiente de registrar (completar tras la primera ejecución)

- [ ] Enlace al run del pipeline en verde: `https://github.com/<owner>/<repo>/actions/runs/<id>`
- [ ] Salida de `make validate` (termina con `VALIDACIÓN DEL STACK CORRECTA`)
- [ ] Tamaño de las imágenes (paso *Tamaño de imágenes* del job `build`)
- [ ] `infra/terraform/.terraform.lock.hcl` generado con
      `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64` y commiteado
