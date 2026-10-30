#!/usr/bin/env python3
"""Regenerate pins.bzl from NVIDIA's CUDA redistributable manifest.

    python3 bazel/cuda/toolkit/update_pins.py 13.4.3

Reads the published manifest for that release, picks out the components
//bazel/cuda needs, and rewrites the version and sha256 lines in place. Run
it from the repository root; it writes nothing else and makes no network
requests beyond the one manifest fetch.
"""

import json
import re
import sys
import urllib.request
from pathlib import Path

BASE = "https://developer.download.nvidia.com/compute/cuda/redist/"
PLATFORM = "linux-x86_64"
PINS = Path(__file__).with_name("pins.bzl")

# Must match the _component() calls in pins.bzl, in order.
COMPONENTS = [
    "cuda_nvcc",
    "libnvvm",
    "cuda_crt",
    "cuda_cudart",
    "cuda_culibos",
    "cccl",
    "cuda_profiler_api",
]


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    version = sys.argv[1]

    url = f"{BASE}redistrib_{version}.json"
    with urllib.request.urlopen(url, timeout=120) as response:
        manifest = json.load(response)

    text = PINS.read_text()
    missing = [c for c in COMPONENTS if c not in manifest]
    if missing:
        print(f"not in {url}: {', '.join(missing)}", file=sys.stderr)
        return 1

    for component in COMPONENTS:
        entry = manifest[component]
        platform = entry.get(PLATFORM)
        if platform is None:
            print(f"{component}: no {PLATFORM} build in {version}", file=sys.stderr)
            return 1
        pattern = re.compile(
            r'(_component\("' + re.escape(component) + r'", ")[^"]+(", ")[^"]+(")'
        )
        text, count = pattern.subn(
            lambda m: m.group(1) + entry["version"] + m.group(2) + platform["sha256"] + m.group(3),
            text,
        )
        if count != 1:
            print(f"{component}: {count} pin lines in pins.bzl, expected 1", file=sys.stderr)
            return 1

    text = re.sub(r'(CUDA_VERSION = ")[^"]+(")', r"\g<1>" + version + r"\g<2>", text, count=1)
    PINS.write_text(text)
    print(f"pins.bzl updated to CUDA {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
