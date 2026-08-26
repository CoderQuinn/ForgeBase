#!/usr/bin/env bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/../.." && pwd)"
readonly known_diagnostic="Sources/ForgeBase/Net/Packets/PacketBuffer.swift:31:9: error: [NeverForceUnwrap] do not force unwrap '\$0.baseAddress'"

cd "${repository_root}"

diagnostics_file="$(mktemp "${TMPDIR:-/tmp}/forgebase-format-diagnostics.XXXXXX")"
trap 'rm -f "${diagnostics_file}"' EXIT

set +e
xcrun swift-format lint \
    --strict \
    --configuration .swift-format \
    --recursive \
    Package.swift Sources Tests \
    2>&1 | tee "${diagnostics_file}"
lint_status=${PIPESTATUS[0]}
set -e

unexpected_diagnostic=false
while IFS= read -r diagnostic; do
    [[ -z "${diagnostic}" ]] && continue
    if [[ "${diagnostic}" == "${known_diagnostic}" ]]; then
        echo "Accepted canonical-main lint baseline: NeverForceUnwrap at PacketBuffer.swift:31"
    else
        unexpected_diagnostic=true
    fi
done < "${diagnostics_file}"

if [[ "${unexpected_diagnostic}" == true ]]; then
    echo "error: swift-format reported an unexpected diagnostic" >&2
    exit 1
fi

if [[ "${lint_status}" -ne 0 ]]; then
    echo "swift-format strict lint passed with only the documented baseline diagnostic."
else
    echo "swift-format strict lint passed with no diagnostics."
fi
