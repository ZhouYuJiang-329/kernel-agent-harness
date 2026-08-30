#!/bin/zsh
set -euo pipefail

[[ $# -eq 1 ]] || {
  echo "用法：make-runtime-portable.command PORTABLE_ROOT" >&2
  exit 2
}

PORTABLE_ROOT="${1:A}"
DSH_ROOT="${PORTABLE_ROOT}/runtime/DeepSeekHarness"
[[ "${PORTABLE_ROOT}" != "/" && -f "${DSH_ROOT}/pnpm-lock.yaml" && -x "${DSH_ROOT}/node_modules/.bin/dsh" ]] || {
  echo "便携 Harness 运行时无效：${DSH_ROOT}" >&2
  exit 1
}

# pnpm's generated shell shims contain the absolute path from the machine on
# which the runtime was installed. Replace it with a root found at runtime so
# the entire package can be moved to another folder or Mac.
IFS= read -r -d '' PORTABLE_BOOTSTRAP <<'EOF' || true
# boujoy-portable-runtime
if [ -z "${BOUJOY_DSH_ROOT:-}" ]; then
  boujoy_probe="$basedir"
  while [ "$boujoy_probe" != "/" ] && [ ! -f "$boujoy_probe/pnpm-lock.yaml" ]; do
    boujoy_probe=$(dirname "$boujoy_probe")
  done
  if [ -f "$boujoy_probe/pnpm-lock.yaml" ]; then
    BOUJOY_DSH_ROOT="$boujoy_probe"
    export BOUJOY_DSH_ROOT
  fi
fi
EOF
export PORTABLE_BOOTSTRAP

SHIM_COUNT=0
while IFS= read -r -d '' shim; do
  /usr/bin/grep -Iq . "${shim}" || continue
  /usr/bin/perl -0pi -e '
    s{/(?:[^/:"\n]+/)*DeepSeekHarness(?=/node_modules/\.pnpm/)}{\${BOUJOY_DSH_ROOT}}g;
    if (index($_, "\${BOUJOY_DSH_ROOT}") >= 0 && index($_, "# boujoy-portable-runtime") < 0) {
      s{(basedir=[^\n]*\n)}{$1 . $ENV{PORTABLE_BOOTSTRAP}}e;
    }
  ' "${shim}"
  if /usr/bin/grep -q 'boujoy-portable-runtime' "${shim}"; then
    (( SHIM_COUNT += 1 ))
  fi
done < <(/usr/bin/find "${DSH_ROOT}/node_modules" -type f -path '*/node_modules/.bin/*' -print0)

# This pnpm bookkeeping path is not used by the packaged runtime. Keeping the
# developer machine's global store path here leaks a username and can confuse
# later offline maintenance.
if [[ -f "${DSH_ROOT}/node_modules/.modules.yaml" ]]; then
  /usr/bin/perl -pi -e 's{^(\s*"storeDir":\s*).*$}{$1".pnpm-store",}' "${DSH_ROOT}/node_modules/.modules.yaml"
fi

PYTHON_BIN="${PORTABLE_ROOT}/runtime/python/bin/python3"
if [[ ! -x "${PYTHON_BIN}" ]]; then
  PYTHON_BIN="$(/usr/bin/which python3 2>/dev/null || true)"
fi
[[ -x "${PYTHON_BIN}" ]] || {
  echo "需要 Python 3 来计算便携软链接的相对路径。" >&2
  exit 1
}

LINK_COUNT=0
for profile_root in "${DSH_ROOT}/home/profiles/node_modules" "${DSH_ROOT}/clean-home/profiles/node_modules"; do
  [[ -d "${profile_root}" ]] || continue
  while IFS= read -r -d '' link; do
    relative_name="${link#${profile_root}/}"
    if [[ "${relative_name}" == '@deepseek-ai/dsh' ]]; then
      target="${DSH_ROOT}/node_modules/@deepseek-ai/dsh"
    else
      target="${DSH_ROOT}/node_modules/.pnpm/node_modules/${relative_name}"
    fi
    [[ -e "${target}" ]] || {
      echo "依赖链接目标不存在：${relative_name}" >&2
      exit 1
    }
    relative_target="$(PYTHONDONTWRITEBYTECODE=1 "${PYTHON_BIN}" -c 'import os,sys; print(os.path.relpath(sys.argv[1], os.path.dirname(sys.argv[2])))' "${target}" "${link}")"
    /bin/ln -sfn "${relative_target}" "${link}"
    (( LINK_COUNT += 1 ))
  done < <(/usr/bin/find "${profile_root}" -type l -print0)
done

ABSOLUTE_LINKS="$(/usr/bin/find "${DSH_ROOT}" -type l -lname '/*' | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
[[ "${ABSOLUTE_LINKS}" == "0" ]] || {
  echo "仍有 ${ABSOLUTE_LINKS} 个绝对软链接。" >&2
  exit 1
}
if /usr/bin/grep -RIlq '/Users/' "${DSH_ROOT}/node_modules/.bin"; then
  echo "顶层 Harness 启动脚本仍包含开发机路径。" >&2
  exit 1
fi

echo "Harness 运行时已便携化：${SHIM_COUNT} 个启动脚本，${LINK_COUNT} 个依赖链接。"
