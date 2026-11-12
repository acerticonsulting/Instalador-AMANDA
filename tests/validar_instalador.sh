#!/usr/bin/env bash
# Entrada única de validação. Não carrega nem executa instaladores completos.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

uso() {
  cat <<'USO'
Uso:
  bash tests/validar_instalador.sh
  bash tests/validar_instalador.sh --plataforma --projeto NOME \
    --frontend-url https://app.exemplo.com/ \
    --backend-url https://api.exemplo.com/health [--servico NOME ...]

Sem argumentos: sintaxe de todos os scripts, contratos e regressões isoladas.
--plataforma: após os testes locais, consulta a instalação indicada (somente leitura).
Leia tests/PLANO_DE_TESTES.md para limites de cobertura e testes em homologação.
USO
}

plataforma=0
case "${1:-}" in
  '') ;;
  --help|-h) uso; exit 0 ;;
  --plataforma) plataforma=1; shift ;;
  *) uso >&2; exit 2 ;;
esac

if (( BASH_VERSINFO[0] < 4 )); then
  printf '%s\n' 'ERRO: Bash 4 ou superior é necessário.' >&2
  exit 2
fi
for comando in bash awk find grep sort mktemp timeout cmp cp chmod rm; do
  command -v "$comando" >/dev/null || { printf 'ERRO: dependência ausente: %s\n' "$comando" >&2; exit 2; }
done

WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT
cd "$ROOT"
falhas=0
scripts=0
etapas=0

# Inclui scripts novos ainda não adicionados ao Git; exclui dependências e saídas.
find . -type d \( -name .git -o -name node_modules -o -name .venv -o -name venv \
  -o -name dist -o -name build -o -name logs -o -name tmp -o -name instalador-oplanov2 \) -prune \
  -o -type f -name '*.sh' -print0 > "$WORK/scripts"
sort -z "$WORK/scripts" -o "$WORK/scripts"
while IFS= read -r -d '' arquivo; do
  scripts=$((scripts+1))
  if ! BASH_ENV= ENV= bash --noprofile --norc -n -- "$arquivo" > "$WORK/sintaxe.log" 2>&1; then
    # Não reproduzir linhas de código que possam conter credenciais.
    printf 'FALHA: sintaxe Bash em %s\n' "$arquivo" >&2
    falhas=$((falhas+1))
  fi
done < "$WORK/scripts"
if (( scripts == 0 )); then
  printf '%s\n' 'FALHA: nenhum script encontrado.' >&2
  exit 1
fi
if (( falhas )); then
  printf 'RESULTADO: REPROVADO (%d falhas em %d scripts). Regressões não executadas.\n' "$falhas" "$scripts" >&2
  exit 1
fi
printf 'OK: sintaxe de %d scripts Shell.\n' "$scripts"

executar_etapa() {
  local nome="$1" arquivo="$2" status
  etapas=$((etapas+1))
  printf '\n[%s]\n' "$nome"
  if BASH_ENV= ENV= timeout --kill-after=5s 120s bash --noprofile --norc "$ROOT/$arquivo"; then
    printf 'OK: %s\n' "$nome"
  else
    status=$?
    printf 'FALHA: %s (código %d).\n' "$nome" "$status" >&2
    falhas=$((falhas+1))
  fi
}

executar_etapa 'Contratos do instalador' tests/verificar_contratos.sh
executar_etapa 'Regressões do instalador com comandos simulados' tests/regressao_instalador.sh
executar_etapa 'Regressões do verificador de plataforma' tests/regressao_plataforma.sh
executar_etapa 'Regressões do executor de testes' tests/regressao_executor.sh
executar_etapa 'Gerenciador Docker-only (comandos simulados)' tests/regressao_docker_only.sh

if (( falhas )); then
  printf '\nRESULTADO: REPROVADO (%d de %d etapas falharam).\n' "$falhas" "$etapas" >&2
  exit 1
fi
printf '\nRESULTADO LOCAL: APROVADO (%d scripts e %d suítes).\n' "$scripts" "$etapas"
if (( plataforma )); then
  BASH_ENV= ENV= bash --noprofile --norc "$ROOT/tests/verificar_plataforma.sh" "$@"
else
  printf '%s\n' 'Plataforma em execução: NÃO VERIFICADA. Use --plataforma em uma instalação existente.'
fi
