terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # After the first successful apply, uncomment backend.tf.example (rename it
  # to backend.tf) and re-run `terraform init -migrate-state` to move your
  # state into Azure Storage instead of your local disk.
}

provider "azurerm" {
  features {}

  # AzureRM provider 5.0 (shipped July 2026) stopped auto-registering Azure
  # resource providers on a fresh subscription, which breaks a first-timer's
  # apply with permission errors. "legacy" restores the old auto-register
  # behavior so you're not fighting provider registration during a learning
  # week. Fine to remove or narrow later once you know which RPs you need.
  resource_provider_registrations = "legacy"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-rg"
  location = var.location

  tags = {
    project = "terraform-helm-week",
    ci = "false",
    test = "true"
  }
}

# Storage account to hold Terraform's own remote state.
# Chicken-and-egg problem: this has to be created with LOCAL state first,
# then you point Terraform at it as a backend. See README.md.
resource "azurerm_storage_account" "tfstate" {
  name                     = "${var.prefix}tfstate${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# Container registry - Day 4 will build your app image and push it here.
# Basic SKU is the cheapest tier (~$0.17/day) and is fine for a solo project.
resource "azurerm_container_registry" "main" {
  name                = "${var.prefix}acr${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
}

module "aks" {
  source              = "./modules/aks"
  prefix              = var.prefix
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  acr_id              = azurerm_container_registry.main.id
}

module "postgres" {
  source              = "./modules/postgres"
  prefix              = var.prefix
  suffix              = random_string.suffix.result
  resource_group_name = azurerm_resource_group.main.name
  location            = "eastus2"
}