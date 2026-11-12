#!/usr/bin/env bash
# Opt-in: socket usado apenas para containers descartáveis de ferramentas.
# A CLI recebe menu --initial 0; não executa instalação nem monta dados da plataforma.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
endpoint=${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}')}
case "$endpoint" in unix://*) socket=${endpoint#unix://} ;; *) printf '%s\n' 'Use um Docker Engine local com socket Unix.' >&2; exit 2 ;; esac
image=amanda-installer:tty-validation
docker build -f "$ROOT/docker/installer/Dockerfile" -t "$image" "$ROOT"
docker run --rm --network none \
  --mount "type=bind,source=$ROOT,target=/suite,readonly" \
  --mount "type=bind,source=$socket,target=/var/run/docker.sock" \
  -e DOCKER_HOST=unix:///var/run/docker.sock -e "AMANDA_TTY_TEST_IMAGE=$image" \
  --entrypoint node "$image" --test --test-name-pattern '^real Docker terminal transport:' /suite/tests/historical.test.cjs
