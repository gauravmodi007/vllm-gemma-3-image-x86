# Gemma 1B Quantized on OpenShift Local (CRC) - V3

**Status:** Configuration fixes implemented; CRC inference validation pending.

This project implements a multi-stage "baked weights" build process, deploying a tightly constrained vLLM CPU instance to OpenShift Local. It is engineered to capture detailed diagnostic data to validate x86 CPU compatibility and memory boundaries.

## Critical Improvements in V3
- **Dependency Isolation:** Model downloading occurs in a separate build stage. The vLLM runtime environment remains completely unaltered.
- **Memory Boundaries:** Enforces `--max-model-len 512`, `--max-num-seqs 1`, and `VLLM_CPU_KVCACHE_SPACE="1"`. `/dev/shm` is correctly budgeted within the 8 GiB container limit.
- **Secure Networking:** Maps the CRC Ingress CA and DNS into the Podman Machine. TLS verification is strictly enforced during image push.
- **Diagnostics:** Includes `05-diagnostics.ps1` to capture `SIGILL`, OOM (Exit 137), and `oc adm top pod` memory metrics.

## Execution (Windows PowerShell)
1. Replace `your_token_here` in the local `.env` file with your Hugging Face token. The `.env` file is excluded by `.gitignore`.
2. Load the token into the current PowerShell session (dot-sourcing is required so the variable remains available):

   ```powershell
   . .\scripts\load-hf-token.ps1
   ```

   The loader does not print the token and rejects the placeholder value.
3. `.\scripts\01-build-local.ps1`
4. `.\scripts\02-push-crc.ps1`
5. `.\scripts\03-deploy.ps1`
6. `.\scripts\04-test-inference.ps1`
7. `.\scripts\05-diagnostics.ps1` (Run this if the pod crashes or to record memory headroom)
