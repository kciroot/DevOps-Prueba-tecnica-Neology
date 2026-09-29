# Despliegue desde GitHub Actions con OIDC: sin access keys de larga duración.
#
# Mínimo privilegio: el pipeline SOLO puede cambiar la versión desplegada
# (nueva task definition + actualizar servicio). Cualquier cambio de red, BD o IAM
# falla con AccessDenied y debe aplicarlo una persona con permisos de infraestructura.
#
# Se crea solo si var.github_repository está definido. El primer apply lo hace un administrador.

locals {
  create_github_role = var.github_repository != null
  github_oidc_provider_arn = !local.create_github_role ? null : (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github[0].arn
  )
}

# El proveedor OIDC es único por cuenta: se crea una sola vez (create_github_oidc_provider)
resource "aws_iam_openid_connect_provider" "github" {
  count          = local.create_github_role && var.create_github_oidc_provider ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = local.create_github_role && !var.create_github_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_assume" {
  count = local.create_github_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    # Solo este repositorio y solo desde el Environment de GitHub de este ambiente
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:environment:${var.environment}"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  count                = local.create_github_role ? 1 : 0
  name                 = "${local.name}-github-deploy"
  assume_role_policy   = data.aws_iam_policy_document.github_assume[0].json
  max_session_duration = 3600
}

# Lectura para que `terraform plan` pueda refrescar el estado de los recursos
resource "aws_iam_role_policy_attachment" "github_deploy_read" {
  count      = local.create_github_role ? 1 : 0
  role       = aws_iam_role.github_deploy[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "github_deploy" {
  count = local.create_github_role ? 1 : 0

  statement {
    sid       = "DeployNewTaskDefinitions"
    actions   = ["ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition", "ecs:TagResource"]
    resources = ["*"] # RegisterTaskDefinition no admite restricción por recurso
  }

  statement {
    sid     = "UpdateOnlyThisEnvironmentServices"
    actions = ["ecs:UpdateService"]
    resources = [
      "arn:aws:ecs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:service/${local.name}/${local.name}-*"
    ]
  }

  statement {
    sid       = "PassOnlyTheEcsRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.execution.arn, aws_iam_role.task.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  dynamic "statement" {
    for_each = var.tf_state_bucket == null ? [] : [1]
    content {
      sid       = "TerraformStateThisEnvironment"
      actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
      resources = ["arn:aws:s3:::${var.tf_state_bucket}/parking/${var.environment}/*"]
    }
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  count  = local.create_github_role ? 1 : 0
  name   = "deploy-image-only"
  role   = aws_iam_role.github_deploy[0].id
  policy = data.aws_iam_policy_document.github_deploy[0].json
}
