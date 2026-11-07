data "azurerm_client_config" "current" {}

# Storage account names are global, 3-24 lowercase letters and digits.
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  # e.g. "streactappdevx1y2z3" (max 2 + 10 + 5 + 6 = 23 characters)
  storage_account_name = "st${var.app_name}${var.environment}${random_string.suffix.result}"

  tags = merge({
    app         = var.app_name
    environment = var.environment
    managed_by  = "terraform"
  }, var.tags)
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.app_name}-${var.environment}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "web" {
  #checkov:skip=CKV_AZURE_59:A static website is public by design; the web endpoint needs public network access.
  #checkov:skip=CKV2_AZURE_33:Same reason: a private endpoint would make the site unreachable from the internet.
  #checkov:skip=CKV_AZURE_206:Content is a reproducible build from git; geo-replication is a cost decision, set replication_type = "GRS" if needed.
  #checkov:skip=CKV2_AZURE_1:Microsoft-managed keys are enough for public website files; a customer-managed key needs a Key Vault.
  #checkov:skip=CKV2_AZURE_40:Terraform configures the static website through the data plane with the account key. Uploads use Entra ID (--auth-mode login), not keys.
  #checkov:skip=CKV_AZURE_33:No queues are used in this account.
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.this.name
  location                 = azurerm_resource_group.this.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.replication_type
  tags                     = local.tags

  # Transport and access
  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false # no anonymous blob access; the site is served by the web endpoint
  local_user_enabled                = false # no SFTP local users
  infrastructure_encryption_enabled = true
  shared_access_key_enabled         = true # see CKV2_AZURE_40 above

  # SAS tokens for this account may be valid for at most a day; longer ones are refused.
  sas_policy {
    expiration_period = "01.00:00:00"
    expiration_action = "Block"
  }

  # Undo a bad upload or an accidental delete.
  blob_properties {
    delete_retention_policy {
      days = var.soft_delete_retention_days
    }
    container_delete_retention_policy {
      days = var.soft_delete_retention_days
    }
  }
}

# Turns on the $web container and the https://<account>.z<n>.web.core.windows.net endpoint.
resource "azurerm_storage_account_static_website" "web" {
  storage_account_id = azurerm_storage_account.web.id
  index_document     = "index.html"
  # Single-page app: unknown paths get index.html so the client-side router can handle them.
  error_404_document = "index.html"
}

# Whoever runs Terraform (you locally, or the CI identity) can upload the build with
# 'az storage blob upload-batch --auth-mode login' instead of an account key.
resource "azurerm_role_assignment" "deployer_blob_contributor" {
  scope                = azurerm_storage_account.web.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
