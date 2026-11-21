output "factory_name" {
  value = azurerm_data_factory.main.name
}

output "factory_id" {
  value = azurerm_data_factory.main.id
}

output "adf_principal_id" {
  value = azurerm_data_factory.main.identity[0].principal_id
}

output "lake_url" {
  value = azurerm_storage_account.lake.primary_dfs_endpoint
}

output "lake_blob_url" {
  value = azurerm_storage_account.lake.primary_blob_endpoint
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "control_server" {
  value = azurerm_mssql_server.control.fully_qualified_domain_name
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "snowflake_public_key" {
  value = replace(replace(replace(tls_private_key.snowflake.public_key_pem, "-----BEGIN PUBLIC KEY-----", ""), "-----END PUBLIC KEY-----", ""), "\n", "")
}
