#!/usr/bin/env bash
# Configuração local do Git; não substitui um caminho de hooks já configurado.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
atual=$(git config --get core.hooksPath || true)
if [ -n "$atual" ] && [ "$atual" != tests/hooks ]; then
  printf '%s\n' 'Há outro core.hooksPath configurado. Integre o hook existente manualmente; nada foi alterado.' >&2
  exit 1
fi
hooks_padrao=$(git rev-parse --git-path hooks)
if [ -z "$atual" ]; then
  for hook in "$hooks_padrao"/*; do
    [ -f "$hook" ] || continue
    case "$hook" in *.sample) continue ;; esac
    printf '%s\n' 'Existem hooks em .git/hooks. Integre-os manualmente; nada foi alterado.' >&2
    exit 1
  done
fi
[ -s tests/hooks/pre-commit ] || exit 1
chmod +x tests/hooks/pre-commit
git config --local core.hooksPath tests/hooks
printf '%s\n' 'Validação antes dos commits ativada neste clone.'
