output "container_app_fqdn" {
  description = "Public hostname of the Container App."
  value       = azurerm_container_app.app.ingress[0].fqdn
}

output "stream_url" {
  description = "Secure WebSocket URL to set in the iOS app (Settings or AppConfig)."
  value       = "wss://${azurerm_container_app.app.ingress[0].fqdn}/stream"
}

output "stream_token" {
  description = "Bearer token the iOS app must send to connect to /stream. Retrieve with: terraform output -raw stream_token"
  value       = random_password.stream_token.result
  sensitive   = true
}

output "health_url" {
  description = "Health check endpoint."
  value       = "https://${azurerm_container_app.app.ingress[0].fqdn}/health"
}

output "tesla_app_domain" {
  description = "Domain to use as TESLA_APP_DOMAIN when enabling Fleet API later (no scheme)."
  value       = azurerm_container_app.app.ingress[0].fqdn
}

output "registry_login_server" {
  description = "ACR login server hosting the backend image."
  value       = azurerm_container_registry.acr.login_server
}

output "cosmos_endpoint" {
  description = "Cosmos DB account endpoint for the telemetry event store (empty when disabled)."
  value       = var.enable_cosmos ? azurerm_cosmosdb_account.events[0].endpoint : ""
}
