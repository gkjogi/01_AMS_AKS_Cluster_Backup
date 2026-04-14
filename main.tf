# 1. PROVIDERS & SETTINGS
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm    = { source = "hashicorp/azurerm", version = "~> 4.0" }
    time       = { source = "hashicorp/time", version = "~> 0.11" }
    helm       = { source = "hashicorp/helm", version = "~> 2.12" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.24" }
    random     = { source = "hashicorp/random", version = "~> 3.0" }
    kubectl    = { source  = "gavinbunney/kubectl", version = "~> 1.14" }
  }
}

provider "kubectl" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  load_config_file       = false
}
provider "azurerm" {
  features {}
}
provider "time" {} 
resource "random_id" "id" {
  byte_length = 4
}






###########################>>>>>>>>>    CORE INFRASTRUCTURE  <<<<<<<<<<<<<<#########################


# Resource_Group + Container_Registry + AKS + Storage_Account + Storage_Container 

resource "azurerm_resource_group" "main1" {
  name     = "RG-AKS-Enterprise-Backup"
  location = "CentralUS"
}

resource "azurerm_container_registry" "acr" {
  name                = "acr${random_id.id.hex}"
  resource_group_name = azurerm_resource_group.main1.name
  location            = azurerm_resource_group.main1.location
  sku                 = "Standard"
  admin_enabled       = true
}

# 3. AKS CLUSTER WITH CSI & WORKLOAD IDENTITY
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-cluster"
  location            = azurerm_resource_group.main1.location
  resource_group_name = azurerm_resource_group.main1.name
  dns_prefix          = "aksbackup"

  identity { type = "SystemAssigned" }

  # Required for Velero Workload Identity & CSI Snapshots
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  
  storage_profile {
    #disk_csi_driver_enabled      = true
    snapshot_controller_enabled = true
  }

  default_node_pool {
    name       = "system"
    vm_size    = "Standard_D2s_v3"
    node_count = 1
  }

  network_profile {
    network_plugin = "azure"
  }
}


# 6. VELERO HELM DEPLOYMENT
provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  }
}

resource "helm_release" "velero" {
  name       = "velero"
  repository = "https://vmware-tanzu.github.io/helm-charts" 
  chart      = "velero"
  namespace  = "velero"
  create_namespace = true 

  values = [
    yamlencode({
      configuration = {
        # Wrap these in [ ] to make them arrays
        backupStorageLocation = [{
          name     = "default"
          provider = "azure"
          bucket   = azurerm_storage_container.velero.name  #"your-container-name" # Update this to your blob container name
          config = {
            resourceGroup  = azurerm_resource_group.main1.name  #"RG-AKS-Enterprise-Backup"
            storageAccount = azurerm_storage_account.velero.name  #"veleroeed1aa6c"
          }
        }]
        volumeSnapshotLocation = [{
          name     = "default"
          provider = "azure"
          config = {
            resourceGroup = azurerm_resource_group.main1.name  #"RG-AKS-Enterprise-Backup"
          }
        }]
      }

     # Workload Identity Settings
      serviceAccount = {
        server = {
          annotations = {
            "azure.workload.identity/client-id" = azurerm_user_assigned_identity.velero.client_id
          }
        }
      }
      
      podLabels = {
        "azure.workload.identity/use" = "true"
      }


      # Ensure initContainers is set if using the Azure plugin
      initContainers = [
        {
          name  = "velero-plugin-for-microsoft-azure"
          image = "velero/velero-plugin-for-microsoft-azure:v1.9.0" # Use latest compatible version
          volumeMounts = [
            {
              mountPath = "/target"
              name      = "plugins"
            }
          ]
        }
      ]
    })
  ]
  # Ensure identity and storage are ready before Helm starts
  depends_on = [azurerm_role_assignment.velero_storage, azurerm_federated_identity_credential.velero]
}


resource "azurerm_federated_identity_credential" "velero" {
  name                = "velero-federated-identity"
  resource_group_name = azurerm_resource_group.main1.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.velero.id
  subject             = "system:serviceaccount:velero:velero-server"
}



provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
  
  # This tells the provider to wait if the cluster isn't reachable yet
  # config_path = "~/.kube/config" # Optional: only if you're running locally
}


# 4. VELERO BACKUP STORAGE
resource "azurerm_storage_account" "velero" {
  name                     = "velero${random_id.id.hex}"
  resource_group_name      = azurerm_resource_group.main1.name
  location                 = azurerm_resource_group.main1.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "velero" {
  name                  = "velero"
  storage_account_id    = azurerm_storage_account.velero.id
}

# 5. VELERO IDENTITY & PERMISSIONS
resource "azurerm_user_assigned_identity" "velero" {
  name                = "velero-identity"
  resource_group_name = azurerm_resource_group.main1.name
  location            = azurerm_resource_group.main1.location
}

resource "azurerm_role_assignment" "velero_storage" {
  scope                = azurerm_storage_account.velero.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.velero.principal_id
  principal_type       = "ServicePrincipal" 
  # FIX: Prevents 403 errors caused by AAD replication lag
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "velero_snapshots" {
  scope                = azurerm_resource_group.main1.id
  role_definition_name = "Disk Snapshot Contributor"
  principal_id         = azurerm_user_assigned_identity.velero.principal_id
  # CRITICAL: This satisfies ABAC conditions that filter on PrincipalType
  principal_type       = "ServicePrincipal" 
  # FIX: Prevents 403 errors caused by AAD replication lag
  skip_service_principal_aad_check = true
}




#resource "helm_release" "velero" {
#  name             = "velero"
#  repository       = "https://vmware-tanzu.github.io/helm-charts" 
#  chart            = "velero"
#  namespace        = "velero"
#  create_namespace = true

#  set {
#    name  = "configuration.backupStorageLocation.provider"
#    value = "azure"
#  }

#  set {
#   name  = "configuration.backupStorageLocation.bucket"
#    value = azurerm_storage_container.velero.name
#  }

#  set {
#    name  = "configuration.backupStorageLocation.config.resourceGroup"
#    value = azurerm_resource_group.main.name
#  }
/*
  set {
    name  = "configuration.backupStorageLocation.config.storageAccount"
    value = azurerm_storage_account.velero.name
  }

  set {
    name  = "configuration.volumeSnapshotLocation.provider"
    value = "azure"
  }

  set {
    name  = "initContainers[0].name"
    value = "velero-plugin-for-microsoft-azure"
  }

  set {
    name  = "initContainers[0].image"
    value = "velero/velero-plugin-for-microsoft-azure:v1.9.0"
  }

  set {
    name  = "initContainers[0].volumeMounts[0].mountPath"
    value = "/target"
  }

  set {
    name  = "initContainers[0].volumeMounts[0].name"
    value = "plugins"
  }

  set {
    name  = "serviceAccount.server.annotations.azure\\.workload\\.identity/client-id"
    value = azurerm_user_assigned_identity.velero.client_id
  }

  set {
    name  = "podLabels.azure\\.workload\\.identity/use"
    value = "true"
  }
}
*/

# 7. CSI SNAPSHOT CLASS (For PV Backups)
#provider "kubernetes" {
#  host                   = azurerm_kubernetes_cluster.aks.kube_config.0.host
#  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
#  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
#  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
#}

#Terraform service principal the Owner role at the subscription or resource group level.
/*
data "azurerm_subscription" "primary" {}

data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "terraform_owner_subscription" {
  scope                = data.azurerm_subscription.primary.id
  role_definition_name = "Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}
*/

#Assign Owner at Resource Group Level
/*
data "azurerm_resource_group" "velero_rg" {
  name = "RG-AKS-Enterprise-Backup"
}

data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "terraform_owner_rg" {
  scope                = data.azurerm_resource_group.velero_rg.id
  role_definition_name = "Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}


*/



# 1. Add a 60-second delay after AKS is created
resource "time_sleep" "wait_for_kubernetes" {
  depends_on = [azurerm_kubernetes_cluster.aks]
  create_duration = "60s"
}

# 2. Update the manifest to depend on the SLEEP, not the cluster
#resource "kubernetes_manifest" "vsc" {
#  manifest = {
#    "apiVersion" = "snapshot.storage.k8s.io/v1"
#    "kind"       = "VolumeSnapshotClass"
#    "metadata" = {
#      "name"   = "velero-vsc"
#      "labels" = { "velero.io/csi-volumesnapshotclass" = "true" }
#    }
#    "driver"         = "://azure.com"
#    "deletionPolicy" = "Delete"
#  }

#  # CRITICAL CHANGE HERE:
#  depends_on = [time_sleep.wait_for_kubernetes]
#}

#resource "kubectl_manifest" "vsc" {
#  yaml_body = <<YAML
#apiVersion: snapshot.storage.k8s.io/v1
#kind: VolumeSnapshotClass
#metadata:
#  name: velero-vsc
#  labels:
#    velero.io/csi-volumesnapshotclass: "true"
#driver: ://azure.com
#deletionPolicy: Delete
#YAML

#  depends_on = [time_sleep.wait_60_seconds]
#}



#resource "kubectl_manifest" "velero_schedule" {
#  yaml_body = <<YAML
#apiVersion: velero.io/v1
#kind: Schedule
#metadata:
#  name: daily-cluster-backup
#  namespace: velero
#spec:
#  schedule: "0 2 * * *"
#  template:
#    includedNamespaces: ["*"]
#    excludedNamespaces: ["kube-system"]
#    snapshotVolumes: true
#    ttl: "336h0m0s"
#YAML

#  depends_on = [helm_release.velero]
#}

