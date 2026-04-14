# 1. Find the secret name Velero is actually using
$secretName = kubectl get backupstoragelocations.velero.io -n velero -o jsonpath="{.items[0].spec.credential.name}"

# 2. Find the specific key name inside that secret
$secretKey = kubectl get backupstoragelocations.velero.io -n velero -o jsonpath="{.items[0].spec.credential.key}"

# 3. If the above are empty (standard install), fallback to defaults
if (-not $secretName) { $secretName = "cloud-credentials" }
if (-not $secretKey) { $secretKey = "cloud" }

# 4. Get and decode the data safely
$raw = kubectl -n velero get secret $secretName -o jsonpath="{.data.$secretKey}"
if ($raw) {
    [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($raw))
} else {
    Write-Error "Could not find data in secret '$secretName' with key '$secretKey'. Run 'kubectl get secrets -n velero' to check names."
}
