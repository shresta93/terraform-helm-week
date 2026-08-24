variable "prefix" {
  description = "Short prefix used for naming (reused from the root module)"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group to deploy the cluster into"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "node_vm_size" {
  description = "VM size for the system node pool"
  type        = string
  default     = "Standard_D2as_v7"
}

variable "node_count" {
  description = "Number of nodes in the system node pool"
  type        = number
  default     = 1
}

variable "acr_id" {
  description = "Resource ID of the Container Registry the cluster should be able to pull from"
  type        = string
}
