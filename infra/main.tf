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

  # Cosmos persistence env. No key is passed: the account disables local auth,
  # so the app authenticates with its user-assigned managed identity. The
  # AZURE_CLIENT_ID lets DefaultAzureCredential pick that identity.
  cosmos_env = var.enable_cosmos ? [
    { name = "COSMOS_ENDPOINT", value = azurerm_cosmosdb_account.events[0].endpoint },
    { name = "COSMOS_DATABASE", value = var.cosmos_database },
    { name = "COSMOS_CONTAINER", value = var.cosmos_container },
    { name = "COSMOS_TTL_SECONDS", value = tostring(var.cosmos_ttl_seconds) },
    { name = "AZURE_CLIENT_ID", value = azurerm_user_assigned_identity.app.client_id },
  ] : []

  env_plain = concat(local.base_env, local.tesla_env, local.cosmos_env)

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

# ── Cosmos DB: free-tier event store, zero redundancy ────────────────────────
# Persists streamed telemetry events with a 30-day TTL. Free tier waives the
# cost of the first 1000 RU/s and 25 GB (one free-tier account per subscription;
# free tier and serverless are mutually exclusive, so this uses provisioned
# throughput). Zero redundancy: single region, no zone redundancy, no
# geo-replication, manual failover only, local (LRS) backup.
resource "azurerm_cosmosdb_account" "events" {
  count               = var.enable_cosmos ? 1 : 0
  name                = "${var.name_prefix}-cosmos-${local.suffix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  # Free tier: first 1000 RU/s + 25 GB free. Throughput provisioned on the
  # database below stays within that allowance.
  free_tier_enabled = true

  consistency_policy {
    consistency_level = "Session"
  }

  # Zero redundancy: one region, no zone redundancy, no automatic failover.
  geo_location {
    location          = azurerm_resource_group.rg.location
    failover_priority = 0
    zone_redundant    = false
  }

  automatic_failover_enabled = false

  # Local (LRS) backup only, no geo-redundant copies.
  backup {
    type               = "Periodic"
    storage_redundancy = "Local"
  }

  # Least privilege: disable key-based (local) auth so the only way in is Entra
  # ID + data-plane RBAC bound to the app's managed identity.
  local_authentication_disabled = true
}

resource "azurerm_cosmosdb_sql_database" "events" {
  count               = var.enable_cosmos ? 1 : 0
  name                = var.cosmos_database
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.events[0].name

  # Database-level autoscale shared across containers. Max 1000 RU/s keeps the
  # account fully inside the free-tier allowance; it scales down to 100 RU/s
  # when idle.
  autoscale_settings {
    max_throughput = 1000
  }
}

resource "azurerm_cosmosdb_sql_container" "events" {
  count                 = var.enable_cosmos ? 1 : 0
  name                  = var.cosmos_container
  resource_group_name   = azurerm_resource_group.rg.name
  account_name          = azurerm_cosmosdb_account.events[0].name
  database_name         = azurerm_cosmosdb_sql_database.events[0].name
  partition_key_paths   = ["/vin"]
  partition_key_version = 2

  # Events auto-expire after the TTL (30 days by default). Documents may also
  # carry their own `ttl` to override per item.
  default_ttl = var.cosmos_ttl_seconds
}

# Custom data-plane role granting ONLY what the backend needs: read account
# metadata (required by the SDK to connect) and create items. No read, no
# delete, no container/database management. This is tighter than the built-in
# "Cosmos DB Built-in Data Contributor" role, which also allows reads, deletes
# and container management we never use.
resource "azurerm_cosmosdb_sql_role_definition" "events_writer" {
  count               = var.enable_cosmos ? 1 : 0
  name                = "${var.name_prefix}-telemetry-writer"
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.events[0].name
  type                = "CustomRole"
  assignable_scopes   = [azurerm_cosmosdb_account.events[0].id]

  permissions {
    data_actions = [
      "Microsoft.DocumentDB/databaseAccounts/readMetadata",
      "Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/create",
    ]
  }
}

# Bind the custom write-only role to the app's managed identity, scoped to the
# single events container (not the whole account) for least privilege.
resource "azurerm_cosmosdb_sql_role_assignment" "events_writer" {
  count               = var.enable_cosmos ? 1 : 0
  resource_group_name = azurerm_resource_group.rg.name
  account_name        = azurerm_cosmosdb_account.events[0].name
  role_definition_id  = azurerm_cosmosdb_sql_role_definition.events_writer[0].id
  principal_id        = azurerm_user_assigned_identity.app.principal_id
  scope               = azurerm_cosmosdb_sql_container.events[0].id
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
    azurerm_cosmosdb_sql_role_assignment.events_writer,
    terraform_data.image_build,
  ]
}
