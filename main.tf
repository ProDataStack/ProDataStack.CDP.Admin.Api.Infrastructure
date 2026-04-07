terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.16.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "terraform_state"
    container_name       = "gitstate"
  }
}

data "azurerm_client_config" "current" {
}

provider "azurerm" {
  features {}
}

# Resource group for CDP Admin API
# Import: RG was pre-created for role assignment scoping before first Terraform run
import {
  to = azurerm_resource_group.cdp_admin_api
  id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.APPLICATION_NAME}"
}

resource "azurerm_resource_group" "cdp_admin_api" {
  name     = var.APPLICATION_NAME
  location = var.LOCATION
}

# Managed identity for Workload Identity
resource "azurerm_user_assigned_identity" "cdp_admin_api_identity" {
  location            = azurerm_resource_group.cdp_admin_api.location
  name                = "cdp-admin-api-identity"
  resource_group_name = azurerm_resource_group.cdp_admin_api.name
}

# AKS cluster data source for OIDC issuer URL
data "azurerm_kubernetes_cluster" "prodatastack_aks" {
  name                = "prodatastack-cluster"
  resource_group_name = "prodatastack_shared"
}

# Federated credential for Workload Identity — links k8s service account to managed identity
resource "azurerm_federated_identity_credential" "admin_api_env" {
  name                = "cdp-admin-api-${var.ENVIRONMENT}-ns"
  resource_group_name = azurerm_resource_group.cdp_admin_api.name
  parent_id           = azurerm_user_assigned_identity.cdp_admin_api_identity.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = data.azurerm_kubernetes_cluster.prodatastack_aks.oidc_issuer_url
  subject             = "system:serviceaccount:cdp-${var.ENVIRONMENT}:cdp-admin-api-serviceaccount"
}

# AKS VNet/subnet data sources for Key Vault network rules
data "azurerm_virtual_network" "aks_network" {
  name                = "aks_vnet"
  resource_group_name = "prodatastack_shared"
}

data "azurerm_subnet" "aks_subnet" {
  name                 = "aks_subnet"
  virtual_network_name = data.azurerm_virtual_network.aks_network.name
  resource_group_name  = "prodatastack_shared"
}

# Key Vault for Admin API secrets
resource "azurerm_key_vault" "vault" {
  name                          = "${var.KEY_VAULT_NAME}-${var.ENVIRONMENT_SHORT}"
  location                      = azurerm_resource_group.cdp_admin_api.location
  resource_group_name           = azurerm_resource_group.cdp_admin_api.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  soft_delete_retention_days    = 90
  purge_protection_enabled      = var.ENVIRONMENT == "production" ? true : false
  public_network_access_enabled = true
  enable_rbac_authorization     = false

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [data.azurerm_subnet.aks_subnet.id]
  }
}

# Access policy for Admin API managed identity (Get secrets at pod startup)
resource "azurerm_key_vault_access_policy" "admin_api_identity" {
  key_vault_id = azurerm_key_vault.vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.cdp_admin_api_identity.principal_id

  secret_permissions = [
    "Get",
    "Set"
  ]
}

# Access policy for GitHub Actions service principal (Get + Set secrets during CI/CD)
resource "azurerm_key_vault_access_policy" "github_actions_sp" {
  key_vault_id = azurerm_key_vault.vault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = var.GITHUB_ACTIONS_OBJECT_ID

  secret_permissions = [
    "Get",
    "Set"
  ]
}

output "managed_identity_client_id" {
  value       = azurerm_user_assigned_identity.cdp_admin_api_identity.client_id
  description = "Client ID of the Admin API managed identity — set as AZURE_DEPLOYMENT_CLIENT_ID on the API repo"
}
