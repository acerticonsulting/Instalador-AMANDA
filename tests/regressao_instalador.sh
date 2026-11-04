#!/usr/bin/env bash
# Executa apenas funções extraídas e comandos simulados, nunca o instalador.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$ROOT/tools/mf_operacoes_seguras.sh"
WORK=$(mktemp -d)
trap 'rm -rf -- "$WORK"' EXIT
LOG="$WORK/docker.log"
export LOG
falhar() { printf 'FALHOU: %s\n' "$*" >&2; exit 1; }
extrair() {
  awk -v nome="$1" '$0 == nome "() {" { ativo=1 } ativo { print } ativo && /^}$/ { exit }' "$ROOT/instalador_single.sh"
}
for nome in mf_verificar_servicos_criticos_docker salvar_etapa carregar_etapa ferramentas_restaurar_sql_em_banco; do
  source /dev/stdin <<< "$(extrair "$nome")"
done
RED='' WHITE='' YELLOW=''
sleep() { :; }

mf_validar_empresa amanda_filial || falhar 'slug válido'
for nome in '../etc' '/tmp/alvo' 'amanda.*' '' '-amanda' 'amanda filial'; do
  if mf_validar_empresa "$nome"; then falhar "slug inválido: $nome"; fi
done

MODO=normal
docker() {
  printf '%s\n' "$*" >> "$LOG"
  case "$1 $2" in
    'ps -a')
      [[ "$*" == *'label=com.docker.compose.project=amanda'* ]] || return 90
      if [ "$MODO" = ausente ]; then return 0; fi
      if [ "$MODO" = duplicado ]; then printf 'c1\nc2\n'; else printf 'c1\n'; fi ;;
    'inspect --format')
      case "$3" in
        *Config.Labels*) if [ "$MODO" = intruso ]; then echo amanda_filial; else echo amanda; fi ;;
        *Health*) if [ "$MODO" = unhealthy ]; then echo unhealthy; else echo healthy; fi ;;
        *) echo running ;;
      esac ;;
    'inspect c1') return 0 ;;
    'volume ls') echo volume_amanda ;;
    'volume inspect') echo amanda ;;
    'volume rm') [ "$MODO" != falha_volume ] ;;
    'rm -f') [ "$MODO" != falha_container ] ;;
    'logs --tail') : ;;
    *) return 91 ;;
  esac
}

[ "$(mf_container_servico amanda backend)" = c1 ] || falhar 'resolução por labels'
MODO=ausente
if mf_container_servico amanda backend; then falhar 'serviço ausente aceito'; fi
MODO=duplicado
if mf_container_servico amanda backend; then falhar 'serviço ambíguo aceito'; fi
MODO=normal
mf_remover_recursos_instancia amanda 0 || falhar 'preservação'
if grep -q '^volume rm' "$LOG"; then falhar 'volume removido no modo preservação'; fi
mf_remover_recursos_instancia amanda 1 || falhar 'remoção identificada'
grep -qx 'volume rm volume_amanda' "$LOG" || falhar 'volume próprio não selecionado'
MODO=intruso
: > "$LOG"
if mf_remover_recursos_instancia amanda 1; then falhar 'recurso de outra empresa aceito'; fi
if grep -q '^rm ' "$LOG"; then falhar 'recurso intruso removido'; fi
for MODO in falha_container falha_volume; do
  if mf_remover_recursos_instancia amanda 1; then falhar 'falha de remoção ignorada'; fi
done

MODO=normal
if mf_verificar_servicos_criticos_docker; then falhar 'nenhum serviço aceito'; fi
mf_verificar_servicos_criticos_docker c1 || falhar 'container saudável'
MODO=unhealthy
if mf_verificar_servicos_criticos_docker c1; then falhar 'container unhealthy aceito'; fi

printf 'OUTRO=preservar\nURL=antiga\nURL=duplicada\n' > "$WORK/env"
valor='https://exemplo.test/?a=1&b=2|literal\fim'
sincronizar_porta_env URL "$valor" "$WORK/env"
sincronizar_porta_env NOVA 'valor com espaços' "$WORK/env"
grep -Fxq "URL=$valor" "$WORK/env" || falhar 'valor alterado por escape'
[ "$(grep -c '^URL=' "$WORK/env")" = 1 ] || falhar 'chave duplicada'
grep -Fxq 'NOVA=valor com espaços' "$WORK/env" || falhar 'chave ausente não inserida'
grep -Fxq 'OUTRO=preservar' "$WORK/env" || falhar 'outro campo alterado'
if sincronizar_porta_env URL $'linha1\nlinha2' "$WORK/env"; then falhar 'multilinha aceita'; fi

# Configurações são dados: metacaracteres não podem executar comandos.
titulo_literal='Cliente O'"'"'Brien "matriz" $(touch NAO_EXECUTAR) `comando` $HOME ; & | \\fim'
mf_gravar_config "$WORK/config" empresa amanda nome_titulo "$titulo_literal" github_token 'token-ficticio' repo_url 'https://exemplo.test/repo.git'
nome_titulo='' github_token='' repo_url=''
mf_carregar_config "$WORK/config" || falhar 'leitura da configuração gravada'
[ "$nome_titulo" = "$titulo_literal" ] || falhar 'metacaracteres ou aspas alterados'
[ "$github_token" = token-ficticio ] && [ "$repo_url" = https://exemplo.test/repo.git ] || falhar 'campos Git alterados'
[ ! -e NAO_EXECUTAR ] || falhar 'configuração executou comando'
# O arquivo gerado também continua legível pelos consumidores Shell legados.
( source "$WORK/config"; [ "$nome_titulo" = "$titulo_literal" ] ) || falhar 'formato legado incompatível'
cp "$WORK/config" "$WORK/antes"
if mf_gravar_config "$WORK/config" nome_titulo $'linha1\nlinha2'; then falhar 'configuração multilinha aceita'; fi
cmp -s "$WORK/config" "$WORK/antes" || falhar 'gravação inválida alterou arquivo existente'
printf 'nome_titulo=novo\ncomando invalido\n' > "$WORK/invalido"
nome_titulo=anterior
if mf_carregar_config "$WORK/invalido"; then falhar 'linha inválida aceita'; fi
[ "$nome_titulo" = anterior ] || falhar 'leitura inválida aplicou estado parcial'
printf 'PATH=/nao-usar\nBASH_ENV=/nao-usar\nSERVER_PORT=3010\n' > "$WORK/restrito"
path_anterior=$PATH
mf_carregar_config "$WORK/restrito"
[ "$PATH" = "$path_anterior" ] && [ "$SERVER_PORT" = 3010 ] || falhar 'lista de campos permitidos'

MF_INSTALADOR_ROOT="$WORK"
ARQUIVO_ETAPAS=ETAPA_INSTALACAO
empresa=amanda
mkdir "$WORK/outra-pasta"
cd "$WORK/outra-pasta"
salvar_etapa 21
carregar_etapa
[ "$etapa" = 21 ] && [ -f "$WORK/ETAPA_INSTALACAO_amanda" ] || falhar 'checkpoint fora da raiz'
[ ! -e ETAPA_INSTALACAO ] || falhar 'checkpoint relativo ao cwd'

# Simula falha SQL sem banco real. Nenhum comando de manutenção é executado.
ferramentas_pm2_parar_para_manutencao_pg() { :; }
ferramentas_psql_admin_pg_nativo() { :; }
ferramentas_garantir_role_pg_nativo() { :; }
ferramentas_pm2_aviso_retomada_manual_pg() { :; }
PG_USUARIO=teste PG_SENHA=teste PG_HOST=localhost PG_PORT=5432
psql() { [[ "$*" == *ON_ERROR_STOP=1* && "$*" == *--single-transaction* ]] || return 99; return 3; }
if ferramentas_restaurar_sql_em_banco teste "$WORK/dump.sql"; then falhar 'erro SQL ignorado'; fi

# Executa só o heredoc de checkout com git simulado.
git() {
  printf '%s\n' "$*" >> "$LOG"
  if [ "$1" = show-ref ] && [ "${BRANCH_AUSENTE:-0}" = 1 ]; then return 1; fi
  return 0
}
export -f git
awk '/^set -e$/ { if (bloco) print; next } /<<.*CHECKOUTRECENT/ { bloco=1; next } /^CHECKOUTRECENT$/ { exit } bloco { print }' "$ROOT/instalador_single.sh" > "$WORK/checkout.sh"
: > "$LOG"
bash -e "$WORK/checkout.sh" "$WORK" release/teste
grep -Fxq 'checkout -B release/teste origin/release/teste' "$LOG" || falhar 'branch escolhida ignorada'
if BRANCH_AUSENTE=1 bash -e "$WORK/checkout.sh" "$WORK" inexistente; then falhar 'branch inexistente aceita'; fi

# Entradas independentes devem parar quando instalação/atualização falha.
selecionar_instancia_apioficial() { :; }
carregar_variaveis() { :; }
verificar_instalacao_apioficial() { :; }
solicitar_porta_apioficial() { :; }
solicitar_dados_apioficial() { :; }
verificar_dns_apioficial() { :; }
configurar_nginx_apioficial() { :; }
criar_banco_apioficial() { :; }
configurar_env_apioficial() { :; }
atualizar_codigo_apioficial() { return 1; }
instalar_apioficial() { return 1; }
reiniciar_apioficial() { falhar 'reinício depois de falha'; }
atualizar_env_backend() { falhar 'integração depois de falha'; }
for arquivo in atualizar_apioficial.sh instalador_apioficial.sh; do
  source /dev/stdin <<< "$(awk '/^main\(\) \{/ { ativo=1 } ativo { print } ativo && /^}$/ { exit }' "$ROOT/$arquivo")"
  if main; then falhar "erro não propagado em $arquivo"; fi
done

# Lock do APT ocupado deve interromper o provisionamento sem matar processos.
(
  source /dev/stdin <<< "$(extrair garantir_docker_e_compose)"
  banner() { :; }
  PURPLE='' GREEN=''
  docker() { return 1; }
  fuser() { return 0; }
  killall() { falhar 'tentativa de matar APT'; }
  rm() { falhar 'tentativa de remover lock'; }
  dpkg() { falhar 'tentativa de reparar dpkg durante outra operação'; }
  apt-get() { falhar 'APT chamado com lock ocupado'; }
  if garantir_docker_e_compose; then falhar 'lock APT ignorado'; fi
  source /dev/stdin <<< "$(awk '/^instalar_docker_compartilhado\(\) \{/ { ativo=1 } ativo { print } ativo && /^}$/ { exit }' "$ROOT/tools/instalar_docker_compartilhado.sh")"
  if instalar_docker_compartilhado; then falhar 'lock APT ignorado pelo helper compartilhado'; fi
)

printf '%s\n' 'OK: isolamento, falhas Docker/SQL/APT, saúde, configuração literal, checkpoints e branch.'
