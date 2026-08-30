#!/bin/zsh
set -euo pipefail

[[ $# -ge 1 && $# -le 2 ]] || {
  echo "用法：bundle-portable-python.command PORTABLE_ROOT [PYTHON_ROOT]" >&2
  exit 2
}

PORTABLE_ROOT="${1:A}"
PYTHON_ROOT="${2:-${BOUJOY_PYTHON_ROOT:-}}"
[[ -n "${PYTHON_ROOT}" ]] || {
  echo "请传入可搬迁的 Python 3.12 根目录，或设置 BOUJOY_PYTHON_ROOT。" >&2
  exit 2
}
PYTHON_ROOT="${PYTHON_ROOT:A}"
DESTINATION="${PORTABLE_ROOT}/runtime/python"
STAGE="$(/usr/bin/mktemp -d /tmp/boujoy-python-bundle.XXXXXX)"
BACKUP="$(/usr/bin/mktemp -d /tmp/boujoy-python-backup.XXXXXX)"
cleanup() {
  [[ "${STAGE}" == /tmp/boujoy-python-bundle.* ]] && /bin/rm -rf -- "${STAGE}"
  [[ "${BACKUP}" == /tmp/boujoy-python-backup.* ]] && /bin/rm -rf -- "${BACKUP}"
}
trap cleanup EXIT

[[ "${PORTABLE_ROOT}" != "/" && -d "${PORTABLE_ROOT}/runtime/DeepSeekHarness" ]] || {
  echo "便携包目录无效：${PORTABLE_ROOT}" >&2
  exit 1
}
[[ -x "${PYTHON_ROOT}/bin/python3.12" && -d "${PYTHON_ROOT}/lib/python3.12" && -f "${PYTHON_ROOT}/lib/libpython3.12.dylib" ]] || {
  echo "Python 3.12 源运行时不完整：${PYTHON_ROOT}" >&2
  exit 1
}

/bin/mkdir -p "${STAGE}/python/bin" "${STAGE}/python/lib/python3.12"
/bin/cp "${PYTHON_ROOT}/bin/python3.12" "${STAGE}/python/bin/python3.12"
/bin/ln -s python3.12 "${STAGE}/python/bin/python3"
/bin/cp "${PYTHON_ROOT}/lib/libpython3.12.dylib" "${STAGE}/python/lib/libpython3.12.dylib"
/usr/bin/rsync -a \
  --exclude 'site-packages/' \
  --exclude '__pycache__/' \
  "${PYTHON_ROOT}/lib/python3.12/" "${STAGE}/python/lib/python3.12/"

# Validate the exact standard-library surface used by boujoy_server.py before
# replacing a previously working portable runtime.
PYTHONDONTWRITEBYTECODE=1 "${STAGE}/python/bin/python3" -c \
  'import argparse, concurrent.futures, hashlib, hmac, ipaddress, json, socketserver, subprocess, urllib.request, xml.etree.ElementTree'

if [[ -d "${DESTINATION}" ]]; then
  /bin/mv "${DESTINATION}" "${BACKUP}/python"
fi
if ! /bin/mv "${STAGE}/python" "${DESTINATION}"; then
  [[ -d "${BACKUP}/python" ]] && /bin/mv "${BACKUP}/python" "${DESTINATION}"
  echo "便携 Python 安装失败，已恢复旧版本。" >&2
  exit 1
fi

echo "已内置便携 Python：${DESTINATION}"
/usr/bin/du -sh "${DESTINATION}"
