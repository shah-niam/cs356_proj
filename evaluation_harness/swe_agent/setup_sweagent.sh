#!/bin/bash
# One-time SWE-agent setup for run_infer.py: clones SWE-agent v1.1.0 next to this directory
# (evaluation_harness/SWE-agent), creates its conda env, and copies in sweagent_overrides/.
# Safe to re-run: it skips what already exists and re-applies the overrides.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SWEA="$HERE/../SWE-agent"
ENV_NAME=${CONDA_ENV:-sweagent1.1.0}

[ -d "$SWEA" ] || git clone --depth 1 --branch v1.1.0 https://github.com/SWE-agent/SWE-agent.git "$SWEA"

source "$(conda info --base)/etc/profile.d/conda.sh"
conda env list | grep -q "^$ENV_NAME " || conda create -n "$ENV_NAME" python=3.11 -y
conda run -n "$ENV_NAME" pip install -q -e "$SWEA"

cp -r "$HERE/sweagent_overrides/." "$SWEA/"
echo "SWE-agent ready at $(cd "$SWEA" && pwd) (conda env: $ENV_NAME)"
