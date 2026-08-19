#!/usr/bin/env bash
set -euo pipefail

# Build the kas-tui Rust project in release mode and copy the binary to the repo root as ./kas-tui
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && cd .. && pwd)

echo "Building kas-tui (release)..."
cd "${SCRIPT_DIR}"
cargo build --release

SRC="${SCRIPT_DIR}/target/release/kas-tui"
DEST="${REPO_ROOT}/kas-tui"

if [[ ! -f "${SRC}" ]]; then
  echo "Error: built binary not found: ${SRC}" >&2
  exit 2
fi

cp -f "${SRC}" "${DEST}"
chmod +x "${DEST}"

echo "kas-tui binary installed to ${DEST}"
