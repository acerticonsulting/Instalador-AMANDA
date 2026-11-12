#!/usr/bin/env bash
# Prova que o comando principal falha em erro de sintaxe e suíte reprovada.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT
mkdir -p "$WORK/projeto com espacos/tests"
projeto="$WORK/projeto com espacos"
cp "$ROOT/tests/validar_instalador.sh" "$projeto/tests/validar_instalador.sh"
for suite in verificar_contratos regressao_instalador regressao_plataforma regressao_executor regressao_docker_only; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$projeto/tests/$suite.sh"
done
printf '#!/usr/bin/env bash\nif then\n' > "$projeto/invalido.sh"
status=0
bash "$projeto/tests/validar_instalador.sh" > "$WORK/saida" 2>&1 || status=$?
[ "$status" = 1 ] && grep -q 'sintaxe Bash' "$WORK/saida" || { printf '%s\n' 'FALHA: sintaxe inválida não reprovou o executor.' >&2; exit 1; }
rm -- "$projeto/invalido.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$projeto/tests/regressao_instalador.sh"
status=0
bash "$projeto/tests/validar_instalador.sh" > "$WORK/saida" 2>&1 || status=$?
[ "$status" = 1 ] && grep -q 'RESULTADO: REPROVADO' "$WORK/saida" || { printf '%s\n' 'FALHA: regressão reprovada foi aceita.' >&2; exit 1; }
printf '#!/usr/bin/env bash\nexit 0\n' > "$projeto/tests/regressao_instalador.sh"
(cd "$WORK" && bash "$projeto/tests/validar_instalador.sh") > "$WORK/saida" 2>&1
grep -q 'RESULTADO LOCAL: APROVADO' "$WORK/saida"
grep -q 'NÃO VERIFICADA' "$WORK/saida"

# The hook must still reject newly introduced whitespace after rewrite detection.
git init -q "$WORK/whitespace"
git -C "$WORK/whitespace" config user.name 'Installer test'
git -C "$WORK/whitespace" config user.email 'installer-test@example.invalid'
printf 'baseline\n' > "$WORK/whitespace/example.txt"
git -C "$WORK/whitespace" add example.txt
git -C "$WORK/whitespace" commit -qm baseline
printf 'new trailing whitespace   \n' > "$WORK/whitespace/example.txt"
git -C "$WORK/whitespace" add example.txt
if git -C "$WORK/whitespace" diff --cached --check -B -M > "$WORK/whitespace-result" 2>&1; then
  printf '%s\n' 'FALHA: validação de whitespace aceitou erro novo.' >&2
  exit 1
fi
printf '%s\n' 'OK: executor detecta erros, propaga falhas e funciona fora da raiz/em caminho com espaços.'
