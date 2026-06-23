locals {
  # Globally-unique-ish suffix for the ACR name (alphanumeric only).
  suffix    = random_string.suffix.result
  acr_name  = "${var.name_prefix}acr${local.suffix}"
  image_ref = "${azurerm_container_registry.acr.login_server}/tesla-dash-backend:${var.image_tag}"

  # Public FQDN of the Container App, derived from the environment's default
  # domain so it can be referenced in the app's own env without a cycle.
  app_fqdn = "${var.name_prefix}-app.${azurerm_container_app_environment.env.default_domain}"

  # Plain (non-secret) environment variables for the backend container.
  base_env = [
    { name = "SOURCE", value = var.source_mode },
    { name = "PORT", value = "8080" },
    { name = "POLL_INTERVAL_MS", value = tostring(var.poll_interval_ms) },
    { name = "PRIMARY_UNIT", value = var.primary_unit },
  ]

  tesla_env = var.source_mode == "tesla" ? concat(
    [
      { name = "TESLA_CLIENT_ID", value = var.tesla_client_id },
      { name = "TESLA_APP_DOMAIN", value = local.app_fqdn },
      { name = "TESLA_REDIRECT_URI", value = "https://${local.app_fqdn}/auth/callback" },
      { name = "TESLA_FLEET_BASE_URL", value = var.tesla_fleet_base_url },
    ],
    var.tesla_vin != "" ? [{ name = "TESLA_VIN", value = var.tesla_vin }] : [],
  ) : []

  env_plain = concat(local.base_env, local.tesla_env)

  # Secret-backed environment variables. STREAM_TOKEN always guards the
  # WebSocket; the Tesla client secret is only present in tesla mode.
  env_secret = concat(
    [{ name = "STREAM_TOKEN", secret_name = "stream-token" }],
    (var.source_mode == "tesla" && var.tesla_client_secret != "") ? [
      { name = "TESLA_CLIENT_SECRET", secret_name = "tesla-client-secret" }
    ] : [],
  )

  app_secrets = merge(
    { "stream-token" = random_password.stream_token.result },
    (var.source_mode == "tesla" && var.tesla_client_secret != "") ? {
      "tesla-client-secret" = var.tesla_client_secret
    } : {},
  )
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

# Shared bearer token guarding the /stream WebSocket. URL-safe so it can ride
# in an Authorization header or query string without escaping.
resource "random_password" "stream_token" {
  length  = 40
  special = false
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.name_prefix}-rg"
  location = var.location
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "${var.name_prefix}-law"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_registry" "acr" {
  name                = local.acr_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "Basic"
  admin_enabled       = false
}

# Managed identity the Container App uses to pull from ACR (no admin creds).
resource "azurerm_user_assigned_identity" "app" {
  name                = "${var.name_prefix}-id"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}

# Build and push the backend image locally with Docker buildx (fast path).
# Container Apps runs linux/amd64, so build for that platform explicitly.
resource "terraform_data" "image_build" {
  triggers_replace = {
    image_tag      = var.image_tag
    dockerfile     = filesha256("${path.module}/../backend/Dockerfile")
    package_json   = filesha256("${path.module}/../backend/package.json")
    src_dir_change = sha256(join(",", [for f in fileset("${path.module}/../backend/src", "**") : filesha256("${path.module}/../backend/src/${f}")]))
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/../backend"
    command     = "az acr login --name ${azurerm_container_registry.acr.name} && docker buildx build --platform linux/amd64 -t ${local.image_ref} -f Dockerfile --push ."
  }

  depends_on = [azurerm_container_registry.acr]
}

resource "azurerm_container_app_environment" "env" {
  name                       = "${var.name_prefix}-env"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
}

resource "azurerm_container_app" "app" {
  name                         = "${var.name_prefix}-app"
  container_app_environment_id = azurerm_container_app_environment.env.id
  resource_group_name          = azurerm_resource_group.rg.name
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app.id]
  }

  registry {
    server   = azurerm_container_registry.acr.login_server
    identity = azurerm_user_assigned_identity.app.id
  }

  dynamic "secret" {
    for_each = local.app_secrets
    content {
      name  = secret.key
      value = secret.value
    }
  }

  template {
    min_replicas = 1
    max_replicas = 1

    container {
      name   = "backend"
      image  = local.image_ref
      cpu    = 0.25
      memory = "0.5Gi"

      dynamic "env" {
        for_each = local.env_plain
        content {
          name  = env.value.name
          value = env.value.value
        }
      }

      dynamic "env" {
        for_each = local.env_secret
        content {
          name        = env.value.name
          secret_name = env.value.secret_name
        }
      }

      liveness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 8080
      }

      readiness_probe {
        transport = "HTTP"
        path      = "/health"
        port      = 8080
      }
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    transport        = "auto"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    terraform_data.image_build,
  ]
}
