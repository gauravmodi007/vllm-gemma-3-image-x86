# CRC + Podman Runbook

This runbook records the Windows/CRC setup that worked for building and running
the baked Gemma vLLM image in this repository. It is intended to be reusable
troubleshooting context for future runs.

## Environment used

- Windows PowerShell with OpenShift Local (CRC) running.
- `oc` is supplied by CRC, not necessarily on the initial `PATH`.
- Podman Desktop's `podman-machine-default` runs in WSL2.
- The project image is built locally, pushed to the CRC image registry, then
  deployed into the `vllm-gemma-3-x86` namespace.

Do not save Hugging Face tokens, OpenShift passwords, registry tokens, or other
credentials in this document, the repository, shell history, or image layers.
The credentials used during the original setup are deliberately not recorded.

## 1. Initialize `oc` and log in

In each new PowerShell session, add CRC's `oc` executable to the current
session's `PATH`:

```powershell
& crc oc-env | Invoke-Expression
oc whoami
```

If the requested operation needs cluster administration, use the locally
provided CRC administrator credentials rather than putting a password into a
script or this runbook:

```powershell
oc login -u kubeadmin https://api.crc.testing:6443
```

The developer account may not be authorized to read the image-registry route,
create the namespace, grant the `anyuid` SCC, or push an image. Those are
authorization failures, not TLS failures.

## 2. Make the Hugging Face token available to the build

The build requires `HF_TOKEN` to download the gated/private model snapshot.
An environment variable set in a different terminal or before restarting VS
Code is not necessarily available to the PowerShell process running the build.
Check availability without printing the value:

```powershell
[bool]$env:HF_TOKEN
```

The repository contains a local `.env` placeholder, and `.gitignore` excludes
`.env` and other `.env.*` files. Replace `your_token_here` in `.env` with the
real token; do not commit or share that file. Load it into the current
PowerShell session by dot-sourcing the helper (the leading dot and space are
important so the environment variable remains in the current session):

```powershell
. .\scripts\load-hf-token.ps1
```

The helper reads only the `HF_TOKEN` entry, rejects an empty value or the
placeholder, sets `$env:HF_TOKEN`, and confirms success without printing the
token. The loader must be run again in each new terminal session. Verify only
that the variable is present:

```powershell
[bool]$env:HF_TOKEN
```

When the Hugging Face CLI has already logged in, its token is normally cached at
`$HOME\.cache\huggingface\token`. The active token can be loaded into the
current PowerShell process without displaying it:

```powershell
$tokenPath = Join-Path $HOME '.cache\huggingface\token'
if (-not (Test-Path -LiteralPath $tokenPath)) {
    throw "Hugging Face token cache not found: $tokenPath"
}
$env:HF_TOKEN = (Get-Content -LiteralPath $tokenPath -Raw).Trim()
if (-not $env:HF_TOKEN) {
    throw 'Hugging Face token cache is empty.'
}
```

The project's `scripts\01-build-local.ps1` checks `$env:HF_TOKEN`, writes it to
a temporary file, and passes that file to Podman as a BuildKit/Buildah secret.
The `Containerfile` consumes it using `RUN --mount=type=secret,id=hf_token`;
the secret is not copied into the resulting image. The script removes its
temporary token file in a `finally` block.

### Podman build path on Windows

The first attempt to run `scripts\01-build-local.ps1` through the Windows
Podman client failed before the build: Podman's WSL secret handling generated a
mixed Windows/WSL path and could not create the temporary build-secret file.
The Podman VM was running, and the Windows project folder and Hugging Face
cache were mounted and readable under `/mnt/c`.

For this environment, the successful workaround was to run the same build
inside the Podman VM, using Linux paths and the cached token as the secret
source. Substitute the actual Windows username/project path if they differ:

```powershell
podman machine start
podman machine ssh "podman build --secret=id=hf_token,src=/mnt/c/Users/<username>/.cache/huggingface/token -t gemma-1b-vllm-local:latest /mnt/c/Users/<username>/Projects/vllm-gemma-3-x86-v3"
```

The build produced `localhost/gemma-1b-vllm-local:latest` in the Podman
machine. Build logs can be large and include progress output; they do not need
to be saved in the repository.

## 3. Configure the Podman VM to reach the CRC registry with TLS verification

### Find the registry hostname and export the ingress CA

As a CRC administrator, get the default registry route:

```powershell
$RegistryHost = (oc get route default-route -n openshift-image-registry `
    --template='{{ .spec.host }}').Trim()
```

Export the ingress router CA to a directory. `oc extract --to=-` did **not**
write the PEM certificate bytes to standard output in this setup; it printed
the extracted filename instead. Extracting to a directory produces `tls.crt`:

```powershell
$CaDirectory = Join-Path $env:TEMP 'crc-router-ca'
New-Item -ItemType Directory -Path $CaDirectory -Force | Out-Null
oc extract secret/router-ca --keys=tls.crt `
    -n openshift-ingress-operator --to=$CaDirectory
$CaFile = Join-Path $CaDirectory 'tls.crt'
```

The exported certificate should begin with
`-----BEGIN CERTIFICATE-----`. Do not use a file that merely contains the
`oc extract` status message.

### Add the correct DNS mapping in the Podman VM

In this CRC configuration, `crc ip` returned `127.0.0.1`. That loopback address
is useful to Windows clients but points back to the Podman VM itself when used
inside its separate WSL2 VM. As a result, mapping the registry route to `crc
ip` made the registry unreachable.

Instead, map the registry route hostname to the Podman VM's default gateway,
which is the Windows host as seen from WSL2. Get the gateway from the
`default via ...` line:

```powershell
podman machine ssh "ip route"
```

For example, if that line says `default via 172.28.144.1`, set the mapping
inside the Podman VM (replace the example address and hostname with current
values):

```powershell
podman machine ssh "echo '172.28.144.1 $RegistryHost' | sudo tee -a /etc/hosts"
```

Do not hard-code the example gateway: it can change when WSL networking is
recreated. Inspect the route again if the registry stops resolving.

### Install the CA in Podman's per-registry trust directory

The Podman VM can read files on the Windows `C:` drive under `/mnt/c`. For
example, with the CA exported under the current user's Windows temp directory:

```powershell
$CaFile = Join-Path $env:TEMP 'crc-router-ca\tls.crt'
$CaVmPath = $CaFile -replace '^([A-Za-z]):', '/mnt/$1'
$CaVmPath = $CaVmPath -replace '\\', '/'
podman machine ssh "sudo mkdir -p /etc/containers/certs.d/$RegistryHost"
podman machine ssh "sudo cp '$CaVmPath' '/etc/containers/certs.d/$RegistryHost/ca.crt'"
```

The required layout is:

```text
/etc/containers/certs.d/<registry-host>/ca.crt
```

The certificate must be the actual ingress CA PEM. A mistaken transfer left an
invalid, shorter file in this directory, and Podman correctly rejected the
registry certificate. Re-export and copy the certificate if verification fails.

Test TLS from the Podman VM before logging in:

```powershell
podman machine ssh "curl -sv --cacert /etc/containers/certs.d/$RegistryHost/ca.crt https://$RegistryHost/v2/ -o /dev/null"
```

An HTTP `401 Unauthorized` response is expected without registry credentials;
it confirms DNS, TCP/TLS connectivity, and certificate verification succeeded.
An `x509: certificate signed by unknown authority` error means the CA file,
hostname-specific certificate path, or network destination is still wrong.

### Authenticate and push without putting the token in shell history

For the initial push, the target OpenShift project had to exist and the
identity pushing the image needed the `system:image-builder` role:

```powershell
$Namespace = 'vllm-gemma-3-x86'
oc new-project $Namespace
oc policy add-role-to-user system:image-builder kubeadmin -n $Namespace
```

If the project already exists, skip `oc new-project`. Grant only the required
push role to the identity being used. Retrieve the short-lived OpenShift token
in memory and pass it to Podman over standard input:

```powershell
$RegistryToken = oc whoami -t
$RegistryToken | podman machine ssh "podman login --username kubeadmin --password-stdin $RegistryHost"
```

Then tag and push the image from within the Podman VM, where the local image
was built:

```powershell
$Image = "$RegistryHost/$Namespace/gemma-1b-vllm:latest"
podman machine ssh "podman tag localhost/gemma-1b-vllm-local:latest $Image && podman push $Image"
```

The OpenShift internal service name
`image-registry.openshift-image-registry.svc:5000` is used by the workload
inside the cluster. The external route hostname is used by Podman on the host
side to push the image.

## 4. Deploy and test

Apply the repository manifest and wait for the deployment:

```powershell
oc apply -f k8s/gemma-baked-app.yaml -n vllm-gemma-3-x86
oc rollout status deployment/gemma-1b-baked `
    -n vllm-gemma-3-x86 --timeout=900s
```

Check pod, route, and logs:

```powershell
oc get deployment,pods,service,route -n vllm-gemma-3-x86
oc logs deployment/gemma-1b-baked -n vllm-gemma-3-x86 --tail=100
```

Then use the repository's inference test:

```powershell
.\scripts\04-test-inference.ps1
```

The route is an HTTP OpenShift route, so the test URL is
`http://<route-host>/v1/chat/completions`.

You can also send a request directly from PowerShell without running the
script. This sample uses the current CRC route and the model name served by
this deployment:

```powershell
$uri = 'http://gemma-1b-baked-vllm-gemma-3-x86.apps-crc.testing/v1/chat/completions'

$body = @{
    model = '/models/RedHatAI/gemma-3-1b-it-quantized.w8a8'
    messages = @(
        @{ role = 'user'; content = 'Explain containerization in one short sentence.' }
    )
    max_tokens = 50
} | ConvertTo-Json -Depth 10

$response = Invoke-RestMethod -Uri $uri -Method Post `
    -ContentType 'application/json' -Body $body

$response.choices[0].message.content
```

If the route hostname changes, get the active host with:

```powershell
oc get route gemma-1b-baked -n vllm-gemma-3-x86 `
    -o jsonpath='{.spec.host}'
```

## 5. Startup memory failure and chosen configuration

The first deployment used a `7Gi` memory limit and
`VLLM_CPU_KVCACHE_SPACE="1"`. The model loaded, but vLLM reported that only
about `0.29/7.0 GiB` remained for KV cache, below its requested `1.0 GiB`, and
the engine exited before the health endpoint became ready. The pod's 2 GiB
memory-backed `/dev/shm` volume also consumes memory charged to the container's
memory budget.

The user chose to preserve the 1 GiB KV-cache setting and raise the pod memory
limit to `8Gi`. The manifest and README were updated accordingly, the
deployment rolled out, and the chat-completions inference test succeeded.
The current limit is in `k8s/gemma-baked-app.yaml`; if changing it again,
reassess the total pod/CRC memory budget, including `/dev/shm` and other
processes.

## Quick troubleshooting map

| Symptom | Likely cause / check |
|---|---|
| `oc` is not recognized | Run `& crc oc-env \| Invoke-Expression` in this PowerShell session. |
| Build says `HF_TOKEN` is not set | The token is not exported in this process; check `$env:HF_TOKEN` or load the local CLI cache as described above. |
| Podman cannot connect | Start the machine with `podman machine start`; confirm using `podman machine list`. |
| Podman build secret path cannot be created | Run the build inside the Podman VM with `/mnt/c/...` paths. |
| Registry route is forbidden | Log in as an authorized CRC administrator to inspect the route or configure registry permissions. |
| Registry TLS says unknown authority | Export the router CA to a directory and install its PEM at `/etc/containers/certs.d/<host>/ca.crt` inside the Podman VM. |
| Registry resolves to `127.0.0.1` inside Podman VM | Map the route host to the VM's current `ip route` default gateway, not `crc ip`. |
| Registry push says `denied` | Ensure the namespace exists and the pushing identity has `system:image-builder` in that namespace. |
| Pod starts but readiness fails on KV-cache allocation | Compare available memory in vLLM logs with `VLLM_CPU_KVCACHE_SPACE`; account for `/dev/shm` under the pod limit. |
