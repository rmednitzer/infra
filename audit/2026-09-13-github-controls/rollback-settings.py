"""Restore the three settings changed by this audit; dry-run by default."""
import argparse
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--apply", action="store_true")
args = parser.parse_args()
for path in sorted((Path(__file__).parent / "settings-before").glob("*.json")):
    previous = json.loads(path.read_text())
    base = f"repos/rmednitzer/{path.stem}"
    operations = [
        (base, "PATCH", previous["repository"]),
        (base + "/actions/permissions", "PUT", {
            "enabled": previous["actions"]["enabled"],
            "sha_pinning_required": previous["actions"]["sha_pinning_required"],
        }),
    ]
    for endpoint, method, payload in operations:
        print(endpoint, method, json.dumps(payload))
        if args.apply:
            subprocess.run(
                ["gh", "api", endpoint, "--method", method, "--input", "-"],
                input=json.dumps(payload), text=True, check=True,
                stdout=subprocess.DEVNULL,
            )
