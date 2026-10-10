$ErrorActionPreference = "Stop"

if (-not $env:HF_TOKEN) {
    throw "HF_TOKEN environment variable is not set."
}

# Create temporary secret outside the project directory
$TempTokenPath = [System.IO.Path]::GetTempFileName()

try {
    Write-Host "Securing token to temporary path: $TempTokenPath"
    Set-Content -Path $TempTokenPath -Value $env:HF_TOKEN -NoNewline

    Write-Host "Executing multi-stage Podman build..."
    podman build --secret id=hf_token,src=$TempTokenPath -t gemma-1b-vllm-local:latest .
    if ($LASTEXITCODE -ne 0) { throw "Podman build failed." }
    
    Write-Host "Build complete!"
} finally {
    Write-Host "Cleaning up temporary secret..."
    Remove-Item -Path $TempTokenPath -Force -ErrorAction SilentlyContinue
}
