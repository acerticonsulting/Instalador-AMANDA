#!/usr/bin/env bash
# Contratos estáticos limitados e rastreáveis; não é um scanner de vulnerabilidades.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
for arquivo in instalador_single.sh docker/installer/manager.cjs docker/installer/cli.cjs legacy/instalador_single.sh legacy/instalador_apioficial.sh legacy/atualizar_apioficial.sh \
  legacy/tools/mf_operacoes_seguras.sh legacy/tools/instalar_docker_compartilhado.sh \
  tests/regressao_instalador.sh tests/regressao_plataforma.sh \
  tests/verificar_plataforma.sh tests/hooks/pre-commit tests/PLANO_DE_TESTES.md AGENTS.md; do
  [ -s "$arquivo" ] || { printf 'FALHA: arquivo obrigatório ausente/vazio: %s\n' "$arquivo" >&2; exit 1; }
done
bash --noprofile --norc -n tests/hooks/pre-commit

falhas=0
while IFS= read -r -d '' arquivo; do
  # Apenas código de provisionamento; os testes contêm exemplos destes padrões.
  if grep -Eq -- '--accept-data-loss|killall[[:space:]]+apt|rm[[:space:]].*/var/lib/dpkg/lock' "$arquivo"; then
    printf 'FALHA: operação destrutiva proibida reapareceu em %s\n' "$arquivo" >&2
    falhas=$((falhas+1))
  fi
done < <(find . -maxdepth 1 -type f -name '*.sh' -print0; find legacy -type f -name '*.sh' -print0)

# Formato do exemplo; nunca imprime valores e não carrega o arquivo como Shell.
if ! awk '
  /^[[:space:]]*($|#)/ { next }
  /^[A-Za-z_][A-Za-z0-9_]*=/ {
    key=$0; sub(/=.*/, "", key)
    if (seen[key]++) bad=1
    next
  }
  { bad=1 }
  END { exit bad }
' legacy/.env.exemplo; then
  printf '%s\n' 'FALHA: formato inválido ou chave duplicada em .env.exemplo.' >&2
  falhas=$((falhas+1))
fi

# O contrato do Python embutido depende de receber a URL como argumento.
# Não executa Python nem afirma validar os demais templates gerados.
if ! grep -Fq 'url_escolhida = sys.argv[6]' legacy/instalador_single.sh; then
  printf '%s\n' 'FALHA: argumento URL ausente na integração Python da API Oficial.' >&2
  falhas=$((falhas+1))
fi
if (( falhas )); then exit 1; fi
printf '%s\n' 'Contratos estáticos e formato do exemplo válidos.'
