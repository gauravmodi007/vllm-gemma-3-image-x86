$EnvFile = Join-Path (Split-Path -Parent $PSScriptRoot) ".env"
if (-not (Test-Path -LiteralPath $EnvFile)) {
    throw "Environment file not found: $EnvFile"
}

$TokenLine = Get-Content -LiteralPath $EnvFile |
    Where-Object { $_ -match '^\s*HF_TOKEN\s*=' } |
    Select-Object -First 1
if (-not $TokenLine) {
    throw "HF_TOKEN entry not found in $EnvFile"
}

$Token = ($TokenLine -split "=", 2)[1].Trim()
if (($Token.StartsWith('"') -and $Token.EndsWith('"')) -or
    ($Token.StartsWith("'") -and $Token.EndsWith("'"))) {
    $Token = $Token.Substring(1, $Token.Length - 2)
} elseif ($Token.StartsWith('"') -or $Token.EndsWith('"') -or
    $Token.StartsWith("'") -or $Token.EndsWith("'")) {
    throw "HF_TOKEN in $EnvFile has an unmatched quote."
}

if ([string]::IsNullOrWhiteSpace($Token) -or $Token -ieq "your_token_here") {
    throw "Replace the HF_TOKEN placeholder in $EnvFile with your Hugging Face token."
}

$env:HF_TOKEN = $Token
Write-Host "HF_TOKEN loaded from .env for this PowerShell session."
