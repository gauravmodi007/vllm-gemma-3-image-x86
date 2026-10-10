# Stage 1: Downloader (Protects vLLM dependencies)
FROM python:3.11-slim AS downloader

ENV MODEL_ID="RedHatAI/gemma-3-1b-it-quantized.w8a8"
# Note: Replace 'main' with an exact immutable commit hash once validated for full reproducibility.
ENV REVISION="main"

RUN pip install --no-cache-dir huggingface_hub==0.24.7

RUN --mount=type=secret,id=hf_token \
    python3 -c "\
from huggingface_hub import snapshot_download; \
import os; \
token = open('/run/secrets/hf_token').read().strip(); \
snapshot_download(repo_id=os.environ['MODEL_ID'], revision=os.environ['REVISION'], local_dir='/models/' + os.environ['MODEL_ID'], token=token) \
"

# Stage 2: Serving Image
# Note: Pin this to an exact image digest (e.g., @sha256:...) once AVX2/VNNI compatibility is proven.
FROM vllm/vllm-openai-cpu:latest

# Copy only the model weights from Stage 1
COPY --from=downloader /models /models

# Unset the inherited entrypoint to prevent argument collision
ENTRYPOINT []

# Launch with conservative, explicitly bounded inference limits
CMD ["python3", "-m", "vllm.entrypoints.openai.api_server", \
     "--model", "/models/RedHatAI/gemma-3-1b-it-quantized.w8a8", \
     "--port", "8000", \
     "--host", "0.0.0.0", \
     "--max-model-len", "512", \
     "--max-num-seqs", "1"]
