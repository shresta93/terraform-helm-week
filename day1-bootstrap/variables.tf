variable "prefix" {
  description = "Short prefix used for naming every resource (letters/numbers only, keep it short - storage account names max 24 chars)"
  type        = string
  default     = "tfhelm"
}

variable "location" {
  description = "Azure region to deploy into"
  type        = string
  default     = "eastus"
}
