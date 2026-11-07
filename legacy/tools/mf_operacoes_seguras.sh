#!/usr/bin/env bash
# Biblioteca sem efeitos ao carregar. Recursos legados sem label são preservados.
mf_chave_config_permitida() {
  case "$1" in
    empresa|email_deploy|senha_deploy|senha_master|nome_titulo|numero_suporte|facebook_app_id|facebook_app_secret|github_token|repo_url|proxy|backend_port|frontend_port|versao_instalacao|commit_instalacao|perfil_otimizacao_vps|apioficial_db_name|subdominio_*|porta_*) return 0 ;;
    ALTA_PERFORMANCE|INSTALACAO_SEM_DOMINIO|BRANCH_AMANDA_ESCOLHIDA|SERVER_PORT|PORT|PORT_*|DB_*|DATABASE_*|REDIS_*|JWT_*|REACT_APP_*|BACKEND_URL|FRONTEND_URL|URL_*|API_*|TOKEN_*|USE_WHATSAPP_OFICIAL|MASTER_*|FIX_LID_JOB_CRON) return 0 ;;
    *) return 1 ;;
  esac
}

# Leitura de dados, sem source/eval, substituição de comandos ou expansão de variáveis.
# Aceita aspas simples/duplas e escapes dos arquivos Shell legados.
mf_carregar_config() {
  local _mf_cfg_file="$1" _mf_cfg_line _mf_cfg_key _mf_cfg_raw
  local _mf_cfg_out _mf_cfg_quote _mf_cfg_char _mf_cfg_next _mf_cfg_i
  local -a _mf_cfg_keys=() _mf_cfg_values=()
  [ -f "$_mf_cfg_file" ] && [ ! -L "$_mf_cfg_file" ] || return 1
  while IFS= read -r _mf_cfg_line || [ -n "$_mf_cfg_line" ]; do
    _mf_cfg_line=${_mf_cfg_line%$'\r'}
    _mf_cfg_line=${_mf_cfg_line#$'\xef\xbb\xbf'}
    [[ "$_mf_cfg_line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$_mf_cfg_line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)=(.*)$ ]] || return 1
    _mf_cfg_key=${BASH_REMATCH[1]}
    _mf_cfg_raw=${BASH_REMATCH[2]}
    mf_chave_config_permitida "$_mf_cfg_key" || continue
    _mf_cfg_out='' _mf_cfg_quote=''
    for ((_mf_cfg_i=0; _mf_cfg_i<${#_mf_cfg_raw}; _mf_cfg_i++)); do
      _mf_cfg_char=${_mf_cfg_raw:_mf_cfg_i:1}
      if [ "$_mf_cfg_quote" = "'" ]; then
        if [ "$_mf_cfg_char" = "'" ]; then _mf_cfg_quote=''; else _mf_cfg_out+=$_mf_cfg_char; fi
      elif [ "$_mf_cfg_char" = '\' ]; then
        ((_mf_cfg_i + 1 < ${#_mf_cfg_raw})) || return 1
        _mf_cfg_next=${_mf_cfg_raw:_mf_cfg_i+1:1}
        if [ "$_mf_cfg_quote" = '"' ] && [[ "$_mf_cfg_next" != [\$\`\"\\] ]]; then
          _mf_cfg_out+='\'
        else
          _mf_cfg_out+=$_mf_cfg_next
          _mf_cfg_i=$((_mf_cfg_i+1))
        fi
      elif [ "$_mf_cfg_char" = '"' ]; then
        if [ "$_mf_cfg_quote" = '"' ]; then _mf_cfg_quote=''; else _mf_cfg_quote='"'; fi
      elif [ "$_mf_cfg_char" = "'" ] && [ -z "$_mf_cfg_quote" ]; then
        _mf_cfg_quote="'"
      else
        _mf_cfg_out+=$_mf_cfg_char
      fi
    done
    [ -z "$_mf_cfg_quote" ] || return 1
    _mf_cfg_keys+=("$_mf_cfg_key")
    _mf_cfg_values+=("$_mf_cfg_out")
  done < "$_mf_cfg_file"
  # Só aplica os campos depois de validar o arquivo completo.
  for ((_mf_cfg_i=0; _mf_cfg_i<${#_mf_cfg_keys[@]}; _mf_cfg_i++)); do
    printf -v "${_mf_cfg_keys[_mf_cfg_i]}" '%s' "${_mf_cfg_values[_mf_cfg_i]}" || return 1
  done
}

mf_gravar_config() {
  local _mf_cfg_dest="$1" _mf_cfg_tmp _mf_cfg_key _mf_cfg_value
  shift
  [ ! -L "$_mf_cfg_dest" ] && (( $# % 2 == 0 )) || return 1
  _mf_cfg_tmp=$(mktemp "${_mf_cfg_dest}.XXXXXX") || return 1
  while (( $# )); do
    _mf_cfg_key="$1" _mf_cfg_value="$2"
    shift 2
    if ! mf_chave_config_permitida "$_mf_cfg_key" || [[ "$_mf_cfg_value" == *$'\n'* || "$_mf_cfg_value" == *$'\r'* ]]; then
      rm -f -- "$_mf_cfg_tmp"
      return 1
    fi
    # Mantém campos simples compatíveis com leitores legados que usam grep/cut.
    local _mf_cfg_format='%s=%s\n'
    if ! [[ "$_mf_cfg_value" =~ ^[a-zA-Z0-9_./:@%+,=!-]*$ ]]; then
      _mf_cfg_value=${_mf_cfg_value//\'/\'\\\'\'}
      _mf_cfg_format="%s='%s'\n"
    fi
    if ! printf "$_mf_cfg_format" "$_mf_cfg_key" "$_mf_cfg_value" >> "$_mf_cfg_tmp"; then
      rm -f -- "$_mf_cfg_tmp"
      return 1
    fi
  done
  chmod 600 "$_mf_cfg_tmp" && mv -f -- "$_mf_cfg_tmp" "$_mf_cfg_dest" && return 0
  rm -f -- "$_mf_cfg_tmp"
  return 1
}

mf_validar_empresa() {
  [[ "${1:-}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]
}

mf_container_servico() {
  local projeto="$1" servico="$2" ids
  mf_validar_empresa "$projeto" || return 1
  ids=$(docker ps -a -q --filter "label=com.docker.compose.project=$projeto" \
    --filter "label=com.docker.compose.service=$servico") || return 1
  # Um serviço ausente ou com múltiplas réplicas precisa de resolução explícita.
  [[ -n "$ids" && "$ids" != *$'\n'* ]] || return 1
  printf '%s\n' "$ids"
}

mf_remover_recursos_instancia() {
  local projeto="$1" apagar_dados="${2:-0}" ids recurso dono
  mf_validar_empresa "$projeto" || return 1
  [[ "$apagar_dados" == 0 || "$apagar_dados" == 1 ]] || return 1
  ids=$(docker ps -a -q --filter "label=com.docker.compose.project=$projeto") || return 1
  while IFS= read -r recurso; do
    [ -n "$recurso" ] || continue
    dono=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$recurso") || return 1
    [ "$dono" = "$projeto" ] || return 1
    # Não remover volumes anônimos implicitamente: podem conter dados compartilhados.
    docker rm -f "$recurso" || return 1
  done <<< "$ids"

  if [ "$apagar_dados" = 1 ]; then
    ids=$(docker volume ls -q --filter "label=com.docker.compose.project=$projeto") || return 1
    while IFS= read -r recurso; do
      [ -n "$recurso" ] || continue
      dono=$(docker volume inspect --format '{{index .Labels "com.docker.compose.project"}}' "$recurso") || return 1
      [ "$dono" = "$projeto" ] || return 1
      # Sem force: um volume ainda em uso deve impedir a conclusão.
      docker volume rm "$recurso" || return 1
    done <<< "$ids"
  fi
}

sincronizar_porta_env() {
  local key="$1"
  local val="$2"
  local file="$3"
  [[ "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 1
  [[ "$val" != *$'\n'* && "$val" != *$'\r'* ]] || return 1
  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  local tmp
  tmp=$(mktemp "${file}.XXXXXX") || return 1
  # Preserva proprietário e modo; ENVIRON evita escapes de sed/awk no valor.
  if ! cp -p -- "$file" "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  if MF_ENV_KEY="$key" MF_ENV_VALUE="$val" awk '
    BEGIN { key=ENVIRON["MF_ENV_KEY"]; value=ENVIRON["MF_ENV_VALUE"] }
    index($0, key "=")==1 { if (!found++) print key "=" value; next }
    { print }
    END { if (!found) print key "=" value }
  ' "$file" > "$tmp" && mv -f -- "$tmp" "$file"; then
    return 0
  fi
  rm -f -- "$tmp"
  return 1
}
