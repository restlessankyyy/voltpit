variable "subscription_id" {
  type        = string
  description = "Azure subscription ID to deploy into."
}

variable "location" {
  type        = string
  description = "Azure region for all resources. Sweden Central is closest to Stockholm."
  default     = "swedencentral"
}

variable "name_prefix" {
  type        = string
  description = "Short lowercase prefix used for resource names."
  default     = "tesladash"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,11}$", var.name_prefix))
    error_message = "name_prefix must be 3-12 chars, lowercase letters/digits, starting with a letter."
  }
}

variable "source_mode" {
  type        = string
  description = "Backend data source: 'simulator' (no Tesla creds needed) or 'tesla'."
  default     = "simulator"

  validation {
    condition     = contains(["simulator", "tesla"], var.source_mode)
    error_message = "source_mode must be 'simulator' or 'tesla'."
  }
}

variable "poll_interval_ms" {
  type        = number
  description = "How often the backend polls the data source, in milliseconds."
  default     = 2500
}

variable "primary_unit" {
  type        = string
  description = "Primary speed unit shown by the app: 'mph' or 'kmh'."
  default     = "kmh"

  validation {
    condition     = contains(["mph", "kmh"], var.primary_unit)
    error_message = "primary_unit must be 'mph' or 'kmh'."
  }
}

variable "image_tag" {
  type        = string
  description = "Container image tag to build and deploy. Leave as 'latest' (the default sentinel) to auto-derive an immutable content hash from the backend build inputs; set an explicit value (e.g. a git SHA) to pin a specific tag."
  default     = "latest"
}

# --- Optional Tesla Fleet API credentials (only used when source_mode = 'tesla') ---

variable "tesla_client_id" {
  type        = string
  description = "Tesla Fleet API OAuth client ID. Leave empty for simulator mode."
  default     = ""
  sensitive   = true
}

variable "tesla_client_secret" {
  type        = string
  description = "Tesla Fleet API OAuth client secret. Leave empty for simulator mode."
  default     = ""
  sensitive   = true
}

variable "tesla_vin" {
  type        = string
  description = "Tesla vehicle VIN to track. Leave empty to use the first vehicle on the account."
  default     = ""
}

variable "tesla_fleet_base_url" {
  type        = string
  description = "Tesla Fleet API regional base URL. EU (Sweden) by default; use the NA URL for North America."
  default     = "https://fleet-api.prd.eu.vn.cloud.tesla.com"
}

# --- Optional Cosmos DB event store (free tier, zero redundancy) ---

variable "enable_cosmos" {
  type        = bool
  description = "Provision a free-tier Cosmos DB account to persist streamed telemetry events with a 30-day TTL. Only one free-tier account is allowed per subscription."
  default     = false
}

variable "cosmos_database" {
  type        = string
  description = "Cosmos SQL database name for telemetry events."
  default     = "tesladash"
}

variable "cosmos_container" {
  type        = string
  description = "Cosmos SQL container name for telemetry events. Partitioned by vehicle VIN."
  default     = "events"
}

variable "cosmos_ttl_seconds" {
  type        = number
  description = "Default per-document time-to-live, in seconds. Events auto-expire after this. 30 days by default."
  default     = 2592000

  validation {
    condition     = var.cosmos_ttl_seconds > 0 && var.cosmos_ttl_seconds <= 2592000
    error_message = "cosmos_ttl_seconds must be between 1 and 2592000 (30 days maximum)."
  }
}
