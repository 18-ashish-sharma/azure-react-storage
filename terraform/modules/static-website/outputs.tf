output "resource_group_name" {
  description = "Resource group holding every resource of this environment."
  value       = azurerm_resource_group.this.name
}

output "storage_account_name" {
  description = "Storage account hosting the site (upload target for the build)."
  value       = azurerm_storage_account.web.name
}

output "website_url" {
  description = "HTTPS URL of the static website."
  value       = azurerm_storage_account.web.primary_web_endpoint
}
