variable "app_name" {
  description = "Short application name used in resource names (lowercase letters and digits, 3-10 chars, because storage account names allow nothing else)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,10}$", var.app_name))
    error_message = "app_name must be 3-10 lowercase letters or digits."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "stage", "prod"], var.environment)
    error_message = "environment must be one of: dev, stage, prod."
  }
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "centralindia"
}

variable "replication_type" {
  description = "Storage redundancy: LRS (one datacentre), ZRS (three zones), GRS or RAGRS (paired region)."
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS"], var.replication_type)
    error_message = "replication_type must be LRS, ZRS, GRS or RAGRS."
  }
}

variable "soft_delete_retention_days" {
  description = "Days a deleted or overwritten blob or container can still be recovered (1-365)."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_retention_days >= 1 && var.soft_delete_retention_days <= 365
    error_message = "soft_delete_retention_days must be between 1 and 365."
  }
}

variable "tags" {
  description = "Extra tags merged onto the default tags (app, environment, managed_by)."
  type        = map(string)
  default     = {}
}
