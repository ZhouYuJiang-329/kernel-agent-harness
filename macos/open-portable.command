#!/bin/zsh
# Run this file from the root of an extracted portable package.  Starting the
# executable directly keeps the package root available even when macOS would
# App-Translocate an unsigned .app launched from Finder.
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP="${SCRIPT_DIR}/Boujoy Harness.app"

if [[ ! -x "${APP}/Contents/MacOS/BoujoyHarness" ]]; then
  echo "未找到同级的 Boujoy Harness.app。请不要把启动器从分享包中单独移走。" >&2
  exit 1
fi

export BOUJOY_HARNESS_ROOT="${SCRIPT_DIR}"
if [[ -f "${SCRIPT_DIR}/boujoy-config.json" ]]; then
  export BOUJOY_HARNESS_CONFIG="${SCRIPT_DIR}/boujoy-config.json"
fi

exec "${APP}/Contents/MacOS/BoujoyHarness" "$@"
