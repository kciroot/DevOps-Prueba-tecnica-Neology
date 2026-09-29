# Atajos para los comandos más usados. Cada target es un comando documentado en el README.
.DEFAULT_GOAL := help
.PHONY: help env up down logs ps test validate scan scan-images drills backup restore-check observability tf-check

help: ## Muestra esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

env: ## Crea .env con un password aleatorio (si no existe)
	@test -f .env && echo ".env ya existe" || { sed "s|CAMBIAR_POR_UN_PASSWORD_ALEATORIO|$$(openssl rand -hex 24)|" .env.example > .env && chmod 600 .env && echo ".env creado"; }

up: env ## Construye y levanta el stack (espera a que esté healthy)
	docker compose up --build --detach --wait

down: ## Detiene el stack (conserva los datos)
	docker compose down

ps: ## Estado y salud de los contenedores
	docker compose ps

logs: ## Logs de la aplicación
	docker compose logs --tail=100 -f backend frontend

test: ## Tests del backend y build del frontend (sin Docker)
	./scripts/verify.sh

validate: env ## Validación completa del stack con Docker (health, seguridad, smoke, correlación)
	./scripts/validate-stack.sh

scan: ## Escaneo de seguridad del repositorio con Trivy
	./scripts/security-scan.sh

scan-images: ## Escaneo del repositorio y de las imágenes locales
	./scripts/security-scan.sh images

drills: ## Simulacros de falla (HTTP, BD caída, app caída, contenedores)
	./scripts/failure-drills.sh

backup: ## Respaldo de PostgreSQL en backups/
	./scripts/backup-db.sh

restore-check: ## Prueba el último respaldo restaurándolo en una BD temporal
	./scripts/restore-db.sh "$$(ls -1t backups/parking-*.dump | head -1)"

observability: ## Levanta Prometheus en http://localhost:9090
	docker compose --profile observability up --detach

tf-check: ## Formato, validación y pruebas de Terraform (sin credenciales AWS)
	cd infra/terraform && terraform fmt -check -recursive && terraform init -backend=false -input=false && terraform validate && terraform test
