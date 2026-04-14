# 1. Create the Azure AD Application & Service Principal
resource "azuread_application" "velero" {
  display_name = "velero-backup-sp"
}

resource "azuread_service_principal" "velero" {
    client_id = azuread_application.velero.client_id 
  #application_id = azuread_application.velero.application_id
}  

resource "azuread_service_principal_password" "velero" {
  service_principal_id = azuread_service_principal.velero.id
}

# 2. Grant the Service Principal "Contributor" access to the Backup Storage Account
# Note: For tighter security, use "Storage Blob Data Contributor" instead.
resource "azurerm_role_assignment" "velero_storage_access" {
  scope                = azurerm_storage_account.velero.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.velero.object_id
}

# 3. Create the Kubernetes Secret for Velero
resource "kubernetes_secret" "velero_credentials" {
  metadata {
    name      = "cloud-credentials"
    namespace = "velero"
  }

  data = {
    cloud = <<EOF
AZURE_SUBSCRIPTION_ID=${data.azurerm_client_config.current.subscription_id}
AZURE_TENANT_ID=${data.azurerm_client_config.current.tenant_id}
AZURE_CLIENT_ID=${azuread_application.velero.client_id}
AZURE_CLIENT_SECRET=${azuread_service_principal_password.velero.value}
AZURE_RESOURCE_GROUP=${azurerm_resource_group.velero-BSL.name}
AZURE_CLOUD_NAME=AzurePublicCloud
EOF
  }

  type = "Opaque"
}

# 4. Data source to fetch your current Subscription and Tenant IDs
data "azurerm_client_config" "current" {}
