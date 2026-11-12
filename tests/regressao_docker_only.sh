#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  mount_root="$ROOT"
  if command -v cygpath >/dev/null 2>&1; then mount_root=$(cygpath -w "$ROOT"); fi
  MSYS_NO_PATHCONV=1 docker run --rm --network none --mount "type=bind,source=${mount_root},target=/suite,readonly" -w /suite node:22-bookworm node --test /suite/tests/docker_only.test.cjs /suite/tests/historical.test.cjs /suite/tests/operation_lock.test.cjs
elif command -v node >/dev/null 2>&1 && [ "$(node -p 'process.platform')" = linux ]; then
  node --test "$ROOT/tests/docker_only.test.cjs" "$ROOT/tests/historical.test.cjs" "$ROOT/tests/operation_lock.test.cjs"
else
  printf '%s\n' 'A validação do gerenciador requer Docker acessível ou Node 22 em Linux (apenas testes de desenvolvimento).' >&2
  exit 1
fi
