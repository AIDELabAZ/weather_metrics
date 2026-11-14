#!/bin/bash
# Fixed-label Sankey classifier on one Puma A100 MIG slice (40 GB) — enough
# for the qwen3-8b embedder/reranker, which are loaded one at a time.
#
# Submit from the lit_review/analysis/hpc directory on Puma:
#   sbatch --account=<PI_GROUP> classify.slurm                 # qwen3-0.6b + 4b + 8b
#   sbatch --account=<PI_GROUP> classify.slurm qwen3-8b bge    # pick backbones explicitly
#
# ~1.3k entries -> expect well under 30 min; time limit is generous.
#SBATCH --job-name=sankey_classify
#SBATCH --partition=gpu_standard
#SBATCH --gres=gpu:nvidia_a100_80gb_pcie_3g.40gb
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --mem=48gb
#SBATCH --time=02:00:00
#SBATCH --output=classify_%j.out
set -euo pipefail

# The group name Slurm was given via --account; used for the /groups path.
PI_GROUP="${SLURM_JOB_ACCOUNT:?submit with --account=<PI_GROUP>}"
WORK="/groups/${PI_GROUP}/${USER}/weather_iv"
export HF_HOME="${WORK}/hf_cache"
export PYTHONNOUSERSITE=1
HERE="${SLURM_SUBMIT_DIR}"
# VENV / SANKEY_CLASSIFIER_CACHE can be overridden with sbatch --export, e.g.
# for the V100 fallback (setup_v100.sh), which needs an older-CUDA torch.
export SANKEY_CLASSIFIER_CACHE="${SANKEY_CLASSIFIER_CACHE:-${HERE}/hpc_cache.json}"
VENV="${VENV:-${WORK}/venv}"

module load python/3.11          # load the module BEFORE activating the venv
source "${VENV}/bin/activate"

nvidia-smi
# Fail fast rather than silently running the 8B models on CPU (e.g. if the
# torch wheel's CUDA version is newer than the node's driver supports).
python3 -c "import torch, sys; ok = torch.cuda.is_available(); print('torch', torch.__version__, 'cuda available:', ok); sys.exit(0 if ok else 1)"
python3 "${HERE}/classify_on_hpc.py" "$@"
echo "Results -> ${SANKEY_CLASSIFIER_CACHE}"
