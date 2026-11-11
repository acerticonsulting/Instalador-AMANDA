#!/usr/bin/env bash
# Consulta uma instalação existente. Nenhum exec, restart, up ou migração.
set -euo pipefail
projeto='' frontend_url='' backend_url=''
nomes_padronizados=false
declare -a obrigatorios=(backend frontend postgres redis)
uso() {
  printf '%s\n' 'Uso: verificar_plataforma.sh --projeto NOME --frontend-url URL --backend-url URL [--servico NOME ...] [--nomes-padronizados]'
}
while (( $# )); do
  case "$1" in
    --nomes-padronizados) nomes_padronizados=true; shift ;;
    --projeto|--frontend-url|--backend-url|--servico)
      (( $# >= 2 )) || { uso >&2; exit 2; }
      case "$1" in
        --projeto) projeto="$2" ;;
        --frontend-url) frontend_url="$2" ;;
        --backend-url) backend_url="$2" ;;
        --servico) obrigatorios+=("$2") ;;
      esac
      shift 2 ;;
    --help|-h) uso; exit 0 ;;
    *) uso >&2; exit 2 ;;
  esac
done
[[ "$projeto" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { uso >&2; exit 2; }
for servico in "${obrigatorios[@]}"; do
  [[ "$servico" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || { uso >&2; exit 2; }
done
for url in "$frontend_url" "$backend_url"; do
  # URLs sem credenciais, fragmentos ou query strings, inclusive para evitar logs sensíveis.
  [[ "$url" =~ ^https?://[^/@?#[:space:]]+(/[^?#[:space:]]*)?$ ]] || { uso >&2; exit 2; }
done
for comando in docker curl timeout; do
  command -v "$comando" >/dev/null || { printf 'ERRO: dependência ausente: %s\n' "$comando" >&2; exit 2; }
done

falhas=0
declare -A encontrados=()
if ! ids=$(timeout --kill-after=5s 20s docker ps -a -q --filter "label=com.docker.compose.project=$projeto" 2>/dev/null); then
  printf '%s\n' 'FALHA: não foi possível consultar o Docker.' >&2
  exit 1
fi
if [ -z "$ids" ]; then
  printf '%s\n' 'FALHA: projeto sem containers identificados.' >&2
  exit 1
fi

formato='{{index .Config.Labels "com.docker.compose.project"}}|{{index .Config.Labels "com.docker.compose.service"}}|{{index .Config.Labels "com.docker.compose.oneoff"}}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}|{{.State.OOMKilled}}|{{.State.ExitCode}}|{{.HostConfig.RestartPolicy.Name}}|{{.Name}}'
while IFS= read -r id; do
  [ -n "$id" ] || continue
  if ! dados=$(timeout --kill-after=5s 20s docker inspect --format "$formato" "$id" 2>/dev/null); then
    printf '%s\n' 'FALHA: não foi possível inspecionar um container.' >&2
    falhas=$((falhas+1)); continue
  fi
  IFS='|' read -r dono servico oneoff estado saude oom codigo_saida reinicio nome <<< "$dados"
  if [ "$dono" != "$projeto" ] || ! [[ "$servico" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
    printf '%s\n' 'FALHA: identidade de container divergente ou incompleta.' >&2
    falhas=$((falhas+1)); continue
  fi
  if "$nomes_padronizados"; then
    if [[ "$oneoff" = True || "$oneoff" = true ]]; then
      [[ "${nome#/}" =~ ^${projeto}_[a-z0-9_]+_[a-f0-9]{32}$ ]] || { printf '%s\n' 'FALHA: nome temporário fora do padrão.' >&2; falhas=$((falhas+1)); }
    else
      sufixo=${servico//-/_}; [ "$servico" != edge ] || sufixo=caddy
      [ "${nome#/}" = "${projeto}_${sufixo}" ] || { printf 'FALHA: nome efetivo divergente para %s.\n' "$servico" >&2; falhas=$((falhas+1)); }
    fi
  fi
  [[ "$oneoff" = True || "$oneoff" = true ]] && continue
  encontrados["$servico"]=1
  case "$servico" in
    migrate|seed|official-db-init|official-migrate)
      if [ "$estado" = exited ] && [ "$codigo_saida" = 0 ] && [ "$oom" = false ] && { [ "$reinicio" = no ] || [ -z "$reinicio" ]; }; then
        printf 'OK: job %s concluído com saída 0.\n' "$servico"
      else
        printf 'FALHA: job %s não foi concluído com sucesso.\n' "$servico" >&2
        falhas=$((falhas+1))
      fi
      continue
      ;;
  esac
  if [ "$estado" != running ] || [ "$oom" != false ] || { [ "$saude" != none ] && [ "$saude" != healthy ]; }; then
    printf 'FALHA: serviço %s não está saudável.\n' "$servico" >&2
    falhas=$((falhas+1))
  elif [ "$saude" = none ]; then
    printf 'AVISO: %s está running, mas não possui healthcheck.\n' "$servico"
  else
    printf 'OK: %s está running/healthy.\n' "$servico"
  fi
done <<< "$ids"

for servico in "${obrigatorios[@]}"; do
  if [ "${encontrados[$servico]:-0}" != 1 ]; then
    printf 'FALHA: serviço obrigatório ausente: %s\n' "$servico" >&2
    falhas=$((falhas+1))
  fi
done

verificar_http() {
  local nome="$1" endereco="$2" codigo
  if ! codigo=$(timeout --kill-after=5s 25s curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 5 --max-time 20 --proto '=http,https' "$endereco" 2>/dev/null); then
    printf 'FALHA: conexão/TLS do endpoint de %s.\n' "$nome" >&2
    falhas=$((falhas+1)); return 0
  fi
  if [[ "$codigo" =~ ^2[0-9][0-9]$ ]]; then
    printf 'OK: endpoint de %s retornou HTTP %s.\n' "$nome" "$codigo"
  else
    printf 'FALHA: endpoint de %s não retornou HTTP 2xx.\n' "$nome" >&2
    falhas=$((falhas+1))
  fi
}
verificar_http frontend "$frontend_url"
verificar_http backend "$backend_url"
if (( falhas )); then
  printf 'RESULTADO DA PLATAFORMA: REPROVADO (%d verificações falharam).\n' "$falhas" >&2
  exit 1
fi
printf '%s\n' 'RESULTADO DA PLATAFORMA: CHECAGENS DE SAÚDE APROVADAS.'
printf '%s\n' 'Login, envio de mensagens, integridade dos dados e recuperação exigem os testes de homologação do plano.'
