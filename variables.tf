variable "LOCATION" {
  type        = string
  description = "The location of the datacentre where the resource should be created."
}

variable "ENVIRONMENT" {
  type        = string
  description = "The environment the resource is being created for. Test, production etc."
}

variable "ENVIRONMENT_SHORT" {
  type        = string
  description = "The environment the resource is being created for. Short name for length restrictions."
}

variable "APPLICATION_NAME" {
  type        = string
  description = "The name of the application."
}

variable "KEY_VAULT_NAME" {
  type        = string
  description = "Key Vault name prefix (max 24 chars with environment suffix)."
}

variable "GITHUB_ACTIONS_OBJECT_ID" {
  type        = string
  description = "GitHub Actions service principal object ID (principal ID) for Key Vault access."
  default     = ""
}
