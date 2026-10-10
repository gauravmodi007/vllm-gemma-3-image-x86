$ErrorActionPreference = "Stop"
$NAMESPACE = "vllm-gemma-3-x86"

$ROUTE_HOST = (oc get route gemma-1b-baked -n $NAMESPACE -o jsonpath='{.spec.host}')
if ([string]::IsNullOrWhiteSpace($ROUTE_HOST)) { throw "Could not resolve API route." }

$URI = "http://$ROUTE_HOST/v1/chat/completions"

$BODY = @{
    model = "/models/RedHatAI/gemma-3-1b-it-quantized.w8a8"
    messages = @(
        @{role = "user"; content = "Explain containerization in one short sentence."}
    )
    max_tokens = 50
} | ConvertTo-Json -Depth 10

Write-Host "Sending inference test to $URI..."
try {
    $response = Invoke-RestMethod -Uri $URI -Method Post -ContentType "application/json" -Body $BODY
    Write-Host "`nResponse from Model:"
    Write-Host $response.choices[0].message.content
} catch {
    Write-Error "Inference request failed. Run 05-diagnostics.ps1 to investigate logs/restarts.`nDetails: $_"
    exit 1
}
