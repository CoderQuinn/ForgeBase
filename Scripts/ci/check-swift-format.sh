#!/usr/bin/env bash

set -euo pipefail

readonly script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repository_root="$(cd "${script_directory}/../.." && pwd)"

main() {
    cd "${repository_root}"

    xcrun swift-format lint \
        --strict \
        --configuration .swift-format \
        --recursive \
        Package.swift Sources Tests

    echo "swift-format strict lint passed with no diagnostics."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
