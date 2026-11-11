# Running the Sankey classifier on UA HPC (Puma)

Only the GPU step (embedding + reranking, `fixed_label_classifier.classify`) runs on HPC.
Data cleaning, plotting and EPS export stay on the Mac. The classifier caches each
entry under a key built from the backbone, taxonomy and prompts. Once the HPC results
are merged into the local cache, the Sankey scripts read them from the cache and never
load the 8B models.

Replace `<netid>` and `<PI_GROUP>` throughout. Your PI group is the name `va` prints
on Puma.

## 0. Mac: export the entries (already done 2026-11-06; rerun if the extraction CSVs or cleaning change)
```bash
cd ~/Documents/GitHub/weather_metrics/lit_review
DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib python3 analysis/hpc/export_classifier_entries.py
```

## 1. Mac: copy the code to Puma
Only three files and this folder are needed:
```bash
cd ~/Documents/GitHub/weather_metrics/lit_review
ssh <netid>@filexfer.hpc.arizona.edu "mkdir -p /groups/<PI_GROUP>/<netid>/weather_iv/lit_review/analysis"
rsync -av analysis/fixed_label_classifier.py analysis/sankey_taxonomy.py \
      <netid>@filexfer.hpc.arizona.edu:/groups/<PI_GROUP>/<netid>/weather_iv/lit_review/analysis/
rsync -av --exclude '*.out' --exclude hpc_cache.json analysis/hpc \
      <netid>@filexfer.hpc.arizona.edu:/groups/<PI_GROUP>/<netid>/weather_iv/lit_review/analysis/
```
If you edit the taxonomy or the prompts in `fixed_label_classifier.py` later, sync again
before the next run. Those edits change the cache key.

## 2. Puma: one-time environment setup
```bash
ssh <netid>@hpc.arizona.edu      # bastion; then type: shell
interactive -a <PI_GROUP> -t 01:00:00
bash /groups/<PI_GROUP>/<netid>/weather_iv/lit_review/analysis/hpc/setup_env.sh <PI_GROUP>
exit
```

## 3. Puma: submit the job (from a login node)
```bash
cd /groups/<PI_GROUP>/<netid>/weather_iv/lit_review/analysis/hpc
sbatch --account=<PI_GROUP> classify.slurm            # qwen3-0.6b (gap-fill) + 4b + 8b
squeue -u <netid>                                      # check status
tail -f classify_<jobid>.out
```
The log prints the share of entries labelled Other for each side. The 0.6B model sent
60–75% of endogenous entries to Other.
The 0.6B pass only fills in entries that aren't in your local 0.6B cache yet (mostly
test-set entries), so all three sizes are compared on the same entries. Your existing
0.6B labels aren't changed. For the bge robustness check, add its model IDs to
`setup_env.sh` and run `classify.slurm qwen3-0.6b qwen3-4b qwen3-8b bge`.

## 4. Mac: fetch, merge and rebuild the Sankeys
```bash
cd ~/Documents/GitHub/weather_metrics/lit_review
rsync -av <netid>@filexfer.hpc.arizona.edu:/groups/<PI_GROUP>/<netid>/weather_iv/lit_review/analysis/hpc/hpc_cache.json analysis/hpc/
python3 analysis/hpc/merge_cache.py analysis/hpc/hpc_cache.json
python3 analysis/hpc/compare_backbones.py     # Other share + agreement per size; diffs -> backbone_comparison_*.csv
for b in qwen3-4b qwen3-8b; do
  SANKEY_BACKBONE=$b DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib python3 analysis/sankey_full_corpus_baselines.py
  SANKEY_BACKBONE=$b DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib python3 analysis/sankey_frontier_baselines.py
done
```
With `SANKEY_BACKBONE` set, outputs get a suffix, for example
`sankey_full_baseline_sol_qwen3-8b_rainfall_endog.png`. Your current 0.6B figures
(no suffix) are not touched.
If a Sankey run logs `[qwen3-8b] scoring N new entries`, some entries were missing from
the HPC run. It will then try to load the 8B model on the Mac. Stop it (Ctrl-C), then
redo steps 0, 1 and 3.

## Notes
- The GPU request is one A100 MIG slice (40 GB, supports bf16). `--gres=gpu:1` can
  start sooner, but it may give you a V100 (32 GB, fp16 only). Recent PyTorch CUDA
  12.8+ wheels have dropped V100 support, so keep the A100 request unless the queue
  is long.
- `hf download` in `setup_env.sh` assumes compute nodes can reach huggingface.co.
  If they can't, run that loop on the file-transfer node instead, with the same `HF_HOME`.
