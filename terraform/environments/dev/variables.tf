variable "app_name" {
  description = "Short application name used in resource names (lowercase letters and digits, 3-10 chars)."
  type        = string
  default     = "reactapp"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "centralindia"
}
