# OpenShift Local (CRC) 1B Quantized Baked Image POC - V3 (Validation Pending)

**Goal:** 
Build a two-stage container image locally with Podman containing the `RedHatAI/gemma-3-1b-it-quantized.w8a8` model weights. Push it to OpenShift Local (CRC) securely via TLS, deploy with strict inference boundaries (max context 512, 1 sequence), and validate execution.

**Execution Steps for Agent (Windows PowerShell):**
1. Verify `$env:HF_TOKEN` is exported and user is logged into CRC (`oc whoami`).
2. Run `.\scripts\01-build-local.ps1` to build the image (multi-stage to protect vLLM dependencies).
3. Run `.\scripts\02-push-crc.ps1` to configure Podman VM DNS/TLS and push the image.
4. Run `.\scripts\03-deploy.ps1` to deploy into `vllm-gemma-3-x86` with a 15-minute startup probe.
5. Run `.\scripts\04-test-inference.ps1` to test the API.
6. Run `.\scripts\05-diagnostics.ps1` to gather memory profiles, events, and termination logs.
