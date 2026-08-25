output "fqdn" {
  value = azurerm_postgresql_flexible_server.main.fqdn
}

output "admin_username" {
  value = azurerm_postgresql_flexible_server.main.administrator_login
}

output "admin_password" {
  value     = random_password.postgres_admin.result
  sensitive = true
}

output "database_name" {
  value = azurerm_postgresql_flexible_server_database.taskapi.name
}
