#!/bin/bash
# V100 fallback environment. The main venv's torch is built for CUDA 13, which
# dropped Volta (V100) support; this venv uses the CUDA 12.6 wheels, which
# still include it. Reuses the models already in HF_HOME.
#
#   sbatch --account=<PI_GROUP> --partition=standard --time=01:00:00 setup_v100.sh <PI_GROUP>
#   sbatch --account=<PI_GROUP> --gres=gpu:volta:1 \
#     --export=ALL,VENV=/groups/<PI_GROUP>/$USER/weather_iv/venv_v100,SANKEY_CLASSIFIER_CACHE=$PWD/hpc_cache_v100.json \
#     classify.slurm
set -euo pipefail

PI_GROUP="${1:?usage: setup_v100.sh <PI_GROUP>}"
WORK="/groups/${PI_GROUP}/${USER}/weather_iv"
VENV="${WORK}/venv_v100"
export PYTHONNOUSERSITE=1

module load python/3.11
python3 -m venv "${VENV}"
source "${VENV}/bin/activate"
pip install --upgrade pip
pip install torch --index-url https://download.pytorch.org/whl/cu126
pip install "transformers==4.57.6" "sentence-transformers==5.4.1" numpy pandas

python3 -c "import torch; print('torch', torch.__version__, 'cuda build', torch.version.cuda, 'archs', torch.cuda.get_arch_list() if torch.cuda.is_available() else 'n/a (no GPU on this node)')"
echo "Setup done: venv=${VENV}"
