terraform {
  # 1.16.7 was released on 22 October 2026. Newer releases are under two weeks old.
  required_version = "~> 1.16.7"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.11.0" # 23 October 2026
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
