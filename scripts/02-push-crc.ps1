$ErrorActionPreference = "Stop"
$NAMESPACE = "vllm-gemma-3-x86"

Write-Host "Extracting CRC Ingress CA..."
oc extract secret/router-ca --keys=tls.crt -n openshift-ingress-operator --to=.
if ($LASTEXITCODE -ne 0) { throw "Failed to extract CA cert." }

$REGISTRY_HOST = (oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
if ([string]::IsNullOrWhiteSpace($REGISTRY_HOST)) { throw "Failed to retrieve registry host." }

$CRC_IP = (crc ip)
if ([string]::IsNullOrWhiteSpace($CRC_IP)) { throw "Failed to retrieve CRC IP." }

try {
    Write-Host "Configuring Podman Machine DNS and CA for $REGISTRY_HOST at $CRC_IP..."
    podman machine ssh "echo '$CRC_IP $REGISTRY_HOST' | sudo tee -a /etc/hosts"
    podman machine ssh "sudo mkdir -p /etc/containers/certs.d/$REGISTRY_HOST"
    
    # Pipe local cert to podman machine
    Get-Content tls.crt | podman machine ssh "sudo tee /etc/containers/certs.d/$REGISTRY_HOST/ca.crt > /dev/null"

    Write-Host "Logging into CRC registry..."
    $TOKEN = (oc whoami -t)
    podman login -u kubeadmin -p $TOKEN $REGISTRY_HOST
    if ($LASTEXITCODE -ne 0) { throw "Podman login failed." }

    Write-Host "Tagging and pushing image..."
    podman tag gemma-1b-vllm-local:latest "$REGISTRY_HOST/$NAMESPACE/gemma-1b-vllm:latest"
    podman push "$REGISTRY_HOST/$NAMESPACE/gemma-1b-vllm:latest"
    if ($LASTEXITCODE -ne 0) { throw "Podman push failed." }

    Write-Host "Push complete."
} finally {
    Remove-Item -Path tls.crt -Force -ErrorAction SilentlyContinue
}
