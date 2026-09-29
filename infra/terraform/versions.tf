terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66"
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
