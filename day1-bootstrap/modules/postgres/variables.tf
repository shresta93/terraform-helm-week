variable "prefix" {
  type = string
}

variable "suffix" {
  description = "Random suffix (reused from root) to keep the server name globally unique"
  type        = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}
