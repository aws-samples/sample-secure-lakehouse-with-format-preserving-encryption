#!/usr/bin/env bash
#
# Build the shared Lambda layer containing the FF3 encryption libraries
# (ff3 + passlib). Targets Lambda's runtime platform (x86_64 manylinux).
#
# Called automatically by Terraform via terraform_data.build_fpe_layer.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAYER_DIR="${ROOT}/assets/fpe_layer/python"
REQS="${ROOT}/assets/encryption_api/requirements.txt"

mkdir -p "${LAYER_DIR}"

# Check if real packages are installed (directories like ff3/, passlib/)
# __init__.py alone doesn't count
PKG_COUNT=$(find "${LAYER_DIR}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')

if [[ "${PKG_COUNT}" -gt 0 ]]; then
  echo "Layer already built (${PKG_COUNT} packages) — skipping."
  exit 0
fi

echo "Installing FPE dependencies into ${LAYER_DIR}..."
python3 -m pip install \
    --quiet \
    --no-compile \
    --platform manylinux2014_x86_64 \
    --implementation cp \
    --python-version 3.12 \
    --only-binary=:all: \
    --target "${LAYER_DIR}" \
    -r "${REQS}" 2>&1 | tail -5

# Verify
VERIFY=$(find "${LAYER_DIR}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
if [[ "${VERIFY}" -eq 0 ]]; then
  echo "ERROR: No packages installed in ${LAYER_DIR}"
  exit 1
fi

echo "Done. ${VERIFY} packages installed."
