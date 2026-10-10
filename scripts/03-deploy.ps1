$ErrorActionPreference = "Stop"
$NAMESPACE = "vllm-gemma-3-x86"

Write-Host "Ensuring namespace exists..."
$nsYaml = oc create namespace $NAMESPACE --dry-run=client -o yaml
$nsYaml | oc apply -f -
if ($LASTEXITCODE -ne 0) { throw "Failed to create or update namespace." }

Write-Host "Granting anyuid SCC..."
oc adm policy add-scc-to-user anyuid -z default -n $NAMESPACE
if ($LASTEXITCODE -ne 0) { throw "Failed to apply SCC." }

Write-Host "Applying Kubernetes manifests..."
oc apply -f k8s/gemma-baked-app.yaml -n $NAMESPACE
if ($LASTEXITCODE -ne 0) { throw "Failed to apply deployment manifests." }

Write-Host "Waiting for pod readiness (Timeout: 15 minutes to allow slow CPU loads)..."
oc wait --for=condition=available deployment/gemma-1b-baked -n $NAMESPACE --timeout=900s
if ($LASTEXITCODE -ne 0) { throw "Deployment did not become available. Run 05-diagnostics.ps1." }

Write-Host "Deployment is active. Proceed to 04-test-inference.ps1."
