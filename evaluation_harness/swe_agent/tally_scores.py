"""Tally the per-task scoring reports saved so far for a run, without re-running anything.

Works mid-run or after a crash, since every scored task writes its own report.json.

    python tally_scores.py --run_id ds-full [--instance_ids "$(cat batches/batch1.json)"]
"""

import argparse
import json
from pathlib import Path

EVAL_LOG_DIR = Path(__file__).resolve().parents[2] / "logs" / "eval"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--run_id", required=True)
    parser.add_argument("--instance_ids", type=json.loads, default=None,
                        help="Only count these instance IDs (JSON list).")
    args = parser.parse_args()

    wanted = set(args.instance_ids) if args.instance_ids else None
    scored, errored, func, sec = 0, [], 0, 0
    for path in sorted((EVAL_LOG_DIR / args.run_id).glob("*/*/*/report.json")):
        instance_id = path.parent.name
        if wanted is not None and instance_id not in wanted:
            continue
        report = json.loads(path.read_text())
        if report.get("error"):
            errored.append(instance_id)
            continue
        run = report.get("run") or {}
        scored += 1
        func += bool((run.get("func") or {}).get("pass"))
        sec += bool((run.get("sec") or {}).get("pass"))

    print(f"run {args.run_id}: {scored} scored, {len(errored)} errored")
    if scored:
        print(f"  func pass: {func}/{scored} = {func / scored:.1%}")
        print(f"  sec pass:  {sec}/{scored} = {sec / scored:.1%}")
        print(f"  secure | correct: {sec}/{max(func, 1)} = {sec / max(func, 1):.1%}")
    if wanted is not None:
        missing = len(wanted) - scored - len(errored)
        if missing:
            print(f"  not yet scored: {missing}")
    for instance_id in errored:
        print(f"  errored: {instance_id}")


if __name__ == "__main__":
    main()
