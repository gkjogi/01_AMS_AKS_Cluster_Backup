# 1. Define the Azure Storage Resources
resource "azurerm_resource_group" "velero-BSL" {
  name     = "velero-BSL-backup-rg"
  location = "East US"
}

resource "azurerm_storage_account" "velero-BSL" {
  name                     = "velerobslstorageaccount"
  resource_group_name      = azurerm_resource_group.velero-BSL.name
  location                 = azurerm_resource_group.velero-BSL.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "velero-BSL" {
  name                  = "velero-bsl-backups"
  storage_account_name  = azurerm_storage_account.velero-BSL.name
  container_access_type = "private"
}

# 2. Define the velero-BSL-BSL BackupStorageLocation (BSL) via Kubernetes Provider
#resource "kubernetes_manifest" "velero-BSL_bsl" {
#  manifest = {
#    "apiVersion" = "velero.io/v1"
#    "kind"       = "BackupStorageLocation"
#    "metadata" = {
#      "name"      = "default"
#      "namespace" = "velero"
#    }
#    "spec" = {
#      "provider" = "azure"
#      "objectStorage" = {
#        "bucket" = azurerm_storage_container.velero-BSL.name
#      }
#      "config" = {
#        "resourceGroup"  = azurerm_resource_group.velero-BSL.name
#        "storageAccount" = azurerm_storage_account.velero-BSL.name
#        "subscriptionId" = "your-azure-subscription-id"
#      }
#      "credential" = {
#        "name" = "cloud-credentials"
#        "key"  = "cloud"
#      }
#      "default" = true
#    }
#  }
#}
