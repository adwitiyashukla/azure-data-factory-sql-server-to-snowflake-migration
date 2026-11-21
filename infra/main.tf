terraform {
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-adfmig-as"
    storage_account_name = "stadfmigtfas"
    container_name       = "tfstate"
    key                  = "adfmig.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
  storage_use_azuread = true
}

locals {
  name      = "adfmig-${var.suffix}"
  deployers = toset(compact([var.admin_object_id, var.ci_principal_id]))
}

data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "main" {
  name = "rg-adfmig-${var.suffix}"
}

resource "azurerm_storage_account" "lake" {
  name                            = "stadfmig${var.suffix}"
  resource_group_name             = data.azurerm_resource_group.main.name
  location                        = data.azurerm_resource_group.main.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  is_hns_enabled                  = true
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false
  local_user_enabled              = false

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_storage_container" "lake" {
  name                  = "lake"
  storage_account_id    = azurerm_storage_account.lake.id
  container_access_type = "private"
}

resource "azurerm_key_vault" "main" {
  name                       = "kv-${local.name}"
  resource_group_name        = data.azurerm_resource_group.main.name
  location                   = data.azurerm_resource_group.main.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
}

resource "azurerm_role_assignment" "deployer_secrets" {
  for_each             = local.deployers
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value
}

resource "time_sleep" "secrets_rbac" {
  depends_on      = [azurerm_role_assignment.deployer_secrets]
  create_duration = "60s"
}

resource "tls_private_key" "snowflake" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "azurerm_key_vault_secret" "onprem_sql_password" {
  name             = "onprem-sql-password"
  key_vault_id     = azurerm_key_vault.main.id
  value_wo         = var.onprem_sql_password
  value_wo_version = 1
  content_type     = "password"
  expiration_date  = var.secret_expiry
  depends_on       = [time_sleep.secrets_rbac]
}

resource "azurerm_key_vault_secret" "snowflake_private_key" {
  name             = "snowflake-private-key"
  key_vault_id     = azurerm_key_vault.main.id
  value_wo         = tls_private_key.snowflake.private_key_pem_pkcs8
  value_wo_version = 1
  content_type     = "application/x-pem-file"
  expiration_date  = var.secret_expiry
  depends_on       = [time_sleep.secrets_rbac]
}

resource "azurerm_mssql_server" "control" {
  name                          = "sql-${local.name}"
  resource_group_name           = data.azurerm_resource_group.main.name
  location                      = var.control_location
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true

  azuread_administrator {
    login_username              = var.admin_login
    object_id                   = var.admin_object_id
    tenant_id                   = data.azurerm_client_config.current.tenant_id
    azuread_authentication_only = true
  }
}

resource "azurerm_mssql_database" "control" {
  name                        = "control"
  server_id                   = azurerm_mssql_server.control.id
  sku_name                    = var.control_sku
  min_capacity                = 0.5
  auto_pause_delay_in_minutes = 60
  max_size_gb                 = 2
  storage_account_type        = "Local"
  zone_redundant              = false
}

resource "azurerm_mssql_firewall_rule" "azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.control.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_mssql_firewall_rule" "admin" {
  count            = var.admin_ip == "" ? 0 : 1
  name             = "AdminLaptop"
  server_id        = azurerm_mssql_server.control.id
  start_ip_address = var.admin_ip
  end_ip_address   = var.admin_ip
}

resource "azurerm_data_factory" "main" {
  name                = "adf-${local.name}"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location

  identity {
    type = "SystemAssigned"
  }

  github_configuration {
    account_name       = var.github_owner
    repository_name    = var.github_repo
    branch_name        = "main"
    git_url            = "https://github.com"
    root_folder        = "/adf"
    publishing_enabled = false
  }
}

resource "azurerm_role_assignment" "adf_lake" {
  scope                            = azurerm_storage_account.lake.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azurerm_data_factory.main.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "adf_secrets" {
  scope                            = azurerm_key_vault.main.id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = azurerm_data_factory.main.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "admin_lake" {
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.admin_object_id
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${local.name}"
  resource_group_name = data.azurerm_resource_group.main.name
  location            = data.azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = var.log_daily_quota_gb
}

resource "azurerm_monitor_diagnostic_setting" "adf" {
  name                           = "adf-to-log-analytics"
  target_resource_id             = azurerm_data_factory.main.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.main.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "PipelineRuns"
  }

  enabled_log {
    category = "ActivityRuns"
  }

  enabled_log {
    category = "TriggerRuns"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_action_group" "main" {
  name                = "ag-${local.name}"
  resource_group_name = data.azurerm_resource_group.main.name
  short_name          = "adfmig"

  email_receiver {
    name                    = "owner"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_metric_alert" "failed_runs" {
  name                = "alert-${local.name}-failed-runs"
  resource_group_name = data.azurerm_resource_group.main.name
  scopes              = [azurerm_data_factory.main.id]
  description         = "A pipeline run failed"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"

  criteria {
    metric_namespace = "Microsoft.DataFactory/factories"
    metric_name      = "PipelineFailedRuns"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}
