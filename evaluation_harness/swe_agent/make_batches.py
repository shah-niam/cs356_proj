"""Split the SusVibes tasks into fixed-size batches you can run one at a time.

Writes batches/batch1.json, batch2.json, ... (git-ignored). The split is a seeded shuffle of the
dataset order, so the same --size and --seed always give the same batches.

    python make_batches.py --size 50              # 50 + 50 + 50 + 36
    python make_batches.py --size 87,99           # explicit sizes: 87 + 99 (the original ds-full split)

With a list, any tasks left over go into one final batch.
"""

import argparse
import json
import random
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATASET = HERE.parents[1] / "datasets" / "default" / "susvibes_dataset.jsonl"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--size", required=True,
                        help="Tasks per batch (e.g. 50), or a comma-separated list of batch sizes (e.g. 87,99).")
    parser.add_argument("--seed", type=int, default=42, help="Shuffle seed (default 42).")
    parser.add_argument("--dataset", type=Path, default=DATASET)
    parser.add_argument("--out_dir", type=Path, default=HERE / "batches")
    args = parser.parse_args()

    ids = [json.loads(line)["instance_id"] for line in args.dataset.read_text().splitlines() if line.strip()]
    random.Random(args.seed).shuffle(ids)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    for old in args.out_dir.glob("batch*.json"):
        old.unlink()
    sizes = [int(s) for s in args.size.split(",") if s.strip()]
    if not sizes or min(sizes) < 1:
        parser.error("--size needs positive integers")
    if len(sizes) == 1:
        sizes = [sizes[0]] * -(-len(ids) // sizes[0])
    start = 0
    for n, size in enumerate(sizes, 1):
        batch = sorted(ids[start:start + size])
        if not batch:
            break
        start += size
        path = args.out_dir / f"batch{n}.json"
        path.write_text(json.dumps(batch, indent=1) + "\n")
        print(f"{path.relative_to(HERE)}: {len(batch)} tasks")
    if start < len(ids):
        path = args.out_dir / f"batch{len(sizes) + 1}.json"
        path.write_text(json.dumps(sorted(ids[start:]), indent=1) + "\n")
        print(f"{path.relative_to(HERE)}: {len(ids) - start} tasks (remainder)")


if __name__ == "__main__":
    main()
