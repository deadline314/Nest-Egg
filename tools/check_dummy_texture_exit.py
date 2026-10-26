#!/usr/bin/env python3
"""Reject DummyTexture leaks in full-suite logs despite legacy fixture exit filters."""
import argparse
import pathlib


def scan_logs(paths):
    count = 0
    samples = []
    for path in paths:
        with path.open(errors="replace") as stream:
            for number, line in enumerate(stream, 1):
                if "DummyTexture" in line and "leaked at exit" in line:
                    count += 1
                    if len(samples) < 32:
                        samples.append(f"{path}:{number}: {line.strip()[:512]}")
    return count, samples


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", type=pathlib.Path)
    args = parser.parse_args()
    paths = sorted(args.logs.glob("shard_*.log"))
    if not paths:
        parser.error("no completed full-suite shard logs were found")
    count, samples = scan_logs(paths)
    for line in samples:
        print(line)
    print(f"DUMMY_TEXTURE_EXIT_CHECK logs={len(paths)} diagnostics={count}")
    return 1 if count else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except OSError as error:
        raise SystemExit(f"Cannot inspect full-suite texture diagnostics: {error}") from error
