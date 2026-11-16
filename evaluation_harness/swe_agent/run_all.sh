#!/bin/bash
# Unattended run: agent phase (retried up to 3x; finished tasks are skipped), then scoring,
# then power-off so an idle server stops billing.
#
#   ./run_all.sh <run_name> [instance-ids JSON]
#   ./run_all.sh ds-full "$(cat batches/batch1.json)"
#
# Env vars: ENV_FILE (default ~/ds.env, must export OPENAI_API_KEY and OPENAI_API_BASE),
# MODEL (default openai/deepseek-flash), RUNS_DIR (default ~/runs), NO_SHUTDOWN=1 to stay on.
# Agent output: $RUNS_DIR/<run_name>/   Log: $RUNS_DIR/<run_name>.log
# Scores: logs/eval/<run_name>/none/<run_name>/   (tally with tally_scores.py)
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
source "${ENV_FILE:-$HOME/ds.env}"
source "$(conda info --base)/etc/profile.d/conda.sh" && conda activate sv

RUN=${1:-ds-full}; IDS=${2:-}
MODEL=${MODEL:-openai/deepseek-flash}
RUNS_DIR=${RUNS_DIR:-$HOME/runs}
OUT=$RUNS_DIR/$RUN; LOG=$RUNS_DIR/$RUN.log; mkdir -p "$RUNS_DIR"

# Fit parallelism to the machine: 4 workers on 8+ CPUs; otherwise 1, with a longer test timeout.
if [ "$(nproc)" -ge 8 ]; then W=4; else W=1; export SV_RUN_TIMEOUT=3600; fi
EXTRA=(); [ -n "$IDS" ] && EXTRA=(--instance_ids "$IDS")

cd "$HERE"
for attempt in 1 2 3; do
  echo "=== agent pass $attempt ($W workers, $MODEL) $(date) ===" >> "$LOG"
  python run_infer.py --dataset_path "$ROOT/datasets/default/susvibes_dataset.jsonl" \
    --model "$MODEL" --run_name "$RUN" --output_dir "$OUT" --num_workers "$W" \
    "${EXTRA[@]}" >> "$LOG" 2>&1 && break
done

cd "$ROOT"
echo "=== scoring $(date) ===" >> "$LOG"
python -m susvibes.eval.core --run_id "$RUN" --max_workers "$W" \
  --predictions_path "$OUT/predictions.json" "${EXTRA[@]}" >> "$LOG" 2>&1
python "$HERE/tally_scores.py" --run_id "$RUN" >> "$LOG" 2>&1
echo "=== done $(date) ===" >> "$LOG"
[ "${NO_SHUTDOWN:-0}" = 1 ] || sudo shutdown -h now
