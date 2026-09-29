provider "aws" {
  region = var.aws_region

  # Todas las etiquetas se aplican a cada recurso: costos y responsables rastreables
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}
