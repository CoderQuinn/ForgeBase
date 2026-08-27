#!/usr/bin/env bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/../.." && pwd)"
readonly known_error_diagnostic="Sources/ForgeBase/Net/Packets/PacketBuffer.swift:31:9: error: [NeverForceUnwrap] do not force unwrap '\$0.baseAddress'"
readonly known_warning_diagnostic="Sources/ForgeBase/Net/Packets/PacketBuffer.swift:31:9: warning: [NeverForceUnwrap] do not force unwrap '\$0.baseAddress'"

validate_swift_format_result() {
    local lint_status="$1"
    local diagnostics_file="$2"
    local diagnostic_count=0
    local allowlisted_count=0

    while IFS= read -r diagnostic; do
        [[ -z "${diagnostic}" ]] && continue
        diagnostic_count=$((diagnostic_count + 1))
        case "${diagnostic}" in
            "${known_error_diagnostic}"|"${known_warning_diagnostic}")
                allowlisted_count=$((allowlisted_count + 1))
                ;;
        esac
    done < "${diagnostics_file}"

    if [[ "${lint_status}" -eq 0 ]]; then
        if [[ "${diagnostic_count}" -eq 0 ]]; then
            echo "swift-format strict lint passed with no diagnostics."
            return 0
        fi
        echo "error: swift-format exited successfully but emitted diagnostics" >&2
        return 1
    fi

    if [[ "${diagnostic_count}" -eq 1 && "${allowlisted_count}" -eq 1 ]]; then
        echo "Accepted canonical-main lint baseline: NeverForceUnwrap at PacketBuffer.swift:31"
        echo "swift-format strict lint passed with exactly one allowlisted diagnostic."
        return 0
    fi

    echo "error: nonzero swift-format exit requires exactly one allowlisted diagnostic" >&2
    return 1
}

main() {
    cd "${repository_root}"

    local diagnostics_file
    diagnostics_file="$(mktemp "${TMPDIR:-/tmp}/forgebase-format-diagnostics.XXXXXX")"

    set +e
    xcrun swift-format lint \
        --strict \
        --configuration .swift-format \
        --recursive \
        Package.swift Sources Tests \
        2>&1 | tee "${diagnostics_file}"
    local lint_status=${PIPESTATUS[0]}
    set -e

    local validation_status=0
    validate_swift_format_result "${lint_status}" "${diagnostics_file}" || validation_status=$?
    rm -f "${diagnostics_file}"
    return "${validation_status}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
