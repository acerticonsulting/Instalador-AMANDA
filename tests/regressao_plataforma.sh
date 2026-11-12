#!/usr/bin/env bash
# Testa o verificador contra executáveis falsos; não acessa Docker ou rede.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT
mkdir "$WORK/bin"
export AMANDA_TEST_LOG="$WORK/comandos.log"
cat > "$WORK/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$AMANDA_TEST_LOG"
case "$1" in
  ps)
    [ "$*" = 'ps -a -q --filter label=com.docker.compose.project=amanda' ] || exit 91
    [ "$AMANDA_TEST_CASE" != daemon_down ] || exit 1
    [ "$AMANDA_TEST_CASE" != vazio ] || exit 0
    printf 'c_backend\nc_frontend\nc_postgres\n'
    [ "$AMANDA_TEST_CASE" = ausente ] || printf 'c_redis\n'
    [ "$AMANDA_TEST_CASE" != oneoff ] || printf 'c_job\n'
    case "$AMANDA_TEST_CASE" in migration_*) printf 'c_migrate\nc_seed\nc_official-db-init\nc_official-migrate\n' ;; esac
    ;;
  inspect)
    [ "$2" = --format ] && [ "$#" = 4 ] || exit 92
    [ "$AMANDA_TEST_CASE" != inspect_fail ] || exit 1
    servico=${4#c_}
    dono=amanda oneoff=False estado=running saude=healthy oom=false codigo_saida=0 reinicio=no
    if [ "$servico" = backend ]; then
      case "$AMANDA_TEST_CASE" in
        unhealthy) saude=unhealthy ;;
        starting) saude=starting ;;
        parado) estado=exited ;;
        intruso) dono=amanda_filial ;;
        oom) oom=true ;;
        sem_healthcheck) saude=none ;;
      esac
    fi
    if [ "$servico" = job ]; then oneoff=True; estado=exited; fi
    case "$servico" in migrate|seed|official-db-init|official-migrate)
      estado=exited saude=none
      case "$AMANDA_TEST_CASE" in
        migration_failed) codigo_saida=1 ;;
        migration_oom) oom=true ;;
        migration_restart) reinicio=always ;;
        migration_pending) estado=created ;;
        migration_running) estado=running ;;
      esac
      ;;
    esac
    nome=amanda_${servico//-/_}
    [ "$AMANDA_TEST_CASE" != nome_errado ] || nome=outro_backend
    printf '%s|%s|%s|%s|%s|%s|%s|%s|/%s\n' "$dono" "$servico" "$oneoff" "$estado" "$saude" "$oom" "$codigo_saida" "$reinicio" "$nome"
    ;;
  *) printf '%s\n' 'Operação Docker não permitida no verificador.' >&2; exit 93 ;;
esac
MOCK
cat > "$WORK/bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf 'curl\n' >> "$AMANDA_TEST_LOG"
for arg in "$@"; do
  case "$arg" in -k|--insecure|-X|--request|-d|--data*) exit 94 ;; esac
done
case "$AMANDA_TEST_CASE" in
  http_500) printf 500 ;;
  http_404) printf 404 ;;
  redirecionamento) printf 302 ;;
  timeout) exit 28 ;;
  tls) exit 60 ;;
  *) printf 200 ;;
esac
MOCK
chmod +x "$WORK/bin/docker" "$WORK/bin/curl"
export PATH="$WORK/bin:$PATH"
verificador="$ROOT/tests/verificar_plataforma.sh"
args=(--projeto amanda --frontend-url https://frontend.invalid/ --backend-url https://backend.invalid/health)
casos=0
for cenario in saudavel oneoff sem_healthcheck unhealthy starting parado intruso oom ausente vazio daemon_down inspect_fail http_500 http_404 redirecionamento timeout tls migration_success migration_failed migration_oom migration_restart migration_pending migration_running; do
  export AMANDA_TEST_CASE="$cenario"
  casos=$((casos+1))
  status=0
  bash "$verificador" "${args[@]}" > "$WORK/resultado" 2>&1 || status=$?
  case "$cenario" in
    saudavel|oneoff|sem_healthcheck|migration_success) esperado=0 ;;
    *) esperado=1 ;;
  esac
  if [ "$status" != "$esperado" ]; then
    printf 'FALHA: cenário %s retornou %s (esperado %s).\n' "$cenario" "$status" "$esperado" >&2
    exit 1
  fi
done
export AMANDA_TEST_CASE=saudavel
status=0
bash "$verificador" "${args[@]}" --servico api_oficial > "$WORK/resultado" 2>&1 || status=$?
[ "$status" = 1 ] || { printf '%s\n' 'FALHA: serviço adicional ausente foi aceito.' >&2; exit 1; }
: > "$AMANDA_TEST_LOG"
status=0
bash "$verificador" --projeto '../outra' --frontend-url https://frontend.invalid/ --backend-url https://backend.invalid/health > "$WORK/resultado" 2>&1 || status=$?
[ "$status" = 2 ] && [ ! -s "$AMANDA_TEST_LOG" ] || { printf '%s\n' 'FALHA: entrada inválida chegou aos serviços externos.' >&2; exit 1; }
printf 'OK: %d cenários de saúde, serviço adicional e rejeição de entrada inválida.\n' "$casos"

export AMANDA_TEST_CASE=saudavel
bash "$verificador" "${args[@]}" --nomes-padronizados > "$WORK/nomes" 2>&1
export AMANDA_TEST_CASE=nome_errado
if bash "$verificador" "${args[@]}" --nomes-padronizados > "$WORK/nomes" 2>&1; then
  printf '%s\n' 'FALHA: nome efetivo divergente foi aceito.' >&2; exit 1
fi
