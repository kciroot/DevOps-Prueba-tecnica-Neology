terraform {
  # >= 1.11: atributos write-only (el password de la BD nunca se guarda en el state)
  required_version = ">= 1.11"

  # Versiones exactas: `terraform init` descarga siempre lo mismo (Dependabot las actualiza)
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.66.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.9.1"
    }
  }

  # State remoto en S3, cifrado y con bloqueo nativo (use_lockfile, sin DynamoDB).
  # Configuración parcial: bucket, key y region se pasan en `terraform init -backend-config=...`
  # para usar un state distinto por ambiente (ver environments/backend.hcl.example).
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}
