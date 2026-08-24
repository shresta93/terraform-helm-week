resource "azurerm_kubernetes_cluster" "main" {
  name                = "${var.prefix}-aks"
  resource_group_name = var.resource_group_name
  location            = var.location
  dns_prefix          = "${var.prefix}-aks"

  sku_tier = "Free" # no uptime-SLA charge - fine for a learning/dev cluster
  node_provisioning_profile {
    mode = "Manual"
  }

  default_node_pool {
    name       = "system"
    vm_size    = var.node_vm_size
    node_count = var.node_count
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "kubenet" # AKS manages its own VNet - no subnet to build yet
  }

  tags = {
    project = "terraform-helm-week"
  }
}

# Let the cluster's own identity pull images from ACR - no stored credentials.
# Requires your logged-in account to have rights to assign roles (Owner /
# User Access Administrator) on the ACR - true by default on a personal sub.
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
