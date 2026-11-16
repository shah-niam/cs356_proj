# Running SusVibes with SWE-agent + DeepSeek on AWS

How the `ds-full` runs were set up: SWE-agent v1.1.0 driving DeepSeek `deepseek-flash`
(V4.1-Flash-1017) over the 186 SusVibes tasks, in two fixed batches, on one EC2 instance.

## What differs from stock SusVibes / SWE-agent

| Change | File | Why |
|---|---|---|
| Import `susvibes.core.agents.sweagent` | `run_infer.py` | `susvibes.core.agents.ports` does not exist |
| Keys `sweagent_dir` / `conda_env` (resolved relative to `setting.yaml`) | `setting.yaml`, `run_infer.py` | The old keys (`dir`, `agent_env`) did not match `SWEAgentPort` |
| Configs `[default, deepseek]`, 150-call cap | `setting.yaml` | Stock configs `susvibes_eval` / `no_cache` are not shipped |
| Keep last 10 command outputs; no Anthropic cache markers | `sweagent_overrides/config/deepseek.yaml` | Smaller prompts; non-Anthropic APIs reject `cache_control` |
| Bootstrap pip before installing tree-sitter | `sweagent_overrides/tools/edit_anthropic/install.sh` | Some task images have no `pip`, which crashed setup |
| Unparseable test logs are recorded as an errored report | `susvibes/eval/task.py` | One such task (paramiko) aborted the whole scoring run |

Unchanged: SWE-agent's default tools and prompts, temperature 0, the 30-second per-command limit.

## 1. Server

EC2, Ubuntu 24.04 **x86_64**, 300-500 GB gp3, SSH from your IP only.

- `m7i-flex.large` (2 vCPU, 8 GB, ~$0.10/hr): `run_all.sh` runs 1 task at a time with a 60-minute
  test timeout. A batch takes about a day.
- `m7i.2xlarge` (8 vCPU, 32 GB, ~$0.40/hr): 4 tasks at a time, a batch in roughly 5-8 hours.

```bash
ssh -i ~/Downloads/susvibes.pem ubuntu@<public IP>   # the IP changes on every start
```

## 2. Install

```bash
sudo apt-get update && sudo apt-get install -y git tmux build-essential
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER          # log out and back in before using docker
docker login                           # free Docker Hub account: 200 pulls / 6 h instead of 100

curl -fsSLo mc.sh https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash mc.sh -b -p ~/miniconda3 && ~/miniconda3/bin/conda init bash && source ~/.bashrc
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

git clone https://github.com/shah-niam/cs356_proj ~/susvibes && cd ~/susvibes
conda create -n sv python=3.11 -y && conda activate sv
pip install -r requirements.txt && pip install -e .
bash evaluation_harness/swe_agent/setup_sweagent.sh
```

## 3. API key

Create `~/ds.env` with `nano ~/ds.env` (typing into nano avoids paste problems), then `chmod 600 ~/ds.env`.
Never commit this file.

```
export OPENAI_API_KEY=sk-...
export OPENAI_API_BASE=https://api.deepseek.com
```

Check: `source ~/ds.env && curl -s https://api.deepseek.com/models -H "Authorization: Bearer $OPENAI_API_KEY"`
should list `deepseek-flash`.

## 4. Run

The 186 tasks are split into `batches/batch1.json` (87) and `batches/batch2.json` (99), a fixed
`random.Random(42)` shuffle of the dataset order. Both batches use the run name `ds-full`, so their
outputs land together and scoring reuses earlier reports.

```bash
cd ~/susvibes/evaluation_harness/swe_agent
# one-task smoke test, server stays on
NO_SHUTDOWN=1 ./run_all.sh ds-smoke '["psf__requests_74ea7cf7a6a27a4eeb2ae24e162bcc942a6706d5"]'
# a batch, in the background; the server powers off when it finishes
tmux new -d -s run './run_all.sh ds-full "$(cat batches/batch1.json)"'
```

Watch it:

```bash
tail -3 ~/runs/ds-full.log                                   # phase and timestamps
cat ~/runs/ds-full/run_batch_exit_statuses.yaml              # finished tasks and how they ended
tail -f $(ls -t ~/runs/ds-full/*/*.info.log | head -1)       # one task, live
```

## 5. Results

```bash
python tally_scores.py --run_id ds-full                                        # all tasks scored so far
python tally_scores.py --run_id ds-full --instance_ids "$(cat batches/batch1.json)"
```

Reports: `~/susvibes/logs/eval/ds-full/none/ds-full/<instance_id>/report.json`.
Agent work: `~/runs/ds-full/<instance_id>/` (trajectory `.traj`) and `~/runs/ds-full/predictions.json`.

To re-score only errored tasks: `python -m susvibes.eval.core --run_id ds-full --resume --predictions_path ~/runs/ds-full/predictions.json`.

**Copy results off before terminating the instance**; terminating deletes the disk. Stopping keeps it
(about $1/day for the disk).

```bash
# on your Mac
rsync -avz -e "ssh -i ~/Downloads/susvibes.pem" \
  ubuntu@<ip>:'~/susvibes/logs/eval ~/runs' ./susvibes-results/
```

## Caveats for analysis

- **Memorized code.** The model sometimes reproduces the upstream project's code from memory, including
  its later security fix. Search trajectories for "upstream".
- **Internet access.** Containers can reach the internet, and one agent ran `pip download Zope==4.0` to
  fetch the original package. Flag these: `grep -lE "pip download|git clone|curl|wget" ~/runs/ds-full/*/*.traj`.
- **Default limits.** The 30-second command limit cuts off long test runs, and `git` can hang on its
  interactive pager until that limit. Both are SWE-agent defaults, kept for comparability.
