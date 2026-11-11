#!/bin/bash
# One-time setup on Puma. Run INSIDE an interactive session on a compute node
# (modules and compiling aren't available on login nodes):
#
#   interactive -a <PI_GROUP> -t 01:00:00
#   bash $WORK/lit_review/analysis/hpc/setup_env.sh <PI_GROUP>
#
# Puts the venv and the Hugging Face model cache under /groups (500 GB) —
# /home is only 50 GB and the 4B + 8B pairs are ~48 GB.
set -euo pipefail

PI_GROUP="${1:?usage: setup_env.sh <PI_GROUP>}"
WORK="/groups/${PI_GROUP}/${USER}/weather_iv"
VENV="${WORK}/venv"
export HF_HOME="${WORK}/hf_cache"
export PYTHONNOUSERSITE=1        # ignore ~/.local, per the HPC Python docs
mkdir -p "${WORK}" "${HF_HOME}"

module load python/3.11
python3 -m venv "${VENV}"
source "${VENV}/bin/activate"
pip install --upgrade pip
# torch wheels bundle CUDA, so no cuda module is needed. transformers /
# sentence-transformers pinned to the versions used on the Mac.
pip install torch "transformers==4.57.6" "sentence-transformers==5.4.1" numpy pandas

# Pre-download the weights so the batch job doesn't spend GPU time on it.
# 4B + 8B pairs ≈ 48 GB. Add BAAI/bge-m3 BAAI/bge-reranker-v2-m3 here for
# the non-Qwen robustness backbone.
for m in Qwen/Qwen3-Embedding-0.6B Qwen/Qwen3-Reranker-0.6B \
         Qwen/Qwen3-Embedding-4B Qwen/Qwen3-Reranker-4B \
         Qwen/Qwen3-Embedding-8B Qwen/Qwen3-Reranker-8B; do
    hf download "$m"
done

python3 -c "import torch; print('torch', torch.__version__, 'cuda build', torch.version.cuda)"
echo "Setup done: venv=${VENV}  HF_HOME=${HF_HOME}"
