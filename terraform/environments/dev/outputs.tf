output "resource_group_name" {
  description = "Resource group of this environment."
  value       = module.static_website.resource_group_name
}

output "storage_account_name" {
  description = "Storage account to upload the build to."
  value       = module.static_website.storage_account_name
}

output "website_url" {
  description = "HTTPS URL of the static website."
  value       = module.static_website.website_url
}
