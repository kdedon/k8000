"""Shared helpers for the RTL generators."""

import os
import sys


class Fail(Exception):
    """A source error; the generator prints it and exits 1."""


def repo_root():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def bits_for(n):
    """Smallest width w >= 1 with 2**w >= n."""
    w = 1
    while (1 << w) < n:
        w += 1
    return w


def write_outputs(name, generate, out_root):
    """Run generate() -> {relative path: text} and write each file under out_root."""
    try:
        outs = generate()
    except Fail as e:
        sys.exit(f"{name}: {e}")
    for rel, text in outs.items():
        path = os.path.join(out_root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
