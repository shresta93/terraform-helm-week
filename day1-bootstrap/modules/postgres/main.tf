# A random password Terraform generates once and stores in state. Restricted
# to URI-safe special characters (-_.~) on purpose: this password ends up
# embedded directly inside a postgresql:// connection URL later, and
# characters like @ : / ? would be misread as URL delimiters instead of
# password characters if they showed up unescaped.
resource "random_password" "postgres_admin" {
  length           = 24
  special          = true
  override_special = "-_.~"
}

resource "azurerm_postgresql_flexible_server" "main" {
  name                = "${var.prefix}-pg-${var.suffix}" # globally unique, like the ACR/storage names
  resource_group_name = var.resource_group_name
  location            = var.location

  version                = "16"
  administrator_login    = "taskapiadmin"
  administrator_password = random_password.postgres_admin.result

  storage_mb = 32768             # 32 GiB - the minimum tier, plenty for this project
  sku_name   = "B_Standard_B1ms" # cheapest Burstable tier, ~$12-15/month compute + ~$4/month storage

  backup_retention_days = 7

  public_network_access_enabled = true

  tags = {
    project = "terraform-helm-week"
  }
}

# Learning-project-simple, not production-grade: this allows any Azure
# service (not the whole public internet) to reach the server, so AKS can
# connect without you having to look up and pin its exact outbound IP. A
# real production setup would use a private endpoint / VNet integration
# instead - noted here so you know this is a deliberate simplification,
# not an oversight.
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_postgresql_flexible_server_database" "taskapi" {
  name      = "taskapi"
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}
