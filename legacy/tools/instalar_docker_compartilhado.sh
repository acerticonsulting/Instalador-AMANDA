#!/bin/bash

# Historical archive: never execute native provisioning on the host.
printf '%s\n' 'Receita histórica bloqueada. Use instalador_single.sh da raiz (100% Docker).' >&2
return 1 2>/dev/null || exit 1
# ==============================================================================
# AMANDA - Instalação e Garantia Oficial de Docker e Docker Compose
# Suporte: Ubuntu 20.04, 22.04, 24.04 (Noble), Debian 11, 12, 13 e derivados
# ==============================================================================

instalar_docker_compartilhado() {
  printf " >> Verificando e garantindo ambiente Docker e Docker Compose...\n"

  # 1. Liberar possíveis travas de pacotes no Ubuntu/Debian (unattended-upgrades, apt lock)
  local max_wait=20
  local wait_count=0
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    if [ $wait_count -eq 0 ]; then
      printf " >> Aguardando liberação do gerenciador de pacotes apt/dpkg...\n"
    fi
    sleep 2
    wait_count=$((wait_count + 1))
    if [ $wait_count -ge $max_wait ]; then
      printf '%s\n' 'APT/DPKG continua ocupado. Aguarde a operação existente terminar e tente novamente.' >&2
      return 1
    fi
  done

  # 2. Instalar dependências essenciais
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y || return 1
  apt-get install -y -o DPkg::Lock::Timeout=120 ca-certificates curl gnupg lsb-release iptables git python3 || return 1

  # 3. Verificar/Instalar Docker Engine
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    printf " >> Instalando Docker Engine...\n"
    if ! curl -fsSL https://get.docker.com | sh; then
      printf " >> Tentando instalar Docker via repositório da distribuição...\n"
      apt-get update -y
      apt-get install -y docker.io containerd
    fi
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable docker 2>/dev/null || true
    systemctl restart docker 2>/dev/null || true

    local docker_wait=0
    while [ $docker_wait -lt 15 ]; do
      docker info >/dev/null 2>&1 && break
      sleep 1
      docker_wait=$((docker_wait + 1))
    done
  fi

  if ! docker info >/dev/null 2>&1; then
    systemctl start docker 2>/dev/null || service docker start 2>/dev/null || true
    sleep 2
  fi

  # 4. Verificar/Instalar Docker Compose (v2 plugin e CLI)
  if ! docker compose version >/dev/null 2>&1; then
    printf " >> Instalando Docker Compose Plugin via APT...\n"
    apt-get update -y || return 1
    apt-get install -y docker-compose-plugin docker-compose-v2 >/dev/null 2>&1 || true
  fi

  # Fallback: baixar binário oficial estático se APT não supriu
  if ! docker compose version >/dev/null 2>&1; then
    printf " >> Baixando binário oficial do Docker Compose Standalone...\n"
    local raw_arch
    raw_arch=$(dpkg --print-architecture 2>/dev/null || uname -m)
    local compose_arch="x86_64"
    case "$raw_arch" in
      aarch64|arm64) compose_arch="aarch64" ;;
      armv7l|armhf)  compose_arch="armv7" ;;
      *)             compose_arch="x86_64" ;;
    esac

    mkdir -p /usr/local/lib/docker/cli-plugins /usr/local/bin
    if curl -fsSL "https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-${compose_arch}" -o /usr/local/lib/docker/cli-plugins/docker-compose 2>/dev/null || \
       curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${compose_arch}" -o /usr/local/lib/docker/cli-plugins/docker-compose 2>/dev/null; then
      chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
      ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose
    fi
  fi

  # 5. Adicionar usuário deploy ao grupo docker
  if id -u deploy >/dev/null 2>&1; then
    usermod -aG docker deploy 2>/dev/null || true
  fi

  if docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    printf " >> Docker e Docker Compose validados com sucesso!\n"
    return 0
  else
    printf " >> AVISO: Falha na validação do Docker/Compose.\n"
    return 1
  fi
}
verificar_docker_funcionando() {
  if ! command -v docker >/dev/null 2>&1; then
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    systemctl start docker >/dev/null 2>&1 || true
    sleep 2
    docker info >/dev/null 2>&1 || return 1
  fi
  docker compose version >/dev/null 2>&1 || command -v docker-compose >/dev/null 2>&1
}

testar_porta_tcp_ocupada() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -tlpn 2>/dev/null | grep -qE "[:.]${p}\b" && return 0
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -tlpn 2>/dev/null | grep -qE "[:.]${p}\b" && return 0
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1 && return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    docker ps --format '{{.Ports}}' 2>/dev/null | grep -qE "(^|[^0-9])${p}->" && return 0
  fi
  (echo >/dev/tcp/127.0.0.1/"$p") 2>/dev/null && return 0
  return 1
}

proxima_porta_livre() {
  local p="$1"
  while testar_porta_tcp_ocupada "$p" || \
        [ "$p" = "${backend_port:-}" ] || \
        [ "$p" = "${frontend_port:-}" ] || \
        [ "$p" = "${PORT_DB:-}" ] || \
        [ "$p" = "${PORT_REDIS:-}" ] || \
        [ "$p" = "${PORT_PGBOUNCER:-}" ] || \
        [ "$p" = "${PORT_TRANSCRIBER:-}" ] || \
        [ "$p" = "${PORT_WUZAPI:-}" ] || \
        [ "$p" = "${PORT_DISPATCHER:-}" ] || \
        [ "$p" = "${PORT_APIOFICIAL:-}" ]; do
    p=$((p + 1))
  done
  printf '%s\n' "$p"
}

resolver_portas_automaticas() {
  local silencioso="${1:-0}"
  unset PORT_DB PORT_REDIS PORT_PGBOUNCER PORT_TRANSCRIBER PORT_WUZAPI PORT_DISPATCHER PORT_APIOFICIAL
  PORT_DB=$(proxima_porta_livre 5432)
  PORT_REDIS=$(proxima_porta_livre 6379)
  PORT_PGBOUNCER=$(proxima_porta_livre 6432)
  PORT_TRANSCRIBER=$(proxima_porta_livre 4002)
  PORT_WUZAPI=$(proxima_porta_livre 8090)
  PORT_DISPATCHER=$(proxima_porta_livre 8095)
  PORT_APIOFICIAL=$(proxima_porta_livre 6000)

  export PORT_DB PORT_REDIS PORT_PGBOUNCER PORT_TRANSCRIBER PORT_WUZAPI PORT_DISPATCHER PORT_APIOFICIAL

  if [ "$silencioso" != "1" ]; then
    if [ "$PORT_DB" != "5432" ]; then
      printf " >> Porta host 5432 em uso. Postgres Docker alocado automaticamente na porta %s (5432 + %s).\n" "$PORT_DB" "$((PORT_DB - 5432))"
    fi
    if [ "$PORT_REDIS" != "6379" ]; then
      printf " >> Porta host 6379 em uso. Redis Docker alocado automaticamente na porta %s (6379 + %s).\n" "$PORT_REDIS" "$((PORT_REDIS - 6379))"
    fi
    if [ "$PORT_PGBOUNCER" != "6432" ]; then
      printf " >> Porta host 6432 em uso. PgBouncer Docker alocado automaticamente na porta %s (6432 + %s).\n" "$PORT_PGBOUNCER" "$((PORT_PGBOUNCER - 6432))"
    fi
    if [ "$PORT_TRANSCRIBER" != "4002" ]; then
      printf " >> Porta host 4002 em uso. Transcrição Docker alocada automaticamente na porta %s (4002 + %s).\n" "$PORT_TRANSCRIBER" "$((PORT_TRANSCRIBER - 4002))"
    fi
    if [ "$PORT_WUZAPI" != "8090" ]; then
      printf " >> Porta host 8090 em uso. Wuzapi Docker alocado automaticamente na porta %s (8090 + %s).\n" "$PORT_WUZAPI" "$((PORT_WUZAPI - 8090))"
    fi
    if [ "$PORT_DISPATCHER" != "8095" ]; then
      printf " >> Porta host 8095 em uso. Dispatcher Docker alocado automaticamente na porta %s (8095 + %s).\n" "$PORT_DISPATCHER" "$((PORT_DISPATCHER - 8095))"
    fi
    if [ "$PORT_APIOFICIAL" != "6000" ]; then
      printf " >> Porta host 6000 em uso. API Oficial Docker alocada automaticamente na porta %s (6000 + %s).\n" "$PORT_APIOFICIAL" "$((PORT_APIOFICIAL - 6000))"
    fi
  fi
}

limpar_conteineres_conflitantes() {
  local compose_dir_alvo="${1:-${compose_dir:-}}"
  local proj_name="${2:-${empresa:-amanda}}"
  if [ -n "$compose_dir_alvo" ] && [ -f "${compose_dir_alvo}/docker-compose.yml" ]; then
    (cd "$compose_dir_alvo" && docker compose -p "${proj_name}" down 2>/dev/null || true)
  fi

  local c
  for c in "${proj_name}_postgres" "${proj_name}_redis" "${proj_name}_pgbouncer" "${proj_name}_backend" "${proj_name}_frontend" "${proj_name}_apioficial" "${proj_name}_wuzapi" "${proj_name}_campaign_dispatcher" "${proj_name}_transcricao"; do
    if docker ps -a --format '{{.Names}}' | grep -qw "$c"; then
      docker rm -f "$c" >/dev/null 2>&1 || true
    fi
  done
  sleep 1
}
