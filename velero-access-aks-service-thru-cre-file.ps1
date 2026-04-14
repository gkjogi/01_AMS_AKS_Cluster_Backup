# 1. Define your Azure variables
$AZURE_SUBSCRIPTION_ID=c99837e1-c73c-41c5-850c-d531d405d8cd
$AZURE_TENANT_ID=3b6fba5e-1e7b-4442-91f7-237e3666b1da
$AZURE_CLIENT_ID=84bcb377-946e-4f06-9cdc-8ab27262897a
$AZURE_CLIENT_SECRET=YD68Q~92w~vDGh6LBxh1K4RHZCIugDpfs52lAaBu
$AZURE_RESOURCE_GROUP=RG-EDJ-Enterprise-LMS-Application  
$AZURE_CLOUD_NAME=AzurePublicCloud

# 2. Create the file with ASCII encoding (required by Velero)
@"
AZURE_SUBSCRIPTION_ID=$AZURE_SUBSCRIPTION_ID
AZURE_TENANT_ID=$AZURE_TENANT_ID
AZURE_CLIENT_ID=$AZURE_CLIENT_ID
AZURE_CLIENT_SECRET=$AZURE_CLIENT_SECRET
AZURE_RESOURCE_GROUP=$AZURE_RESOURCE_GROUP
AZURE_CLOUD_NAME=$AZURE_CLOUD_NAME
"@ | Out-File -FilePath credentials-velero -Encoding ascii

# 3. Create the missing Kubernetes secret
kubectl create secret generic cloud-credentials `
    --namespace velero `
    --from-file cloud=credentials-velero

# 4. Verify the secret was created
kubectl get secret cloud-credentials -n velero

#5.  Force Velero to Re-validate
#After creating the secret, restart the Velero pod to make it "see" the new credentials immediately:

kubectl rollout restart deployment velero -n velero
Start-Sleep -s 30
velero backup-location get
