#!/usr/bin/env bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/../.." && pwd)"
readonly minimum_line_coverage="${FORGEBASE_LINE_COVERAGE_MIN:-95.0}"
readonly coverage_scratch_path="${FORGEBASE_COVERAGE_SCRATCH_PATH:-${repository_root}/.build/ci-coverage}"

cd "${repository_root}"

swift package --scratch-path "${coverage_scratch_path}" clean
swift test \
    --scratch-path "${coverage_scratch_path}" \
    --enable-code-coverage

coverage_json="$(
    swift test \
        --scratch-path "${coverage_scratch_path}" \
        --show-codecov-path
)"

summary_output="$(mktemp "${TMPDIR:-/tmp}/forgebase-coverage-summary.XXXXXX")"
trap 'rm -f "${summary_output}"' EXIT

set +e
python3 "${script_directory}/summarize-swift-coverage.py" \
    --coverage-json "${coverage_json}" \
    --repository-root "${repository_root}" \
    --minimum-line-coverage "${minimum_line_coverage}" \
    | tee "${summary_output}"
summary_status=${PIPESTATUS[0]}
set -e

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        echo "## Production Swift line coverage"
        echo
        echo '```text'
        cat "${summary_output}"
        echo '```'
    } >> "${GITHUB_STEP_SUMMARY}"
fi

exit "${summary_status}"
