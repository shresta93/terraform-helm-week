output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "tfstate_storage_account" {
  value = azurerm_storage_account.tfstate.name
}

output "tfstate_container" {
  value = azurerm_storage_container.tfstate.name
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "acr_name" {
  value = azurerm_container_registry.main.name
}

output "cluster_name" {
  value = module.aks.cluster_name
}

output "postgres_fqdn" {
  value = module.postgres.fqdn
}

output "postgres_admin_username" {
  value = module.postgres.admin_username
}

output "postgres_admin_password" {
  value     = module.postgres.admin_password
  sensitive = true
}

output "postgres_database_name" {
  value = module.postgres.database_name
}