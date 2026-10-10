$ErrorActionPreference = "Continue"
$NAMESPACE = "vllm-gemma-3-x86"

Write-Host "=================== POD STATUS ==================="
oc get pods -n $NAMESPACE

Write-Host "`n=================== MEMORY USAGE ==================="
oc adm top pod -n $NAMESPACE

$POD_NAME = (oc get pods -n $NAMESPACE -l app=gemma-1b-baked -o jsonpath='{.items[0].metadata.name}')
if ([string]::IsNullOrWhiteSpace($POD_NAME)) {
    Write-Error "Could not find a running pod."
    exit 1
}

Write-Host "`n=================== POD EVENTS ==================="
oc describe pod $POD_NAME -n $NAMESPACE | Select-String -Pattern "(?i)Events:" -Context 0,20

Write-Host "`n=================== RESTART / TERMINATION LOGS ==================="
oc logs $POD_NAME -n $NAMESPACE --previous 2>$null || Write-Host "No previous terminated container found (No restarts detected)."

Write-Host "`n=================== ACTIVE POD LOGS (Tail 50) ==================="
oc logs $POD_NAME -n $NAMESPACE --tail=50
