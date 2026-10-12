#!/usr/bin/env python3
"""Compare two Metadata.appintents bundles: compare.py GENERATED COMMITTED

Exits 1, naming each file, when they differ in a way that matters. Xcode's
output is not the same from one build to the next, so two things are let
through:

- nlu/nlu.lzfse is compressed differently each time. It is built from the
  phrases in root.ssu.yaml, which is compared.
- extract.actionsdata lists each parameter's resolvableInputTypes in a
  different order each time, so those lists are sorted first.
"""

import json
import sys
from pathlib import Path

UNSTABLE = {"nlu/nlu.lzfse"}


def files(bundle: Path) -> set[str]:
    found = {p.relative_to(bundle).as_posix() for p in bundle.rglob("*") if p.is_file()}
    return found - UNSTABLE


def ordered(value):
    """The JSON value with every resolvableInputTypes list sorted."""
    if isinstance(value, dict):
        return {
            key: sorted(map(ordered, item), key=json.dumps) if key == "resolvableInputTypes" else ordered(item)
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [ordered(item) for item in value]
    return value


def content(path: Path):
    data = path.read_bytes()
    return ordered(json.loads(data)) if path.name == "extract.actionsdata" else data


def main() -> int:
    generated, committed = Path(sys.argv[1]), Path(sys.argv[2])
    ours, theirs = files(committed), files(generated)
    differences = [f"{name}: only in {committed}" for name in sorted(ours - theirs)]
    differences += [f"{name}: only in {generated}" for name in sorted(theirs - ours)]
    differences += [
        f"{name}: differs" for name in sorted(ours & theirs) if content(generated / name) != content(committed / name)
    ]
    for difference in differences:
        print(difference)
    return 1 if differences else 0


if __name__ == "__main__":
    sys.exit(main())
