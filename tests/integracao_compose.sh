#!/usr/bin/env bash
# Integração opt-in: somente ferramentas, parser e arquivos de exemplo.
# Não inicia plataforma, migrations, seeds, bancos ou restaurações.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [ "$#" != 1 ]; then
  printf '%s\n' 'Uso: bash tests/integracao_compose.sh /caminho/da/fonte/AMANDA' >&2
  exit 2
fi
platform_source=$(cd -- "$1" && pwd)
for file in docker-compose.yml .env.example docker/configure.cjs docker/caddy-entry.sh docker/Caddyfile; do
  [ -f "$platform_source/$file" ] || { printf 'Fonte oficial incompleta: %s\n' "$file" >&2; exit 2; }
done
mount_root=$ROOT mount_source=$platform_source
if command -v cygpath >/dev/null 2>&1; then
  mount_root=$(cygpath -w "$ROOT")
  mount_source=$(cygpath -w "$platform_source")
fi
image=amanda-installer:wizard-validation
MSYS_NO_PATHCONV=1 docker build -f "$mount_root/docker/installer/Dockerfile" -t "$image" "$mount_root"
MSYS_NO_PATHCONV=1 docker run --rm --name "amanda_contract_compose_$$" --network none \
  --mount "type=bind,source=$mount_root,target=/suite,readonly" \
  --mount "type=bind,source=$mount_source,target=/platform,readonly" \
  -e AMANDA_PLATFORM_SOURCE=/platform --entrypoint node "$image" \
  --test /suite/tests/compose_contract.test.cjs
MSYS_NO_PATHCONV=1 docker run --rm --name "amanda_contract_resume_$$" --network none \
  --mount "type=bind,source=$mount_root,target=/suite,readonly" \
  -w /suite --entrypoint node "$image" \
  --test --test-name-pattern '^integration: old main' /suite/tests/docker_only.test.cjs
