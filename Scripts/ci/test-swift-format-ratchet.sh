#!/usr/bin/env bash

set -euo pipefail

readonly ratchet_script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ratchet_script_directory}/check-swift-format.sh"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/forgebase-format-ratchet.XXXXXX")"
trap 'rm -rf "${temporary_directory}"' EXIT

assert_passes() {
    local name="$1"
    local status="$2"
    local diagnostics_file="$3"
    if ! validate_swift_format_result "${status}" "${diagnostics_file}" >/dev/null 2>&1; then
        echo "error: expected ratchet case to pass: ${name}" >&2
        exit 1
    fi
}

assert_fails() {
    local name="$1"
    local status="$2"
    local diagnostics_file="$3"
    if validate_swift_format_result "${status}" "${diagnostics_file}" >/dev/null 2>&1; then
        echo "error: expected ratchet case to fail: ${name}" >&2
        exit 1
    fi
}

empty_output="${temporary_directory}/empty"
single_allowlisted="${temporary_directory}/single-allowlisted"
duplicate_allowlisted="${temporary_directory}/duplicate-allowlisted"
unexpected_output="${temporary_directory}/unexpected"
mixed_output="${temporary_directory}/mixed"

: > "${empty_output}"
printf '%s\n' "${known_diagnostic}" > "${single_allowlisted}"
printf '%s\n%s\n' "${known_diagnostic}" "${known_diagnostic}" > "${duplicate_allowlisted}"
printf '%s\n' "unexpected diagnostic" > "${unexpected_output}"
printf '%s\n%s\n' "${known_diagnostic}" "unexpected diagnostic" > "${mixed_output}"

assert_passes "zero status with zero diagnostics" 0 "${empty_output}"
assert_passes "nonzero status with one allowlisted diagnostic" 1 "${single_allowlisted}"

assert_fails "zero status with diagnostics" 0 "${single_allowlisted}"
assert_fails "nonzero status with no diagnostics" 1 "${empty_output}"
assert_fails "nonzero status with duplicate allowlisted diagnostics" 1 "${duplicate_allowlisted}"
assert_fails "nonzero status with unexpected diagnostic" 1 "${unexpected_output}"
assert_fails "nonzero status with mixed diagnostics" 1 "${mixed_output}"

echo "swift-format ratchet self-check passed."
