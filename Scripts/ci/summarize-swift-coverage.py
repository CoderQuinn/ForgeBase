#!/usr/bin/env python3

import argparse
import json
import sys
from pathlib import Path
from typing import List, Optional, Tuple


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize SwiftPM line coverage for ForgeBase production sources."
    )
    parser.add_argument("--coverage-json", type=Path, required=True)
    parser.add_argument("--repository-root", type=Path, required=True)
    parser.add_argument("--minimum-line-coverage", type=float, required=True)
    return parser.parse_args()


def relative_production_path(filename: str, repository_root: Path) -> Optional[Path]:
    source_path = Path(filename).resolve()
    try:
        relative_path = source_path.relative_to(repository_root)
    except ValueError:
        return None

    if len(relative_path.parts) < 3 or relative_path.parts[0] != "Sources":
        return None
    if relative_path.parts[1] not in {"ForgeBase", "ForgeBaseC"}:
        return None
    return relative_path


def main() -> int:
    arguments = parse_arguments()
    repository_root = arguments.repository_root.resolve()

    with arguments.coverage_json.open(encoding="utf-8") as coverage_file:
        coverage = json.load(coverage_file)

    production_files: List[Tuple[Path, int, int]] = []
    for file_coverage in coverage["data"][0]["files"]:
        relative_path = relative_production_path(
            file_coverage["filename"], repository_root
        )
        if relative_path is None:
            continue

        line_summary = file_coverage["summary"]["lines"]
        production_files.append(
            (relative_path, line_summary["covered"], line_summary["count"])
        )

    if not production_files:
        print("error: coverage JSON contains no ForgeBase production sources", file=sys.stderr)
        return 2

    production_files.sort(key=lambda item: str(item[0]))
    covered_lines = sum(item[1] for item in production_files)
    executable_lines = sum(item[2] for item in production_files)
    line_coverage = covered_lines / executable_lines * 100
    instrumented_targets = sorted({item[0].parts[1] for item in production_files})

    print(f"Instrumented production targets: {', '.join(instrumented_targets)}")
    print("Tests and non-Sources paths are not counted.")
    print()
    print(f"{'Production source':<55} {'Covered':>9} {'Lines':>7} {'Line %':>9}")
    print("-" * 83)
    for path, covered, count in production_files:
        percentage = covered / count * 100 if count else 100.0
        print(f"{str(path):<55} {covered:>9} {count:>7} {percentage:>8.2f}%")
    print("-" * 83)
    print(
        f"{'TOTAL':<55} {covered_lines:>9} {executable_lines:>7} "
        f"{line_coverage:>8.2f}%"
    )
    print(f"Required production line coverage: {arguments.minimum_line_coverage:.2f}%")

    if line_coverage + 1e-9 < arguments.minimum_line_coverage:
        print(
            f"error: production line coverage {line_coverage:.2f}% is below "
            f"{arguments.minimum_line_coverage:.2f}%",
            file=sys.stderr,
        )
        return 1

    print("Coverage gate passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
