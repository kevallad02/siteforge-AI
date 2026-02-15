#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${ROOT_DIR}/.venv"

echo "Creating virtual environment at ${VENV_DIR}"
python3 -m venv "${VENV_DIR}"

echo "Installing tooling dependencies into .venv"
"${VENV_DIR}/bin/python" -m pip install --upgrade pip setuptools wheel hatchling editables
"${VENV_DIR}/bin/python" -m pip install -e ".[dev]" --no-build-isolation

echo "Bootstrap complete."
echo "Use:"
echo "  ${VENV_DIR}/bin/python -m ruff check ."
echo "  ${VENV_DIR}/bin/python -m pytest"
