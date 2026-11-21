terraform {
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  features {}
  storage_use_azuread = true
}

variable "suffix" {
  type    = string
  default = "as"
}

variable "location" {
  type    = string
  default = "westus2"
}

variable "github_repo" {
  type    = string
  default = "adwitiyashukla/azure-data-factory-sql-server-to-snowflake-migration"
}

variable "github_owner_id" {
  type    = number
  default = 293685877
}

variable "github_repository_id" {
  type    = number
  default = 1466153518
}

locals {
  github_subject = "repo:${split("/", var.github_repo)[0]}@${var.github_owner_id}/${split("/", var.github_repo)[1]}@${var.github_repository_id}"
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "main" {
  name     = "rg-adfmig-${var.suffix}"
  location = var.location
}

resource "azurerm_storage_account" "state" {
  name                            = "stadfmigtf${var.suffix}"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false
  local_user_enabled              = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

resource "azurerm_user_assigned_identity" "ci" {
  name                = "id-adfmig-ci"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}

resource "azurerm_federated_identity_credential" "main_branch" {
  name                      = "github-main"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "${local.github_subject}:ref:refs/heads/main"
}

resource "azurerm_federated_identity_credential" "pull_request" {
  name                      = "github-pull-request"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "${local.github_subject}:pull_request"
}

resource "azurerm_federated_identity_credential" "dev_environment" {
  name                      = "github-environment-dev"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "${local.github_subject}:environment:dev"
}

resource "azurerm_role_assignment" "ci_contributor" {
  scope                            = azurerm_resource_group.main.id
  role_definition_name             = "Contributor"
  principal_id                     = azurerm_user_assigned_identity.ci.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "ci_rbac_admin" {
  scope                            = azurerm_resource_group.main.id
  role_definition_name             = "Role Based Access Control Administrator"
  principal_id                     = azurerm_user_assigned_identity.ci.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "ci_state" {
  scope                            = azurerm_storage_account.state.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azurerm_user_assigned_identity.ci.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "admin_state" {
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

output "subscription_id" {
  value = data.azurerm_client_config.current.subscription_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "admin_object_id" {
  value = data.azurerm_client_config.current.object_id
}

output "ci_client_id" {
  value = azurerm_user_assigned_identity.ci.client_id
}

output "ci_principal_id" {
  value = azurerm_user_assigned_identity.ci.principal_id
}

output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "state_storage_account" {
  value = azurerm_storage_account.state.name
}
