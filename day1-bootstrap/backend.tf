# STEP 2 of the remote-state migration (see README.md "Remote state" section).
#
# After your first `terraform apply` succeeds, copy the three output values
# below, fill them in here, rename this file to backend.tf, then run:
#
#   terraform init -migrate-state
#
# Terraform will ask to copy your existing local state into this storage
# account - say yes. From then on your state lives in Azure, not on your laptop.

 terraform {
   backend "azurerm" {
     resource_group_name  = "tfhelm-rg"              # <- output: resource_group_name
     storage_account_name = "tfhelmtfstateg9u9sc"     # <- output: tfstate_storage_account
     container_name       = "tfstate"                 # <- output: tfstate_container
     key                  = "bootstrap.tfstate"
   }
 }
