#!/bin/bash
MF_INSTALADOR_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || exit 1
readonly MF_INSTALADOR_ROOT
source "${MF_INSTALADOR_ROOT}/tools/mf_repositorio_amanda.sh" || exit 1
mf_solicitar_repositorio_amanda || exit 1
source "${MF_INSTALADOR_ROOT}/tools/mf_operacoes_seguras.sh" || exit 1
_mf_baileys_tools="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tools/baileys_hineken_package_json.sh"
[ -f "$_mf_baileys_tools" ] && . "$_mf_baileys_tools"

# Cores do Tema Oficial AMANDA (Brilhantes e de alto contraste em fundos escuros/pretos)
# Evita o tom escuro/preto gerado pelo código ANSI legado e garante máxima visibilidade no terminal
if [ "${COLORTERM:-}" = "truecolor" ] || [ "${COLORTERM:-}" = "24bit" ] || [ -n "${WT_SESSION:-}" ] || [[ "${TERM:-}" =~ (xterm|256color|screen|tmux|linux|alacritty|kitty) ]]; then
  PURPLE='\033[38;2;139;92;246m' # Roxo Luminoso AMANDA (#8B5CF6)
  purple='\033[38;2;139;92;246m'
  BLUE='\033[1;38;2;167;139;250m' # Lilás/Roxo Claro para números e destaques (#A78BFA)
  MAGENTA='\033[38;2;192;132;252m' # Roxo Real Claro (#C084FC)
  ROXO='\033[38;2;139;92;246m'
  GREEN='\033[1;38;2;74;222;128m'   # Verde Esmeralda Luminoso (#4ADE80 - ultra legível no fundo preto)
  WHITE='\033[1;38;2;255;255;255m' # Branco Puro Brilhante (#FFFFFF)
  RED='\033[1;38;2;248;113;113m'   # Vermelho Coral Claro (#F87171 - legível e nítido)
  YELLOW='\033[1;38;2;250;204;21m'  # Amarelo Ouro Vivo (#FACC15 - nunca marrom/preto)
  CYAN='\033[1;38;2;56;189;248m'    # Ciano Céu Luminoso (#38BDF8)
else
  PURPLE='\033[38;5;99m' # 256-cores: Roxo #875fff puro
  purple='\033[38;5;99m'
  BLUE='\033[1;94m'      # High Intensity Light Blue
  MAGENTA='\033[1;95m'   # High Intensity Light Magenta
  ROXO='\033[38;5;99m'
  GREEN='\033[1;92m'     # High Intensity Light Green (verde vivo)
  WHITE='\033[1;97m'     # High Intensity Bright White (branco puro)
  RED='\033[1;91m'       # High Intensity Light Red (vermelho vivo)
  YELLOW='\033[1;93m'    # High Intensity Light Yellow (amarelo vivo brilhante)
  CYAN='\033[1;96m'      # High Intensity Light Cyan (ciano vivo)
fi
NC='\033[0m'
RESET='\033[0m'
export PURPLE purple BLUE MAGENTA ROXO GREEN WHITE RED YELLOW CYAN NC RESET

# Variaveis Padrão
ARCH=$(uname -m)
UBUNTU_VERSION=$(lsb_release -sr)
ARQUIVO_VARIAVEIS="VARIAVEIS_INSTALACAO"
ARQUIVO_ETAPAS="ETAPA_INSTALACAO"
# Modo Alta Performance: Redis, Postgres e PgBouncer via Docker (não instala nativos)
[ -f "ALTA_PERFORMANCE_MODE" ] && mf_carregar_config ALTA_PERFORMANCE_MODE 2>/dev/null || true
FFMPEG="$(pwd)/ffmpeg.x"
FFMPEG_DIR="$(pwd)/ffmpeg"
ip_atual=$(curl -s http://checkip.amazonaws.com)
jwt_secret=$(openssl rand -base64 32)
jwt_refresh_secret=$(openssl rand -base64 32)

if [ "$EUID" -ne 0 ]; then
  echo
  printf "${WHITE} >> Este script precisa ser executado como root ${RED}ou com privilégios de superusuário${WHITE}.\n"
  echo
  sleep 2
  exit 1
fi

# Ubuntu 24 (imagem mínima) pode não trazer sudo; o instalador usa sudo em várias etapas
mf_garantir_sudo() {
  command -v sudo >/dev/null 2>&1 && return 0
  printf "${YELLOW} >> Pacote sudo não encontrado. Instalando (comum em Ubuntu 24 minimal)...${WHITE}\n"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y || return 1
  apt-get install -y sudo || return 1
  printf "${GREEN} >> sudo instalado com sucesso.${WHITE}\n"
}

mf_garantir_sudo || {
  printf "${RED} >> ERRO: não foi possível instalar sudo. Execute como root: apt update && apt install -y sudo${WHITE}\n"
  exit 1
}

# tools/*.sh: +x cedo (evita Permission denied / 127 se algum trecho executar em vez de source)
INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "${INSTALADOR_DIR}/tools" ]; then
  chmod a+rx "${INSTALADOR_DIR}/tools"/*.sh 2>/dev/null || true
fi
if [ -f "${INSTALADOR_DIR}/tools/git_sincronizar_repositorio.sh" ]; then
  # shellcheck source=/dev/null
  . "${INSTALADOR_DIR}/tools/git_sincronizar_repositorio.sh"
  type mf_garantir_tools_executaveis >/dev/null 2>&1 && mf_garantir_tools_executaveis "${INSTALADOR_DIR}/tools"
fi

# Codename APT (noble, jammy, trixie…) sem depender só de lsb-release (Ubuntu 24 minimal / Debian)
mf_detectar_codename_apt() {
  local codename id ver

  codename="$(lsb_release -cs 2>/dev/null || true)"
  if [ -n "$codename" ]; then
    printf '%s\n' "$codename"
    return 0
  fi

  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    ver="${VERSION_ID:-}"

    if [ -n "${VERSION_CODENAME:-}" ] && [ "${VERSION_CODENAME}" != "n/a" ] && [ "${VERSION_CODENAME}" != "unknown" ]; then
      printf '%s\n' "$VERSION_CODENAME"
      return 0
    fi
    if [ -n "${UBUNTU_CODENAME:-}" ]; then
      printf '%s\n' "$UBUNTU_CODENAME"
      return 0
    fi

    case "${id}:${ver}" in
      ubuntu:24.04|ubuntu:24.04*) printf '%s\n' noble; return 0 ;;
      ubuntu:22.04|ubuntu:22.04*) printf '%s\n' jammy; return 0 ;;
      ubuntu:20.04|ubuntu:20.04*) printf '%s\n' focal; return 0 ;;
      debian:13|debian:13.*)      printf '%s\n' trixie; return 0 ;;
      debian:12|debian:12.*)      printf '%s\n' bookworm; return 0 ;;
      debian:11|debian:11.*)      printf '%s\n' bullseye; return 0 ;;
    esac
  fi

  return 1
}

banner() {
  clear
  printf "${PURPLE}"
  printf "\n"
  printf "  █████╗ ███╗   ███╗ █████╗ ███╗   ██╗██████╗  █████╗ \n"
  printf " ██╔══██╗████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔══██╗\n"
  printf " ███████║██╔████╔██║███████║██╔██╗ ██║██║  ██║███████║\n"
  printf " ██╔══██║██║╚██╔╝██║██╔══██║██║╚██╗██║██║  ██║██╔══██║\n"
  printf " ██║  ██║██║ ╚═╝ ██║██║  ██║██║ ╚████║██████╔╝██║  ██║\n"
  printf " ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝ ╚═╝  ╚═╝\n"
  printf "       AMANDA - PLATAFORMA DE ATENDIMENTO MULTICANAL v1.0.0\n"
  printf "       Instalador e Gerenciador Oficial 100%% Docker\n"
  printf "${WHITE}\n"
}

# Função para manipular erros e encerrar o script
trata_erro() {
  printf "${RED}Erro encontrado na etapa $1. Encerrando o script.${WHITE}\n"
  echo "$1" >"${ARQUIVO_ETAPAS}.erro" 2>/dev/null || true
  exit 1
}

# Verificar conectividade de rede e DNS
verificar_conectividade() {
  printf "${WHITE} >> Verificando conectividade de rede...\n"
  
  # Verificar se consegue fazer ping no Google DNS
  if ! ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
    printf "${RED} >> ERRO: Sem conectividade de rede (não consegue alcançar 8.8.8.8)${WHITE}\n"
    printf "${YELLOW} >> Verifique sua conexão de internet.${WHITE}\n"
    return 1
  fi
  
  # Verificar resolução DNS
  if ! ping -c 1 -W 2 google.com >/dev/null 2>&1; then
    printf "${RED} >> ERRO: Problema com resolução DNS${WHITE}\n"
    printf "${YELLOW} >> Verifique a configuração do DNS em /etc/resolv.conf${WHITE}\n"
    printf "${YELLOW} >> Você pode tentar:${WHITE}\n"
    printf "${YELLOW} >>   echo 'nameserver 8.8.8.8' >> /etc/resolv.conf${WHITE}\n"
    printf "${YELLOW} >>   echo 'nameserver 8.8.4.4' >> /etc/resolv.conf${WHITE}\n"
    return 1
  fi
  
  printf "${GREEN} >> Conectividade de rede OK!${WHITE}\n"
  return 0
}

# Tentar corrigir problemas de DNS
tentar_corrigir_dns() {
  printf "${WHITE} >> Tentando corrigir problemas de DNS...\n"
  
  # Adicionar Google DNS se não estiver presente
  if ! grep -q "8.8.8.8" /etc/resolv.conf 2>/dev/null; then
    printf "${WHITE} >> Adicionando Google DNS (8.8.8.8)...\n"
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf
  fi
  
  # Tentar usar systemd-resolve se disponível
  if command -v systemd-resolve &> /dev/null; then
    systemd-resolve --flush-caches >/dev/null 2>&1 || true
  fi
  
  sleep 2
}

# Salvar variáveis
salvar_variaveis() {
  local -a mf_cfg_pairs=()
  mf_validar_empresa "${empresa:-}" || return 1
  local arq_dest="${ARQUIVO_VARIAVEIS:-VARIAVEIS_INSTALACAO}"
  [[ "$arq_dest" = /* ]] || arq_dest="${MF_INSTALADOR_ROOT}/${arq_dest}"
  mf_cfg_pairs+=("subdominio_backend" "${subdominio_backend}")
  mf_cfg_pairs+=("subdominio_frontend" "${subdominio_frontend}")
  mf_cfg_pairs+=("email_deploy" "${email_deploy}")
  mf_cfg_pairs+=("empresa" "${empresa}")
  mf_cfg_pairs+=("senha_deploy" "${senha_deploy}")
  mf_cfg_pairs+=("senha_master" "${senha_master}")
  mf_cfg_pairs+=("nome_titulo" "${nome_titulo}")
  mf_cfg_pairs+=("numero_suporte" "${numero_suporte}")
  mf_cfg_pairs+=("facebook_app_id" "${facebook_app_id}")
  mf_cfg_pairs+=("facebook_app_secret" "${facebook_app_secret}")
  mf_cfg_pairs+=("github_token" "${github_token}")
  mf_cfg_pairs+=("repo_url" "${repo_url}")
  mf_cfg_pairs+=("proxy" "${proxy}")
  mf_cfg_pairs+=("backend_port" "${backend_port:-8080}")
  mf_cfg_pairs+=("frontend_port" "${frontend_port:-3000}")
  mf_cfg_pairs+=("PORT_DB" "${PORT_DB:-5432}")
  mf_cfg_pairs+=("PORT_REDIS" "${PORT_REDIS:-6379}")
  mf_cfg_pairs+=("PORT_PGBOUNCER" "${PORT_PGBOUNCER:-6432}")
  mf_cfg_pairs+=("PORT_TRANSCRIBER" "${PORT_TRANSCRIBER:-4002}")
  mf_cfg_pairs+=("PORT_WUZAPI" "${PORT_WUZAPI:-8090}")
  mf_cfg_pairs+=("PORT_DISPATCHER" "${PORT_DISPATCHER:-8095}")
  mf_cfg_pairs+=("PORT_APIOFICIAL" "${PORT_APIOFICIAL:-6000}")
  # Salvar versão (usar underscore se for "Mais Recente" para evitar problemas com espaços)
  local versao_para_salvar="${versao_instalacao}"
  if [ "${versao_instalacao}" = "Mais Recente" ] || [ "${versao_instalacao}" = "Mais_Recente" ]; then
    versao_para_salvar="Mais_Recente"
  fi
  mf_cfg_pairs+=("versao_instalacao" "${versao_para_salvar}")
  mf_cfg_pairs+=("commit_instalacao" "${commit_instalacao}")
  # Registro se a instalação foi em modo Alta Performance (Redis, Postgres e PgBouncer via Docker)
  mf_cfg_pairs+=("ALTA_PERFORMANCE" "${ALTA_PERFORMANCE:-0}")
  mf_cfg_pairs+=("subdominio_oficial" "${subdominio_oficial}")
  mf_cfg_pairs+=("INSTALACAO_SEM_DOMINIO" "${INSTALACAO_SEM_DOMINIO:-0}")
  mf_cfg_pairs+=("perfil_otimizacao_vps" "${perfil_otimizacao_vps:-0}")

  mf_gravar_config "$arq_dest" "${mf_cfg_pairs[@]}" || return 1

  # Sincronizar cópia individual da instância para compatibilidade total
  if [ -n "${empresa:-}" ]; then
    local instalador_dir_local
    instalador_dir_local="${MF_INSTALADOR_ROOT}"
    mf_gravar_config "${instalador_dir_local}/VARIAVEIS_INSTALACAO_INSTANCIA_${empresa}" "${mf_cfg_pairs[@]}" || return 1
  fi
}

# Carregar variáveis
carregar_variaveis() {
  local arq_carregar="${ARQUIVO_VARIAVEIS:-VARIAVEIS_INSTALACAO}"
  [[ "$arq_carregar" = /* ]] || arq_carregar="${MF_INSTALADOR_ROOT}/${arq_carregar}"
  if [ -f "$arq_carregar" ]; then
    mf_carregar_config "$arq_carregar" || return 1
    empresa="${empresa:-amanda}"
    nome_titulo="${nome_titulo:-AMANDA}"
    INSTALACAO_SEM_DOMINIO="${INSTALACAO_SEM_DOMINIO:-0}"
    PORT_DB="${PORT_DB:-5432}"
    PORT_REDIS="${PORT_REDIS:-6379}"
    PORT_PGBOUNCER="${PORT_PGBOUNCER:-6432}"
    PORT_TRANSCRIBER="${PORT_TRANSCRIBER:-4002}"
    PORT_WUZAPI="${PORT_WUZAPI:-8090}"
    PORT_DISPATCHER="${PORT_DISPATCHER:-8095}"
    PORT_APIOFICIAL="${PORT_APIOFICIAL:-6000}"
  else
    empresa="${empresa:-amanda}"
    nome_titulo="AMANDA"
    INSTALACAO_SEM_DOMINIO="0"
    PORT_DB="5432"
    PORT_REDIS="6379"
    PORT_PGBOUNCER="6432"
    PORT_TRANSCRIBER="4002"
    PORT_WUZAPI="8090"
    PORT_DISPATCHER="8095"
    PORT_APIOFICIAL="6000"
  fi
}

# Salvar etapa concluída
salvar_etapa() {
  local arq_e="${ARQUIVO_ETAPAS:-ETAPA_INSTALACAO}"
  [[ "$arq_e" = /* ]] || arq_e="${MF_INSTALADOR_ROOT}/${arq_e}"
  echo "$1" >"$arq_e"
  if [ -n "${empresa:-}" ] && [ "$arq_e" = "${MF_INSTALADOR_ROOT}/ETAPA_INSTALACAO" ]; then
    local instalador_dir_local
    instalador_dir_local="${MF_INSTALADOR_ROOT}"
    echo "$1" >"${instalador_dir_local}/ETAPA_INSTALACAO_${empresa}" 2>/dev/null || true
  fi
}

# Carregar última etapa
carregar_etapa() {
  local arq_e="${ARQUIVO_ETAPAS:-ETAPA_INSTALACAO}"
  [[ "$arq_e" = /* ]] || arq_e="${MF_INSTALADOR_ROOT}/${arq_e}"
  if [ -f "$arq_e" ]; then
    etapa=$(cat "$arq_e" 2>/dev/null | tr -d '\r\n ')
    if ! [[ "$etapa" =~ ^[0-9]+$ ]]; then
      printf "${YELLOW} >> Aviso: etapa inválida em ${arq_e} (${etapa:-vazio}). Reiniciando controle de etapas.${WHITE}\n"
      etapa="0"
      salvar_etapa "$etapa"
    fi
  else
    etapa="0"
  fi
}

# ================================================================
# FUNÇÃO DE TESTE DE PING E CONECTIVIDADE DE URLs
# ================================================================
verificar_conectividade_url() {
  local url_input="$1"
  local rotulo="${2:-URL}"
  [ -z "$url_input" ] && return 0

  local host_alvo
  host_alvo=$(echo "$url_input" | sed -e 's|^[^/]*//||' -e 's|/.*$||' -e 's|:.*$||')
  [ -z "$host_alvo" ] && return 0

  case "$host_alvo" in
    localhost|127.0.0.1|0.0.0.0|backend|frontend|postgres|pgbouncer|redis|api_oficial|api_transcricao|wuzapi|goflow_dispatcher)
      return 0
      ;;
  esac

  banner
  printf "${WHITE} >> Testando conectividade e apontamento para ${PURPLE}%s${WHITE} (%s)...\n" "$host_alvo" "$rotulo"
  echo

  local ok=0

  # 1. Resolução DNS
  if getent hosts "$host_alvo" >/dev/null 2>&1 || host "$host_alvo" >/dev/null 2>&1 || dig +short "$host_alvo" 2>/dev/null | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
    printf "   ${GREEN}✓${WHITE} Resolução DNS: ${GREEN}OK${WHITE}\n"
    ok=1
  else
    printf "   ${YELLOW}!${WHITE} Resolução DNS: ${YELLOW}Ainda não propagou ou sem resposta${WHITE}\n"
  fi

  # 2. Ping ICMP
  if ping -c 2 -W 3 "$host_alvo" >/dev/null 2>&1; then
    printf "   ${GREEN}✓${WHITE} Teste de Ping (ICMP): ${GREEN}OK (Respondendo)${WHITE}\n"
    ok=1
  else
    printf "   ${YELLOW}!${WHITE} Teste de Ping (ICMP): ${YELLOW}Sem resposta ICMP (pode ser bloqueio de firewall/Cloudflare)${WHITE}\n"
  fi

  # 3. Teste Web TCP/HTTP (80 ou 443)
  if curl -Is --connect-timeout 4 "https://${host_alvo}" >/dev/null 2>&1 || \
     curl -Is --connect-timeout 4 "http://${host_alvo}" >/dev/null 2>&1 || \
     nc -z -w 3 "$host_alvo" 443 >/dev/null 2>&1 || \
     nc -z -w 3 "$host_alvo" 80 >/dev/null 2>&1; then
    printf "   ${GREEN}✓${WHITE} Teste Web HTTP/HTTPS (Porta 80/443): ${GREEN}OK${WHITE}\n"
    ok=1
  fi

  echo
  if [ "$ok" -eq 1 ]; then
    printf "   ${GREEN}>> Conectividade confirmada com sucesso para ${PURPLE}%s${GREEN}!${WHITE}\n\n" "$host_alvo"
    sleep 1
    return 0
  else
    printf "   ${RED}>> AVISO: Não foi possível obter resposta de Ping, DNS ou Web para '${PURPLE}%s${RED}'.${WHITE}\n" "$host_alvo"
    printf "   ${YELLOW}>> O domínio pode não estar apontado ou seu servidor/provedor bloqueia requisições de saída.${WHITE}\n\n"
    printf "   ${WHITE}Deseja aplicar a nova URL mesmo assim? (S/N): ${PURPLE}"
    read -r resp_cont
    resp_cont=$(echo "${resp_cont}" | tr '[:lower:]' '[:upper:]')
    echo
    if [ "$resp_cont" == "S" ]; then
      printf "   ${YELLOW}>> Continuando aplicação da URL por confirmação manual...${WHITE}\n\n"
      sleep 1
      return 0
    else
      printf "   ${RED}>> Atualização cancelada.${WHITE}\n\n"
      sleep 2
      return 1
    fi
  fi
}

# ================================================================
# ATUALIZAR NGINX E SSL PARA DOMÍNIO
# ================================================================
atualizar_nginx_e_ssl_dominio() {
  local servico="$1"
  local novo_host="$2"

  [ -z "$novo_host" ] && return 0
  case "$novo_host" in
    localhost|127.0.0.1|0.0.0.0|backend|frontend|postgres|pgbouncer|redis|api_oficial|api_transcricao|wuzapi|goflow_dispatcher)
      return 0
      ;;
  esac

  if [ ! -d "/etc/nginx/sites-available" ]; then
    return 0
  fi

  local emp="${empresa:-amanda}"
  local site_conf="/etc/nginx/sites-available/${emp}-${servico}"
  local porta_local=${frontend_port:-3000}
  [ "$servico" = "backend" ] && porta_local=${backend_port:-8080}
  [ "$servico" = "api_oficial" ] && porta_local=${PORT_APIOFICIAL:-6000}

  banner
  printf "${PURPLE} >> Atualizando configuração do Nginx para ${servico} (${novo_host})...${WHITE}\n"
  echo

  cat > "$site_conf" <<EOF
server {
  server_name ${novo_host};
  location / {
    proxy_pass http://127.0.0.1:${porta_local};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
  }
}
EOF

  ln -sf "$site_conf" "/etc/nginx/sites-enabled/${emp}-${servico}" 2>/dev/null || true

  if nginx -t 2>/dev/null; then
    systemctl reload nginx 2>/dev/null || true
    printf "${GREEN} >> Nginx atualizado e recarregado para ${novo_host}!${WHITE}\n"
  else
    printf "${RED} >> Erro no teste de configuração do Nginx.${WHITE}\n"
  fi

  if command -v certbot >/dev/null 2>&1 && [[ "$novo_host" == *.* ]]; then
    printf "${WHITE} >> Deseja emitir/atualizar certificado SSL (Let's Encrypt) para ${PURPLE}%s${WHITE}? (S/N): " "$novo_host"
    read -r resp_ssl
    resp_ssl=$(echo "$resp_ssl" | tr '[:lower:]' '[:upper:]')
    if [ "$resp_ssl" = "S" ]; then
      certbot --nginx --agree-tos --non-interactive --redirect -d "$novo_host" 2>/dev/null || \
      certbot -d "$novo_host" --nginx 2>/dev/null || true
    fi
  fi
}

# ================================================================
# LOCALIZADOR INTELIGENTE DO DIRETÓRIO DO DOCKER COMPOSE
# ================================================================
localizar_diretorio_compose() {
  local base_dir="${1:-/home/deploy/${empresa:-amanda}}"
  if [ -f "${base_dir}/amanda/docker-compose.yml" ]; then
    printf '%s\n' "${base_dir}/amanda"
  elif [ -f "${base_dir}/docker-compose.yml" ]; then
    printf '%s\n' "${base_dir}"
  elif [ -f "${base_dir}/multiflow/docker-compose.yml" ]; then
    printf '%s\n' "${base_dir}/multiflow"
  else
    local achado
    achado=$(find "${base_dir}" -maxdepth 2 -name "docker-compose.yml" 2>/dev/null | head -n 1)
    if [ -n "$achado" ]; then
      dirname "$achado"
    else
      printf '%s\n' "${base_dir}"
    fi
  fi
}

# ================================================================
# APLICAR ATUALIZAÇÃO INDIVIDUAL DE URL E REINICIAR CONTÊINER
# ================================================================
aplicar_atualizacao_url_individual() {
  local chave="$1"
  local valor="$2"
  local env_file="$3"
  local compose_dir="$4"
  local servico="$5"

  banner
  printf "${WHITE} >> Atualizando ${PURPLE}%s${WHITE} para: ${GREEN}%s${WHITE}...\n" "$chave" "$valor"
  echo

  # 1. Atualizar no .env principal
  if grep -q "^${chave}=" "$env_file" 2>/dev/null; then
    sed -i "s|^${chave}=.*|${chave}=${valor}|" "$env_file"
  else
    echo "${chave}=${valor}" >> "$env_file"
  fi

  # 2. Sincronizar em subpastas
  if [ "$chave" = "BACKEND_URL" ]; then
    [ -f "${compose_dir}/backend/.env" ] && sed -i "s|^BACKEND_URL=.*|BACKEND_URL=${valor}|" "${compose_dir}/backend/.env"
    [ -f "${compose_dir}/frontend/.env" ] && sed -i "s|^REACT_APP_BACKEND_URL=.*|REACT_APP_BACKEND_URL=${valor}|" "${compose_dir}/frontend/.env"
    [ -f "${compose_dir}/api_oficial/.env" ] && sed -i "s|^URL_BACKEND_MULT100=.*|URL_BACKEND_MULT100=${valor}|" "${compose_dir}/api_oficial/.env"
  elif [ "$chave" = "FRONTEND_URL" ]; then
    [ -f "${compose_dir}/backend/.env" ] && sed -i "s|^FRONTEND_URL=.*|FRONTEND_URL=${valor}|" "${compose_dir}/backend/.env"
  elif [ "$chave" = "URL_API_OFICIAL" ]; then
    [ -f "${compose_dir}/backend/.env" ] && sed -i "s|^URL_API_OFICIAL=.*|URL_API_OFICIAL=${valor}|" "${compose_dir}/backend/.env"
    [ -f "${compose_dir}/api_oficial/.env" ] && sed -i "s|^URL_API_OFICIAL=.*|URL_API_OFICIAL=${valor}|" "${compose_dir}/api_oficial/.env"
  fi

  # 3. Atualizar Nginx reverso e SSL se for domínio externo
  local host_limpo
  host_limpo=$(echo "$valor" | sed -e 's|^[^/]*//||' -e 's|/.*$||' -e 's|:.*$||')
  atualizar_nginx_e_ssl_dominio "$servico" "$host_limpo"

  # 4. Reiniciar os contêineres afetados imediatamente!
  banner
  printf "${PURPLE} >> Reiniciando contêineres para aplicar a nova URL...${WHITE}\n"
  echo
  cd "$compose_dir" || return 1
  local proj_name="${empresa:-amanda}"
  if [ -f "${compose_dir}/.env" ]; then
    local p_env
    p_env=$(grep -E "^(COMPOSE_PROJECT_NAME|EMPRESA)=" "${compose_dir}/.env" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"\r ')
    [ -n "$p_env" ] && proj_name="$p_env"
  fi

  case "$servico" in
    frontend)
      docker compose -p "$proj_name" up -d --build frontend
      docker compose -p "$proj_name" restart backend 2>/dev/null || true
      ;;
    backend)
      docker compose -p "$proj_name" up -d backend
      docker compose -p "$proj_name" restart frontend goflow_dispatcher 2>/dev/null || true
      [ -d "${compose_dir}/api_oficial" ] && docker compose -p "$proj_name" restart api_oficial 2>/dev/null || true
      ;;
    api_oficial)
      docker compose -p "$proj_name" up -d api_oficial
      docker compose -p "$proj_name" restart backend 2>/dev/null || true
      ;;
    *)
      docker compose -p "$proj_name" restart backend 2>/dev/null || true
      ;;
  esac

  echo
  printf "${GREEN} >> Sucesso! O contêiner de %s foi reiniciado com a nova URL: ${PURPLE}%s${WHITE}\n\n" "$servico" "$valor"
  printf "${WHITE}>> Pressione Enter para continuar...${WHITE}\n"
  read -r
}

# ================================================================
# ATUALIZAR TODAS AS URLs EM LOTE
# ================================================================
atualizar_todas_urls_em_lote() {
  local env_file="$1"
  local compose_dir="$2"

  banner
  printf "${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "${PURPLE}║${WHITE}           ATUALIZAR TODAS AS URLs EM LOTE                    ${PURPLE}║${WHITE}\n"
  printf "${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"

  printf "${WHITE} >> Digite a nova URL do ${PURPLE}Frontend${WHITE} (ex: https://app.seudominio.com.br): ${PURPLE}\n"
  read -r n_front
  n_front=$(echo "$n_front" | tr -d '[:space:]')
  [[ -n "$n_front" && "$n_front" != http* ]] && n_front="https://${n_front}"

  printf "${WHITE} >> Digite a nova URL do ${PURPLE}Backend${WHITE} (ex: https://api.seudominio.com.br): ${PURPLE}\n"
  read -r n_back
  n_back=$(echo "$n_back" | tr -d '[:space:]')
  [[ -n "$n_back" && "$n_back" != http* ]] && n_back="https://${n_back}"

  printf "${WHITE} >> Digite a nova URL da ${PURPLE}API Oficial${WHITE} (ex: https://oficial.seudominio.com.br): ${PURPLE}\n"
  read -r n_oficial
  n_oficial=$(echo "$n_oficial" | tr -d '[:space:]')
  [[ -n "$n_oficial" && "$n_oficial" != http* ]] && n_oficial="https://${n_oficial}"

  # Validações de conectividade com ping/DNS
  [ -n "$n_front" ] && { verificar_conectividade_url "$n_front" "Frontend" || return 1; }
  [ -n "$n_back" ] && { verificar_conectividade_url "$n_back" "Backend" || return 1; }
  [ -n "$n_oficial" ] && { verificar_conectividade_url "$n_oficial" "API Oficial" || return 1; }

  # Aplica no .env principal
  [ -n "$n_front" ] && sed -i "s|^FRONTEND_URL=.*|FRONTEND_URL=${n_front}|" "$env_file"
  [ -n "$n_back" ] && sed -i "s|^BACKEND_URL=.*|BACKEND_URL=${n_back}|" "$env_file"
  [ -n "$n_oficial" ] && sed -i "s|^URL_API_OFICIAL=.*|URL_API_OFICIAL=${n_oficial}|" "$env_file"

  # Sincroniza subpastas
  [ -f "${compose_dir}/backend/.env" ] && {
    [ -n "$n_front" ] && sed -i "s|^FRONTEND_URL=.*|FRONTEND_URL=${n_front}|" "${compose_dir}/backend/.env"
    [ -n "$n_back" ] && sed -i "s|^BACKEND_URL=.*|BACKEND_URL=${n_back}|" "${compose_dir}/backend/.env"
    [ -n "$n_oficial" ] && sed -i "s|^URL_API_OFICIAL=.*|URL_API_OFICIAL=${n_oficial}|" "${compose_dir}/backend/.env"
  }
  [ -f "${compose_dir}/frontend/.env" ] && [ -n "$n_back" ] && {
    sed -i "s|^REACT_APP_BACKEND_URL=.*|REACT_APP_BACKEND_URL=${n_back}|" "${compose_dir}/frontend/.env"
  }
  [ -f "${compose_dir}/api_oficial/.env" ] && {
    [ -n "$n_back" ] && sed -i "s|^URL_BACKEND_MULT100=.*|URL_BACKEND_MULT100=${n_back}|" "${compose_dir}/api_oficial/.env"
    [ -n "$n_oficial" ] && sed -i "s|^URL_API_OFICIAL=.*|URL_API_OFICIAL=${n_oficial}|" "${compose_dir}/api_oficial/.env"
  }

  # Atualiza Nginx
  [ -n "$n_front" ] && atualizar_nginx_e_ssl_dominio "frontend" "$(echo "$n_front" | sed -e 's|^[^/]*//||' -e 's|/.*$||' -e 's|:.*$||')"
  [ -n "$n_back" ] && atualizar_nginx_e_ssl_dominio "backend" "$(echo "$n_back" | sed -e 's|^[^/]*//||' -e 's|/.*$||' -e 's|:.*$||')"
  [ -n "$n_oficial" ] && atualizar_nginx_e_ssl_dominio "api_oficial" "$(echo "$n_oficial" | sed -e 's|^[^/]*//||' -e 's|/.*$||' -e 's|:.*$||')"

  # Reinicia contêineres afetados
  banner
  printf "${PURPLE} >> Reiniciando contêineres com as novas URLs...${WHITE}\n"
  cd "$compose_dir" || return 1
  local proj_name="${empresa:-amanda}"
  if [ -f "${compose_dir}/.env" ]; then
    local p_env
    p_env=$(grep -E "^(COMPOSE_PROJECT_NAME|EMPRESA)=" "${compose_dir}/.env" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"\r ')
    [ -n "$p_env" ] && proj_name="$p_env"
  fi
  docker compose -p "$proj_name" up -d --build frontend
  docker compose -p "$proj_name" up -d backend goflow_dispatcher

  printf "\n${GREEN} >> Todas as URLs foram atualizadas e os contêineres reiniciados com sucesso!${WHITE}\n\n"
  printf "${WHITE}>> Pressione Enter para continuar...${WHITE}\n"
  read -r
}

# ================================================================
# GERENCIAR URLs DO SISTEMA AMANDA
# ================================================================
gerenciar_urls_sistema() {
  selecionar_instancia_atualizar "gerenciar URLs" || return 0
  local app_dir="/home/deploy/${empresa:-amanda}"
  local compose_dir
  compose_dir=$(localizar_diretorio_compose "${app_dir}")

  local env_file="${compose_dir}/.env"
  if [ ! -f "$env_file" ]; then
    local alt_env
    alt_env=$(ls -1 /home/deploy/*/.env /home/deploy/*/multiflow/.env /home/deploy/*/amanda/.env 2>/dev/null | head -1)
    if [ -n "$alt_env" ] && [ -f "$alt_env" ]; then
      env_file="$alt_env"
      compose_dir=$(dirname "$env_file")
      empresa=$(basename "$(dirname "$compose_dir")")
      [ "$empresa" = "deploy" ] && empresa=$(basename "$compose_dir")
    fi
  fi

  if [ ! -f "$env_file" ]; then
    banner
    printf "${RED} >> ERRO: Arquivo de configuração .env não encontrado em ${compose_dir}!${WHITE}\n"
    printf "${YELLOW} >> Realize a instalação do sistema primeiro [Opção 1].${WHITE}\n\n"
    printf "${WHITE}>> Pressione Enter para voltar...${WHITE}\n"
    read -r
    return 1
  fi

  while true; do
    local cur_frontend cur_backend cur_oficial cur_transcribe cur_wuzapi cur_dispatcher
    cur_frontend=$(grep -E "^FRONTEND_URL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r')
    cur_backend=$(grep -E "^BACKEND_URL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r')
    cur_oficial=$(grep -E "^URL_API_OFICIAL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r')
    cur_transcribe=$(grep -E "^TRANSCRIBE_URL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r')
    cur_wuzapi=$(grep -E "^WUZAPI_URL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r')
    cur_dispatcher=$(grep -E "^GOFLOW_DISPATCHER_URL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r')

    banner
    printf "   ${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
    printf "   ${PURPLE}║${WHITE}             GERENCIAR URLs DO SISTEMA AMANDA                 ${PURPLE}║${WHITE}\n"
    printf "   ${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
    printf "   ${WHITE}URLs Atualmente Configuradas:${WHITE}\n\n"
    printf "     [1] Frontend (Painel Web):       ${PURPLE}%s${WHITE}\n" "${cur_frontend:-Não definida}"
    printf "     [2] Backend (API REST / Socket): ${PURPLE}%s${WHITE}\n" "${cur_backend:-Não definida}"
    printf "     [3] API Oficial (Meta Cloud):    ${PURPLE}%s${WHITE}\n" "${cur_oficial:-Não definida}"
    printf "     [4] Transcrição de Áudio:        ${PURPLE}%s${WHITE}\n" "${cur_transcribe:-http://api_transcricao:4002}"
    printf "     [5] WuzAPI (WhatsMeow):          ${PURPLE}%s${WHITE}\n" "${cur_wuzapi:-http://wuzapi:8080}"
    printf "     [6] GoFlow Dispatcher:           ${PURPLE}%s${WHITE}\n" "${cur_dispatcher:-http://goflow_dispatcher:8095}"
    printf "     [7] Alterar Todas as URLs Principais (Frontend, Backend, Oficial)\n"
    echo
    printf "     [0] Voltar ao Menu Principal\n\n"
    printf "${WHITE}   Escolha qual URL deseja atualizar: ${PURPLE}"
    read -r escolha_url
    echo

    case "$escolha_url" in
      1)
        printf "${WHITE} >> Digite a nova URL do ${PURPLE}Frontend${WHITE} (ex: https://app.seudominio.com.br): ${PURPLE}\n"
        read -r nova_url_front
        nova_url_front=$(echo "$nova_url_front" | tr -d '[:space:]')
        if [ -n "$nova_url_front" ]; then
          [[ "$nova_url_front" != http* ]] && nova_url_front="https://${nova_url_front}"
          if verificar_conectividade_url "$nova_url_front" "Frontend"; then
            aplicar_atualizacao_url_individual "FRONTEND_URL" "$nova_url_front" "$env_file" "$compose_dir" "frontend"
          fi
        fi
        ;;
      2)
        printf "${WHITE} >> Digite a nova URL do ${PURPLE}Backend${WHITE} (ex: https://api.seudominio.com.br): ${PURPLE}\n"
        read -r nova_url_back
        nova_url_back=$(echo "$nova_url_back" | tr -d '[:space:]')
        if [ -n "$nova_url_back" ]; then
          [[ "$nova_url_back" != http* ]] && nova_url_back="https://${nova_url_back}"
          if verificar_conectividade_url "$nova_url_back" "Backend"; then
            aplicar_atualizacao_url_individual "BACKEND_URL" "$nova_url_back" "$env_file" "$compose_dir" "backend"
          fi
        fi
        ;;
      3)
        printf "${WHITE} >> Digite a nova URL da ${PURPLE}API Oficial${WHITE} (ex: https://oficial.seudominio.com.br): ${PURPLE}\n"
        read -r nova_url_oficial
        nova_url_oficial=$(echo "$nova_url_oficial" | tr -d '[:space:]')
        if [ -n "$nova_url_oficial" ]; then
          [[ "$nova_url_oficial" != http* ]] && nova_url_oficial="https://${nova_url_oficial}"
          if verificar_conectividade_url "$nova_url_oficial" "API Oficial"; then
            aplicar_atualizacao_url_individual "URL_API_OFICIAL" "$nova_url_oficial" "$env_file" "$compose_dir" "api_oficial"
          fi
        fi
        ;;
      4)
        printf "${WHITE} >> Digite a nova URL da ${PURPLE}API de Transcrição${WHITE} [padrão: http://api_transcricao:4002]: ${PURPLE}\n"
        read -r nova_url_trans
        nova_url_trans=$(echo "$nova_url_trans" | tr -d '[:space:]')
        nova_url_trans="${nova_url_trans:-http://api_transcricao:4002}"
        if verificar_conectividade_url "$nova_url_trans" "Transcrição"; then
          aplicar_atualizacao_url_individual "TRANSCRIBE_URL" "$nova_url_trans" "$env_file" "$compose_dir" "backend"
        fi
        ;;
      5)
        printf "${WHITE} >> Digite a nova URL da ${PURPLE}WuzAPI${WHITE} [padrão: http://wuzapi:8080]: ${PURPLE}\n"
        read -r nova_url_wuz
        nova_url_wuz=$(echo "$nova_url_wuz" | tr -d '[:space:]')
        nova_url_wuz="${nova_url_wuz:-http://wuzapi:8080}"
        if verificar_conectividade_url "$nova_url_wuz" "WuzAPI"; then
          aplicar_atualizacao_url_individual "WUZAPI_URL" "$nova_url_wuz" "$env_file" "$compose_dir" "backend"
        fi
        ;;
      6)
        printf "${WHITE} >> Digite a nova URL do ${PURPLE}GoFlow Dispatcher${WHITE} [padrão: http://goflow_dispatcher:8095]: ${PURPLE}\n"
        read -r nova_url_disp
        nova_url_disp=$(echo "$nova_url_disp" | tr -d '[:space:]')
        nova_url_disp="${nova_url_disp:-http://goflow_dispatcher:8095}"
        if verificar_conectividade_url "$nova_url_disp" "GoFlow Dispatcher"; then
          aplicar_atualizacao_url_individual "GOFLOW_DISPATCHER_URL" "$nova_url_disp" "$env_file" "$compose_dir" "backend"
        fi
        ;;
      7)
        atualizar_todas_urls_em_lote "$env_file" "$compose_dir"
        ;;
      0)
        break
        ;;
      *)
        printf "${RED}Opção inválida.${WHITE}\n"
        sleep 1
        ;;
    esac
  done
}

# ================================================================
# GARANTIR DOCKER E DOCKER COMPOSE AUTOMÁTICO (UBUNTU / DEBIAN)
# ================================================================
garantir_docker_e_compose() {
  banner
  printf "${PURPLE} >> Verificando e garantindo ambiente Docker e Docker Compose...${WHITE}\n"
  echo

  # 1. Se docker e docker compose já estiverem operacionais, apenas confirma
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    printf "${GREEN} >> Docker e Docker Compose já estão instalados e operacionais!${WHITE}\n"
    id -u deploy >/dev/null 2>&1 && usermod -aG docker deploy 2>/dev/null || true
    sleep 1
    return 0
  fi

  # 2. Liberar possíveis travas do APT/DPKG (comum em VPS recém iniciadas)
  local max_wait=20
  local wait_count=0
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    if [ $wait_count -eq 0 ]; then
      printf "${YELLOW} >> Aguardando liberação do gerenciador de pacotes apt/dpkg...${WHITE}\n"
    fi
    sleep 2
    wait_count=$((wait_count + 1))
    if [ $wait_count -ge $max_wait ]; then
      printf '%s\n' 'APT/DPKG continua ocupado. Aguarde a operação existente terminar e tente novamente.' >&2
      return 1
    fi
  done

  # 3. Instalar dependências essenciais
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y || return 1
  apt-get install -y -o DPkg::Lock::Timeout=120 ca-certificates curl gnupg lsb-release iptables git python3 || return 1

  # 4. Instalar Docker se ausente ou daemon inativo
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    printf "${PURPLE} >> Instalando Docker Engine Oficial...${WHITE}\n"
    if ! curl -fsSL https://get.docker.com | sh; then
      printf "${YELLOW} >> Tentando instalação do Docker via repositório da distribuição...${WHITE}\n"
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

  # 5. Instalar Docker Compose (v2 plugin e CLI)
  if ! docker compose version >/dev/null 2>&1; then
    printf "${PURPLE} >> Instalando Docker Compose Plugin...${WHITE}\n"
    apt-get update -y || return 1
    apt-get install -y docker-compose-plugin docker-compose-v2 >/dev/null 2>&1 || true
  fi

  # Fallback definitivo: baixar binário oficial estático se o APT não supriu
  if ! docker compose version >/dev/null 2>&1; then
    printf "${PURPLE} >> Baixando binário oficial estático do Docker Compose Standalone...${WHITE}\n"
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

  # 6. Adicionar usuário deploy ao grupo docker
  if id -u deploy >/dev/null 2>&1; then
    usermod -aG docker deploy 2>/dev/null || true
  fi

  if docker info >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    printf "${GREEN} >> Docker e Docker Compose prontos e validados com sucesso!${WHITE}\n"
  else
    printf "${RED} >> Não foi possível validar o Docker/Compose.${WHITE}\n"
    return 1
  fi
  sleep 1
}

# ================================================================
# RESOLUÇÃO AUTOMÁTICA DE PORTAS (POSTGRESQL, REDIS E PGBOUNCER)
# Identifica se a porta padrão está em uso e aloca a próxima (+1)
# Exemplo: se 5432 estiver em uso -> 5433 (5432 + 1)
# ================================================================
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
  local ignorar="${2:-}"
  while testar_porta_tcp_ocupada "$p" || \
        { [ -n "${backend_port:-}" ] && [ "$p" = "${backend_port}" ] && [ "$ignorar" != "backend_port" ]; } || \
        { [ -n "${frontend_port:-}" ] && [ "$p" = "${frontend_port}" ] && [ "$ignorar" != "frontend_port" ]; } || \
        { [ -n "${PORT_DB:-}" ] && [ "$p" = "${PORT_DB}" ] && [ "$ignorar" != "PORT_DB" ]; } || \
        { [ -n "${PORT_REDIS:-}" ] && [ "$p" = "${PORT_REDIS}" ] && [ "$ignorar" != "PORT_REDIS" ]; } || \
        { [ -n "${PORT_PGBOUNCER:-}" ] && [ "$p" = "${PORT_PGBOUNCER}" ] && [ "$ignorar" != "PORT_PGBOUNCER" ]; } || \
        { [ -n "${PORT_TRANSCRIBER:-}" ] && [ "$p" = "${PORT_TRANSCRIBER}" ] && [ "$ignorar" != "PORT_TRANSCRIBER" ]; } || \
        { [ -n "${PORT_WUZAPI:-}" ] && [ "$p" = "${PORT_WUZAPI}" ] && [ "$ignorar" != "PORT_WUZAPI" ]; } || \
        { [ -n "${PORT_DISPATCHER:-}" ] && [ "$p" = "${PORT_DISPATCHER}" ] && [ "$ignorar" != "PORT_DISPATCHER" ]; } || \
        { [ -n "${PORT_APIOFICIAL:-}" ] && [ "$p" = "${PORT_APIOFICIAL}" ] && [ "$ignorar" != "PORT_APIOFICIAL" ]; }; do
    p=$((p + 1))
  done
  printf '%s\n' "$p"
}


sincronizar_todas_portas_env() {
  local file="${1:-${compose_dir}/.env}"
  [ ! -f "$file" ] && return 0
  sincronizar_porta_env "PORT_DB" "${PORT_DB:-5432}" "$file"
  sincronizar_porta_env "PORT_REDIS" "${PORT_REDIS:-6379}" "$file"
  sincronizar_porta_env "PORT_PGBOUNCER" "${PORT_PGBOUNCER:-6432}" "$file"
  sincronizar_porta_env "PORT_TRANSCRIBER" "${PORT_TRANSCRIBER:-4002}" "$file"
  sincronizar_porta_env "PORT_WUZAPI" "${PORT_WUZAPI:-8090}" "$file"
  sincronizar_porta_env "PORT_DISPATCHER" "${PORT_DISPATCHER:-8095}" "$file"
  sincronizar_porta_env "PORT_APIOFICIAL" "${PORT_APIOFICIAL:-6000}" "$file"
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
      printf "${YELLOW} >> Porta host 5432 em uso. Postgres Docker alocado automaticamente na porta ${PORT_DB} (5432 + $((PORT_DB - 5432))).${WHITE}\n"
    fi
    if [ "$PORT_REDIS" != "6379" ]; then
      printf "${YELLOW} >> Porta host 6379 em uso. Redis Docker alocado automaticamente na porta ${PORT_REDIS} (6379 + $((PORT_REDIS - 6379))).${WHITE}\n"
    fi
    if [ "$PORT_PGBOUNCER" != "6432" ]; then
      printf "${YELLOW} >> Porta host 6432 em uso. PgBouncer Docker alocado automaticamente na porta ${PORT_PGBOUNCER} (6432 + $((PORT_PGBOUNCER - 6432))).${WHITE}\n"
    fi
    if [ "$PORT_TRANSCRIBER" != "4002" ]; then
      printf "${YELLOW} >> Porta host 4002 em uso. Transcrição Docker alocada automaticamente na porta ${PORT_TRANSCRIBER} (4002 + $((PORT_TRANSCRIBER - 4002))).${WHITE}\n"
    fi
    if [ "$PORT_WUZAPI" != "8090" ]; then
      printf "${YELLOW} >> Porta host 8090 em uso. Wuzapi Docker alocado automaticamente na porta ${PORT_WUZAPI} (8090 + $((PORT_WUZAPI - 8090))).${WHITE}\n"
    fi
    if [ "$PORT_DISPATCHER" != "8095" ]; then
      printf "${YELLOW} >> Porta host 8095 em uso. Dispatcher Docker alocado automaticamente na porta ${PORT_DISPATCHER} (8095 + $((PORT_DISPATCHER - 8095))).${WHITE}\n"
    fi
    if [ "$PORT_APIOFICIAL" != "6000" ]; then
      printf "${YELLOW} >> Porta host 6000 em uso. API Oficial Docker alocada automaticamente na porta ${PORT_APIOFICIAL} (6000 + $((PORT_APIOFICIAL - 6000))).${WHITE}\n"
    fi
  fi
}

# ================================================================
# INSTALAÇÃO COMPLETA AMANDA VIA DOCKER COMPOSE (TODAS AS APIs)
# ================================================================
instalar_amanda_docker_stack() {
  banner
  printf "${WHITE} >> Iniciando Instalação da Stack AMANDA via Docker Compose...\n"
  echo
  sleep 1

  if [ "${DADOS_COLETADOS_NOVA_INSTANCIA:-0}" != "1" ]; then
    carregar_variaveis
    questoes_dns_base || trata_erro "questoes_dns_base"
    verificar_dns_base || trata_erro "verificar_dns_base"
    questoes_variaveis_base || trata_erro "questoes_variaveis_base"
    define_proxy_base || trata_erro "define_proxy_base"
    define_portas_base || trata_erro "define_portas_base"
    confirma_dados_instalacao_base || trata_erro "confirma_dados_instalacao_base"
    salvar_variaveis || trata_erro "salvar_variaveis"
  fi
  export DADOS_COLETADOS_NOVA_INSTANCIA=0

  atualiza_vps_base || trata_erro "atualiza_vps_base"
  cria_deploy_base || trata_erro "cria_deploy_base"
  config_timezone_base || trata_erro "config_timezone_base"
  config_firewall_base || trata_erro "config_firewall_base"

  # Garantir Docker e Docker Compose instalados e 100% operacionais automaticamente
  garantir_docker_e_compose || return 1

  local proj_name="${empresa:-amanda}"

  # Limpar contêineres Docker órfãos e resolver portas automaticamente (+1 se em uso)
  limpar_conteineres_conflitantes "/home/deploy/${proj_name}" "${proj_name}"
  resolver_portas_automaticas

  # Selecionar canal/branch da AMANDA (Estável vs Dev)
  selecionar_canal_branch_amanda "a instalação"

  # Instalar Git e baixar o repositório
  instala_git_base || trata_erro "instala_git_base"
  codifica_clone_base || trata_erro "codifica_clone_base"
  baixa_codigo_base || trata_erro "baixa_codigo_base"

  # Localizar e padronizar diretório da aplicação para amanda
  local app_dir="/home/deploy/${empresa:-amanda}"
  if [ -d "${app_dir}/multiflow" ] && [ ! -d "${app_dir}/amanda" ]; then
    printf "${PURPLE} >> Criando link do diretório da aplicação para amanda...${WHITE}\n"
    ln -sfn "${app_dir}/multiflow" "${app_dir}/amanda" 2>/dev/null || true
  fi
  local compose_dir
  compose_dir=$(localizar_diretorio_compose "${app_dir}")

  banner
  printf "${WHITE} >> Configurando variáveis de ambiente da Stack AMANDA (${proj_name})...\n"
  printf "${PURPLE} >> Diretório do Compose detectado: ${BLUE}%s${WHITE}\n" "$compose_dir"
  echo

  # Preparar .env da Stack Docker Compose com todas as APIs
  cat <<EOF > "${compose_dir}/.env"
COMPOSE_PROJECT_NAME=${empresa:-amanda}
EMPRESA=${empresa:-amanda}
NODE_ENV=production
BACKEND_URL=${subdominio_backend}
FRONTEND_URL=${subdominio_frontend}
URL_API_OFICIAL=${subdominio_oficial:-}
PORT_BACKEND=${backend_port:-8080}
PORT_FRONTEND=${frontend_port:-3000}
PORT_DB=${PORT_DB:-5432}
PORT_PGBOUNCER=${PORT_PGBOUNCER:-6432}
PORT_REDIS=${PORT_REDIS:-6379}
PORT_WUZAPI=${PORT_WUZAPI:-8090}
PORT_DISPATCHER=${PORT_DISPATCHER:-8095}
PORT_TRANSCRIBER=${PORT_TRANSCRIBER:-4002}

DB_USER=${empresa:-amanda}
DB_PASS=${senha_deploy:-Acertitech13@}
DB_NAME=${empresa:-amanda}
DB_NAME_APIOFICIAL=api_oficial
REDIS_URI_ACK=redis://redis:6379

JWT_SECRET=${jwt_secret}
JWT_REFRESH_SECRET=${jwt_refresh_secret}
MASTER_KEY=${senha_master}

FACEBOOK_APP_ID=${facebook_app_id:-}
FACEBOOK_APP_SECRET=${facebook_app_secret:-}

WUZAPI_ADMIN_TOKEN=adminpro123
WUZAPI_TOKEN=adminpro123
WUZAPI_WEBHOOK_BASE_URL=http://backend:8080
WUZAPI_GLOBAL_ENCRYPTION_KEY=mF9vK2xQ8zP4wR6tY1uI3oA5sD7fG0hJ
WUZAPI_GLOBAL_HMAC_KEY=kH3jL5mN7pQ9rT1vX3zB5dF7gJ9lO1qS

USE_WHATSAPP_OFICIAL=false
TOKEN_API_OFICIAL=adminpro
USE_GO_CAMPAIGN_DISPATCHER=true
TRANSCRIBE_URL=http://api_transcricao:4002
EOF

  # Garantir cópia do .env também na raiz do app_dir se diferente
  [ "${compose_dir}" != "${app_dir}" ] && cp "${compose_dir}/.env" "${app_dir}/.env" 2>/dev/null || true

  [ -d "${compose_dir}/backend" ] && cp "${compose_dir}/.env" "${compose_dir}/backend/.env" 2>/dev/null || true
  [ -d "${compose_dir}/frontend" ] && echo "REACT_APP_BACKEND_URL=${subdominio_backend}" > "${compose_dir}/frontend/.env" 2>/dev/null || true

  # Configurar .env da API Oficial e corrigir estrutura de pastas (public)
  if [ -d "${compose_dir}/api_oficial" ]; then
    cat <<EOF > "${compose_dir}/api_oficial/.env"
DATABASE_LINK=postgresql://${empresa:-amanda}:${senha_deploy:-Acertitech13@}@postgres:5432/api_oficial?schema=public
URL_BACKEND_MULT100=http://backend:8080
REDIS_URI=redis://redis:6379
PORT=6000
TOKEN_ADMIN=adminpro
NAME_ADMIN=SetupAutomatizado
EMAIL_ADMIN=admin@amanda.com.br
PASSWORD_ADMIN=${senha_deploy:-Acertitech13@}
JWT_REFRESH_SECRET=${jwt_refresh_secret}
URL_API_OFICIAL=${subdominio_oficial}
RABBITMQ_ENABLED_GLOBAL=false
TZ=America/Sao_Paulo
EOF
    # Garante a existência do diretório public e Dockerfile com compatibilidade CommonJS
    mkdir -p "${compose_dir}/api_oficial/public"
    touch "${compose_dir}/api_oficial/public/.gitkeep"
    if [ -f "${compose_dir}/api_oficial/package.json" ]; then
      sed -i 's|"@nestjs/mapped-types": "[^"]*"|"@nestjs/mapped-types": "2.0.5"|g' "${compose_dir}/api_oficial/package.json" 2>/dev/null || true
    fi
    cat << 'EOF_API_DF' > "${compose_dir}/api_oficial/Dockerfile"
FROM node:20-alpine
WORKDIR /app
RUN apk add --no-cache openssl
COPY package*.json ./
RUN sed -i 's/"@nestjs\/mapped-types": "[^"]*"/"@nestjs\/mapped-types": "2.0.5"/g' package.json 2>/dev/null || true
RUN npm install --production && npm install prisma@5.14.0 @nestjs/mapped-types@2.0.5
COPY . .
RUN mkdir -p /app/public
RUN npx prisma generate
EXPOSE 6000
CMD ["node", "dist/main.js"]
EOF_API_DF
  fi

  # Assegurar Dockerfiles para que todas as imagens sejam construídas e tagueadas com o nome da empresa
  [ -f "${compose_dir}/postgres/Dockerfile" ] || (mkdir -p "${compose_dir}/postgres" && echo "FROM postgres:17" > "${compose_dir}/postgres/Dockerfile")
  [ -f "${compose_dir}/redis/Dockerfile" ] || (mkdir -p "${compose_dir}/redis" && echo "FROM redis:7.4-alpine" > "${compose_dir}/redis/Dockerfile")
  [ -f "${compose_dir}/pgbouncer/Dockerfile" ] || (mkdir -p "${compose_dir}/pgbouncer" && echo "FROM edoburu/pgbouncer:1.21.0-p2" > "${compose_dir}/pgbouncer/Dockerfile")
  [ -f "${compose_dir}/wuzapi/Dockerfile.official" ] || (mkdir -p "${compose_dir}/wuzapi" && echo "FROM asternic/wuzapi:latest" > "${compose_dir}/wuzapi/Dockerfile.official")

  # Padronizar e otimizar docker-compose.yml com precisão total (100% amanda_, todas imagens com prefixo da empresa)
  if [ -f "${compose_dir}/docker-compose.yml" ]; then
    printf "${PURPLE} >> Padronizando docker-compose.yml para AMANDA e tagueando todas imagens com a empresa...${WHITE}\n"
    python3 - "${compose_dir}/docker-compose.yml" "${empresa:-amanda}" "${senha_deploy:-Acertitech13@}" << 'PYEOF'
import sys, re

compose_file = sys.argv[1]
db_user = sys.argv[2]
db_pass = sys.argv[3]

with open(compose_file, "r", encoding="utf-8") as f:
    content = f.read()

# 1. Garantir name: ${COMPOSE_PROJECT_NAME:-amanda}
if not re.search(r"^name:\s*", content, re.M):
    content = "name: ${COMPOSE_PROJECT_NAME:-amanda}\n" + content
else:
    content = re.sub(r"^name:\s*.*$", "name: ${COMPOSE_PROJECT_NAME:-amanda}", content, flags=re.M)

# 2. Parametrizar container_name para usar ${COMPOSE_PROJECT_NAME:-amanda}_
content = re.sub(r'container_name:\s*(?:multiflow|amanda)_', 'container_name: ${COMPOSE_PROJECT_NAME:-amanda}_', content)

# 3. Parametrizar network para ${COMPOSE_PROJECT_NAME:-amanda}_net
content = re.sub(r'name:\s*(?:multiflow|amanda)_net', 'name: ${COMPOSE_PROJECT_NAME:-amanda}_net', content)

# 4. Parametrizar volumes externos para ${COMPOSE_PROJECT_NAME:-amanda}_<volume>
content = re.sub(r'name:\s*(?:multiflow|amanda)_(postgres_data|redis_data|backend_database|backend_public|wuzapi_data)', r'name: ${COMPOSE_PROJECT_NAME:-amanda}_\1', content)

# 5. Garantir que api_oficial NAO esteja no docker-compose principal (instalacao separada via menu)
if "api_oficial:" in content:
    content = re.sub(r'\n[ ]{2}#?[^\n]*API OFICIAL[^\n]*\n[ ]{2}api_oficial:\n(?:[ ]{4,}.*\n)*', '\n', content)
    content = re.sub(r'^[ ]{2}api_oficial:\n(?:[ ]{4,}.*\n)*', '', content, flags=re.M)

with open(compose_file, "w", encoding="utf-8") as f:
    f.write(content)
PYEOF
  fi

  chown -R deploy:deploy "${app_dir}"
  chmod -R u+rwX,go+rX,go-w "${app_dir}" || return 1
  find "${app_dir}" -type f \( -name '.env' -o -name '.env.*' \) -exec chmod 600 {} + || return 1

  # Criar volumes externos necessários com o nome da empresa/projeto
  local proj_name="${empresa:-amanda}"
  banner
  printf "${WHITE} >> Criando volumes de dados persistentes do Docker (${proj_name})...\n"
  echo
  docker volume create "${proj_name}_postgres_data" 2>/dev/null || true
  docker volume create "${proj_name}_redis_data" 2>/dev/null || true
  docker volume create "${proj_name}_backend_database" 2>/dev/null || true
  docker volume create "${proj_name}_backend_public" 2>/dev/null || true
  docker volume create "${proj_name}_wuzapi_data" 2>/dev/null || true
  # Compatibilidade de volumes legados caso seja amanda
  if [ "${proj_name}" = "amanda" ]; then
    docker volume create amanda_postgres_data 2>/dev/null || true
    docker volume create amanda_redis_data 2>/dev/null || true
    docker volume create amanda_backend_database 2>/dev/null || true
    docker volume create amanda_backend_public 2>/dev/null || true
    docker volume create amanda_wuzapi_data 2>/dev/null || true
    docker volume create multiflow_postgres_data 2>/dev/null || true
    docker volume create multiflow_redis_data 2>/dev/null || true
    docker volume create multiflow_backend_database 2>/dev/null || true
    docker volume create multiflow_backend_public 2>/dev/null || true
    docker volume create multiflow_wuzapi_data 2>/dev/null || true
  fi

  # Subir stack
  banner
  printf "${WHITE} >> Construindo e iniciando todos os contêineres e APIs da AMANDA (${proj_name})...\n"
  printf "${YELLOW} >> Esse processo pode levar alguns minutos (download de imagens e build dos serviços)...\n"
  echo
  cd "${compose_dir}" || trata_erro "cd para compose_dir"

  # Validação de integridade do arquivo Compose antes de subir
  if ! docker compose -p "${proj_name}" config >/dev/null 2>&1; then
    printf "${YELLOW} >> Detectada divergência no docker-compose.yml. Restaurando compose limpo do repositório...${WHITE}\n"
    git checkout -f docker-compose.yml 2>/dev/null || true
  fi

  # Assegurar Dockerfiles auxiliares e tagueamento inicial das imagens com o nome da empresa
  [ -f "${compose_dir}/postgres/Dockerfile" ] || (mkdir -p "${compose_dir}/postgres" && echo "FROM postgres:17" > "${compose_dir}/postgres/Dockerfile")
  [ -f "${compose_dir}/redis/Dockerfile" ] || (mkdir -p "${compose_dir}/redis" && echo "FROM redis:7.4-alpine" > "${compose_dir}/redis/Dockerfile")
  [ -f "${compose_dir}/pgbouncer/Dockerfile" ] || (mkdir -p "${compose_dir}/pgbouncer" && echo "FROM edoburu/pgbouncer:1.21.0-p2" > "${compose_dir}/pgbouncer/Dockerfile")
  [ -f "${compose_dir}/wuzapi/Dockerfile.official" ] || (mkdir -p "${compose_dir}/wuzapi" && echo "FROM asternic/wuzapi:latest" > "${compose_dir}/wuzapi/Dockerfile.official")
  docker image inspect postgres:17 >/dev/null 2>&1 && docker tag postgres:17 "${proj_name}_postgres:17" 2>/dev/null || true
  docker image inspect redis:7.4-alpine >/dev/null 2>&1 && docker tag redis:7.4-alpine "${proj_name}_redis:7.4-alpine" 2>/dev/null || true
  docker image inspect edoburu/pgbouncer:1.21.0-p2 >/dev/null 2>&1 && docker tag edoburu/pgbouncer:1.21.0-p2 "${proj_name}_pgbouncer:1.21.0-p2" 2>/dev/null || true
  docker image inspect asternic/wuzapi:latest >/dev/null 2>&1 && docker tag asternic/wuzapi:latest "${proj_name}_wuzapi:latest" 2>/dev/null || true

  limpar_conteineres_conflitantes "${compose_dir}" "${proj_name}"
  resolver_portas_automaticas
  sincronizar_todas_portas_env "${compose_dir}/.env"

  if ! docker compose -p "${proj_name}" up -d --build; then
    printf "${YELLOW} >> Alerta ao subir contêineres. Limpando contêineres e reavaliando portas...${WHITE}\n"
    limpar_conteineres_conflitantes "${compose_dir}" "${proj_name}"
    resolver_portas_automaticas
    sincronizar_todas_portas_env "${compose_dir}/.env"
    sleep 2
    if ! docker compose -p "${proj_name}" up -d; then
      printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
      printf "${RED}❌ ERRO CRÍTICO: Falha ao compilar e subir os contêineres Docker!${WHITE}\n"
      printf "${YELLOW}   Diretório: ${BLUE}${compose_dir}${WHITE}\n"
      printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
      sleep 5
      exit 1
    fi
  fi

  # Localizar dinamicamente os nomes dos contêineres iniciados para este projeto
  local pg_container be_container oficial_container
  pg_container=$(mf_container_servico "$proj_name" postgres) || return 1
  be_container=$(mf_container_servico "${empresa:-amanda}" backend) || return 1
  oficial_container=$(mf_container_servico "${empresa:-amanda}" api_oficial) || oficial_container=""

  # Aguardar banco de dados ficar pronto
  banner
  printf "${WHITE} >> Aguardando banco de dados PostgreSQL inicializar...\n"
  echo
  local tentativas=0
  while [ $tentativas -lt 30 ]; do
    if [ -n "$pg_container" ] && docker exec "$pg_container" pg_isready -U "${empresa:-amanda}" -d "${empresa:-amanda}" >/dev/null 2>&1; then
      printf "${GREEN} >> Banco de dados pronto! (${pg_container})${WHITE}\n"
      break
    fi
    tentativas=$((tentativas + 1))
    sleep 2
  done

  [ "$tentativas" -lt 30 ] || { printf '%s\n' 'PostgreSQL não ficou pronto no prazo esperado.' >&2; return 1; }

  # Executar migrações e seeds do Backend
  if [ -n "$be_container" ]; then
    banner
    printf "${WHITE} >> Executando migrações do Backend (db:migrate)...\n"
    echo
    docker exec "$be_container" npx sequelize db:migrate || return 1
    sleep 2

    banner
    printf "${WHITE} >> Inserindo registros iniciais do sistema Backend (db:seed:all)...\n"
    echo
    docker exec "$be_container" npx sequelize db:seed:all || return 1
    sleep 2

    # Sincronizar credenciais oficiais AMANDA no banco de dados
    if [ -n "$pg_container" ]; then
      docker exec -e PGPASSWORD="${senha_deploy:-Acertitech13@}" "$pg_container" psql -U "${empresa:-amanda}" -d "${empresa:-amanda}" -c "UPDATE \"Users\" SET email = 'admin@amanda.com.br' WHERE id = 1 AND email != 'admin@amanda.com.br';" 2>/dev/null || true
    fi

    # Reiniciar backend para carregar todas as tabelas e seeds aplicadas
    docker restart "$be_container" 2>/dev/null || true
  fi

  # Verificar se há contêineres rodando para este projeto
  local total_rodando
  total_rodando=$(docker ps --filter "name=${proj_name}_" -q | wc -l)
  if [ "$total_rodando" -eq 0 ]; then
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    printf "${RED}❌ ERRO: Nenhum contêiner da AMANDA está ativo após a instalação!${WHITE}\n"
    printf "${YELLOW}   Consulte os logs com: docker compose -f ${compose_dir}/docker-compose.yml logs${WHITE}\n"
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    sleep 5
    exit 1
  fi

  # Configurar Proxy Reverso e SSL (apenas se houver domínios configurados)
  if [ "${INSTALACAO_SEM_DOMINIO:-0}" != "1" ] && [ "${proxy}" != "none" ]; then
    banner
    printf "${WHITE} >> Configurando proxy reverso Nginx e SSL (Certbot)...\n"
    echo
    if [ "${proxy}" == "nginx" ]; then
      instala_nginx_base || trata_erro "instala_nginx_base"
      config_nginx_base || trata_erro "config_nginx_base"
    elif [ "${proxy}" == "traefik" ]; then
      instala_traefik_base || trata_erro "instala_traefik_base"
      config_traefik_base || trata_erro "config_traefik_base"
    fi
  else
    banner
    printf "${GREEN} >> Modo Sem Domínio: Os contêineres estão acessíveis diretamente pelas portas mapeadas.${WHITE}\n\n"
    printf "   ${WHITE}Frontend (Web):   ${PURPLE}${subdominio_frontend}${WHITE}\n"
    printf "   ${WHITE}Backend (API):    ${PURPLE}${subdominio_backend}${WHITE}\n"
    [ -n "${subdominio_oficial}" ] && printf "   ${WHITE}API Oficial Meta: ${PURPLE}${subdominio_oficial}${WHITE}\n\n"
    sleep 2
  fi

  local criticos=()
  [ -n "$be_container" ] && criticos+=("$be_container")
  [ -n "$oficial_container" ] && criticos+=("$oficial_container")
  if ! mf_verificar_servicos_criticos_docker "${criticos[@]}"; then
    return 1
  fi

  salvar_etapa 21

  # Resumo final
  banner
  printf "   ${GREEN}>> INSTALAÇÃO AMANDA (DOCKER COMPOSE) CONCLUÍDA COM SUCESSO!${WHITE}\n\n"
  printf "   ${WHITE}Frontend (Painel Web):  ${PURPLE}${subdominio_frontend}${WHITE}\n"
  printf "   ${WHITE}Backend (API REST):      ${PURPLE}${subdominio_backend}${WHITE}\n"
  [ -n "${subdominio_oficial}" ] && printf "   ${WHITE}API Oficial (WhatsApp): ${PURPLE}${subdominio_oficial}${WHITE}\n"
  echo
  printf "   ${WHITE}Usuário Administrador:   ${PURPLE}admin@amanda.com.br${WHITE}\n"
  printf "   ${WHITE}Senha Padrão:            ${PURPLE}adminamanda${WHITE}\n\n"
  printf "   ${PURPLE}>> Todos os Contêineres e APIs Ativos:${WHITE}\n"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "multiflow|amanda|NAMES" || docker ps
  echo
  printf "${WHITE}>> Pressione qualquer tecla para voltar ao menu principal...${WHITE}\n"
  read -p ""
}

# Evita declarar instalação/atualização concluída com backend ou API Oficial reiniciando.
mf_verificar_servicos_criticos_docker() {
  local containers=()
  for c in "$@"; do
    [ -n "$c" ] && containers+=("$c")
  done
  local container=""
  local state=""
  local falha=0

  if [ "${#containers[@]}" -eq 0 ]; then
    printf '%s\n' 'Nenhum container crítico da instância foi identificado.' >&2
    return 1
  fi

  sleep 5
  for container in "${containers[@]}"; do
    [ -z "${container}" ] && continue
    if ! docker inspect "${container}" >/dev/null 2>&1; then
      printf "${YELLOW} >> Container crítico ${container} não encontrado; verifique o nome no Compose.${WHITE}\n"
      falha=1
      continue
    fi

    state=$(docker inspect --format '{{.State.Status}}' "${container}" 2>/dev/null)
    local health
    health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${container}" 2>/dev/null) || return 1
    if [ "${state}" != "running" ] || { [ "$health" != "none" ] && [ "$health" != "healthy" ]; }; then
      printf "${RED} >> ${container} está com estado '${state:-desconhecido}'. Últimos logs:${WHITE}\n"
      docker logs --tail 80 "${container}" 2>&1
      falha=1
    fi
  done

  if [ "${falha}" -ne 0 ]; then
    printf "${RED} >> A plataforma não foi marcada como concluída. Corrija os erros acima e tente novamente.${WHITE}\n"
    return 1
  fi
  return 0
}

# ================================================================
# SELEÇÃO DE CANAL / BRANCH AMANDA (Estável vs Desenvolvimento)
# ================================================================
selecionar_canal_branch_amanda() {
  local motivo="${1:-a atualização}"
  banner 2>/dev/null || true
  printf "   ${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "   ${PURPLE}║${WHITE}           SELEÇÃO DE CANAL DE VERSÃO / BRANCH AMANDA         ${PURPLE}║${WHITE}\n"
  printf "   ${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
  printf "   ${WHITE}Escolha qual versão/branch você deseja utilizar para ${motivo}:${WHITE}\n\n"
  printf "   [${BLUE}1${WHITE}] ${GREEN}Versão Estável (main)${WHITE} - Recomendada para Produção / Clientes\n"
  printf "   [${BLUE}2${WHITE}] ${YELLOW}Versão de Desenvolvimento (davi-alteracoes)${WHITE} - Correções e recursos recentes (GLPI)\n"
  printf "   [${BLUE}3${WHITE}] ${PURPLE}Versão de Desenvolvimento (alan-alteracoes)${WHITE} - Recursos em homologação\n"
  printf "   [${BLUE}4${WHITE}] ${CYAN}Personalizada${WHITE} - Digitar o nome de outra branch específica\n\n"
  printf "   ${WHITE}Digite a opção desejada [1-4] (Padrão: 1): ${PURPLE}"
  read -r opt_branch
  opt_branch="${opt_branch:-1}"

  case "${opt_branch}" in
    2)
      BRANCH_AMANDA_ESCOLHIDA="davi-alteracoes"
      ;;
    3)
      BRANCH_AMANDA_ESCOLHIDA="alan-alteracoes"
      ;;
    4)
      printf "\n   ${WHITE}Digite o nome exato da branch remota: ${PURPLE}"
      read -r BRANCH_AMANDA_ESCOLHIDA
      [ -z "${BRANCH_AMANDA_ESCOLHIDA}" ] && BRANCH_AMANDA_ESCOLHIDA="main"
      ;;
    *)
      BRANCH_AMANDA_ESCOLHIDA="main"
      ;;
  esac

  export BRANCH_AMANDA_ESCOLHIDA
  if [ -n "${ARQUIVO_VARIAVEIS_USADO:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_USADO}" ]; then
    sed -i '/^BRANCH_AMANDA_ESCOLHIDA=/d' "${ARQUIVO_VARIAVEIS_USADO}"
    echo "BRANCH_AMANDA_ESCOLHIDA=\"${BRANCH_AMANDA_ESCOLHIDA}\"" >> "${ARQUIVO_VARIAVEIS_USADO}"
  elif [ -n "${empresa:-}" ] && [ -f "/root/VARIAVEIS_INSTALACAO_INSTANCIA_${empresa}" ]; then
    sed -i '/^BRANCH_AMANDA_ESCOLHIDA=/d' "/root/VARIAVEIS_INSTALACAO_INSTANCIA_${empresa}"
    echo "BRANCH_AMANDA_ESCOLHIDA=\"${BRANCH_AMANDA_ESCOLHIDA}\"" >> "/root/VARIAVEIS_INSTALACAO_INSTANCIA_${empresa}"
  fi

  printf "\n   ${GREEN}>> Canal selecionado: ${BLUE}%s${WHITE}\n\n" "${BRANCH_AMANDA_ESCOLHIDA}"
  sleep 1
}

# ================================================================
# ATUALIZAÇÃO DOCKER COMPOSE AMANDA
# ================================================================
atualizar_amanda_docker() {
  selecionar_instancia_atualizar "atualizar" || return 0
  local app_dir="/home/deploy/${empresa:-amanda}"
  local compose_dir
  compose_dir=$(localizar_diretorio_compose "${app_dir}")
  local repo_dir="${app_dir}"
  local branch_atual=""
  if [ ! -d "${repo_dir}/.git" ] && [ -d "${compose_dir}/.git" ]; then
    repo_dir="${compose_dir}"
  fi
  if [ -d "${repo_dir}/.git" ]; then
    branch_atual=$(sudo -u deploy -- git -C "${repo_dir}" branch --show-current 2>/dev/null || true)
  fi

  banner
  printf "   ${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "   ${PURPLE}║${WHITE}             ATUALIZAR AMANDA (DOCKER COMPOSE)                ${PURPLE}║${WHITE}\n"
  printf "   ${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
  printf "   ${WHITE}Instância selecionada: ${GREEN}%s${WHITE}\n\n" "${empresa:-amanda}"
  if [ "${branch_atual}" = "v1.0131012a" ]; then
    printf "   ${WHITE}Deseja atualizar os quatro serviços da homologação GHCR? (S/N): ${PURPLE}"
  else
    printf "   ${WHITE}Deseja iniciar a atualização de todos os contêineres da AMANDA? (S/N): ${PURPLE}"
  fi
  read -r confirm_upd
  confirm_upd=$(echo "${confirm_upd}" | tr '[:lower:]' '[:upper:]')
  [ "$confirm_upd" != "S" ] && return 0

  if [ "${branch_atual}" = "v1.0131012a" ]; then
    if [ ! -f "${compose_dir}/docker-compose.yml" ]; then
      printf "${RED} >> Compose de homologação não encontrado em ${compose_dir}.${WHITE}\n"
      return 1
    fi

    banner
    printf "${PURPLE} >> Atualizando a branch de homologação v1.0131012a...${WHITE}\n"
    local estado_git
    estado_git=$(sudo -u deploy -- git -C "${repo_dir}" status --porcelain 2>/dev/null) || {
      printf "${RED} >> Não foi possível verificar o estado local do repositório.${WHITE}\n"
      return 1
    }
    if [ -n "${estado_git}" ]; then
      printf "${RED} >> Há alterações locais no repositório; salve-as antes de atualizar homologação.${WHITE}\n"
      return 1
    fi
    if ! sudo -u deploy -- git -C "${repo_dir}" fetch origin "refs/heads/v1.0131012a:refs/remotes/origin/v1.0131012a" ||
      ! sudo -u deploy -- git -C "${repo_dir}" pull --ff-only origin v1.0131012a; then
      printf "${RED} >> Falha ao sincronizar a branch de homologação. Nenhum container foi atualizado.${WHITE}\n"
      return 1
    fi

    if ! (cd "${compose_dir}" && DOCKER_CONFIG=/root/.docker docker compose pull backend frontend api_transcricao goflow_dispatcher); then
      printf "${RED} >> Falha ao baixar as imagens do GHCR. Os containers em execução não foram alterados.${WHITE}\n"
      return 1
    fi
    if ! (cd "${compose_dir}" && DOCKER_CONFIG=/root/.docker docker compose up -d --no-build backend frontend api_transcricao goflow_dispatcher); then
      printf "${RED} >> Falha ao aplicar as imagens de homologação.${WHITE}\n"
      return 1
    fi

    local backend_container
    backend_container=$(cd "${compose_dir}" && docker compose ps -q backend 2>/dev/null)
    if [ -z "${backend_container}" ]; then
      printf "${RED} >> O container backend não foi encontrado após a atualização GHCR.${WHITE}\n"
      return 1
    fi
    if ! docker exec "${backend_container}" npx sequelize db:migrate; then
      printf "${RED} >> A migração do backend falhou; confira os logs antes de continuar.${WHITE}\n"
      docker logs --tail 80 "${backend_container}" 2>&1
      return 1
    fi
    if ! mf_verificar_servicos_criticos_docker "${backend_container}"; then
      return 1
    fi
    banner
    printf "   ${GREEN}>> ATUALIZAÇÃO DA HOMOLOGAÇÃO CONCLUÍDA!${WHITE}\n\n"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "multiflow|NAMES" || docker ps
    echo
    printf "${WHITE}>> Pressione Enter para voltar ao menu principal...${WHITE}\n"
    read -r
    return 0
  fi

  # Selecionar canal/branch desejado
  selecionar_canal_branch_amanda "a atualização"

  banner
  printf "${PURPLE} >> Sincronizando com o repositório oficial (branch ${BRANCH_AMANDA_ESCOLHIDA})...${WHITE}\n"
  echo

  cd "${repo_dir}" || cd "${app_dir}" || cd "${compose_dir}" || trata_erro "cd para diretorio da instalacao"
  git config --global --add safe.directory "${repo_dir}" 2>/dev/null || true
  git fetch --all --prune 2>/dev/null || true
  git clean -fd -e .env -e "*/.env" -e ssl 2>/dev/null || true
  git checkout -f 2>/dev/null || true
  git reset --hard 2>/dev/null || true

  if git show-ref --verify --quiet "refs/remotes/origin/${BRANCH_AMANDA_ESCOLHIDA}"; then
    git checkout -f -B "${BRANCH_AMANDA_ESCOLHIDA}" "origin/${BRANCH_AMANDA_ESCOLHIDA}"
    git reset --hard "origin/${BRANCH_AMANDA_ESCOLHIDA}"
    printf "${GREEN} >> Sincronizado com sucesso na branch: ${BRANCH_AMANDA_ESCOLHIDA}${WHITE}\n"
  elif git show-ref --verify --quiet refs/remotes/origin/main; then
    printf "${YELLOW} >> Aviso: Branch '${BRANCH_AMANDA_ESCOLHIDA}' não encontrada no origin. Sincronizando com a branch main...${WHITE}\n"
    git checkout -f -B main origin/main
    git reset --hard origin/main
  else
    git checkout -f -B master origin/master
    git reset --hard origin/master
  fi
  git clean -fd -e .env -e "*/.env" -e ssl 2>/dev/null || true

  # Assegurar que o .env do Docker Compose existe (restaura a partir das variáveis salvas se necessário)
  if [ ! -f "${compose_dir}/.env" ]; then
    if [ -n "${ARQUIVO_VARIAVEIS_USADO:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_USADO}" ]; then
      mf_carregar_config "${ARQUIVO_VARIAVEIS_USADO}" 2>/dev/null
    elif [ -f "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO_INSTANCIA_${empresa:-amanda}" ]; then
      mf_carregar_config "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO_INSTANCIA_${empresa:-amanda}" 2>/dev/null
    elif [ -f "/root/VARIAVEIS_INSTALACAO_INSTANCIA_${empresa:-amanda}" ]; then
      mf_carregar_config "/root/VARIAVEIS_INSTALACAO_INSTANCIA_${empresa:-amanda}" 2>/dev/null
    fi
    cat <<EOF > "${compose_dir}/.env"
COMPOSE_PROJECT_NAME=${empresa:-amanda}
EMPRESA=${empresa:-amanda}
NODE_ENV=production
BACKEND_URL=${subdominio_backend}
FRONTEND_URL=${subdominio_frontend}
URL_API_OFICIAL=${subdominio_oficial:-${subdominio_api_oficial:-}}
PORT_BACKEND=${backend_port:-8080}
PORT_FRONTEND=${frontend_port:-3000}
PORT_DB=${PORT_DB:-5432}
PORT_PGBOUNCER=${PORT_PGBOUNCER:-6432}
PORT_REDIS=${PORT_REDIS:-6379}
PORT_WUZAPI=${PORT_WUZAPI:-8090}
PORT_DISPATCHER=${PORT_DISPATCHER:-8095}
PORT_TRANSCRIBER=${PORT_TRANSCRIBER:-4002}

DB_USER=${empresa:-amanda}
DB_PASS=${senha_deploy:-Acertitech13@}
DB_NAME=${empresa:-amanda}
DB_NAME_APIOFICIAL=api_oficial
REDIS_URI_ACK=redis://redis:6379

JWT_SECRET=${jwt_secret}
JWT_REFRESH_SECRET=${jwt_refresh_secret}
MASTER_KEY=${senha_master}

FACEBOOK_APP_ID=${facebook_app_id:-}
FACEBOOK_APP_SECRET=${facebook_app_secret:-}

WUZAPI_ADMIN_TOKEN=adminpro123
WUZAPI_TOKEN=adminpro123
WUZAPI_WEBHOOK_BASE_URL=http://backend:8080
WUZAPI_GLOBAL_ENCRYPTION_KEY=mF9vK2xQ8zP4wR6tY1uI3oA5sD7fG0hJ
WUZAPI_GLOBAL_HMAC_KEY=kH3jL5mN7pQ9rT1vX3zB5dF7gJ9lO1qS

USE_WHATSAPP_OFICIAL=false
TOKEN_API_OFICIAL=adminpro
USE_GO_CAMPAIGN_DISPATCHER=true
TRANSCRIBE_URL=http://api_transcricao:4002
EOF
    [ "${compose_dir}" != "${app_dir}" ] && cp "${compose_dir}/.env" "${app_dir}/.env" 2>/dev/null || true
    [ -d "${compose_dir}/backend" ] && cp "${compose_dir}/.env" "${compose_dir}/backend/.env" 2>/dev/null || true
    [ -d "${compose_dir}/frontend" ] && echo "REACT_APP_BACKEND_URL=${subdominio_backend}" > "${compose_dir}/frontend/.env" 2>/dev/null || true
  fi

  banner
  printf "${PURPLE} >> Reconstruindo e reiniciando todos os contêineres da AMANDA (${empresa:-amanda})...${WHITE}\n"
  cd "${compose_dir}" || cd "${app_dir}" || return 1
  # Assegurar componente WuzAPI
  if [ ! -d "${compose_dir}/wuzapi" ]; then
    git clone --depth 1 https://github.com/asternic/wuzapi.git "${compose_dir}/wuzapi" 2>/dev/null || true
  fi

  # Assegurar Dockerfiles para que todas as imagens sejam construídas e tagueadas com o nome da empresa
  [ -f "${compose_dir}/postgres/Dockerfile" ] || (mkdir -p "${compose_dir}/postgres" && echo "FROM postgres:17" > "${compose_dir}/postgres/Dockerfile")
  [ -f "${compose_dir}/redis/Dockerfile" ] || (mkdir -p "${compose_dir}/redis" && echo "FROM redis:7.4-alpine" > "${compose_dir}/redis/Dockerfile")
  [ -f "${compose_dir}/pgbouncer/Dockerfile" ] || (mkdir -p "${compose_dir}/pgbouncer" && echo "FROM edoburu/pgbouncer:1.21.0-p2" > "${compose_dir}/pgbouncer/Dockerfile")
  [ -f "${compose_dir}/wuzapi/Dockerfile.official" ] || (mkdir -p "${compose_dir}/wuzapi" && echo "FROM asternic/wuzapi:latest" > "${compose_dir}/wuzapi/Dockerfile.official")
  if [ -f "${compose_dir}/docker-compose.yml" ]; then
    python3 - "${compose_dir}/docker-compose.yml" "${empresa:-amanda}" << 'PYEOF'
import sys, re
compose_file = sys.argv[1]
with open(compose_file, "r", encoding="utf-8") as f:
    content = f.read()
if not re.search(r"^name:\s*", content, re.M):
    content = "name: ${COMPOSE_PROJECT_NAME:-amanda}\n" + content
content = re.sub(r'container_name:\s*(?:multiflow|amanda)_', 'container_name: ${COMPOSE_PROJECT_NAME:-amanda}_', content)
with open(compose_file, "w", encoding="utf-8") as f:
    f.write(content)
PYEOF
  fi

  # Validação de integridade do Compose antes do build
  if ! docker compose -p "${empresa:-amanda}" config >/dev/null 2>&1; then
    printf "${YELLOW} >> Detectada anomalia no docker-compose.yml. Restaurando compose original do repositório...${WHITE}\n"
    git checkout -f docker-compose.yml 2>/dev/null || true
  fi

  docker compose -p "${empresa:-amanda}" pull 2>/dev/null || true
  docker compose -p "${empresa:-amanda}" up -d --build --force-recreate backend frontend api_transcricao goflow_dispatcher || return 1

  # Localizar contêineres dinamicamente para esta empresa
  local be_container oficial_container
  be_container=$(mf_container_servico "${empresa:-amanda}" backend) || return 1
  oficial_container=$(mf_container_servico "${empresa:-amanda}" api_oficial) || oficial_container=""

  banner
  printf "${PURPLE} >> Executando migrações do banco de dados (Backend e API Oficial)...${WHITE}\n"
  echo
  [ -n "$be_container" ] || return 1
  docker exec "$be_container" npx sequelize db:migrate || return 1
  [ -n "$oficial_container" ] && {
    docker exec "$oficial_container" npx prisma migrate deploy || return 1
  }

  local criticos=()
  [ -n "$be_container" ] && criticos+=("$be_container")
  [ -n "$oficial_container" ] && criticos+=("$oficial_container")
  if ! mf_verificar_servicos_criticos_docker "${criticos[@]}"; then
    return 1
  fi

  banner
  printf "   ${GREEN}>> ATUALIZAÇÃO AMANDA CONCLUÍDA COM SUCESSO!${WHITE}\n\n"
  printf "   ${PURPLE}>> Status dos Contêineres:${WHITE}\n"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "multiflow|amanda|NAMES" || docker ps
  echo
  printf "${WHITE}>> Pressione Enter para voltar ao menu principal...${WHITE}\n"
  read -r
  return 0
}

# Atualiza uma variável sem substituir o restante do arquivo .env.
mf_watchtower_set_env() {
  local env_file="$1"
  local key="$2"
  local value="$3"
  local temp_file

  temp_file=$(mktemp "${env_file}.tmp.XXXXXX") || return 1
  if [ -f "${env_file}" ]; then
    awk -v key="${key}" -v value="${value}" '
      index($0, key "=") == 1 {
        if (!replaced) print key "=" value
        replaced = 1
        next
      }
      { print }
      END {
        if (!replaced) print key "=" value
      }
    ' "${env_file}" > "${temp_file}" || {
      rm -f "${temp_file}"
      return 1
    }
  else
    printf '%s=%s\n' "${key}" "${value}" > "${temp_file}" || {
      rm -f "${temp_file}"
      return 1
    }
  fi

  chmod 600 "${temp_file}" &&
    chown deploy:deploy "${temp_file}" &&
    mv -f "${temp_file}" "${env_file}"
}

# Prepara uma instância de homologação e oferece ativar o Watchtower.
configurar_watchtower_homologacao() {
  selecionar_instancia_atualizar "configurar homologação GHCR" || return 0
  local branch="v1.0131012a"
  local app_dir="/home/deploy/${empresa:-amanda}"
  local repo_dir="${app_dir}"
  local compose_dir
  compose_dir=$(localizar_diretorio_compose "${app_dir}")
  local origin_url=""
  local origin_normalizado=""
  local estado_git=""
  local docker_config_dir="/root/.docker"
  local docker_config_file="/root/.docker/config.json"
  local ghcr_user=""
  local ghcr_token=""
  local confirmar=""
  local ativar=""
  local env_source=""
  local candidate=""

  banner
  printf "   ${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "   ${PURPLE}║${WHITE}     HOMOLOGAÇÃO GHCR E ATUALIZAÇÃO AUTOMÁTICA              ${PURPLE}║${WHITE}\n"
  printf "   ${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
  printf "${YELLOW} >> Esta opção muda o código da plataforma para a branch ${branch}.${WHITE}\n"
  printf "${YELLOW} >> Ela atualiza somente backend, frontend, transcrição e GoFlow.${WHITE}\n"
  printf "${YELLOW} >> PostgreSQL, PgBouncer, Redis e WuzAPI não serão atualizados.${WHITE}\n\n"
  printf "${WHITE}   Deseja continuar? (S/N): ${PURPLE}"
  read -r confirmar
  confirmar=$(printf '%s' "${confirmar}" | tr '[:lower:]' '[:upper:]')
  [ "${confirmar}" != "S" ] && return 0

  if [ ! -d "${app_dir}/.git" ] && [ -d "${app_dir}/amanda/.git" ]; then
    repo_dir="${app_dir}/amanda"
  elif [ ! -d "${app_dir}/.git" ] && [ -d "${compose_dir}/.git" ]; then
    repo_dir="${compose_dir}"
  fi
  if [ ! -d "${repo_dir}/.git" ]; then
    printf "${RED} >> Repositório da plataforma não encontrado em ${app_dir}.${WHITE}\n"
    printf "${YELLOW} >> Instale primeiro a plataforma pelo menu principal.${WHITE}\n"
    return 1
  fi
  if ! id deploy >/dev/null 2>&1; then
    printf "${RED} >> O usuário deploy não existe; não é possível atualizar o repositório com segurança.${WHITE}\n"
    return 1
  fi

  origin_url=$(sudo -u deploy -- git -C "${repo_dir}" remote get-url origin 2>/dev/null) || {
    printf "${RED} >> Não foi possível validar o repositório remoto da plataforma.${WHITE}\n"
    return 1
  }
  origin_normalizado=$(printf '%s' "${origin_url}" | sed -E 's#^(https?://)[^/@]+@#\1#' | tr '[:upper:]' '[:lower:]')
  case "${origin_normalizado}" in
    https://github.com/alansuporteamanda/amanda|https://github.com/alansuporteamanda/amanda.git|git@github.com:alansuporteamanda/amanda|git@github.com:alansuporteamanda/amanda.git)
      ;;
    *)
      printf "${RED} >> Esta opção só pode ser usada com o repositório oficial AMANDA.${WHITE}\n"
      return 1
      ;;
  esac

  estado_git=$(sudo -u deploy -- git -C "${repo_dir}" status --porcelain 2>/dev/null) || {
    printf "${RED} >> Não foi possível verificar o estado local do repositório.${WHITE}\n"
    return 1
  }
  if [ -n "${estado_git}" ]; then
    printf "${RED} >> Há alterações locais no repositório. Salve ou remova-as antes de trocar de branch.${WHITE}\n"
    return 1
  fi

  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    printf "${RED} >> Docker não está disponível ou não está em execução.${WHITE}\n"
    return 1
  fi

  printf "${WHITE}   Usuário do GitHub com acesso de leitura ao GHCR: ${PURPLE}"
  read -r ghcr_user
  if [ -z "${ghcr_user}" ]; then
    printf "${RED} >> O usuário do GitHub não pode ficar vazio.${WHITE}\n"
    return 1
  fi
  printf "${WHITE}   Token GHCR (read:packages; entrada oculta): ${PURPLE}"
  read -r -s ghcr_token
  printf "\n"
  if [ -z "${ghcr_token}" ]; then
    printf "${RED} >> O token não pode ficar vazio.${WHITE}\n"
    return 1
  fi

  mkdir -p "${docker_config_dir}" || return 1
  chmod 700 "${docker_config_dir}" || return 1
  if ! printf '%s' "${ghcr_token}" | DOCKER_CONFIG="${docker_config_dir}" docker login ghcr.io --username "${ghcr_user}" --password-stdin; then
    unset ghcr_token
    printf "${RED} >> Login no GHCR falhou. Verifique o usuário, o token e a permissão read:packages.${WHITE}\n"
    return 1
  fi
  unset ghcr_token
  chmod 600 "${docker_config_file}" || {
    printf "${RED} >> Não foi possível restringir as permissões de ${docker_config_file}.${WHITE}\n"
    return 1
  }

  printf "${WHITE} >> Baixando a versão de homologação do repositório...${WHITE}\n"
  if ! sudo -u deploy -- git -C "${repo_dir}" fetch origin "refs/heads/${branch}:refs/remotes/origin/${branch}" ||
    ! sudo -u deploy -- git -C "${repo_dir}" checkout -B "${branch}" "origin/${branch}"; then
    printf "${RED} >> Não foi possível preparar a branch ${branch}.${WHITE}\n"
    return 1
  fi

  compose_dir=$(localizar_diretorio_compose "${repo_dir}")
  if [ ! -f "${compose_dir}/docker-compose.yml" ] || [ ! -f "${compose_dir}/.env" ]; then
    if [ ! -f "${compose_dir}/.env" ]; then
      for candidate in "${repo_dir}/.env" "${app_dir}/.env" "${app_dir}/amanda/.env"; do
        if [ -f "${candidate}" ]; then
          env_source="${candidate}"
          break
        fi
      done
      if [ -n "${env_source}" ]; then
        cp "${env_source}" "${compose_dir}/.env" &&
          chown deploy:deploy "${compose_dir}/.env" &&
          chmod 600 "${compose_dir}/.env"
      fi
    fi
  fi
  if [ ! -f "${compose_dir}/docker-compose.yml" ] || [ ! -f "${compose_dir}/.env" ]; then
    printf "${RED} >> Compose ou .env não encontrado em ${compose_dir}.${WHITE}\n"
    printf "${YELLOW} >> Confira a instalação antes de continuar; nenhum container foi iniciado por esta opção.${WHITE}\n"
    return 1
  fi

  local image
  for image in amanda-backend amanda-frontend amanda-api-transcricao amanda-goflow-dispatcher; do
    if ! grep -Fq "image: ghcr.io/alansuporteamanda/${image}:" "${compose_dir}/docker-compose.yml"; then
      printf "${RED} >> O Compose não contém todas as imagens GHCR esperadas.${WHITE}\n"
      return 1
    fi
  done
  local enabled_labels
  enabled_labels=$(grep -Fc 'com.centurylinklabs.watchtower.enable: "true"' "${compose_dir}/docker-compose.yml")
  if [ "${enabled_labels}" -ne 4 ] ||
    ! grep -q '^  watchtower:' "${compose_dir}/docker-compose.yml" ||
    ! grep -q 'auto-update' "${compose_dir}/docker-compose.yml"; then
    printf "${RED} >> O Compose não parece oferecer suporte ao perfil do Watchtower.${WHITE}\n"
    return 1
  fi

  if ! mf_watchtower_set_env "${compose_dir}/.env" "APP_VERSION" "${branch}" ||
    ! mf_watchtower_set_env "${compose_dir}/.env" "DOCKER_CONFIG_FILE" "${docker_config_file}"; then
    printf "${RED} >> Falha ao salvar as configurações de homologação no arquivo .env.${WHITE}\n"
    return 1
  fi
  if ! grep -q '^WATCHTOWER_POLL_INTERVAL=' "${compose_dir}/.env" &&
    ! mf_watchtower_set_env "${compose_dir}/.env" "WATCHTOWER_POLL_INTERVAL" "1800"; then
    printf "${RED} >> Falha ao configurar o intervalo de verificação do Watchtower.${WHITE}\n"
    return 1
  fi

  if ! (cd "${compose_dir}" && DOCKER_CONFIG="${docker_config_dir}" docker compose --profile auto-update config --quiet); then
    printf "${RED} >> A validação do Docker Compose falhou; os containers não foram alterados.${WHITE}\n"
    return 1
  fi
  if ! (cd "${compose_dir}" && DOCKER_CONFIG="${docker_config_dir}" docker compose pull backend frontend api_transcricao goflow_dispatcher); then
    printf "${RED} >> Não foi possível baixar as imagens publicadas no GHCR.${WHITE}\n"
    printf "${YELLOW} >> Corrija o acesso e execute novamente esta opção; Watchtower continua desligado.${WHITE}\n"
    return 1
  fi
  if ! (cd "${compose_dir}" && DOCKER_CONFIG="${docker_config_dir}" docker compose up -d --no-build backend frontend api_transcricao goflow_dispatcher); then
    printf "${RED} >> Falha ao iniciar os serviços de homologação.${WHITE}\n"
    return 1
  fi

  banner
  printf "${GREEN} >> Imagens de homologação aplicadas com sucesso.${WHITE}\n\n"
  (cd "${compose_dir}" && docker compose ps backend frontend api_transcricao goflow_dispatcher)
  echo
  printf "${WHITE}   Deseja ativar agora o Watchtower? (S/N): ${PURPLE}"
  read -r ativar
  ativar=$(printf '%s' "${ativar}" | tr '[:lower:]' '[:upper:]')
  if [ "${ativar}" = "S" ]; then
    if ! (cd "${compose_dir}" && DOCKER_CONFIG="${docker_config_dir}" docker compose --profile auto-update up -d watchtower); then
      printf "${RED} >> Não foi possível iniciar o Watchtower. Os serviços continuam na versão aplicada.${WHITE}\n"
      return 1
    fi
    printf "${GREEN} >> Watchtower ativado. Ele verificará novas imagens a cada 30 minutos.${WHITE}\n"
  else
    printf "${YELLOW} >> Watchtower permaneceu desligado. Você pode ativá-lo depois pelo menu.${WHITE}\n"
  fi
  printf "${YELLOW} >> Para enviar alertas, configure WATCHTOWER_NOTIFICATION_URL no arquivo .env; atualmente nenhum provedor foi escolhido.${WHITE}\n"
  echo
  printf "${WHITE}>> Pressione Enter para voltar ao menu principal...${WHITE}\n"
  read -r
  return 0
}

# ================================================================
# STATUS E REINICIALIZAÇÃO DE CONTÊINERES
# ================================================================
menu_status_reiniciar_containers() {
  selecionar_instancia_atualizar "gerenciar contêineres" || return 0
  local emp="${empresa:-amanda}"
  banner
  printf "   ${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "   ${PURPLE}║${WHITE}            STATUS E REINÍCIO DE CONTÊINERES                  ${PURPLE}║${WHITE}\n"
  printf "   ${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
  printf "   ${WHITE}Instância selecionada: ${GREEN}%s${WHITE}\n\n" "$emp"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "${emp}_|NAMES" || docker ps
  echo
  printf "   ${WHITE}Opções:\n"
  printf "     [1] Reiniciar TODOS os contêineres da instância [%s]\n" "$emp"
  printf "     [2] Reiniciar apenas Backend (${emp}_backend)\n"
  printf "     [3] Reiniciar apenas Frontend (${emp}_frontend)\n"
  printf "     [4] Reiniciar apenas API Oficial (${emp}_apioficial)\n"
  printf "     [5] Reiniciar apenas WuzAPI (${emp}_wuzapi)\n"
  printf "     [6] Reiniciar apenas Transcrição (${emp}_transcricao)\n"
  printf "     [0] Voltar ao Menu Principal\n\n"
  printf "${WHITE}   Escolha uma opção: ${PURPLE}"
  read -r op_rest
  case "$op_rest" in
    1) docker restart $(docker ps -q --filter "name=${emp}_") 2>/dev/null || true; printf "${GREEN} >> Contêineres de ${emp} reiniciados!${WHITE}\n"; sleep 2 ;;
    2) docker restart $(docker ps -q --filter "name=${emp}_backend") 2>/dev/null || true; printf "${GREEN} >> Backend de ${emp} reiniciado!${WHITE}\n"; sleep 2 ;;
    3) docker restart $(docker ps -q --filter "name=${emp}_frontend") 2>/dev/null || true; printf "${GREEN} >> Frontend de ${emp} reiniciado!${WHITE}\n"; sleep 2 ;;
    4) docker restart $(docker ps -q --filter "name=${emp}_apioficial") 2>/dev/null || true; printf "${GREEN} >> API Oficial de ${emp} reiniciada!${WHITE}\n"; sleep 2 ;;
    5) docker restart $(docker ps -q --filter "name=${emp}_wuzapi") 2>/dev/null || true; printf "${GREEN} >> WuzAPI de ${emp} reiniciada!${WHITE}\n"; sleep 2 ;;
    6) docker restart $(docker ps -q --filter "name=${emp}_transcricao") 2>/dev/null || true; printf "${GREEN} >> Transcrição de ${emp} reiniciada!${WHITE}\n"; sleep 2 ;;
    *) ;;
  esac
}

# ================================================================
# LOGS EM TEMPO REAL
# ================================================================
menu_logs_containers() {
  selecionar_instancia_atualizar "ver logs" || return 0
  banner
  printf "${PURPLE} >> Exibindo logs dos contêineres de [%s] (Pressione CTRL+C para sair dos logs e voltar)...\n${WHITE}" "${empresa:-amanda}"
  sleep 2
  local app_dir="/home/deploy/${empresa:-amanda}"
  local compose_dir
  compose_dir=$(localizar_diretorio_compose "${app_dir}")
  cd "$compose_dir" 2>/dev/null || true
  docker compose -p "${empresa:-amanda}" logs -f --tail=100
}

# ================================================================
# BACKUP DO BANCO POSTGRESQL (DOCKER)
# ================================================================
exec_backup_banco_docker() {
  selecionar_instancia_atualizar "fazer backup" || return 0
  banner
  printf "${PURPLE} >> Gerando backup do banco de dados PostgreSQL ([%s])...${WHITE}\n" "${empresa:-amanda}"
  local backup_dir="/home/deploy/backups"
  mf_validar_empresa "${empresa:-amanda}" || return 1
  mkdir -p "$backup_dir" || return 1
  local pg_container backup_tmp backup_file
  pg_container=$(mf_container_servico "${empresa:-amanda}" postgres) || return 1
  backup_tmp=$(mktemp "${backup_dir}/${empresa:-amanda}_backup_$(date +%Y%m%d_%H%M%S)_XXXXXX") || return 1
  backup_file="${backup_tmp}.sql"
  if docker exec "$pg_container" pg_dump -U "${empresa:-amanda}" "${empresa:-amanda}" > "$backup_tmp" && [ -s "$backup_tmp" ] && mv -- "$backup_tmp" "$backup_file"; then
    printf "${GREEN} >> Backup gerado com sucesso em: ${PURPLE}%s${WHITE}\n" "$backup_file"
  else
    printf "${RED} >> Erro ao gerar backup do banco de dados.${WHITE}\n"
    rm -f -- "$backup_tmp"
    return 1
  fi
  echo
  printf "${WHITE}>> Pressione Enter para continuar...${WHITE}\n"
  read -r
}

# ================================================================
# RESTAURAR BANCO POSTGRESQL (DOCKER)
# ================================================================
exec_restaurar_banco_docker() {
  selecionar_instancia_atualizar "restaurar backup" || return 0
  banner
  printf "${PURPLE} >> Restaurar backup do banco de dados PostgreSQL ([%s])...${WHITE}\n" "${empresa:-amanda}"
  printf "${WHITE} >> Digite o caminho completo do arquivo .sql de backup: ${PURPLE}\n"
  read -r arq_backup
  if [ ! -f "$arq_backup" ]; then
    printf "${RED} >> Arquivo não encontrado: %s${WHITE}\n" "$arq_backup"
    sleep 2
    return 1
  fi
  printf "${YELLOW} >> Importar SQL em [%s] em uma transação? A base deve estar preparada para o dump; conflitos interrompem a importação. (S/N): ${PURPLE}" "${empresa:-amanda}"
  read -r conf_rest
  conf_rest=$(echo "$conf_rest" | tr '[:lower:]' '[:upper:]')
  if [ "$conf_rest" = "S" ]; then
    local pg_c
    pg_c=$(mf_container_servico "${empresa:-amanda}" postgres) || return 1
    if ! docker exec -i "$pg_c" psql -X -v ON_ERROR_STOP=1 --single-transaction -U "${empresa:-amanda}" "${empresa:-amanda}" < "$arq_backup"; then
      printf '%s\n' 'Falha na restauração; nenhuma conclusão de sucesso foi registrada.' >&2
      return 1
    fi
    printf "${GREEN} >> Restauração concluída! Reiniciando backend...${WHITE}\n"
    docker restart "${empresa:-amanda}_backend" 2>/dev/null || true
  fi
  echo
  printf "${WHITE}>> Pressione Enter para continuar...${WHITE}\n"
  read -r
}

# Resetar etapas e variáveis
resetar_instalacao() {
  rm -f $ARQUIVO_VARIAVEIS $ARQUIVO_ETAPAS
  printf "${GREEN} >> Instalação resetada! Iniciando uma nova instalação...${WHITE}\n"
  sleep 2
  instalar_amanda_docker_stack
}

iniciar_instalacao_nova_instancia() {
  banner
  printf "   ${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "   ${PURPLE}║${WHITE}         INSTALAR NOVA PLATAFORMA ADICIONAL (MULTI-EMPRESA)    ${PURPLE}║${WHITE}\n"
  printf "   ${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
  printf "${WHITE} >> Esta opção permite rodar mais de uma AMANDA de forma 100%% independente nesta VPS.\n"
  printf "${WHITE} >> Cada instância terá seus próprios contêineres, volumes de banco e portas isoladas.\n\n"

  detectar_instancias_instaladas
  local nova_empresa=""
  while true; do
    printf "${WHITE} >> Digite o ${GREEN}Nome da Nova Empresa${WHITE} (letras minusculas, sem espaço/acentos, ex: amanda2, filial_sp): ${WHITE}\n"
    read -p "> " nova_empresa
    nova_empresa=$(echo "$nova_empresa" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')
    if [ -z "$nova_empresa" ]; then
      printf "${RED}❌ O nome da empresa não pode ficar vazio.${WHITE}\n\n"
      continue
    fi
    local duplicado=0
    for e in "${NOMES_EMPRESAS_DETECTADAS[@]}"; do
      if [ "$e" = "$nova_empresa" ]; then
        duplicado=1
        break
      fi
    done
    if [ $duplicado -eq 1 ] || [ -d "/home/deploy/${nova_empresa}" ]; then
      printf "${RED}❌ Já existe uma instalação com o nome '%s' nesta VPS! Escolha outro nome.${WHITE}\n\n" "$nova_empresa"
      continue
    fi
    break
  done

  # Configurar variáveis de sessão específicas para a nova instância
  empresa="${nova_empresa}"
  ARQUIVO_VARIAVEIS="VARIAVEIS_INSTALACAO_INSTANCIA_${nova_empresa}"
  ARQUIVO_ETAPAS="ETAPA_INSTALACAO_${nova_empresa}"
  etapa=0
  salvar_etapa 0

  # Executar o fluxo padrão de coleta e confirmação de dados
  questoes_dns_base || trata_erro "questoes_dns_base"
  verificar_dns_base || trata_erro "verificar_dns_base"
  questoes_variaveis_base || trata_erro "questoes_variaveis_base"
  define_proxy_base || trata_erro "define_proxy_base"
  define_portas_base || trata_erro "define_portas_base"
  confirma_dados_instalacao_base || trata_erro "confirma_dados_instalacao_base"
  salvar_variaveis || trata_erro "salvar_variaveis"
  salvar_etapa 1
  export DADOS_COLETADOS_NOVA_INSTANCIA=1

  # Executa a stack de instalação Docker 100% isolada
  instalar_amanda_docker_stack
}

selecionar_instancia_para_reinstalar() {
  detectar_instancias_instaladas
  banner
  printf "${WHITE} >> Selecione qual instalação deseja resetar ou reinstalar:\n\n"
  for i in "${!NOMES_EMPRESAS_DETECTADAS[@]}"; do
    printf "   [${BLUE}%d${WHITE}] %s (/home/deploy/%s)\n" "$((i+1))" "${NOMES_EMPRESAS_DETECTADAS[$i]}" "${NOMES_EMPRESAS_DETECTADAS[$i]}"
  done
  printf "   [${BLUE}0${WHITE}] Voltar ao Menu Principal\n\n"
  read -p "> " sel
  if [ "$sel" = "0" ] || [ -z "$sel" ]; then
    return 0
  fi
  local idx=$((sel - 1))
  if [ $idx -ge 0 ] && [ $idx -lt ${#INSTANCIAS_DETECTADAS[@]} ]; then
    ARQUIVO_VARIAVEIS="${INSTANCIAS_DETECTADAS[$idx]}"
    mf_carregar_config "$ARQUIVO_VARIAVEIS" 2>/dev/null
    if [ -f "ETAPA_INSTALACAO_${empresa}" ]; then
      ARQUIVO_ETAPAS="ETAPA_INSTALACAO_${empresa}"
    else
      ARQUIVO_ETAPAS="ETAPA_INSTALACAO"
    fi
    resetar_instalacao
  fi
}

# Pergunta se deseja continuar ou recomeçar
verificar_arquivos_existentes() {
  detectar_instancias_instaladas
  local total_instancias=${#INSTANCIAS_DETECTADAS[@]}

  if [ $total_instancias -gt 0 ]; then
    banner
    printf "   ${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
    printf "   ${PURPLE}║${WHITE}          GERENCIADOR DE INSTALAÇÕES (MULTI-EMPRESA)           ${PURPLE}║${WHITE}\n"
    printf "   ${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
    printf "${GREEN} >> Detectada(s) ${total_instancias} plataforma(s) instalada(s) nesta VPS:${WHITE}\n\n"
    for i in "${!NOMES_EMPRESAS_DETECTADAS[@]}"; do
      printf "      • ${BLUE}%s${WHITE} (/home/deploy/%s)\n" "${NOMES_EMPRESAS_DETECTADAS[$i]}" "${NOMES_EMPRESAS_DETECTADAS[$i]}"
    done
    echo
    printf "   [${BLUE}1${WHITE}] Instalar uma ${GREEN}NOVA PLATAFORMA ADICIONAL${WHITE} (Multi-Empresa / Nova Empresa)\n"
    printf "   [${BLUE}2${WHITE}] Reinstalar ou Continuar instalação de uma empresa existente\n"
    printf "   [${BLUE}0${WHITE}] Voltar ao Menu Principal\n\n"
    read -p "> " escolha_modo
    case "${escolha_modo}" in
      1)
        iniciar_instalacao_nova_instancia
        ;;
      2)
        selecionar_instancia_para_reinstalar
        ;;
      0)
        return 0
        ;;
      *)
        printf "${RED}Opção inválida.${WHITE}\n"
        sleep 2
        return 0
        ;;
    esac
  elif [ -f "$ARQUIVO_VARIAVEIS" ] && [ -f "$ARQUIVO_ETAPAS" ]; then
    carregar_etapa
    if [ "$etapa" -eq 21 ]; then
      banner
      printf "${YELLOW} >> Instalação anterior detectada (já concluída).\n\n"
      printf "   [${BLUE}1${WHITE}] Instalar uma ${GREEN}NOVA PLATAFORMA ADICIONAL${WHITE} (Multi-Empresa)\n"
      printf "   [${BLUE}2${WHITE}] Resetar e reinstalar a plataforma atual (${empresa:-amanda})\n"
      printf "   [${BLUE}0${WHITE}] Voltar ao Menu Principal\n\n"
      read -p "> " escolha_inst
      case "${escolha_inst}" in
        1)
          iniciar_instalacao_nova_instancia
          ;;
        2)
          resetar_instalacao
          ;;
        0)
          return 0
          ;;
        *)
          return 0
          ;;
      esac
    elif [ "$etapa" -lt 21 ]; then
      banner
      printf "${YELLOW} >> Instalação Incompleta Detectada na etapa $etapa.\n"
      printf "${WHITE} >> Deseja continuar de onde parou? (S/N): ${WHITE}"
      read -r escolha_cont
      escolha_cont=$(echo "${escolha_cont}" | tr '[:lower:]' '[:upper:]')
      if [ "$escolha_cont" == "S" ]; then
        instalar_amanda_docker_stack
      else
        return 0
      fi
    fi
  else
    instalar_amanda_docker_stack
  fi
}

# Função para atualizar MultiFlow VOZ já instalado (git pull + rebuild)
atualizar_multiflow_voz() {
  banner
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  printf "${YELLOW}⚠️  ATUALIZAR MULTIFLOW VOZ${WHITE}\n"
  echo
  printf "${WHITE}   Atualiza o código do repositório (git) e recompila API + Frontend + Engine.${WHITE}\n"
  printf "${WHITE}   Mantém .env, SQLite, gravações e configurações já salvas.${WHITE}\n"
  echo
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  echo
  printf "${WHITE}   Deseja continuar? (S/N):${WHITE}\n"
  echo
  read -p "> " confirmacao_voz_upd
  confirmacao_voz_upd=$(echo "${confirmacao_voz_upd}" | tr '[:lower:]' '[:upper:]')
  echo

  if [ "${confirmacao_voz_upd}" != "S" ]; then
    printf "${GREEN} >> Operação cancelada. Voltando ao menu de ferramentas...${WHITE}\n"
    sleep 2
    return
  fi

  banner
  printf "${WHITE} >> Digite o TOKEN de autorização do GitHub (acesso ao repositório multiflow-voz):${WHITE}\n"
  echo
  read -p "> " TOKEN_AUTH

  if [ -z "$TOKEN_AUTH" ]; then
    printf "${RED}❌ ERRO: Token de autorização não pode estar vazio.${WHITE}\n"
    sleep 2
    return
  fi

  printf "${BLUE} >> Token recebido. Validando acesso ao repositório...${WHITE}\n"
  echo

  INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  TEST_DIR="${INSTALADOR_DIR}/test_clone_voz_upd_$(date +%s)"
  REPO_URL="https://${TOKEN_AUTH}@github.com/scriptswhitelabel/multiflow-voz.git"

  if git clone --depth 1 "${REPO_URL}" "${TEST_DIR}" >/dev/null 2>&1; then
    rm -rf "${TEST_DIR}" >/dev/null 2>&1
    printf "${GREEN}✅ Token validado com sucesso!${WHITE}\n"
    echo
    sleep 1

    VOZ_SCRIPT="${INSTALADOR_DIR}/tools/instalador_multiflow_voz.sh"
    if [ -f "$VOZ_SCRIPT" ]; then
      chmod 775 "$VOZ_SCRIPT"
      printf "${GREEN} >> Executando atualização MultiFlow-VOZ...${WHITE}\n"
      echo
      TOKEN_AUTH="${TOKEN_AUTH}" bash "$VOZ_SCRIPT" --atualizar
      echo
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
    else
      printf "${RED} >> Erro: Arquivo ${VOZ_SCRIPT} não encontrado!${WHITE}\n"
      sleep 3
    fi
  else
    rm -rf "${TEST_DIR}" >/dev/null 2>&1
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    printf "${RED}❌ ERRO: Token inválido ou sem acesso ao repositório multiflow-voz.${WHITE}\n"
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    echo
    printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
    read -r
  fi
}

# Função para instalar MultiFlow VOZ (softphone / ligações)
instalar_multiflow_voz() {
  banner
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  printf "${YELLOW}⚠️  MULTIFLOW VOZ${WHITE}\n"
  echo
  printf "${WHITE}   Instala o sistema de ligações WhatsApp (API + Frontend + Engine).${WHITE}\n"
  printf "${WHITE}   Pode ser no mesmo VPS do Multiflow (reaproveita variáveis) ou em VPS limpo.${WHITE}\n"
  echo
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  echo
  printf "${WHITE}   Deseja continuar? (S/N):${WHITE}\n"
  echo
  read -p "> " confirmacao_voz
  confirmacao_voz=$(echo "${confirmacao_voz}" | tr '[:lower:]' '[:upper:]')
  echo

  if [ "${confirmacao_voz}" != "S" ]; then
    printf "${GREEN} >> Operação cancelada. Voltando ao menu de ferramentas...${WHITE}\n"
    sleep 2
    return
  fi

  banner
  printf "${WHITE} >> Digite o TOKEN de autorização do GitHub (acesso ao repositório multiflow-voz):${WHITE}\n"
  echo
  read -p "> " TOKEN_AUTH

  if [ -z "$TOKEN_AUTH" ]; then
    printf "${RED}❌ ERRO: Token de autorização não pode estar vazio.${WHITE}\n"
    sleep 2
    return
  fi

  printf "${BLUE} >> Token recebido. Validando acesso ao repositório...${WHITE}\n"
  echo

  INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  TEST_DIR="${INSTALADOR_DIR}/test_clone_voz_$(date +%s)"
  REPO_URL="https://${TOKEN_AUTH}@github.com/scriptswhitelabel/multiflow-voz.git"

  if git clone --depth 1 "${REPO_URL}" "${TEST_DIR}" >/dev/null 2>&1; then
    rm -rf "${TEST_DIR}" >/dev/null 2>&1
    printf "${GREEN}✅ Token validado com sucesso!${WHITE}\n"
    echo
    sleep 1

    VOZ_SCRIPT="${INSTALADOR_DIR}/tools/instalador_multiflow_voz.sh"
    if [ -f "$VOZ_SCRIPT" ]; then
      chmod 775 "$VOZ_SCRIPT"
      printf "${GREEN} >> Executando Instalador MultiFlow-VOZ...${WHITE}\n"
      echo
      TOKEN_AUTH="${TOKEN_AUTH}" bash "$VOZ_SCRIPT"
      echo
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
    else
      printf "${RED} >> Erro: Arquivo ${VOZ_SCRIPT} não encontrado!${WHITE}\n"
      sleep 3
    fi
  else
    rm -rf "${TEST_DIR}" >/dev/null 2>&1
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    printf "${RED}❌ ERRO: Token inválido ou sem acesso ao repositório multiflow-voz.${WHITE}\n"
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    echo
    printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
    read -r
  fi
}

# Função para atualizar HUB MultiFlow já instalado
atualizar_multiflow_hub() {
  banner
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  printf "${YELLOW}⚠️  ATUALIZAR HUB MULTIFLOW${WHITE}\n"
  echo
  printf "${WHITE}   Atualiza o código do repositório (git) e recompila backend + painel.${WHITE}\n"
  printf "${WHITE}   Mantém .env, banco, Nginx e configurações já salvas (com rollback automático).${WHITE}\n"
  echo
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  echo
  printf "${WHITE}   Deseja continuar? (S/N):${WHITE}\n"
  echo
  read -p "> " confirmacao_hub_upd
  confirmacao_hub_upd=$(echo "${confirmacao_hub_upd}" | tr '[:lower:]' '[:upper:]')
  echo

  if [ "${confirmacao_hub_upd}" != "S" ]; then
    printf "${GREEN} >> Operação cancelada. Voltando ao menu de ferramentas...${WHITE}\n"
    sleep 2
    return
  fi

  banner
  printf "${WHITE} >> Digite o TOKEN de autorização do GitHub (acesso ao repositório multiflow-hub):${WHITE}\n"
  echo
  read -p "> " TOKEN_AUTH

  if [ -z "$TOKEN_AUTH" ]; then
    printf "${RED}❌ ERRO: Token de autorização não pode estar vazio.${WHITE}\n"
    sleep 2
    return
  fi

  printf "${BLUE} >> Token recebido. Validando acesso ao repositório...${WHITE}\n"
  echo

  INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  TEST_DIR="${INSTALADOR_DIR}/test_clone_hub_upd_$(date +%s)"
  REPO_URL="https://${TOKEN_AUTH}@github.com/scriptswhitelabel/multiflow-hub.git"

  if git clone --depth 1 "${REPO_URL}" "${TEST_DIR}" >/dev/null 2>&1; then
    rm -rf "${TEST_DIR}" >/dev/null 2>&1
    printf "${GREEN}✅ Token validado com sucesso!${WHITE}\n"
    echo
    sleep 1

    HUB_SCRIPT="${INSTALADOR_DIR}/tools/instalador_multiflow_hub.sh"
    if [ -f "$HUB_SCRIPT" ]; then
      chmod 775 "$HUB_SCRIPT"
      printf "${GREEN} >> Executando atualização HUB MultiFlow...${WHITE}\n"
      echo
      TOKEN_AUTH="${TOKEN_AUTH}" bash "$HUB_SCRIPT" --atualizar
      echo
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
    else
      printf "${RED} >> Erro: Arquivo ${HUB_SCRIPT} não encontrado!${WHITE}\n"
      sleep 3
    fi
  else
    rm -rf "${TEST_DIR}" >/dev/null 2>&1
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    printf "${RED}❌ ERRO: Token inválido ou sem acesso ao repositório multiflow-hub.${WHITE}\n"
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    echo
    printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
    read -r
  fi
}

# Função para instalar HUB MultiFlow (Central ou Local)
instalar_multiflow_hub() {
  banner
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  printf "${YELLOW}⚠️  HUB MULTIFLOW${WHITE}\n"
  echo
  printf "${WHITE}   Instala o HUB Meta Connect / WhatsApp Oficial (Central ou Local).${WHITE}\n"
  printf "${WHITE}   Pode ser no mesmo VPS do Multiflow (reaproveita Nginx/Postgres/Redis)${WHITE}\n"
  printf "${WHITE}   ou em VPS limpo (o instalador do HUB sobe a base completa).${WHITE}\n"
  echo
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  echo
  printf "${WHITE}   Deseja continuar? (S/N):${WHITE}\n"
  echo
  read -p "> " confirmacao_hub
  confirmacao_hub=$(echo "${confirmacao_hub}" | tr '[:lower:]' '[:upper:]')
  echo

  if [ "${confirmacao_hub}" != "S" ]; then
    printf "${GREEN} >> Operação cancelada. Voltando ao menu de ferramentas...${WHITE}\n"
    sleep 2
    return
  fi

  banner
  printf "${WHITE} >> Digite o TOKEN de autorização do GitHub (acesso ao repositório multiflow-hub):${WHITE}\n"
  echo
  read -p "> " TOKEN_AUTH

  if [ -z "$TOKEN_AUTH" ]; then
    printf "${RED}❌ ERRO: Token de autorização não pode estar vazio.${WHITE}\n"
    sleep 2
    return
  fi

  printf "${BLUE} >> Token recebido. Validando acesso ao repositório...${WHITE}\n"
  echo

  INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  TEST_DIR="${INSTALADOR_DIR}/test_clone_hub_$(date +%s)"
  REPO_URL="https://${TOKEN_AUTH}@github.com/scriptswhitelabel/multiflow-hub.git"

  if git clone --depth 1 "${REPO_URL}" "${TEST_DIR}" >/dev/null 2>&1; then
    rm -rf "${TEST_DIR}" >/dev/null 2>&1
    printf "${GREEN}✅ Token validado com sucesso!${WHITE}\n"
    echo
    sleep 1

    HUB_SCRIPT="${INSTALADOR_DIR}/tools/instalador_multiflow_hub.sh"
    if [ -f "$HUB_SCRIPT" ]; then
      chmod 775 "$HUB_SCRIPT"
      printf "${GREEN} >> Executando Instalador HUB MultiFlow...${WHITE}\n"
      echo
      TOKEN_AUTH="${TOKEN_AUTH}" bash "$HUB_SCRIPT"
      echo
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
    else
      printf "${RED} >> Erro: Arquivo ${HUB_SCRIPT} não encontrado!${WHITE}\n"
      sleep 3
    fi
  else
    rm -rf "${TEST_DIR}" >/dev/null 2>&1
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    printf "${RED}❌ ERRO: Token inválido ou sem acesso ao repositório multiflow-hub.${WHITE}\n"
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    echo
    printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
    read -r
  fi
}

# Função para instalar API WhatsMeow
instalar_whatsmeow() {
  banner
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  printf "${YELLOW}⚠️  ATENÇÃO:${WHITE}\n"
  echo
  printf "${WHITE}   A WhatsMeow é uma API Alternativa à Bayles, muito estável.${WHITE}\n"
  printf "${WHITE}   Ela está disponível apenas para a versão do MultiFlow PRO${WHITE}\n"
  printf "${WHITE}   - A partir da Versão ${BLUE}6.4.4${WHITE}.${WHITE}\n"
  echo
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  echo
  printf "${WHITE}   Deseja continuar? (S/N):${WHITE}\n"
  echo
  read -p "> " confirmacao_whatsmeow
  confirmacao_whatsmeow=$(echo "${confirmacao_whatsmeow}" | tr '[:lower:]' '[:upper:]')
  echo
  
  if [ "${confirmacao_whatsmeow}" != "S" ]; then
    printf "${GREEN} >> Operação cancelada. Voltando ao menu de ferramentas...${WHITE}\n"
    sleep 2
    return
  fi
  
  banner
  printf "${WHITE} >> Digite o TOKEN de autorização do GitHub para acesso ao repositório multiflow-pro:${WHITE}\n"
  echo
  read -p "> " TOKEN_AUTH
  
  # Verificar se o token foi informado
  if [ -z "$TOKEN_AUTH" ]; then
    printf "${RED}❌ ERRO: Token de autorização não pode estar vazio.${WHITE}\n"
    sleep 2
    return
  fi
  
  printf "${BLUE} >> Token de autorização recebido. Validando...${WHITE}\n"
  echo
  
  # Validar o token usando a mesma lógica do atualizador_pro.sh
  INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  TEST_DIR="${INSTALADOR_DIR}/test_clone_$(date +%s)"
  REPO_URL="https://${TOKEN_AUTH}@github.com/scriptswhitelabel/multiflow-pro.git"
  
  printf "${WHITE} >> Validando token com teste de git clone...\n"
  echo
  
  # Tentar fazer clone de teste
  if git clone --depth 1 "${REPO_URL}" "${TEST_DIR}" >/dev/null 2>&1; then
    # Clone bem-sucedido, remover diretório de teste
    rm -rf "${TEST_DIR}" >/dev/null 2>&1
    printf "${GREEN}✅ Token validado com sucesso! Git clone funcionou corretamente.${WHITE}\n"
    echo
    sleep 2
    
    # Executar o instalador WhatsMeow
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    WHATSMEOW_SCRIPT="${SCRIPT_DIR}/instalador_whatsmeow.sh"
    
    if [ -f "$WHATSMEOW_SCRIPT" ]; then
      printf "${GREEN} >> Executando Instalador API WhatsMeow...${WHITE}\n"
      echo
      bash "$WHATSMEOW_SCRIPT"
      echo
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
    else
      printf "${RED} >> Erro: Arquivo ${WHATSMEOW_SCRIPT} não encontrado!${WHITE}\n"
      printf "${RED} >> Certifique-se de que o arquivo instalador_whatsmeow.sh está no mesmo diretório do instalador.${WHITE}\n"
      sleep 3
    fi
  else
    # Clone falhou, token inválido
    rm -rf "${TEST_DIR}" >/dev/null 2>&1
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    printf "${RED}❌ ERRO: Token de autorização inválido!${WHITE}\n"
    echo
    printf "${RED}   O teste de git clone falhou. O token informado não tem acesso ao repositório multiflow-pro.${WHITE}\n"
    echo
    printf "${YELLOW}   ⚠️  IMPORTANTE:${WHITE}\n"
    printf "${YELLOW}   O MultiFlow PRO é um projeto fechado e requer autorização especial.${WHITE}\n"
    printf "${YELLOW}   Para solicitar acesso ou analisar a disponibilidade,${WHITE}\n"
    printf "${YELLOW}   entre em contato com o suporte:${WHITE}\n"
    echo
    printf "${BLUE}   📱 WhatsApp:${WHITE}\n"
    printf "${WHITE}   • https://wa.me/5518996755165${WHITE}\n"
    printf "${WHITE}   • https://wa.me/558499418159${WHITE}\n"
    echo
    printf "${RED}   Instalação interrompida.${WHITE}\n"
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    echo
    printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
    read -r
  fi
}

# Atualizar WhatsMeow (WuzAPI) já instalado: git pull + rebuild do container da API
atualizar_whatsmeow() {
  banner
  printf "${WHITE} >> Atualizar API WhatsMeow (WuzAPI)${WHITE}\n"
  printf "${WHITE} >> Atualiza o código (git pull) e reconstrói só o container wuzapi-server da stack existente.${WHITE}\n"
  printf "${YELLOW} >> Não cria stack nova nem remove banco Postgres / RabbitMQ.${WHITE}\n"
  echo
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  WHATSMEOW_SCRIPT="${SCRIPT_DIR}/instalador_whatsmeow.sh"
  if [ -f "$WHATSMEOW_SCRIPT" ]; then
    bash "$WHATSMEOW_SCRIPT" --atualizar
    echo
    printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
    read -r
  else
    printf "${RED} >> Arquivo ${WHATSMEOW_SCRIPT} não encontrado.${WHITE}\n"
    sleep 3
  fi
}

# --- Redis: Docker (instâncias) e nativo ---
ferramentas_redis_dir_backup_instancia() {
  printf '/home/deploy/backup-%s/redis' "${empresa}"
}

ferramentas_dir_backup_banco_instancia() {
  printf '/home/deploy/backup-%s' "$1"
}

ferramentas_carregar_redis_instancia() {
  local env_file="/home/deploy/${empresa}/backend/.env"
  REDIS_SENHA="${senha_deploy:-}"
  REDIS_PORT="6379"
  REDIS_URI_RAW=""
  REDIS_CONTAINER_PADRAO="redis_${empresa}"
  if [ -f "$env_file" ]; then
    REDIS_URI_RAW=$(grep -m1 '^REDIS_URI=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r' | head -1)
  fi
  if [ -n "$REDIS_URI_RAW" ]; then
    if [[ "$REDIS_URI_RAW" =~ redis://:([^@]+)@[^:]+:([0-9]+) ]]; then
      REDIS_SENHA="${BASH_REMATCH[1]}"
      REDIS_PORT="${BASH_REMATCH[2]}"
    elif [[ "$REDIS_URI_RAW" =~ redis://[^/@]+:([0-9]+) ]]; then
      REDIS_PORT="${BASH_REMATCH[1]}"
    fi
  fi
}

ferramentas_listar_containers_redis_docker() {
  FERRAMENTAS_REDIS_CONTAINERS=()
  local name img
  while IFS=$'\t' read -r name img; do
    [ -z "$name" ] && continue
    if echo "$name $img" | grep -qi redis; then
      FERRAMENTAS_REDIS_CONTAINERS+=("$name")
    fi
  done < <(docker ps --format '{{.Names}}\t{{.Image}}' 2>/dev/null)
}

ferramentas_redis_cli_docker() {
  local container="$1"
  shift
  if [ -n "${REDIS_SENHA}" ]; then
    docker exec "$container" redis-cli -a "${REDIS_SENHA}" "$@" 2>/dev/null
  else
    docker exec "$container" redis-cli "$@" 2>/dev/null
  fi
}

ferramentas_redis_nativo_ping() {
  if [ -n "${REDIS_SENHA}" ]; then
    redis-cli -a "${REDIS_SENHA}" -p "${REDIS_PORT}" ping 2>/dev/null | grep -q PONG
  else
    redis-cli -p "${REDIS_PORT}" ping 2>/dev/null | grep -q PONG
  fi
}

ferramentas_redis_fonte_nativo_disponivel() {
  if ferramentas_redis_nativo_ping; then
    return 0
  fi
  if [ "${REDIS_PORT}" = "6379" ] && systemctl is-active --quiet redis-server 2>/dev/null; then
    return 0
  fi
  return 1
}

ferramentas_montar_lista_fontes_redis() {
  FERRAMENTAS_REDIS_FONTES=()
  FERRAMENTAS_REDIS_FONTES_LABELS=()
  local c uri_host uri_port
  uri_host=""
  uri_port=""
  if [ -n "${REDIS_URI_RAW}" ]; then
    if [[ "$REDIS_URI_RAW" =~ redis://([^:/@]+):([0-9]+) ]]; then
      uri_host="${BASH_REMATCH[1]}"
      uri_port="${BASH_REMATCH[2]}"
    elif [[ "$REDIS_URI_RAW" =~ redis://:([^@]+)@([^:/]+):([0-9]+) ]]; then
      uri_host="${BASH_REMATCH[2]}"
      uri_port="${BASH_REMATCH[3]}"
    elif [[ "$REDIS_URI_RAW" =~ redis://([^:/@]+)/ ]]; then
      uri_host="${BASH_REMATCH[1]}"
      uri_port="6379"
    fi
  fi

  ferramentas_listar_containers_redis_docker
  for c in "${FERRAMENTAS_REDIS_CONTAINERS[@]}"; do
    FERRAMENTAS_REDIS_FONTES+=("docker:${c}")
    if [ "$c" = "${REDIS_CONTAINER_PADRAO}" ]; then
      FERRAMENTAS_REDIS_FONTES_LABELS+=("${c} (Docker — sugerido para ${empresa})")
    else
      FERRAMENTAS_REDIS_FONTES_LABELS+=("${c} (Docker)")
    fi
  done

  if ferramentas_redis_fonte_nativo_disponivel; then
    FERRAMENTAS_REDIS_FONTES+=("native:${REDIS_PORT}")
    if [ "$uri_port" = "${REDIS_PORT}" ] && { [ "$uri_host" = "127.0.0.1" ] || [ "$uri_host" = "localhost" ] || [ -z "$uri_host" ]; }; then
      FERRAMENTAS_REDIS_FONTES_LABELS+=("127.0.0.1:${REDIS_PORT} (Redis nativo local — instância ${empresa})")
    else
      FERRAMENTAS_REDIS_FONTES_LABELS+=("127.0.0.1:${REDIS_PORT} (Redis nativo local, porta ${REDIS_PORT})")
    fi
  fi
}

ferramentas_escolher_fonte_redis() {
  local prompt_msg="${1:-Escolha a fonte do Redis}"
  ferramentas_montar_lista_fontes_redis
  if [ ${#FERRAMENTAS_REDIS_FONTES[@]} -eq 0 ]; then
    return 1
  fi
  if [ ${#FERRAMENTAS_REDIS_FONTES[@]} -eq 1 ]; then
    FERRAMENTAS_REDIS_FONTE="${FERRAMENTAS_REDIS_FONTES[0]}"
    printf "${GREEN} >> Fonte Redis: ${FERRAMENTAS_REDIS_FONTES_LABELS[0]}${WHITE}\n"
    return 0
  fi
  if ferramentas_escolher_item_lista "$prompt_msg" "${FERRAMENTAS_REDIS_FONTES_LABELS[@]}"; then
    local i
    for i in "${!FERRAMENTAS_REDIS_FONTES_LABELS[@]}"; do
      if [ "${FERRAMENTAS_REDIS_FONTES_LABELS[$i]}" = "${FERRAMENTAS_ESCOLHA}" ]; then
        FERRAMENTAS_REDIS_FONTE="${FERRAMENTAS_REDIS_FONTES[$i]}"
        return 0
      fi
    done
  fi
  return 1
}

ferramentas_backup_redis_nativo() {
  local backup_dir="$1"
  local redis_dir="/var/lib/redis"
  local redis_conf="/etc/redis/redis.conf"
  [ -f "$redis_conf" ] && redis_dir=$(grep "^dir " "$redis_conf" 2>/dev/null | awk '{print $2}' || echo "/var/lib/redis")
  local dump_rdb="${redis_dir}/dump.rdb"
  local aof_file="${redis_dir}/appendonly.aof"
  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  printf "${WHITE} >> Gerando snapshot no Redis nativo (porta ${REDIS_PORT})...${WHITE}\n"
  if [ -n "${REDIS_SENHA}" ]; then
    redis-cli -a "${REDIS_SENHA}" -p "${REDIS_PORT}" BGSAVE 2>/dev/null || redis-cli BGSAVE 2>/dev/null || true
  else
    redis-cli -p "${REDIS_PORT}" BGSAVE 2>/dev/null || redis-cli BGSAVE 2>/dev/null || true
  fi
  sleep 2
  if [ -f "$dump_rdb" ]; then
    cp "$dump_rdb" "${backup_dir}/dump_${ts}.rdb"
    chown deploy:deploy "${backup_dir}/dump_${ts}.rdb" 2>/dev/null || true
    printf "${GREEN} >> Backup RDB: ${backup_dir}/dump_${ts}.rdb${WHITE}\n"
  else
    printf "${YELLOW} >> dump.rdb não encontrado em ${dump_rdb}.${WHITE}\n"
    return 1
  fi
  if [ -f "$aof_file" ]; then
    cp "$aof_file" "${backup_dir}/appendonly_${ts}.aof"
    chown deploy:deploy "${backup_dir}/appendonly_${ts}.aof" 2>/dev/null || true
    printf "${GREEN} >> Backup AOF: ${backup_dir}/appendonly_${ts}.aof${WHITE}\n"
  fi
  return 0
}

ferramentas_executar_backup_redis_fonte() {
  local backup_dir="$1"
  case "${FERRAMENTAS_REDIS_FONTE}" in
    docker:*)
      ferramentas_backup_redis_docker "${FERRAMENTAS_REDIS_FONTE#docker:}" "$backup_dir"
      ;;
    native:*)
      ferramentas_backup_redis_nativo "$backup_dir"
      ;;
    *)
      printf "${RED} >> Fonte Redis inválida: ${FERRAMENTAS_REDIS_FONTE}${WHITE}\n"
      return 1
      ;;
  esac
}

ferramentas_restaurar_redis_nativo() {
  local arquivo_rdb="$1"
  local redis_dir="/var/lib/redis"
  local redis_conf="/etc/redis/redis.conf"
  [ -f "$redis_conf" ] && redis_dir=$(grep "^dir " "$redis_conf" 2>/dev/null | awk '{print $2}' || echo "/var/lib/redis")
  local dump_rdb="${redis_dir}/dump.rdb"
  local aof_file="${redis_dir}/appendonly.aof"
  systemctl stop redis-server 2>/dev/null || true
  sleep 2
  cp "$arquivo_rdb" "$dump_rdb"
  chown redis:redis "$dump_rdb" 2>/dev/null || true
  chmod 660 "$dump_rdb" 2>/dev/null || true
  [ -f "$aof_file" ] && mv "$aof_file" "${aof_file}.bak_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
  systemctl start redis-server 2>/dev/null || true
  sleep 2
  if systemctl is-active --quiet redis-server 2>/dev/null || ferramentas_redis_nativo_ping; then
    printf "${GREEN} >> Redis nativo (porta ${REDIS_PORT}) reiniciado. Restauração concluída.${WHITE}\n"
    return 0
  fi
  printf "${RED} >> Redis nativo não respondeu após restauração.${WHITE}\n"
  return 1
}

ferramentas_executar_restaurar_redis_fonte() {
  local arquivo_rdb="$1"
  case "${FERRAMENTAS_REDIS_FONTE}" in
    docker:*)
      ferramentas_restaurar_redis_docker "${FERRAMENTAS_REDIS_FONTE#docker:}" "$arquivo_rdb"
      ;;
    native:*)
      ferramentas_restaurar_redis_nativo "$arquivo_rdb"
      ;;
    *)
      printf "${RED} >> Destino Redis inválido: ${FERRAMENTAS_REDIS_FONTE}${WHITE}\n"
      return 1
      ;;
  esac
}

ferramentas_escolher_container_redis_docker() {
  local prompt_msg="${1:-Escolha o container Redis}"
  ferramentas_listar_containers_redis_docker
  if [ ${#FERRAMENTAS_REDIS_CONTAINERS[@]} -eq 0 ]; then
    return 1
  fi
  if [ ${#FERRAMENTAS_REDIS_CONTAINERS[@]} -eq 1 ]; then
    FERRAMENTAS_REDIS_CONTAINER="${FERRAMENTAS_REDIS_CONTAINERS[0]}"
    printf "${GREEN} >> Container Redis: ${FERRAMENTAS_REDIS_CONTAINER}${WHITE}\n"
    return 0
  fi
  local labels=()
  local c
  for c in "${FERRAMENTAS_REDIS_CONTAINERS[@]}"; do
    if [ "$c" = "${REDIS_CONTAINER_PADRAO}" ]; then
      labels+=("${c} (sugerido para ${empresa})")
    else
      labels+=("$c")
    fi
  done
  if ferramentas_escolher_item_lista "$prompt_msg" "${labels[@]}"; then
    FERRAMENTAS_REDIS_CONTAINER="${FERRAMENTAS_ESCOLHA%% *}"
    return 0
  fi
  return 1
}

ferramentas_backup_redis_docker() {
  local container="$1"
  local backup_dir="$2"
  local ts
  ts=$(date +%Y%m%d_%H%M%S)
  printf "${WHITE} >> Gerando snapshot no container ${container}...${WHITE}\n"
  ferramentas_redis_cli_docker "$container" BGSAVE >/dev/null || true
  sleep 3
  if docker cp "${container}:/data/dump.rdb" "${backup_dir}/dump_${ts}.rdb" 2>/dev/null; then
    chown deploy:deploy "${backup_dir}/dump_${ts}.rdb" 2>/dev/null || true
    printf "${GREEN} >> Backup RDB: ${backup_dir}/dump_${ts}.rdb${WHITE}\n"
  else
    printf "${RED} >> Falha ao copiar dump.rdb do container ${container}.${WHITE}\n"
    return 1
  fi
  if docker cp "${container}:/data/appendonly.aof" "${backup_dir}/appendonly_${ts}.aof" 2>/dev/null; then
    chown deploy:deploy "${backup_dir}/appendonly_${ts}.aof" 2>/dev/null || true
    printf "${GREEN} >> Backup AOF: ${backup_dir}/appendonly_${ts}.aof${WHITE}\n"
  fi
  return 0
}

ferramentas_restaurar_redis_docker() {
  local container="$1"
  local arquivo_rdb="$2"
  local vol
  printf "${YELLOW} >> Parando container ${container}...${WHITE}\n"
  docker stop "$container" >/dev/null 2>&1 || true
  sleep 2
  vol=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}' "$container" 2>/dev/null)
  if [ -n "$vol" ]; then
    docker run --rm -v "${vol}:/data" -v "$(dirname "$arquivo_rdb"):/backup:ro" alpine \
      sh -c "cp /backup/$(basename "$arquivo_rdb") /data/dump.rdb && rm -f /data/appendonly.aof /data/appendonly.aof.* 2>/dev/null; chmod 644 /data/dump.rdb" 2>/dev/null \
      || docker cp "$arquivo_rdb" "${container}:/data/dump.rdb" 2>/dev/null
  else
    docker cp "$arquivo_rdb" "${container}:/data/dump.rdb" 2>/dev/null
  fi
  printf "${WHITE} >> Iniciando container ${container}...${WHITE}\n"
  docker start "$container" >/dev/null 2>&1
  sleep 3
  if docker ps --format '{{.Names}}' | grep -qx "$container"; then
    if ferramentas_redis_cli_docker "$container" PING | grep -q PONG; then
      printf "${GREEN} >> Redis no container ${container} respondeu PING. Restauração concluída.${WHITE}\n"
      return 0
    fi
    printf "${GREEN} >> Container ${container} em execução. Verifique os dados na aplicação.${WHITE}\n"
    return 0
  fi
  printf "${RED} >> Container ${container} não subiu. Verifique: docker logs ${container}${WHITE}\n"
  return 1
}

# Backup Redis: pasta da instância (/home/deploy/backup-<empresa>/redis); Docker ou nativo.
backup_redis_ferramentas() {
  banner
  printf "${WHITE} >> Backup do Redis...\n"
  echo

  if ! selecionar_instancia_atualizar "fazer backup do Redis"; then
    sleep 2
    return 1
  fi

  ferramentas_carregar_redis_instancia
  local backup_dir
  backup_dir=$(ferramentas_redis_dir_backup_instancia)
  mkdir -p "$backup_dir"
  chown deploy:deploy "$(dirname "$backup_dir")" 2>/dev/null || true
  chown deploy:deploy "$(dirname "$(dirname "$backup_dir")")" 2>/dev/null || true
  chown deploy:deploy "$backup_dir" 2>/dev/null || true

  printf "${WHITE} >> Pasta de destino: ${backup_dir}${WHITE}\n"
  echo

  if ! ferramentas_escolher_fonte_redis "Fonte do Redis para backup (instância ${empresa}):"; then
    printf "${RED} >> Nenhuma fonte Redis disponível (Docker ou nativo local).${WHITE}\n"
    sleep 2
    return 1
  fi

  ferramentas_executar_backup_redis_fonte "$backup_dir" || return 1
  printf "${GREEN} >> Backup concluído em ${backup_dir}${WHITE}\n"
  echo
  sleep 2
  return 0
}

# Restaura Redis: backups em /home/deploy/backup-<empresa>/redis → container Docker escolhido (ou nativo).
restaurar_redis_ferramentas() {
  banner
  printf "${WHITE} >> Restaurar Redis...\n"
  echo

  if ! selecionar_instancia_atualizar "restaurar o Redis"; then
    sleep 2
    return 1
  fi

  ferramentas_carregar_redis_instancia
  local backup_dir
  backup_dir=$(ferramentas_redis_dir_backup_instancia)
  if [ ! -d "$backup_dir" ]; then
    printf "${RED} >> Pasta não encontrada: ${backup_dir}${WHITE}\n"
    printf "${YELLOW} >> Coloque os arquivos .rdb nesta pasta ou faça backup pela opção 8.${WHITE}\n"
    sleep 2
    return 1
  fi

  shopt -s nullglob 2>/dev/null || true
  local rdb_backups=("$backup_dir"/dump_*.rdb "$backup_dir"/*.rdb)
  shopt -u nullglob 2>/dev/null || true
  local rdb_unicos=()
  local f seen
  for f in "${rdb_backups[@]}"; do
    [ -f "$f" ] || continue
    seen=0
    for x in "${rdb_unicos[@]}"; do
      [ "$x" = "$f" ] && seen=1 && break
    done
    [ "$seen" -eq 0 ] && rdb_unicos+=("$f")
  done
  if [ ${#rdb_unicos[@]} -eq 0 ]; then
    printf "${RED} >> Nenhum arquivo .rdb em ${backup_dir}${WHITE}\n"
    sleep 2
    return 1
  fi

  local labels=()
  for f in "${rdb_unicos[@]}"; do
    labels+=("$(basename "$f")")
  done
  if ! ferramentas_escolher_item_lista "Arquivo de backup (.rdb) da instância ${empresa}:" "${labels[@]}"; then
    printf "${YELLOW} >> Cancelado.${WHITE}\n"
    sleep 2
    return 0
  fi
  local arquivo_rdb=""
  for f in "${rdb_unicos[@]}"; do
    if [ "$(basename "$f")" = "${FERRAMENTAS_ESCOLHA}" ]; then
      arquivo_rdb="$f"
      break
    fi
  done
  if [ -z "$arquivo_rdb" ] || [ ! -f "$arquivo_rdb" ]; then
    printf "${RED} >> Arquivo não encontrado.${WHITE}\n"
    sleep 2
    return 1
  fi

  printf "${GREEN} >> Backup selecionado: $(basename "$arquivo_rdb")${WHITE}\n"
  echo

  if ! ferramentas_escolher_fonte_redis "Destino do Redis para restauração (instância ${empresa}):"; then
    printf "${RED} >> Nenhum destino Redis disponível (Docker ou nativo local).${WHITE}\n"
    sleep 2
    return 1
  fi

  local destino_msg
  case "${FERRAMENTAS_REDIS_FONTE}" in
    docker:*) destino_msg="container '${FERRAMENTAS_REDIS_FONTE#docker:}'" ;;
    native:*) destino_msg="Redis nativo local (porta ${REDIS_PORT})" ;;
    *) destino_msg="${FERRAMENTAS_REDIS_FONTE}" ;;
  esac
  printf "${YELLOW} >> ATENÇÃO: o ${destino_msg} será substituído pelo backup. Continuar? (s/N):${WHITE}\n"
  read -p "> " confirma
  if [ "$confirma" != "s" ] && [ "$confirma" != "S" ]; then
    printf "${YELLOW} >> Cancelado.${WHITE}\n"
    sleep 2
    return 0
  fi
  ferramentas_executar_restaurar_redis_fonte "$arquivo_rdb"
  echo
  sleep 2
  return 0
}

# Carrega credenciais PostgreSQL nativo do .env da instância (empresa já definida).
# Define: PG_USUARIO, PG_SENHA, PG_HOST, PG_PORT, PG_DB_NAME
ferramentas_carregar_credenciais_pg_instancia() {
  local env_file="/home/deploy/${empresa}/backend/.env"
  PG_USUARIO="${empresa}"
  PG_SENHA="${senha_deploy:-}"
  PG_HOST="127.0.0.1"
  PG_PORT="5432"
  PG_DB_NAME="${empresa}"
  if [ -f "$env_file" ]; then
    PG_USUARIO=$(grep -m1 '^DB_USER=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r' | tr -d ' ' | tr -d '"' | head -1)
    PG_SENHA=$(grep -m1 '^DB_PASS=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r' | tr -d '"' | head -1)
    PG_HOST=$(grep -m1 '^DB_HOST=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r' | tr -d ' ' | head -1)
    PG_PORT=$(grep -m1 '^DB_PORT=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r' | tr -d ' ' | head -1)
    PG_DB_NAME=$(grep -m1 '^DB_NAME=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r' | tr -d ' ' | head -1)
  fi
  [ -z "$PG_USUARIO" ] && PG_USUARIO="${empresa}"
  [ -z "$PG_DB_NAME" ] && PG_DB_NAME="${empresa}"
  [ -z "$PG_HOST" ] || [ "$PG_HOST" = "localhost" ] && PG_HOST="127.0.0.1"
  [ -z "$PG_PORT" ] && PG_PORT="5432"
}

# Carrega credenciais PG a partir do nome da instância/banco (ex.: web → /home/deploy/web/backend/.env).
ferramentas_carregar_credenciais_pg_por_nome() {
  local nome_instancia="$1"
  local empresa_salva="${empresa:-}"
  empresa="${nome_instancia}"
  ferramentas_carregar_credenciais_pg_instancia
  empresa="${empresa_salva}"
}

# Localiza pasta da instância pelo nome do banco.
# Prioridade: arquivos VARIAVEIS_INSTALACAO* do instalador → .env no servidor.
# Define FERRAMENTAS_INSTANCIA_POR_DB (ex.: oficialweb → web via apioficial_db_name).
ferramentas_resolver_instancia_por_db_name() {
  local db_name="$1"
  local instalador_dir="${2:-}"
  local dir env_file db_env db_user nome_inst arq temp_emp apiof_db
  FERRAMENTAS_INSTANCIA_POR_DB=""

  if [ -z "$instalador_dir" ]; then
    instalador_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi

  # 1) Variáveis de instalação registradas no instalador
  for arq in "${instalador_dir}/${ARQUIVO_VARIAVEIS:-VARIAVEIS_INSTALACAO}" \
             "${instalador_dir}"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
    [ -f "$arq" ] || continue
    temp_emp=$(grep -m1 '^empresa=' "$arq" 2>/dev/null | cut -d '=' -f2- | tr -d '\r' | tr -d ' ' | tr -d '"' | head -1)
    [ -n "$temp_emp" ] || continue

    if [ "$db_name" = "$temp_emp" ]; then
      FERRAMENTAS_INSTANCIA_POR_DB="$temp_emp"
      return 0
    fi

    apiof_db=$(grep -m1 '^apioficial_db_name=' "$arq" 2>/dev/null | cut -d '=' -f2- | tr -d '\r' | tr -d ' ' | tr -d '"' | head -1)
    if [ -n "$apiof_db" ] && [ "$db_name" = "$apiof_db" ]; then
      FERRAMENTAS_INSTANCIA_POR_DB="$temp_emp"
      return 0
    fi

    if [ "$db_name" = "oficial${temp_emp}" ] || [ "$db_name" = "oficial_${temp_emp}" ]; then
      FERRAMENTAS_INSTANCIA_POR_DB="$temp_emp"
      return 0
    fi

    if [ -f "/home/deploy/${temp_emp}/backend/.env" ]; then
      db_env=$(grep -m1 '^DB_NAME=' "/home/deploy/${temp_emp}/backend/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r' | tr -d ' ' | tr -d '"' | head -1)
      if [ "$db_name" = "$db_env" ]; then
        FERRAMENTAS_INSTANCIA_POR_DB="$temp_emp"
        return 0
      fi
    fi
  done

  # 2) Fallback: pastas em /home/deploy (api_oficial, backend, convenções)
  if [ -d "/home/deploy/${db_name}/backend" ] && [ -f "/home/deploy/${db_name}/backend/.env" ]; then
    FERRAMENTAS_INSTANCIA_POR_DB="${db_name}"
    return 0
  fi

  for dir in /home/deploy/*/api_oficial; do
    [ -d "$dir" ] || continue
    env_file="${dir}/.env"
    [ -f "$env_file" ] || continue
    db_env=$(grep -m1 '^DATABASE_NAME=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r' | tr -d ' ' | tr -d '"' | head -1)
    if [ "$db_env" = "$db_name" ]; then
      nome_inst=$(basename "$(dirname "$dir")")
      FERRAMENTAS_INSTANCIA_POR_DB="${nome_inst}"
      return 0
    fi
  done

  for dir in /home/deploy/*/backend; do
    [ -d "$dir" ] || continue
    nome_inst=$(basename "$(dirname "$dir")")
    if [ "$db_name" = "oficial${nome_inst}" ] || [ "$db_name" = "oficial_${nome_inst}" ]; then
      FERRAMENTAS_INSTANCIA_POR_DB="${nome_inst}"
      return 0
    fi
    env_file="${dir}/.env"
    [ -f "$env_file" ] || continue
    db_env=$(grep -m1 '^DB_NAME=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r' | tr -d ' ' | tr -d '"' | head -1)
    if [ "$db_env" = "$db_name" ]; then
      FERRAMENTAS_INSTANCIA_POR_DB="${nome_inst}"
      return 0
    fi
    db_user=$(grep -m1 '^DB_USER=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r' | tr -d ' ' | tr -d '"' | head -1)
    if [ "$db_user" = "$db_name" ]; then
      FERRAMENTAS_INSTANCIA_POR_DB="${nome_inst}"
      return 0
    fi
  done

  return 1
}

# Preenche FERRAMENTAS_LISTA_DB com bancos do cluster (PostgreSQL nativo).
ferramentas_listar_bancos_pg_nativo() {
  FERRAMENTAS_LISTA_DB=()
  while IFS= read -r line; do
    [ -n "$line" ] && FERRAMENTAS_LISTA_DB+=("$line")
  done < <(PGPASSWORD="${PG_SENHA}" psql -U "${PG_USUARIO}" -h "${PG_HOST}" -p "${PG_PORT}" -d postgres -t -A -c \
    "SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres' ORDER BY datname;" 2>/dev/null)
}

ferramentas_pg_nativo_eh_local() {
  [ "${PG_HOST}" = "127.0.0.1" ] || [ "${PG_HOST}" = "localhost" ] || [ "${PG_HOST}" = "/var/run/postgresql" ]
}

ferramentas_psql_admin_pg_nativo() {
  local sql="$1"
  if ferramentas_pg_nativo_eh_local && id postgres >/dev/null 2>&1; then
    sudo -u postgres psql -p "${PG_PORT}" -d postgres -v ON_ERROR_STOP=1 -c "$sql"
  else
    PGPASSWORD="${PG_SENHA}" psql -U "${PG_USUARIO}" -h "${PG_HOST}" -p "${PG_PORT}" -d postgres -v ON_ERROR_STOP=1 -c "$sql"
  fi
}

ferramentas_garantir_role_pg_nativo() {
  local role="$1"
  local pass="${2:-}"
  local role_sql pass_sql
  role_sql=$(printf "%s" "$role" | sed "s/'/''/g")
  pass_sql=$(printf "%s" "$pass" | sed "s/'/''/g")

  if ferramentas_pg_nativo_eh_local && id postgres >/dev/null 2>&1; then
    if sudo -u postgres psql -p "${PG_PORT}" -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='${role_sql}'" 2>/dev/null | grep -qx 1; then
      sudo -u postgres psql -p "${PG_PORT}" -d postgres -v ON_ERROR_STOP=1 \
        -c "ALTER ROLE \"${role}\" WITH LOGIN SUPERUSER INHERIT CREATEDB CREATEROLE PASSWORD '${pass_sql}';" >/dev/null
    else
      sudo -u postgres psql -p "${PG_PORT}" -d postgres -v ON_ERROR_STOP=1 \
        -c "CREATE ROLE \"${role}\" WITH LOGIN SUPERUSER INHERIT CREATEDB CREATEROLE PASSWORD '${pass_sql}';" >/dev/null
    fi
  fi
}

# Escolhe item numerado; retorna 0 e define FERRAMENTAS_ESCOLHA, ou 1 se cancelar/inválido.
ferramentas_escolher_item_lista() {
  local prompt_msg="$1"
  shift
  local -a itens=("$@")
  local total=${#itens[@]}
  local i op
  if [ "$total" -eq 0 ]; then
    return 1
  fi
  printf "${WHITE} >> %s${WHITE}\n" "$prompt_msg"
  echo
  i=1
  for item in "${itens[@]}"; do
    printf "   [${BLUE}%s${WHITE}] %s\n" "$i" "$item"
    ((i++))
  done
  printf "   [${BLUE}0${WHITE}] Cancelar\n"
  echo
  read -p "> " op
  if [ "$op" = "0" ] || [ -z "$op" ]; then
    return 1
  fi
  if ! [[ "$op" =~ ^[0-9]+$ ]] || [ "$op" -lt 1 ] || [ "$op" -gt "$total" ]; then
    return 1
  fi
  FERRAMENTAS_ESCOLHA="${itens[$((op - 1))]}"
  return 0
}

# Para contêineres e aplicações da instância para liberar sessões do banco de dados antes de DROP/CREATE
ferramentas_pm2_parar_para_manutencao_pg() {
  local em="${1:-${empresa:-}}"
  [ -n "$em" ] || return 0
  printf "${WHITE} >> Parando serviços da instância %s (libera conexões no PostgreSQL)...${WHITE}\n" "$em"
  # Parar contêineres Docker da instância
  docker stop "${em}_backend" "${em}_frontend" "${em}_transcricao" "${em}_apioficial" 2>/dev/null || true
  # Limpar/parar eventuais processos PM2 legados
  sudo su - deploy -c "for _p in '${em}-backend' '${em}-frontend' '${em}-transcricao' 'transc-${em}' 'api_oficial_${em}'; do pm2 stop \"\$_p\" 2>/dev/null || true; done" 2>/dev/null || true
  sleep 2
}

ferramentas_pm2_aviso_retomada_manual_pg() {
  local em="${1:-${empresa:-}}"
  [ -n "$em" ] || return 0
  printf "${YELLOW} >> Serviços/contêineres da instância %s ficaram parados de propósito.${WHITE}\n" "$em"
  printf "${YELLOW} >> Após validar a importação, inicie os contêineres pelo Menu opção 4 ou execute 'docker compose up -d'.${WHITE}\n"
}

# DROP + CREATE + restore em banco alvo (PostgreSQL nativo).
ferramentas_restaurar_sql_em_banco() {
  local db_alvo="$1"
  local arquivo_sql="$2"
  local owner_db="${PG_USUARIO}"
  local db_sql
  ferramentas_pm2_parar_para_manutencao_pg || true
  db_sql=$(printf "%s" "$db_alvo" | sed "s/'/''/g")
  printf "${WHITE} >> Encerrando conexões com o banco ${db_alvo}...${WHITE}\n"
  ferramentas_psql_admin_pg_nativo "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${db_sql}' AND pid <> pg_backend_pid();" || true
  sleep 2
  printf "${WHITE} >> Recriando banco ${db_alvo}...${WHITE}\n"
  ferramentas_psql_admin_pg_nativo "DROP DATABASE IF EXISTS \"${db_alvo}\";" || true
  ferramentas_garantir_role_pg_nativo "${owner_db}" "${PG_SENHA}" || true
  if ! ferramentas_psql_admin_pg_nativo "CREATE DATABASE \"${db_alvo}\" OWNER \"${owner_db}\";"; then
    printf "${YELLOW} >> Falha ao criar com owner ${owner_db}. Tentando criar sem owner explícito...${WHITE}\n"
    if ! ferramentas_psql_admin_pg_nativo "CREATE DATABASE \"${db_alvo}\";"; then
      printf "${RED} >> Erro ao criar o banco ${db_alvo}. Verifique a mensagem do PostgreSQL acima.${WHITE}\n"
      ferramentas_pm2_aviso_retomada_manual_pg || true
      return 1
    fi
  fi
  printf "${WHITE} >> Restaurando backup em ${db_alvo}...${WHITE}\n"
  if PGPASSWORD="${PG_SENHA}" psql -X -v ON_ERROR_STOP=1 --single-transaction -U "${PG_USUARIO}" -h "${PG_HOST}" -p "${PG_PORT}" -d "${db_alvo}" -f "$arquivo_sql"; then
    printf "${GREEN} >> Banco ${db_alvo} restaurado com sucesso.${WHITE}\n"
    ferramentas_pm2_aviso_retomada_manual_pg || true
    return 0
  fi
  printf "${YELLOW} >> Falha na restauração. O banco não foi recuperado; mantenha os serviços parados.${WHITE}\n"
  ferramentas_pm2_aviso_retomada_manual_pg || true
  return 1
}

# Importar/restaurar backup do banco nativo (PostgreSQL): instância, lista de bancos, substituir ou criar novo.
importar_backup_banco_ferramentas() {
  banner
  printf "${WHITE} >> Importar backup do banco (PostgreSQL nativo)...\n"
  echo

  if ! selecionar_instancia_atualizar "importar o backup do banco"; then
    sleep 2
    return 1
  fi

  if [ "${ALTA_PERFORMANCE:-0}" = "1" ]; then
    printf "${YELLOW} >> AVISO: Esta instância está em modo Alta Performance (Postgres em Docker).${WHITE}\n"
    printf "${YELLOW} >> Use a opção 14 para backup/restore do banco Docker, ou importe com Postgres nativo na porta 5432.${WHITE}\n"
    echo
  fi

  ferramentas_carregar_credenciais_pg_instancia
  if [ -z "${PG_SENHA}" ]; then
    printf "${YELLOW} >> Informe usuário e senha do PostgreSQL:${WHITE}\n"
    read -p "   Usuário [${PG_USUARIO}]: " input_user
    [ -n "$input_user" ] && PG_USUARIO="$input_user"
    read -s -p "   Senha: " PG_SENHA
    echo
    [ -z "${PG_SENHA}" ] && printf "${RED} >> Senha não informada. Cancelado.${WHITE}\n" && sleep 2 && return 1
  fi

  if ! PGPASSWORD="${PG_SENHA}" psql -U "${PG_USUARIO}" -h "${PG_HOST}" -p "${PG_PORT}" -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
    printf "${RED} >> Não foi possível conectar ao PostgreSQL em ${PG_HOST}:${PG_PORT} com o usuário ${PG_USUARIO}.${WHITE}\n"
    sleep 2
    return 1
  fi

  ferramentas_listar_bancos_pg_nativo
  if [ ${#FERRAMENTAS_LISTA_DB[@]} -eq 0 ]; then
    printf "${RED} >> Nenhum banco listado ou credenciais incorretas.${WHITE}\n"
    sleep 2
    return 1
  fi

  printf "${WHITE} >> Bancos no PostgreSQL (${PG_HOST}:${PG_PORT}):${WHITE}\n"
  echo
  local db
  for db in "${FERRAMENTAS_LISTA_DB[@]}"; do
    if [ "$db" = "${PG_DB_NAME}" ]; then
      printf "   ${GREEN}* ${db}${WHITE} ${YELLOW}(DB_NAME da instância ${empresa})${WHITE}\n"
    else
      printf "   - ${db}\n"
    fi
  done
  echo

  BACKUP_BASE="/home/deploy/backup-${empresa}"
  if [ ! -d "$BACKUP_BASE" ]; then
    mkdir -p "$BACKUP_BASE"
    chown deploy:deploy "$BACKUP_BASE" 2>/dev/null || true
    printf "${YELLOW} >> Pasta criada: ${BACKUP_BASE} — coloque o arquivo .sql e execute novamente.${WHITE}\n"
    sleep 2
    return 1
  fi

  BACKUPS_SQL=()
  while IFS= read -r f; do
    [ -n "$f" ] && BACKUPS_SQL+=("$f")
  done < <(find "$BACKUP_BASE" -maxdepth 2 -type f -name "*.sql" 2>/dev/null | sort -r)
  if [ ${#BACKUPS_SQL[@]} -eq 0 ]; then
    printf "${RED} >> Nenhum arquivo .sql em ${BACKUP_BASE}${WHITE}\n"
    sleep 2
    return 1
  fi

  BACKUP_LABELS=()
  local f
  for f in "${BACKUPS_SQL[@]}"; do
    BACKUP_LABELS+=("$(basename "$f")")
  done
  if ! ferramentas_escolher_item_lista "Escolha o arquivo de backup (.sql):" "${BACKUP_LABELS[@]}"; then
    printf "${YELLOW} >> Cancelado.${WHITE}\n"
    sleep 2
    return 0
  fi
  local arquivo_escolhido=""
  for f in "${BACKUPS_SQL[@]}"; do
    if [ "$(basename "$f")" = "${FERRAMENTAS_ESCOLHA}" ]; then
      arquivo_escolhido="$f"
      break
    fi
  done
  if [ -z "$arquivo_escolhido" ] || [ ! -f "$arquivo_escolhido" ]; then
    printf "${RED} >> Arquivo não encontrado. Cancelado.${WHITE}\n"
    sleep 2
    return 1
  fi
  printf "${GREEN} >> Backup: ${FERRAMENTAS_ESCOLHA}${WHITE}\n"
  echo

  printf "${YELLOW} >> Como deseja restaurar?${WHITE}\n"
  printf "   [${BLUE}1${WHITE}] Substituir um banco existente (lista os bancos e você escolhe qual apagar/recriar)\n"
  printf "   [${BLUE}2${WHITE}] Criar um banco novo e restaurar nele (mantém os demais)\n"
  printf "   [${BLUE}0${WHITE}] Cancelar\n"
  echo
  read -p "> " op_modo
  if [ "$op_modo" = "0" ] || [ -z "$op_modo" ]; then
    printf "${YELLOW} >> Cancelado.${WHITE}\n"
    sleep 2
    return 0
  fi

  local db_destino=""

  if [ "$op_modo" = "1" ]; then
    if ! ferramentas_escolher_item_lista "Escolha o banco que será SUBSTITUÍDO (DROP + CREATE + restore):" "${FERRAMENTAS_LISTA_DB[@]}"; then
      printf "${RED} >> Opção inválida ou cancelada.${WHITE}\n"
      sleep 2
      return 1
    fi
    db_destino="${FERRAMENTAS_ESCOLHA}"
    printf "${YELLOW} >> ATENÇÃO: o banco '${db_destino}' será apagado e recriado. Continuar? (s/N):${WHITE}\n"
    read -p "> " confirma
    confirma=$(echo "$confirma" | tr '[:upper:]' '[:lower:]')
    if [ "$confirma" != "s" ]; then
      printf "${YELLOW} >> Cancelado.${WHITE}\n"
      sleep 2
      return 0
    fi
    ferramentas_restaurar_sql_em_banco "$db_destino" "$arquivo_escolhido" || return 1
    if [ "$db_destino" != "${PG_DB_NAME}" ]; then
      printf "${YELLOW} >> O .env da instância ${empresa} usa DB_NAME=${PG_DB_NAME}. Ajuste se a aplicação deve usar ${db_destino}.${WHITE}\n"
    fi
  elif [ "$op_modo" = "2" ]; then
    printf "${YELLOW} >> Nome do novo banco [padrão: ${PG_DB_NAME}]:${WHITE}\n"
    read -p "> " nome_novo_banco
    nome_novo_banco=$(echo "$nome_novo_banco" | tr -d ' ')
    db_destino="${nome_novo_banco:-${PG_DB_NAME}}"
    if printf '%s\n' "${FERRAMENTAS_LISTA_DB[@]}" | grep -qx "$db_destino"; then
      printf "${RED} >> O banco '${db_destino}' já existe. Use a opção 1 para substituir ou escolha outro nome.${WHITE}\n"
      sleep 2
      return 1
    fi
    ferramentas_pm2_parar_para_manutencao_pg || true
    printf "${WHITE} >> Criando banco ${db_destino}...${WHITE}\n"
    ferramentas_garantir_role_pg_nativo "${PG_USUARIO}" "${PG_SENHA}" || true
    if ! ferramentas_psql_admin_pg_nativo "CREATE DATABASE \"${db_destino}\" OWNER \"${PG_USUARIO}\";"; then
      printf "${YELLOW} >> Falha ao criar com owner ${PG_USUARIO}. Tentando criar sem owner explícito...${WHITE}\n"
      if ! ferramentas_psql_admin_pg_nativo "CREATE DATABASE \"${db_destino}\";"; then
        printf "${RED} >> Erro ao criar banco ${db_destino}. Verifique a mensagem do PostgreSQL acima.${WHITE}\n"
        ferramentas_pm2_aviso_retomada_manual_pg || true
        sleep 2
        return 1
      fi
    fi
    printf "${WHITE} >> Restaurando backup em ${db_destino}...${WHITE}\n"
    if PGPASSWORD="${PG_SENHA}" psql -X -v ON_ERROR_STOP=1 --single-transaction -U "${PG_USUARIO}" -h "${PG_HOST}" -p "${PG_PORT}" -d "${db_destino}" -f "$arquivo_escolhido"; then
      printf "${GREEN} >> Banco ${db_destino} restaurado com sucesso.${WHITE}\n"
    else
      printf "${YELLOW} >> Falha na restauração. O banco não foi recuperado; mantenha os serviços parados.${WHITE}\n"
      ferramentas_pm2_aviso_retomada_manual_pg || true
      return 1
    fi
    ferramentas_pm2_aviso_retomada_manual_pg || true
    if [ "$db_destino" != "${PG_DB_NAME}" ]; then
      printf "${YELLOW} >> Atualize DB_NAME no .env do backend (${empresa}) para: ${db_destino}${WHITE}\n"
    fi
  else
    printf "${RED} >> Opção inválida.${WHITE}\n"
    sleep 2
    return 1
  fi

  echo
  sleep 2
  return 0
}

# Importar/restaurar backup do banco da API Oficial (PostgreSQL nativo ou Alta Performance / Docker)
importar_backup_banco_api_oficial_ferramentas() {
  banner
  printf "${WHITE} >> Importar backup do banco da API Oficial...\n"
  echo

  if ! selecionar_instancia_atualizar "importar o backup da API Oficial"; then
    sleep 2
    return 1
  fi

  if [ -n "${ARQUIVO_VARIAVEIS_USADO:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_USADO}" ]; then
    # shellcheck source=/dev/null
    mf_carregar_config "${ARQUIVO_VARIAVEIS_USADO}" 2>/dev/null
  fi
  local alta_perf="${ALTA_PERFORMANCE:-0}"

  local db_oficial=""
  if [ -f "/home/deploy/${empresa}/api_oficial/.env" ]; then
    db_oficial=$(grep -m1 '^DATABASE_NAME=' "/home/deploy/${empresa}/api_oficial/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  fi
  if [ -z "$db_oficial" ] && [ -n "${ARQUIVO_VARIAVEIS_USADO:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_USADO}" ]; then
    db_oficial=$(grep -m1 '^apioficial_db_name=' "${ARQUIVO_VARIAVEIS_USADO}" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  fi
  if [ -z "$db_oficial" ]; then
    if [[ "${ARQUIVO_VARIAVEIS_USADO:-}" == *VARIAVEIS_INSTALACAO_INSTANCIA_* ]]; then
      db_oficial="oficial${empresa}"
    else
      db_oficial="oficialseparado"
    fi
  fi

  if [ "${alta_perf}" = "1" ]; then
    printf "${GREEN} >> Instância: ${BLUE}${empresa}${WHITE} | Banco API Oficial: ${YELLOW}${db_oficial}${WHITE} | ${BLUE}Alta Performance (Docker)${WHITE}\n"
  else
    printf "${GREEN} >> Instância: ${BLUE}${empresa}${WHITE} | Banco API Oficial: ${YELLOW}${db_oficial}${WHITE} | PostgreSQL nativo${WHITE}\n"
  fi
  echo

  local BACKUP_BASE BACKUP_BASE_LEGACY
  if [ "${alta_perf}" = "1" ]; then
    BACKUP_BASE="/home/deploy/backup-bd-docker-${empresa}"
    BACKUP_BASE_LEGACY="/home/deploy/backup-bd-docker"
    if [ ! -d "${BACKUP_BASE}" ] && [ -d "${BACKUP_BASE_LEGACY}" ]; then
      printf "${YELLOW} >> Pasta por empresa não encontrada; usando legado: ${BACKUP_BASE_LEGACY}${WHITE}\n"
      BACKUP_BASE="${BACKUP_BASE_LEGACY}"
    fi
  else
    BACKUP_BASE="/home/deploy/backup-${empresa}"
  fi

  if [ ! -d "$BACKUP_BASE" ]; then
    if [ "${alta_perf}" = "1" ]; then
      printf "${RED} >> Pasta não encontrada: /home/deploy/backup-bd-docker-${empresa}${WHITE}\n"
      printf "${YELLOW} >> Em Alta Performance os backups ficam em backup-bd-docker-<empresa> (opção 6 do menu).${WHITE}\n"
    else
      printf "${RED} >> Pasta não encontrada: ${BACKUP_BASE}${WHITE}\n"
    fi
    sleep 2
    return 1
  fi

  BACKUPS_SQL=()
  if [ "${alta_perf}" = "1" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] && BACKUPS_SQL+=("$f")
    done < <(find "$BACKUP_BASE" -maxdepth 1 -type f \( -name "backup-${db_oficial}-*.sql.gz" -o -name "backup-${db_oficial}-*.sql" -o -name "backup_${db_oficial}_*.sql.gz" -o -name "backup_${db_oficial}_*.sql" \) 2>/dev/null | sort -r)
    if [ ${#BACKUPS_SQL[@]} -eq 0 ]; then
      while IFS= read -r f; do
        [ -n "$f" ] && BACKUPS_SQL+=("$f")
      done < <(find "$BACKUP_BASE" -maxdepth 1 -type f \( -name "*.sql.gz" -o -name "*.sql" \) 2>/dev/null | sort -r)
      if [ ${#BACKUPS_SQL[@]} -gt 0 ]; then
        printf "${YELLOW} >> Nenhum backup com nome do banco ${db_oficial}; listando todos da pasta Docker.${WHITE}\n"
        echo
      fi
    fi
  else
    while IFS= read -r f; do
      [ -n "$f" ] && BACKUPS_SQL+=("$f")
    done < <(find "$BACKUP_BASE" -maxdepth 2 -type f -name "*.sql" 2>/dev/null | sort -r)
  fi

  if [ ${#BACKUPS_SQL[@]} -eq 0 ]; then
    printf "${RED} >> Nenhum backup encontrado em ${BACKUP_BASE}${WHITE}\n"
    sleep 2
    return 1
  fi
  printf "${WHITE} >> Backups disponíveis:${WHITE}\n"
  echo
  local i=1
  for f in "${BACKUPS_SQL[@]}"; do
    printf "   [${BLUE}%s${WHITE}] %s\n" "$i" "$(basename "$f")"
    ((i++))
  done
  printf "   [${BLUE}0${WHITE}] Cancelar\n"
  echo
  printf "${YELLOW} >> Escolha o número do backup para restaurar no banco da API Oficial:${WHITE}\n"
  read -p "> " op_backup
  if [ "$op_backup" = "0" ] || [ -z "$op_backup" ]; then
    printf "${YELLOW} >> Cancelado.${WHITE}\n"
    sleep 2
    return 0
  fi
  local arquivo_escolhido=""
  i=1
  for f in "${BACKUPS_SQL[@]}"; do
    if [ "$i" = "$op_backup" ]; then
      arquivo_escolhido="$f"
      break
    fi
    ((i++))
  done
  if [ -z "$arquivo_escolhido" ] || [ ! -f "$arquivo_escolhido" ]; then
    printf "${RED} >> Opção inválida. Cancelado.${WHITE}\n"
    sleep 2
    return 1
  fi
  printf "${WHITE} >> Backup selecionado: %s${WHITE}\n" "$(basename "$arquivo_escolhido")"
  echo
  printf "${YELLOW} >> Deseja apagar o banco da API Oficial existente ou criar um novo?${WHITE}\n"
  printf "   [${BLUE}1${WHITE}] Apagar banco existente e restaurar (substitui o banco ${db_oficial})\n"
  printf "   [${BLUE}2${WHITE}] Criar novo banco e restaurar (mantém o existente, cria ${db_oficial}_novo)\n"
  printf "   [${BLUE}0${WHITE}] Cancelar\n"
  echo
  read -p "> " op_tipo
  if [ "$op_tipo" = "0" ] || [ -z "$op_tipo" ]; then
    printf "${YELLOW} >> Cancelado.${WHITE}\n"
    sleep 2
    return 0
  fi

  if [ "${alta_perf}" = "1" ]; then
    local senha_db="${senha_deploy}"
    local POSTGRES_CONTAINER="postgres_${empresa}"
    local db_destino="${db_oficial}"
    [ "$op_tipo" = "2" ] && db_destino="${db_oficial}_novo"

    if [ -z "$senha_db" ]; then
      [ -f "/home/deploy/${empresa}/backend/.env" ] && senha_db=$(grep -m1 '^DB_PASS=' "/home/deploy/${empresa}/backend/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
    fi
    if [ -z "$senha_db" ]; then
      printf "${YELLOW} >> Informe a senha do banco (senha_deploy):${WHITE}\n"
      read -s -p "> " senha_db
      echo
      [ -z "$senha_db" ] && printf "${RED} >> Senha não informada. Cancelado.${WHITE}\n" && sleep 2 && return 1
    fi
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${POSTGRES_CONTAINER}$"; then
      printf "${RED} >> Container ${POSTGRES_CONTAINER} não está em execução.${WHITE}\n"
      sleep 2
      return 1
    fi

    ferramentas_pm2_parar_para_manutencao_pg || true

    if [ "$op_tipo" = "1" ]; then
      printf "${WHITE} >> Encerrando conexões com ${db_oficial}...${WHITE}\n"
      docker exec "${POSTGRES_CONTAINER}" env PGPASSWORD="${senha_db}" psql -h 127.0.0.1 -p 5432 -U "${empresa}" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${db_oficial}' AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
      sleep 1
      printf "${WHITE} >> Apagando banco existente e criando novo...${WHITE}\n"
      docker exec "${POSTGRES_CONTAINER}" env PGPASSWORD="${senha_db}" psql -h 127.0.0.1 -p 5432 -U "${empresa}" -d postgres -c "DROP DATABASE IF EXISTS ${db_oficial};" >/dev/null 2>&1 || true
      if ! docker exec "${POSTGRES_CONTAINER}" env PGPASSWORD="${senha_db}" psql -h 127.0.0.1 -p 5432 -U "${empresa}" -d postgres -c "CREATE DATABASE ${db_oficial} OWNER ${empresa};" >/dev/null 2>&1; then
        printf "${RED} >> Erro ao criar banco ${db_oficial} no container ${POSTGRES_CONTAINER}.${WHITE}\n"
        ferramentas_pm2_aviso_retomada_manual_pg || true
        sleep 2
        return 1
      fi
      db_destino="${db_oficial}"
    else
      printf "${WHITE} >> Criando banco ${db_destino} (mantendo ${db_oficial})...${WHITE}\n"
      if ! docker exec "${POSTGRES_CONTAINER}" env PGPASSWORD="${senha_db}" psql -h 127.0.0.1 -p 5432 -U "${empresa}" -d postgres -c "CREATE DATABASE ${db_destino} OWNER ${empresa};" >/dev/null 2>&1; then
        printf "${RED} >> Erro ao criar banco ${db_destino}. Pode já existir.${WHITE}\n"
        ferramentas_pm2_aviso_retomada_manual_pg || true
        sleep 2
        return 1
      fi
    fi

    printf "${WHITE} >> Restaurando backup em ${db_destino} (Docker)...${WHITE}\n"
    local restore_ok=0
    if [[ "${arquivo_escolhido}" == *.sql.gz ]]; then
      if gunzip -c "${arquivo_escolhido}" | docker exec -i "${POSTGRES_CONTAINER}" env PGPASSWORD="${senha_db}" psql -h 127.0.0.1 -p 5432 -U "${empresa}" -d "${db_destino}" >/dev/null 2>&1; then
        restore_ok=1
      fi
    elif cat "${arquivo_escolhido}" | docker exec -i "${POSTGRES_CONTAINER}" env PGPASSWORD="${senha_db}" psql -h 127.0.0.1 -p 5432 -U "${empresa}" -d "${db_destino}" >/dev/null 2>&1; then
      restore_ok=1
    fi

    if [ "$restore_ok" = "1" ]; then
      printf "${GREEN} >> Banco da API Oficial (${db_destino}) restaurado com sucesso no Postgres Docker.${WHITE}\n"
      if [ "$op_tipo" = "2" ]; then
        printf "${YELLOW} >> Para usar na API Oficial, altere DATABASE_NAME no .env da API Oficial para: ${db_destino}${WHITE}\n"
      fi
    else
      printf "${RED} >> Erro ao restaurar o backup em ${db_destino}. Verifique o arquivo e os logs do container.${WHITE}\n"
    fi
    ferramentas_pm2_aviso_retomada_manual_pg || true
    echo
    sleep 2
    return 0
  fi

  local usuario_db="${empresa}"
  local senha_db="${senha_deploy}"
  [ -z "$senha_db" ] && [ -f "/home/deploy/${empresa}/backend/.env" ] && senha_db=$(grep "DB_PASS=" "/home/deploy/${empresa}/backend/.env" 2>/dev/null | cut -d '=' -f2)
  if [ -z "$senha_db" ]; then
    printf "${YELLOW} >> Informe o usuário e a senha do banco:${WHITE}\n"
    read -p "   Usuário: " usuario_db
    read -s -p "   Senha: " senha_db
    echo
    [ -z "$usuario_db" ] && printf "${RED} >> Usuário não informado. Cancelado.${WHITE}\n" && sleep 2 && return 1
    [ -z "$senha_db" ] && printf "${RED} >> Senha não informada. Cancelado.${WHITE}\n" && sleep 2 && return 1
  fi
  local db_port="5432"
  if ! PGPASSWORD="${senha_db}" psql -U "${usuario_db}" -h 127.0.0.1 -p 5432 -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
    if PGPASSWORD="${senha_db}" psql -U "${usuario_db}" -h 127.0.0.1 -p 7532 -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
      db_port="7532"
      printf "${WHITE} >> Usando PostgreSQL da API Oficial (porta 7532).${WHITE}\n"
    else
      printf "${RED} >> Não foi possível conectar ao PostgreSQL (portas 5432 e 7532). Verifique usuário/senha e se o serviço está ativo.${WHITE}\n"
      sleep 2
      return 1
    fi
  fi
  if [ "$op_tipo" = "1" ]; then
    ferramentas_pm2_parar_para_manutencao_pg || true
    # Conectar ao banco 'postgres' para terminate/DROP/CREATE; senão psql conecta ao banco com nome do usuário e não permite dropar.
    printf "${WHITE} >> Encerrando conexões com o banco ${db_oficial}...${WHITE}\n"
    PGPASSWORD="${senha_db}" psql -U "${usuario_db}" -h 127.0.0.1 -p "${db_port}" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${db_oficial}' AND pid <> pg_backend_pid();" 2>/dev/null || true
    sleep 1
    printf "${WHITE} >> Apagando banco existente e criando novo...${WHITE}\n"
    PGPASSWORD="${senha_db}" psql -U "${usuario_db}" -h 127.0.0.1 -p "${db_port}" -d postgres -c "DROP DATABASE IF EXISTS ${db_oficial};" 2>/dev/null || true
    PGPASSWORD="${senha_db}" psql -U "${usuario_db}" -h 127.0.0.1 -p "${db_port}" -d postgres -c "CREATE DATABASE ${db_oficial} OWNER ${empresa};" 2>/dev/null || true
    if [ $? -ne 0 ]; then
      printf "${RED} >> Erro ao criar banco. Verifique se o usuário ${empresa} existe no PostgreSQL (porta ${db_port}).${WHITE}\n"
      ferramentas_pm2_aviso_retomada_manual_pg || true
      sleep 2
      return 1
    fi
    printf "${WHITE} >> Restaurando backup em ${db_oficial}...${WHITE}\n"
    PGPASSWORD="${senha_db}" psql -U "${usuario_db}" -h 127.0.0.1 -p "${db_port}" -d "${db_oficial}" -f "$arquivo_escolhido" 2>/dev/null
    if [ $? -eq 0 ]; then
      printf "${GREEN} >> Banco da API Oficial (${db_oficial}) restaurado com sucesso.${WHITE}\n"
    else
      printf "${YELLOW} >> Restauração concluída (verifique erros acima).${WHITE}\n"
    fi
    ferramentas_pm2_aviso_retomada_manual_pg || true
  else
    ferramentas_pm2_parar_para_manutencao_pg || true
    local db_novo="${db_oficial}_novo"
    printf "${WHITE} >> Criando banco ${db_novo} (mantendo ${db_oficial})...${WHITE}\n"
    PGPASSWORD="${senha_db}" psql -U "${usuario_db}" -h 127.0.0.1 -p "${db_port}" -d postgres -c "CREATE DATABASE ${db_novo} OWNER ${empresa};" 2>/dev/null || true
    if [ $? -ne 0 ]; then
      printf "${RED} >> Erro ao criar banco ${db_novo}. Pode já existir.${WHITE}\n"
      ferramentas_pm2_aviso_retomada_manual_pg || true
      sleep 2
      return 1
    fi
    printf "${WHITE} >> Restaurando backup em ${db_novo}...${WHITE}\n"
    PGPASSWORD="${senha_db}" psql -U "${usuario_db}" -h 127.0.0.1 -p "${db_port}" -d "${db_novo}" -f "$arquivo_escolhido" 2>/dev/null
    if [ $? -eq 0 ]; then
      printf "${GREEN} >> Banco ${db_novo} restaurado com sucesso.${WHITE}\n"
      printf "${YELLOW} >> Para usar na API Oficial, altere DATABASE_NAME no .env da API Oficial para: ${db_novo}${WHITE}\n"
    else
      printf "${YELLOW} >> Restauração concluída (verifique erros acima).${WHITE}\n"
    fi
    ferramentas_pm2_aviso_retomada_manual_pg || true
  fi
  echo
  sleep 2
}

# Backup do banco nativo (PostgreSQL): lista bancos, salva em /home/deploy/backup-<instância>/
backup_banco_ferramentas() {
  banner
  printf "${WHITE} >> Backup do banco (PostgreSQL nativo)...\n"
  echo
  INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ARQUIVO_VARIAVEIS_INSTALADOR="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
  if [ -f "$ARQUIVO_VARIAVEIS_INSTALADOR" ]; then
    mf_carregar_config "$ARQUIVO_VARIAVEIS_INSTALADOR" 2>/dev/null
  fi
  local empresa_listagem="${empresa:-}"
  if [ -z "${empresa_listagem}" ]; then
    printf "${YELLOW} >> Empresa não encontrada nas variáveis. Informe o usuário PostgreSQL para listar bancos (ex: app):${WHITE}\n"
    read -p "> " empresa_listagem
    [ -z "$empresa_listagem" ] && printf "${RED} >> Usuário não informado. Cancelado.${WHITE}\n" && sleep 2 && return 1
  fi
  local usuario_db="${empresa_listagem}"
  local senha_db="${senha_deploy}"
  [ -z "$senha_db" ] && [ -f "/home/deploy/${empresa_listagem}/backend/.env" ] && senha_db=$(grep "DB_PASS=" "/home/deploy/${empresa_listagem}/backend/.env" 2>/dev/null | cut -d '=' -f2)
  # Listar bancos com usuário empresa (sem postgres)
  LISTA_DB=()
  while IFS= read -r line; do
    [ -n "$line" ] && LISTA_DB+=("$line")
  done < <(PGPASSWORD="${senha_db}" psql -U "${usuario_db}" -h localhost -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres' ORDER BY datname;" 2>/dev/null)
  if [ ${#LISTA_DB[@]} -eq 0 ]; then
    printf "${YELLOW} >> Não foi possível listar com usuário ${usuario_db}. Informe usuário e senha do banco:${WHITE}\n"
    read -p "   Usuário: " usuario_db
    read -s -p "   Senha: " senha_db
    echo
    [ -z "$usuario_db" ] && printf "${RED} >> Usuário não informado. Cancelado.${WHITE}\n" && sleep 2 && return 1
    LISTA_DB=()
    while IFS= read -r line; do
      [ -n "$line" ] && LISTA_DB+=("$line")
    done < <(PGPASSWORD="${senha_db}" psql -U "${usuario_db}" -h localhost -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres' ORDER BY datname;" 2>/dev/null)
  fi
  if [ ${#LISTA_DB[@]} -eq 0 ]; then
    printf "${RED} >> Nenhum banco encontrado ou usuário/senha incorretos.${WHITE}\n"
    sleep 2
    return 1
  fi
  printf "${WHITE} >> Bancos disponíveis:${WHITE}\n"
  echo
  local i=1
  for db in "${LISTA_DB[@]}"; do
    printf "   [${BLUE}%s${WHITE}] %s\n" "$i" "$db"
    ((i++))
  done
  printf "   [${BLUE}0${WHITE}] Cancelar\n"
  echo
  printf "${YELLOW} >> Escolha o número do banco para fazer backup:${WHITE}\n"
  read -p "> " op_db
  if [ "$op_db" = "0" ] || [ -z "$op_db" ]; then
    printf "${YELLOW} >> Cancelado.${WHITE}\n"
    sleep 2
    return 0
  fi
  local db_escolhido=""
  i=1
  for db in "${LISTA_DB[@]}"; do
    if [ "$i" = "$op_db" ]; then
      db_escolhido="$db"
      break
    fi
    ((i++))
  done
  if [ -z "$db_escolhido" ]; then
    printf "${RED} >> Opção inválida. Cancelado.${WHITE}\n"
    sleep 2
    return 1
  fi

  # Pasta sempre da instância (ex.: banco web ou oficialweb → /home/deploy/backup-web/)
  local instancia_resolvida=""
  local BACKUP_DIR=""
  local pg_host="127.0.0.1"
  local pg_port="5432"

  if ferramentas_resolver_instancia_por_db_name "${db_escolhido}" "${INSTALADOR_DIR}"; then
    instancia_resolvida="${FERRAMENTAS_INSTANCIA_POR_DB}"
    ferramentas_carregar_credenciais_pg_por_nome "${instancia_resolvida}"
    usuario_db="${PG_USUARIO:-$db_escolhido}"
    senha_db="${PG_SENHA:-$senha_db}"
    pg_host="${PG_HOST:-127.0.0.1}"
    pg_port="${PG_PORT:-5432}"
    BACKUP_DIR=$(ferramentas_dir_backup_banco_instancia "${instancia_resolvida}")
    printf "${GREEN} >> Instância: ${instancia_resolvida} (banco ${db_escolhido})${WHITE}\n"
  elif PGPASSWORD="${senha_db}" psql -U "${db_escolhido}" -h localhost -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
    usuario_db="${db_escolhido}"
    BACKUP_DIR=$(ferramentas_dir_backup_banco_instancia "${db_escolhido}")
    printf "${WHITE} >> Usando credenciais do usuário PostgreSQL ${db_escolhido}.${WHITE}\n"
  elif PGPASSWORD="${senha_db}" psql -U "${usuario_db}" -h localhost -d "${db_escolhido}" -c "SELECT 1;" >/dev/null 2>&1; then
    BACKUP_DIR=$(ferramentas_dir_backup_banco_instancia "${empresa_listagem}")
    printf "${WHITE} >> Usando credenciais de listagem (usuário ${usuario_db}).${WHITE}\n"
  else
    printf "${YELLOW} >> Não foi possível localizar a instância do banco ${db_escolhido}.${WHITE}\n"
    printf "${YELLOW} >> Informe o nome da pasta da instância em /home/deploy (ex.: web):${WHITE}\n"
    read -p "> " instancia_resolvida
    [ -z "$instancia_resolvida" ] && printf "${RED} >> Instância não informada. Cancelado.${WHITE}\n" && sleep 2 && return 1
    BACKUP_DIR=$(ferramentas_dir_backup_banco_instancia "${instancia_resolvida}")
    printf "${YELLOW} >> Informe usuário e senha do banco ${db_escolhido}:${WHITE}\n"
    read -p "   Usuário [${db_escolhido}]: " input_user
    usuario_db="${input_user:-$db_escolhido}"
    read -s -p "   Senha: " senha_db
    echo
    [ -z "$senha_db" ] && printf "${RED} >> Senha não informada. Cancelado.${WHITE}\n" && sleep 2 && return 1
  fi

  mkdir -p "$BACKUP_DIR"
  chown deploy:deploy "$BACKUP_DIR" 2>/dev/null || true

  TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  local arquivo_nome="${db_escolhido}_${TIMESTAMP}.sql"
  local ARQUIVO_BACKUP="${BACKUP_DIR}/${arquivo_nome}"

  printf "${WHITE} >> Gerando backup de ${db_escolhido}...${WHITE}\n"
  printf "${WHITE} >> Pasta de destino: ${BACKUP_DIR}${WHITE}\n"

  PGPASSWORD="${senha_db}" pg_dump -U "${usuario_db}" -h "${pg_host}" -p "${pg_port}" "$db_escolhido" > "$ARQUIVO_BACKUP" 2>/dev/null
  if [ $? -eq 0 ] && [ -s "$ARQUIVO_BACKUP" ]; then
    chown deploy:deploy "$ARQUIVO_BACKUP" 2>/dev/null || true
    printf "${GREEN} >> Backup salvo: ${ARQUIVO_BACKUP}${WHITE}\n"
  else
    printf "${RED} >> Erro ao gerar backup. Verifique usuário e senha do banco.${WHITE}\n"
    [ -f "$ARQUIVO_BACKUP" ] && rm -f "$ARQUIVO_BACKUP"
    sleep 2
    return 1
  fi
  echo
  sleep 2
}

# Listar bancos existentes no PostgreSQL nativo (porta 5432; se falhar, tenta 7532)
listar_bancos_ferramentas() {
  banner
  printf "${WHITE} >> Listar bancos existentes (PostgreSQL nativo)...\n"
  echo
  INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ARQUIVO_VARIAVEIS_INSTALADOR="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
  if [ -f "$ARQUIVO_VARIAVEIS_INSTALADOR" ]; then
    mf_carregar_config "$ARQUIVO_VARIAVEIS_INSTALADOR" 2>/dev/null
  fi
  if [ -z "${empresa}" ]; then
    printf "${YELLOW} >> Empresa não encontrada nas variáveis. Informe o nome da empresa (ex: multiflow):${WHITE}\n"
    read -p "> " empresa
    [ -z "$empresa" ] && printf "${RED} >> Empresa não informada. Cancelado.${WHITE}\n" && sleep 2 && return 1
  fi
  local usuario_db="${empresa}"
  local senha_db="${senha_deploy}"
  [ -z "$senha_db" ] && [ -f "/home/deploy/${empresa}/backend/.env" ] && senha_db=$(grep "DB_PASS=" "/home/deploy/${empresa}/backend/.env" 2>/dev/null | cut -d '=' -f2)
  # Tenta porta 5432 (nativo)
  LISTA_5432=()
  while IFS= read -r line; do
    [ -n "$line" ] && LISTA_5432+=("$line")
  done < <(PGPASSWORD="${senha_db}" psql -U "${usuario_db}" -h 127.0.0.1 -p 5432 -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;" 2>/dev/null)
  if [ ${#LISTA_5432[@]} -eq 0 ]; then
    # Pode ser que precise de usuário/senha ou que só exista PostgreSQL na 7532
    if ! PGPASSWORD="${senha_db}" psql -U "${usuario_db}" -h 127.0.0.1 -p 5432 -d postgres -c "SELECT 1;" >/dev/null 2>&1; then
      printf "${YELLOW} >> Não foi possível conectar na porta 5432. Informe usuário e senha do banco (ou Enter para tentar porta 7532):${WHITE}\n"
      read -p "   Usuário [${empresa}]: " input_user
      [ -n "$input_user" ] && usuario_db="$input_user"
      read -s -p "   Senha: " senha_db
      echo
      LISTA_5432=()
      while IFS= read -r line; do
        [ -n "$line" ] && LISTA_5432+=("$line")
      done < <(PGPASSWORD="${senha_db}" psql -U "${usuario_db}" -h 127.0.0.1 -p 5432 -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;" 2>/dev/null)
    fi
  fi
  if [ ${#LISTA_5432[@]} -gt 0 ]; then
    printf "${WHITE} >> Bancos no PostgreSQL (porta 5432 - nativo):${WHITE}\n"
    echo
    for db in "${LISTA_5432[@]}"; do
      printf "   • %s\n" "$db"
    done
    echo
  fi
  # Tenta porta 7532 (Docker API Oficial)
  LISTA_7532=()
  while IFS= read -r line; do
    [ -n "$line" ] && LISTA_7532+=("$line")
  done < <(PGPASSWORD="${senha_db}" psql -U "${usuario_db}" -h 127.0.0.1 -p 7532 -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname;" 2>/dev/null)
  if [ ${#LISTA_7532[@]} -gt 0 ]; then
    printf "${WHITE} >> Bancos no PostgreSQL (porta 7532 - Docker/API Oficial):${WHITE}\n"
    echo
    for db in "${LISTA_7532[@]}"; do
      printf "   • %s\n" "$db"
    done
    echo
  fi
  if [ ${#LISTA_5432[@]} -eq 0 ] && [ ${#LISTA_7532[@]} -eq 0 ]; then
    printf "${RED} >> Nenhum banco listado. Verifique se o PostgreSQL está ativo e usuário/senha.${WHITE}\n"
  fi
  printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
  read -r
}

# Restaurar backup do Postgres Alta Performance (Docker) a partir de /home/deploy/backup-bd-docker-<empresa>
restaurar_backup_banco_alta_performance_ferramentas() {
  banner
  printf "${WHITE} >> Restaurar backup do banco Alta Performance (Docker)...${WHITE}\n"
  echo
  INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ARQUIVO_VARIAVEIS_INSTALADOR="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
  if [ -f "$ARQUIVO_VARIAVEIS_INSTALADOR" ]; then
    mf_carregar_config "$ARQUIVO_VARIAVEIS_INSTALADOR" 2>/dev/null
  fi
  if [ "${ALTA_PERFORMANCE}" != "1" ]; then
    printf "${RED} >> Esta opção é apenas para instalação em modo Alta Performance.${WHITE}\n"
    sleep 2
    return 1
  fi
  if [ -z "${empresa}" ]; then
    printf "${YELLOW} >> Empresa não encontrada nas variáveis. Informe o nome da empresa:${WHITE}\n"
    read -p "> " empresa
    [ -z "$empresa" ] && printf "${RED} >> Empresa não informada. Cancelado.${WHITE}\n" && sleep 2 && return 1
  fi
  local senha_db="${senha_deploy}"
  if [ -z "${senha_db}" ]; then
    printf "${YELLOW} >> Senha do banco (senha_deploy) não encontrada. Informe a senha:${WHITE}\n"
    read -s -p "> " senha_db
    echo
    [ -z "$senha_db" ] && printf "${RED} >> Senha não informada. Cancelado.${WHITE}\n" && sleep 2 && return 1
  fi
  local BACKUP_DIR="/home/deploy/backup-bd-docker-${empresa}"
  local BACKUP_DIR_LEGACY="/home/deploy/backup-bd-docker"
  if [ ! -d "${BACKUP_DIR}" ] && [ -d "${BACKUP_DIR_LEGACY}" ]; then
    printf "${YELLOW} >> Pasta por empresa não encontrada; usando legado: ${BACKUP_DIR_LEGACY}${WHITE}\n"
    BACKUP_DIR="${BACKUP_DIR_LEGACY}"
  fi
  if [ ! -d "${BACKUP_DIR}" ]; then
    printf "${RED} >> Pasta de backup não encontrada: /home/deploy/backup-bd-docker-${empresa}${WHITE}\n"
    sleep 2
    return 1
  fi
  local POSTGRES_CONTAINER="postgres_${empresa}"
  if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${POSTGRES_CONTAINER}$"; then
    printf "${RED} >> Container ${POSTGRES_CONTAINER} não está em execução.${WHITE}\n"
    sleep 2
    return 1
  fi
  BACKUPS_AP=()
  while IFS= read -r f; do
    [ -n "$f" ] && BACKUPS_AP+=("$f")
  done < <(find "${BACKUP_DIR}" -maxdepth 1 -type f \( -name "*.sql.gz" -o -name "*.sql" \) 2>/dev/null | sort -r)
  if [ ${#BACKUPS_AP[@]} -eq 0 ]; then
    printf "${RED} >> Nenhum backup encontrado em ${BACKUP_DIR}${WHITE}\n"
    sleep 2
    return 1
  fi

  printf "${WHITE} >> Backups encontrados em ${BACKUP_DIR}:${WHITE}\n"
  echo
  local i=1
  for f in "${BACKUPS_AP[@]}"; do
    printf "   [${BLUE}%s${WHITE}] %s\n" "$i" "$(basename "$f")"
    ((i++))
  done
  printf "   [${BLUE}0${WHITE}] Cancelar\n"
  echo
  printf "${YELLOW} >> Escolha o backup que deseja restaurar:${WHITE}\n"
  read -p "> " op_backup
  if [ "$op_backup" = "0" ] || [ -z "$op_backup" ]; then
    printf "${YELLOW} >> Cancelado.${WHITE}\n"
    sleep 2
    return 0
  fi
  local arquivo_escolhido=""
  i=1
  for f in "${BACKUPS_AP[@]}"; do
    if [ "$i" = "$op_backup" ]; then
      arquivo_escolhido="$f"
      break
    fi
    ((i++))
  done
  if [ -z "$arquivo_escolhido" ] || [ ! -f "$arquivo_escolhido" ]; then
    printf "${RED} >> Opção inválida. Cancelado.${WHITE}\n"
    sleep 2
    return 1
  fi

  local nome_arquivo db_origem base_nome
  nome_arquivo="$(basename "$arquivo_escolhido")"
  base_nome="${nome_arquivo%.sql.gz}"
  base_nome="${base_nome%.sql}"
  db_origem=""
  if [[ "$base_nome" =~ ^backup-([A-Za-z0-9_]+)-[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
    db_origem="${BASH_REMATCH[1]}"
  elif [[ "$base_nome" =~ backup_([A-Za-z0-9_]+)_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
    db_origem="${BASH_REMATCH[1]}"
  elif [[ "$base_nome" =~ backup-([A-Za-z0-9_]+)$ ]]; then
    db_origem="${BASH_REMATCH[1]}"
  fi
  if [ -z "$db_origem" ]; then
    printf "${YELLOW} >> Não foi possível detectar o banco automaticamente pelo nome do arquivo.${WHITE}\n"
    printf "${YELLOW} >> Informe o nome do banco de destino base (ex: ${empresa}):${WHITE}\n"
    read -p "> " db_origem
    [ -z "$db_origem" ] && printf "${RED} >> Banco não informado. Cancelado.${WHITE}\n" && sleep 2 && return 1
  fi
  printf "${WHITE} >> Backup selecionado: %s${WHITE}\n" "${nome_arquivo}"
  printf "${WHITE} >> Banco de destino base: %s${WHITE}\n" "${db_origem}"
  echo
  printf "${YELLOW} >> Como deseja restaurar?${WHITE}\n"
  printf "   [${BLUE}1${WHITE}] Substituir banco ${db_origem} (DROP + CREATE + RESTORE)\n"
  printf "   [${BLUE}2${WHITE}] Restaurar em novo banco ${db_origem}_novo\n"
  printf "   [${BLUE}0${WHITE}] Cancelar\n"
  echo
  read -p "> " op_tipo
  if [ "$op_tipo" = "0" ] || [ -z "$op_tipo" ]; then
    printf "${YELLOW} >> Cancelado.${WHITE}\n"
    sleep 2
    return 0
  fi
  local db_destino="${db_origem}"
  if [ "$op_tipo" = "2" ]; then
    db_destino="${db_origem}_novo"
  fi
  if [ "$op_tipo" = "1" ]; then
    printf "${WHITE} >> Encerrando conexões com ${db_origem}...${WHITE}\n"
    docker exec "${POSTGRES_CONTAINER}" env PGPASSWORD="${senha_db}" psql -h 127.0.0.1 -p 5432 -U "${empresa}" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${db_origem}' AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
    sleep 1
    printf "${WHITE} >> Recriando banco ${db_origem}...${WHITE}\n"
    docker exec "${POSTGRES_CONTAINER}" env PGPASSWORD="${senha_db}" psql -h 127.0.0.1 -p 5432 -U "${empresa}" -d postgres -c "DROP DATABASE IF EXISTS ${db_origem};" >/dev/null 2>&1 || true
    if ! docker exec "${POSTGRES_CONTAINER}" env PGPASSWORD="${senha_db}" psql -h 127.0.0.1 -p 5432 -U "${empresa}" -d postgres -c "CREATE DATABASE ${db_origem} OWNER ${empresa};" >/dev/null 2>&1; then
      printf "${RED} >> Erro ao criar banco ${db_origem} no container.${WHITE}\n"
      sleep 2
      return 1
    fi
  else
    printf "${WHITE} >> Criando banco ${db_destino}...${WHITE}\n"
    if ! docker exec "${POSTGRES_CONTAINER}" env PGPASSWORD="${senha_db}" psql -h 127.0.0.1 -p 5432 -U "${empresa}" -d postgres -c "CREATE DATABASE ${db_destino} OWNER ${empresa};" >/dev/null 2>&1; then
      printf "${RED} >> Erro ao criar banco ${db_destino}. Pode já existir.${WHITE}\n"
      sleep 2
      return 1
    fi
  fi
  printf "${WHITE} >> Restaurando backup em ${db_destino}...${WHITE}\n"
  if [[ "${arquivo_escolhido}" == *.sql.gz ]]; then
    if gunzip -c "${arquivo_escolhido}" | docker exec -i "${POSTGRES_CONTAINER}" env PGPASSWORD="${senha_db}" psql -h 127.0.0.1 -p 5432 -U "${empresa}" -d "${db_destino}" >/dev/null 2>&1; then
      printf "${GREEN} >> Restauração concluída com sucesso em ${db_destino}.${WHITE}\n"
    else
      printf "${RED} >> Erro ao restaurar o backup compactado em ${db_destino}.${WHITE}\n"
      sleep 2
      return 1
    fi
  else
    if cat "${arquivo_escolhido}" | docker exec -i "${POSTGRES_CONTAINER}" env PGPASSWORD="${senha_db}" psql -h 127.0.0.1 -p 5432 -U "${empresa}" -d "${db_destino}" >/dev/null 2>&1; then
      printf "${GREEN} >> Restauração concluída com sucesso em ${db_destino}.${WHITE}\n"
    else
      printf "${RED} >> Erro ao restaurar o backup em ${db_destino}.${WHITE}\n"
      sleep 2
      return 1
    fi
  fi
  echo
  sleep 2
}

# --- WhatsMeow (WuzAPI): backup/restore PostgreSQL Docker (RabbitMQ não necessário) ---
ferramentas_whatsmeow_dir_backup() {
  printf '/home/deploy/backup-%s/whatsmeow' "${empresa}"
}

whatsmeow_ferramentas_ler_credenciais() {
  local emp="${1:-$empresa}"
  local env_file="/home/deploy/${emp}/wuzapi/.env"
  WHATSMEOW_DB_USER=""
  WHATSMEOW_DB_PASSWORD=""
  WHATSMEOW_DB_NAME=""
  WHATSMEOW_DB_CONTAINER=""
  WHATSMEOW_SERVER_CONTAINER=""

  [ -f "$env_file" ] || return 1
  WHATSMEOW_DB_USER=$(grep -m1 '^DB_USER=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  WHATSMEOW_DB_PASSWORD=$(grep -m1 '^DB_PASSWORD=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  WHATSMEOW_DB_NAME=$(grep -m1 '^DB_NAME=' "$env_file" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  WHATSMEOW_DB_USER="${WHATSMEOW_DB_USER:-wuzapi}"
  WHATSMEOW_DB_NAME="${WHATSMEOW_DB_NAME:-${WHATSMEOW_DB_USER}}"
  [ -n "$WHATSMEOW_DB_PASSWORD" ] && [ -n "$WHATSMEOW_DB_NAME" ] || return 1
  return 0
}

whatsmeow_ferramentas_resolver_containers() {
  local emp="${1:-$empresa}"
  local wuz_dir="/home/deploy/${emp}/wuzapi"
  local names proj="" c patterns_db patterns_srv

  WHATSMEOW_DB_CONTAINER=""
  WHATSMEOW_SERVER_CONTAINER=""
  names=$(docker ps -a --format '{{.Names}}' 2>/dev/null || true)

  patterns_db=(
    "wuzapi_${emp}-db"
    "wuzapi-db"
  )
  patterns_srv=(
    "wuzapi_${emp}-wuzapi-server"
    "wuzapi_${emp}-server"
    "wuzapi-wuzapi-server"
    "wuzapi-server"
  )

  for c in "${patterns_db[@]}"; do
    WHATSMEOW_DB_CONTAINER=$(echo "$names" | grep -E "^${c}(-[0-9]+)?$" | head -1)
    [ -n "$WHATSMEOW_DB_CONTAINER" ] && break
  done

  if [ -z "$WHATSMEOW_DB_CONTAINER" ] && [ -f "${wuz_dir}/docker-compose.yml" ]; then
    proj=$(grep -m1 '^name:' "${wuz_dir}/docker-compose.yml" 2>/dev/null | sed -E 's/^name:[[:space:]]*//; s/["'"'"']//g; s/[[:space:]]+$//')
    if [ -n "$proj" ]; then
      WHATSMEOW_DB_CONTAINER=$(echo "$names" | grep -E "^${proj}-db(-[0-9]+)?$" | head -1)
    fi
  fi

  if [ -z "$WHATSMEOW_DB_CONTAINER" ] && [ -f "${wuz_dir}/docker-compose.yml" ]; then
    local cid
    cid=$(cd "$wuz_dir" && docker compose ps -q db 2>/dev/null | head -1)
    if [ -n "$cid" ]; then
      WHATSMEOW_DB_CONTAINER=$(docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's|^/||')
    fi
  fi

  for c in "${patterns_srv[@]}"; do
    WHATSMEOW_SERVER_CONTAINER=$(echo "$names" | grep -E "^${c}(-[0-9]+)?$" | head -1)
    [ -n "$WHATSMEOW_SERVER_CONTAINER" ] && break
  done

  if [ -z "$WHATSMEOW_SERVER_CONTAINER" ] && [ -n "$proj" ]; then
    WHATSMEOW_SERVER_CONTAINER=$(echo "$names" | grep -E "^${proj}-(wuzapi-server|server)(-[0-9]+)?$" | head -1)
  fi

  docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$WHATSMEOW_DB_CONTAINER" || return 1
  return 0
}

whatsmeow_ferramentas_parar_api() {
  local emp="${1:-$empresa}"
  local wuz_dir="/home/deploy/${emp}/wuzapi"
  if [ -n "$WHATSMEOW_SERVER_CONTAINER" ]; then
    docker stop "$WHATSMEOW_SERVER_CONTAINER" 2>/dev/null || true
    return 0
  fi
  [ -f "${wuz_dir}/docker-compose.yml" ] && (cd "$wuz_dir" && docker compose stop wuzapi-server 2>/dev/null) || true
}

whatsmeow_ferramentas_iniciar_api() {
  local emp="${1:-$empresa}"
  local wuz_dir="/home/deploy/${emp}/wuzapi"
  if [ -n "$WHATSMEOW_SERVER_CONTAINER" ]; then
    docker start "$WHATSMEOW_SERVER_CONTAINER" 2>/dev/null && return 0
  fi
  [ -f "${wuz_dir}/docker-compose.yml" ] && (cd "$wuz_dir" && docker compose up -d wuzapi-server 2>/dev/null) && return 0
  return 1
}

backup_whatsmeow_ferramentas() {
  banner
  printf "${WHITE} >> Backup do banco WhatsMeow (WuzAPI)...${WHITE}\n"
  printf "${WHITE} >> Inclui sessões WhatsApp, usuários e dados no PostgreSQL.${WHITE}\n"
  printf "${YELLOW} >> RabbitMQ não entra no backup (fila de eventos transitória; recria ao subir a API).${WHITE}\n"
  echo
  if ! selecionar_instancia_atualizar "fazer backup do WhatsMeow"; then
    return 1
  fi
  if [ ! -d "/home/deploy/${empresa}/wuzapi" ] || [ ! -f "/home/deploy/${empresa}/wuzapi/docker-compose.yml" ]; then
    printf "${RED} >> WhatsMeow não instalado em ${empresa}.${WHITE}\n"
    sleep 2
    return 1
  fi
  if ! whatsmeow_ferramentas_ler_credenciais "${empresa}"; then
    printf "${RED} >> Não foi possível ler DB_USER/DB_PASSWORD/DB_NAME em wuzapi/.env${WHITE}\n"
    sleep 2
    return 1
  fi
  if ! whatsmeow_ferramentas_resolver_containers "${empresa}"; then
    printf "${RED} >> Container PostgreSQL do WuzAPI não está em execução.${WHITE}\n"
    printf "${YELLOW} >> Suba a stack: cd /home/deploy/${empresa}/wuzapi && docker compose up -d db${WHITE}\n"
    sleep 2
    return 1
  fi
  local backup_dir arquivo ts
  backup_dir=$(ferramentas_whatsmeow_dir_backup)
  mkdir -p "$backup_dir"
  chown deploy:deploy "$backup_dir" 2>/dev/null || true
  ts=$(date +%Y%m%d_%H%M%S)
  arquivo="${backup_dir}/wuzapi_${WHATSMEOW_DB_NAME}_${ts}.sql.gz"
  printf "${WHITE} >> Container: ${WHATSMEOW_DB_CONTAINER} | Banco: ${WHATSMEOW_DB_NAME}${WHITE}\n"
  printf "${WHITE} >> Destino: ${backup_dir}${WHITE}\n"
  printf "${WHITE} >> Gerando backup...${WHITE}\n"
  if docker exec "${WHATSMEOW_DB_CONTAINER}" env PGPASSWORD="${WHATSMEOW_DB_PASSWORD}" \
    pg_dump -U "${WHATSMEOW_DB_USER}" "${WHATSMEOW_DB_NAME}" 2>/dev/null | gzip > "$arquivo"; then
    if [ -s "$arquivo" ]; then
      chown deploy:deploy "$arquivo" 2>/dev/null || true
      printf "${GREEN} >> Backup salvo: ${arquivo}${WHITE}\n"
    else
      rm -f "$arquivo"
      printf "${RED} >> Backup vazio ou falhou.${WHITE}\n"
      sleep 2
      return 1
    fi
  else
    [ -f "$arquivo" ] && rm -f "$arquivo"
    printf "${RED} >> Erro ao executar pg_dump no container ${WHATSMEOW_DB_CONTAINER}.${WHITE}\n"
    sleep 2
    return 1
  fi
  echo
  sleep 2
}

restaurar_whatsmeow_ferramentas() {
  banner
  printf "${WHITE} >> Restaurar backup do banco WhatsMeow (WuzAPI)...${WHITE}\n"
  echo
  if ! selecionar_instancia_atualizar "restaurar backup do WhatsMeow"; then
    return 1
  fi
  if [ ! -d "/home/deploy/${empresa}/wuzapi" ] || [ ! -f "/home/deploy/${empresa}/wuzapi/docker-compose.yml" ]; then
    printf "${RED} >> WhatsMeow não instalado em ${empresa}.${WHITE}\n"
    sleep 2
    return 1
  fi
  if ! whatsmeow_ferramentas_ler_credenciais "${empresa}"; then
    printf "${RED} >> Não foi possível ler credenciais em wuzapi/.env${WHITE}\n"
    sleep 2
    return 1
  fi
  if ! whatsmeow_ferramentas_resolver_containers "${empresa}"; then
    printf "${RED} >> Container PostgreSQL do WuzAPI não está em execução.${WHITE}\n"
    sleep 2
    return 1
  fi
  local backup_dir BACKUPS_WZ=() f i arquivo_escolhido nome_arquivo
  backup_dir=$(ferramentas_whatsmeow_dir_backup)
  if [ ! -d "$backup_dir" ]; then
    printf "${RED} >> Pasta não encontrada: ${backup_dir}${WHITE}\n"
    printf "${YELLOW} >> Faça backup pela opção 22 ou coloque .sql/.sql.gz nesta pasta.${WHITE}\n"
    sleep 2
    return 1
  fi
  while IFS= read -r f; do
    [ -n "$f" ] && BACKUPS_WZ+=("$f")
  done < <(find "$backup_dir" -maxdepth 1 -type f \( -name "*.sql.gz" -o -name "*.sql" \) 2>/dev/null | sort -r)
  if [ ${#BACKUPS_WZ[@]} -eq 0 ]; then
    printf "${RED} >> Nenhum backup em ${backup_dir}${WHITE}\n"
    sleep 2
    return 1
  fi
  printf "${WHITE} >> Backups disponíveis:${WHITE}\n"
  echo
  i=1
  for f in "${BACKUPS_WZ[@]}"; do
    printf "   [${BLUE}%s${WHITE}] %s\n" "$i" "$(basename "$f")"
    ((i++))
  done
  printf "   [${BLUE}0${WHITE}] Cancelar\n"
  echo
  printf "${YELLOW} >> Escolha o backup para restaurar:${WHITE}\n"
  read -p "> " op_backup
  if [ "$op_backup" = "0" ] || [ -z "$op_backup" ]; then
    printf "${YELLOW} >> Cancelado.${WHITE}\n"
    sleep 2
    return 0
  fi
  arquivo_escolhido=""
  i=1
  for f in "${BACKUPS_WZ[@]}"; do
    if [ "$i" = "$op_backup" ]; then
      arquivo_escolhido="$f"
      break
    fi
    ((i++))
  done
  if [ -z "$arquivo_escolhido" ] || [ ! -f "$arquivo_escolhido" ]; then
    printf "${RED} >> Opção inválida.${WHITE}\n"
    sleep 2
    return 1
  fi
  nome_arquivo=$(basename "$arquivo_escolhido")
  printf "${WHITE} >> Backup: ${nome_arquivo}${WHITE}\n"
  printf "${WHITE} >> Banco de destino: ${WHATSMEOW_DB_NAME}${WHITE}\n"
  echo
  printf "${YELLOW} >> ATENÇÃO: o banco ${WHATSMEOW_DB_NAME} será substituído. A API WuzAPI será parada durante a restauração.${WHITE}\n"
  printf "${RED} >> Continuar? (s/N):${WHITE}\n"
  read -p "> " conf
  if [ "$conf" != "s" ] && [ "$conf" != "S" ]; then
    printf "${YELLOW} >> Cancelado.${WHITE}\n"
    sleep 2
    return 0
  fi
  printf "${WHITE} >> Parando wuzapi-server...${WHITE}\n"
  whatsmeow_ferramentas_parar_api "${empresa}"
  sleep 2
  printf "${WHITE} >> Encerrando conexões com ${WHATSMEOW_DB_NAME}...${WHITE}\n"
  docker exec "${WHATSMEOW_DB_CONTAINER}" env PGPASSWORD="${WHATSMEOW_DB_PASSWORD}" \
    psql -U "${WHATSMEOW_DB_USER}" -d postgres -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${WHATSMEOW_DB_NAME}' AND pid <> pg_backend_pid();" \
    >/dev/null 2>&1 || true
  sleep 1
  printf "${WHITE} >> Recriando banco ${WHATSMEOW_DB_NAME}...${WHITE}\n"
  docker exec "${WHATSMEOW_DB_CONTAINER}" env PGPASSWORD="${WHATSMEOW_DB_PASSWORD}" \
    psql -U "${WHATSMEOW_DB_USER}" -d postgres -c "DROP DATABASE IF EXISTS \"${WHATSMEOW_DB_NAME}\";" >/dev/null 2>&1 || true
  if ! docker exec "${WHATSMEOW_DB_CONTAINER}" env PGPASSWORD="${WHATSMEOW_DB_PASSWORD}" \
    psql -U "${WHATSMEOW_DB_USER}" -d postgres -c "CREATE DATABASE \"${WHATSMEOW_DB_NAME}\" OWNER \"${WHATSMEOW_DB_USER}\";" >/dev/null 2>&1; then
    printf "${RED} >> Erro ao recriar o banco ${WHATSMEOW_DB_NAME}.${WHITE}\n"
    whatsmeow_ferramentas_iniciar_api "${empresa}" || true
    sleep 2
    return 1
  fi
  printf "${WHITE} >> Restaurando backup...${WHITE}\n"
  if [[ "$arquivo_escolhido" == *.sql.gz ]]; then
    if ! gunzip -c "$arquivo_escolhido" | docker exec -i "${WHATSMEOW_DB_CONTAINER}" env PGPASSWORD="${WHATSMEOW_DB_PASSWORD}" \
      psql -U "${WHATSMEOW_DB_USER}" -d "${WHATSMEOW_DB_NAME}" >/dev/null 2>&1; then
      printf "${RED} >> Erro ao restaurar backup compactado.${WHITE}\n"
      whatsmeow_ferramentas_iniciar_api "${empresa}" || true
      sleep 2
      return 1
    fi
  else
    if ! cat "$arquivo_escolhido" | docker exec -i "${WHATSMEOW_DB_CONTAINER}" env PGPASSWORD="${WHATSMEOW_DB_PASSWORD}" \
      psql -U "${WHATSMEOW_DB_USER}" -d "${WHATSMEOW_DB_NAME}" >/dev/null 2>&1; then
      printf "${RED} >> Erro ao restaurar backup.${WHITE}\n"
      whatsmeow_ferramentas_iniciar_api "${empresa}" || true
      sleep 2
      return 1
    fi
  fi
  printf "${GREEN} >> Banco restaurado com sucesso.${WHITE}\n"
  printf "${WHITE} >> Reiniciando wuzapi-server...${WHITE}\n"
  if whatsmeow_ferramentas_iniciar_api "${empresa}"; then
    printf "${GREEN} >> WhatsMeow (${empresa}) reiniciado.${WHITE}\n"
  else
    printf "${YELLOW} >> Inicie manualmente: cd /home/deploy/${empresa}/wuzapi && docker compose up -d wuzapi-server${WHITE}\n"
  fi
  echo
  sleep 2
}

# Ferramentas: reinstala Baileys PRO (registry Heineken) no backend e reinicia o PM2 da instância
atualizar_baileys_pro_heineken_ferramentas() {
  banner
  printf "${WHITE} >> Atualizar Baileys PRO (Heineken) — tudo no diretório do sistema roda como usuário ${BLUE}deploy${WHITE} (package.json, npm i, PM2).${WHITE}\n"
  echo

  if ! selecionar_instancia_atualizar; then
    printf "${RED} >> Operação cancelada.${WHITE}\n"
    sleep 2
    return 1
  fi

  if [ -n "${ARQUIVO_VARIAVEIS_USADO:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_USADO}" ]; then
    # shellcheck source=/dev/null
    mf_carregar_config "${ARQUIVO_VARIAVEIS_USADO}" 2>/dev/null
  fi

  if ! echo "${repo_url:-}" | grep -Eqi 'github\.com'; then
    printf "${YELLOW} >> Aviso: o repositório configurado não parece ser HTTPS GitHub (Baileys/Heineken costuma exigir token).${WHITE}\n"
    printf "${YELLOW} >> Continuar mesmo assim? (s/N):${WHITE}\n"
    read -r continuar_nf
    continuar_nf=$(printf '%s' "${continuar_nf:-}" | tr '[:upper:]' '[:lower:]')
    if [ "$continuar_nf" != "s" ] && [ "$continuar_nf" != "sim" ]; then
      printf "${YELLOW} >> Cancelado.${WHITE}\n"
      sleep 2
      return 0
    fi
  fi

  if ! validar_e_atualizar_token_antes_atualizar; then
    printf "${RED} >> Token inválido ou operação cancelada.${WHITE}\n"
    sleep 2
    return 1
  fi

  if [ -n "${ARQUIVO_VARIAVEIS_USADO:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_USADO}" ]; then
    # shellcheck source=/dev/null
    mf_carregar_config "${ARQUIVO_VARIAVEIS_USADO}" 2>/dev/null
  fi

  local backend_dir="/home/deploy/${empresa}/backend"
  if [ ! -d "$backend_dir" ]; then
    printf "${RED} >> Pasta backend não encontrada: ${backend_dir}${WHITE}\n"
    sleep 2
    return 1
  fi

  # Token no package.json (registry Baileys) também aplicado como deploy — evita arquivo com dono root antes do npm i
  local tok_sed="${github_token//&/\\&}"

  printf "${WHITE} >> Como usuário ${BLUE}deploy${WHITE}: TOKEN no package.json (se MultiFlow-PRO), rm baileys + lock, npm i e reinício dos serviços...${WHITE}\n"
  echo

  if ! sudo su - deploy <<BAILEYSDEPLOY
  if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
    . /root/instalador_single_oficial/tools/path_node_deploy.sh
  else
    export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
    if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
      export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
    elif [ -d /usr/local/n/versions/node ]; then
      _mf_nv=\$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
      if [ -n "\$_mf_nv" ] && [ -d "/usr/local/n/versions/node/\$_mf_nv/bin" ]; then
        export PATH="/usr/local/n/versions/node/\$_mf_nv/bin:\$PATH"
      fi
    fi
  fi
  cd "${backend_dir}" || exit 1
  if [ -f package.json ] && grep -q "TOKEN_GITHUB" package.json 2>/dev/null; then
    sed -i "s|TOKEN_GITHUB|${tok_sed}|g" package.json
    printf "${GREEN} >> Token aplicado no package.json (Baileys).${WHITE}\n"
  fi
  if grep -q 'scriptswhitelabel/Hineken' package.json 2>/dev/null; then
    sed -i -E 's|(github\.com/scriptswhitelabel/Hineken\.git)(#[^"]*)?|\1#main|g' package.json
    printf "${GREEN} >> Baileys/Hineken fixado na branch main no package.json.${WHITE}\n"
  fi
  rm -rf node_modules/baileys package-lock.json
  npm i || exit 1
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE "^${empresa}_backend"; then
    docker restart "${empresa}_backend" 2>/dev/null || true
    echo ">> Contêiner ${empresa}_backend reiniciado com sucesso."
  elif pm2 list 2>/dev/null | grep -qE "${empresa}-backend[[:space:]]"; then
    pm2 restart "${empresa}-backend"
    pm2 save
    echo ">> Backend ${empresa}-backend reiniciado no PM2."
  else
    echo ">> Reinicie o backend: docker restart ${empresa}_backend"
  fi
  exit 0
BAILEYSDEPLOY
  then
    printf "${RED} >> Falha na etapa como usuário deploy (npm i ou ambiente). Verifique os logs acima.${WHITE}\n"
    sleep 2
    return 1
  fi

  echo
  sleep 2
  return 0
}

# Ferramentas: Portainer CE (painel Docker) — comandos conforme doc. oficial (9443 HTTPS, 8000 Edge)
instalar_portainer_ferramentas() {
  printf "${WHITE} >> Verificando se o Portainer já está instalado...${WHITE}\n"
  if ! command -v docker >/dev/null 2>&1; then
    printf "${RED} >> Docker não encontrado. Instale o Docker antes de continuar.${WHITE}\n"
    return 1
  fi
  if ! docker info >/dev/null 2>&1; then
    printf "${RED} >> Docker não está em execução ou sem permissão. Ex.: ${WHITE}systemctl start docker${RED}.${WHITE}\n"
    return 1
  fi

  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx portainer; then
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx portainer; then
      printf "${GREEN} >> Este servidor já possui o Portainer rodando (container Docker 'portainer').${WHITE}\n"
      printf "${WHITE} >> Não é necessário instalar novamente.${WHITE}\n"
    else
      printf "${YELLOW} >> Já existe o container 'portainer' neste servidor, mas ele não está em execução.${WHITE}\n"
      printf "${WHITE} >> Para iniciar manualmente: ${BLUE}docker start portainer${WHITE}\n"
      echo
      return 0
    fi
  else
    printf "${WHITE} >> Portainer não encontrado. Instalando via Docker...${WHITE}\n"
    docker volume inspect portainer_data >/dev/null 2>&1 || docker volume create portainer_data || {
      printf "${RED} >> Falha ao criar o volume portainer_data.${WHITE}\n"
      return 1
    }
    if ! docker run -d -p 8000:8000 -p 9443:9443 --name portainer --restart=always \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v portainer_data:/data \
      portainer/portainer-ce:latest; then
      printf "${RED} >> Falha ao subir o container Portainer.${WHITE}\n"
      return 1
    fi
    printf "${GREEN} >> Portainer instalado e em execução.${WHITE}\n"
  fi

  local ip_acesso
  ip_acesso=$(curl -s --max-time 8 http://checkip.amazonaws.com | tr -d '\r')
  if [ -z "${ip_acesso}" ]; then
    ip_acesso=$(hostname -I 2>/dev/null | awk '{print $1}')
  fi
  echo
  printf "${GREEN} >> Link de acesso ao Portainer:${WHITE}\n"
  printf "   ${BLUE}https://${ip_acesso}:9443${WHITE}\n"
  printf "${WHITE}   (Agentes Edge usam a porta ${BLUE}8000${WHITE}: ${BLUE}http://${ip_acesso}:8000${WHITE})\n"
  echo
  return 0
}

# Menu de Ferramentas
menu_ferramentas() {
  while true; do
    banner
    printf "${WHITE} Selecione abaixo a ferramenta desejada:\n"
    echo
    printf "  ${BLUE}━━ Instalações e integrações ━━${WHITE}\n"
    printf "   [${BLUE}2${WHITE}] Instalar Push Notifications\n"
    printf "   [${BLUE}3${WHITE}] Instalar API WhatsMeow\n"
    printf "   [${BLUE}5${WHITE}] Instalar Nova Instância\n"
    printf "   [${BLUE}24${WHITE}] Instalar MultiFlow-VOZ\n"
    printf "   [${BLUE}25${WHITE}] Atualizar MultiFlow-VOZ\n"
    printf "   [${BLUE}26${WHITE}] Instalar HUB MultiFlow\n"
    printf "   [${BLUE}27${WHITE}] Atualizar HUB MultiFlow\n"
    printf "   [${BLUE}31${WHITE}] Instalar ou Gerenciar API Oficial (WhatsApp Meta Cloud)\n"
    printf "   [${BLUE}32${WHITE}] Atualizar API Oficial (Docker)\n"
    echo
    printf "  ${BLUE}━━ Versão da aplicação ━━${WHITE}\n"
    printf "   [${BLUE}4${WHITE}] Roolback Versão\n"
    printf "   [${BLUE}30${WHITE}] Atualizar token GitHub + FAST (qualquer repo)\n"
    echo
    printf "  ${BLUE}━━ Backups agendados ━━${WHITE}\n"
    printf "   [${BLUE}6${WHITE}] Agendar Backup Diário do Banco Alta Performance\n"
    printf "   [${BLUE}7${WHITE}] Agendar Backup Diário do Banco Nativo\n"
    echo
    printf "  ${BLUE}━━ Redis ━━${WHITE}\n"
    printf "   [${BLUE}8${WHITE}] Backup do Redis (instância / Docker ou nativo)\n"
    printf "   [${BLUE}9${WHITE}] Restaurar Redis (backup da instância → container)\n"
    echo
    printf "  ${BLUE}━━ Banco de dados (PostgreSQL) ━━${WHITE}\n"
    printf "   [${BLUE}10${WHITE}] Importar backup do banco (instância + escolher banco)\n"
    printf "   [${BLUE}11${WHITE}] Backup do banco\n"
    printf "   [${BLUE}12${WHITE}] Importar backup do banco da API Oficial (nativo ou Alta Performance)\n"
    printf "   [${BLUE}13${WHITE}] Listar Bancos Existentes\n"
    printf "   [${BLUE}14${WHITE}] Restaurar backup do Banco Alta Performance (Docker)\n"
    echo
    printf "  ${BLUE}━━ WhatsMeow (WuzAPI) ━━${WHITE}\n"
    printf "   [${BLUE}22${WHITE}] Backup do banco WhatsMeow (PostgreSQL Docker)\n"
    printf "   [${BLUE}23${WHITE}] Restaurar backup do banco WhatsMeow\n"
    echo
    printf "  ${BLUE}━━ Domínio, SSL e Docker ━━${WHITE}\n"
    printf "   [${BLUE}15${WHITE}] Trocar domínios (URL backend / frontend)\n"
    printf "   [${BLUE}21${WHITE}] Aplicar certificado SSL no Nginx\n"
    printf "   [${BLUE}20${WHITE}] Domínio + porta + SSL no Nginx (proxy reverso)\n"
    printf "   [${BLUE}19${WHITE}] Instalar Portainer (Docker)\n"
    echo
    printf "  ${BLUE}━━ Performance e dependências ━━${WHITE}\n"
    printf "   [${BLUE}16${WHITE}] Atualizar Baileys PRO (Heineken)\n"
    printf "   [${BLUE}17${WHITE}] Atualizar API WhatsMeow (WuzAPI — git pull + rebuild)\n"
    printf "   [${BLUE}18${WHITE}] Otimizar Postgres Nativo\n"
    echo
    printf "  ${BLUE}━━ Menu ━━${WHITE}\n"
    printf "   [${BLUE}0${WHITE}] Voltar ao Menu Principal\n"
    echo
    read -p "> " option_tools
    case "${option_tools}" in
    2)
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      PUSH_SCRIPT="${SCRIPT_DIR}/tools/instalar_push.sh"
      if [ -f "$PUSH_SCRIPT" ]; then
        printf "${GREEN} >> Executando Instalador Push Notifications...${WHITE}\n"
        echo
        bash "$PUSH_SCRIPT"
        echo
        printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
        read -r
      else
        printf "${RED} >> Erro: Arquivo ${PUSH_SCRIPT} não encontrado!${WHITE}\n"
        sleep 3
      fi
      ;;
    3)
      instalar_whatsmeow
      ;;
    4)
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      ROLLBACK_SCRIPT="${SCRIPT_DIR}/tools/roolback_versao.sh"
      if [ -f "$ROLLBACK_SCRIPT" ]; then
        printf "${GREEN} >> Executando Roolback Versão...${WHITE}\n"
        echo
        bash "$ROLLBACK_SCRIPT"
        echo
        printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
        read -r
      else
        printf "${RED} >> Erro: Arquivo ${ROLLBACK_SCRIPT} não encontrado!${WHITE}\n"
        sleep 3
      fi
      ;;
    5)
      iniciar_instalacao_nova_instancia
      echo
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
      ;;
    24)
      instalar_multiflow_voz
      ;;
    25)
      atualizar_multiflow_voz
      ;;
    26)
      instalar_multiflow_hub
      ;;
    27)
      atualizar_multiflow_hub
      ;;
    30)
      atualizar_ultrawhats
      ;;
    31)
      instalar_api_oficial
      ;;
    32)
      atualizar_api_oficial
      ;;
    6)
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      BACKUP_SCRIPT="${SCRIPT_DIR}/tools/agendar_backup_bd_docker.sh"
      if [ -f "$BACKUP_SCRIPT" ]; then
        chmod 775 "$BACKUP_SCRIPT"
        bash "$BACKUP_SCRIPT"
        echo
        printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
        read -r
      else
        printf "${RED} >> Erro: Arquivo ${BACKUP_SCRIPT} não encontrado!${WHITE}\n"
        sleep 3
      fi
      ;;
    7)
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      BACKUP_SCRIPT="${SCRIPT_DIR}/tools/agendar_backup_bd_nativo.sh"
      if [ -f "$BACKUP_SCRIPT" ]; then
        chmod 775 "$BACKUP_SCRIPT"
        bash "$BACKUP_SCRIPT"
        echo
        printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
        read -r
      else
        printf "${RED} >> Erro: Arquivo ${BACKUP_SCRIPT} não encontrado!${WHITE}\n"
        sleep 3
      fi
      ;;
    8)
      backup_redis_ferramentas
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
      ;;
    9)
      restaurar_redis_ferramentas
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
      ;;
    10)
      importar_backup_banco_ferramentas
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
      ;;
    11)
      backup_banco_ferramentas
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
      ;;
    12)
      importar_backup_banco_api_oficial_ferramentas
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
      ;;
    13)
      listar_bancos_ferramentas
      ;;
    14)
      restaurar_backup_banco_alta_performance_ferramentas
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
      ;;
    22)
      backup_whatsmeow_ferramentas
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
      ;;
    23)
      restaurar_whatsmeow_ferramentas
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
      ;;
    15)
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      TROCAR_DOM_SCRIPT="${SCRIPT_DIR}/tools/trocar_dominios.sh"
      if [ -f "$TROCAR_DOM_SCRIPT" ]; then
        chmod 775 "$TROCAR_DOM_SCRIPT" 2>/dev/null || true
        printf "${GREEN} >> Executando troca de domínios...${WHITE}\n"
        echo
        bash "$TROCAR_DOM_SCRIPT"
        echo
        printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
        read -r
      else
        printf "${RED} >> Erro: Arquivo ${TROCAR_DOM_SCRIPT} não encontrado!${WHITE}\n"
        sleep 3
      fi
      ;;
    16)
      atualizar_baileys_pro_heineken_ferramentas
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
      ;;
    17)
      atualizar_whatsmeow
      ;;
    18)
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      OTIMIZAR_PG_SCRIPT="${SCRIPT_DIR}/tools/otimizar_postgres_nativo.sh"
      if [ -f "$OTIMIZAR_PG_SCRIPT" ]; then
        chmod 775 "$OTIMIZAR_PG_SCRIPT"
        bash "$OTIMIZAR_PG_SCRIPT"
        echo
        printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
        read -r
      else
        printf "${RED} >> Erro: Arquivo ${OTIMIZAR_PG_SCRIPT} não encontrado!${WHITE}\n"
        sleep 3
      fi
      ;;
    21)
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      SSL_NGINX_SCRIPT="${SCRIPT_DIR}/tools/aplicar_certificado_ssl_nginx.sh"
      if [ -f "$SSL_NGINX_SCRIPT" ]; then
        chmod 775 "$SSL_NGINX_SCRIPT"
        bash "$SSL_NGINX_SCRIPT"
        echo
        printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
        read -r
      else
        printf "${RED} >> Erro: Arquivo ${SSL_NGINX_SCRIPT} não encontrado!${WHITE}\n"
        sleep 3
      fi
      ;;
    19)
      instalar_portainer_ferramentas
      printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
      read -r
      ;;
    20)
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      NG_DOM_SSL_SCRIPT="${SCRIPT_DIR}/tools/nginx_dominio_porta_ssl.sh"
      if [ -f "$NG_DOM_SSL_SCRIPT" ]; then
        chmod 775 "$NG_DOM_SSL_SCRIPT" 2>/dev/null || true
        printf "${GREEN} >> Domínio, porta local e SSL (Nginx)...${WHITE}\n"
        echo
        bash "$NG_DOM_SSL_SCRIPT"
        echo
        printf "${GREEN} >> Pressione Enter para voltar ao menu de ferramentas...${WHITE}\n"
        read -r
      else
        printf "${RED} >> Erro: Arquivo ${NG_DOM_SSL_SCRIPT} não encontrado!${WHITE}\n"
        sleep 3
      fi
      ;;
    0)
      return
      ;;
    *)
      printf "${RED}Opção inválida. Tente novamente.${WHITE}"
      sleep 2
      ;;
    esac
  done
}

# ================================================================
# DESINSTALADOR OFICIAL DA PLATAFORMA (100% DOCKER - ISOLADO)
# ================================================================
selecionar_plataforma_desinstalacao() {
  local plataformas=()
  local p_dir nome

  # 1. Buscar diretórios em /home/deploy que sejam plataformas reais do AMANDA
  if [ -d "/home/deploy" ]; then
    for p_dir in /home/deploy/*; do
      if [ -d "$p_dir" ]; then
        nome=$(basename "$p_dir")
        case "$nome" in
          .*|backup*|lost+found|deploy|personalizacoes|redis*) continue ;;
        esac
        # Validar se é de fato uma plataforma AMANDA com compose ou código
        if [ -f "${p_dir}/docker-compose.yml" ] || \
           [ -f "${p_dir}/amanda/docker-compose.yml" ] || \
           [ -f "${p_dir}/.env" ] || \
           [ -f "${p_dir}/amanda/.env" ] || \
           [ -d "${p_dir}/backend" ] || \
           [ -d "${p_dir}/amanda" ]; then
          plataformas+=("$nome")
        fi
      fi
    done
  fi

  # 2. Buscar projetos ativos no Docker Compose ou prefixos de contêineres Docker
  if command -v docker >/dev/null 2>&1; then
    local c_nomes
    c_nomes=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E '_(backend|frontend|postgres|redis)' | sed -E 's/_.*//' | sort -u)
    for nome in $c_nomes; do
      case "$nome" in
        .*|backup*|lost+found|deploy|personalizacoes|redis*) continue ;;
      esac
      local ja_existe=0
      for p in "${plataformas[@]}"; do
        [ "$p" = "$nome" ] && ja_existe=1 && break
      done
      [ $ja_existe -eq 0 ] && plataformas+=("$nome")
    done

    # 3. Buscar nomes a partir de volumes residuais de plataformas
    local v_nomes
    v_nomes=$(docker volume ls -q 2>/dev/null | grep -E '_(postgres_data|redis_data|backend_database|backend_public|wuzapi_data)' | sed -E 's/_.*//' | sort -u)
    for nome in $v_nomes; do
      case "$nome" in
        .*|backup*|lost+found|deploy|personalizacoes|redis*|portainer*) continue ;;
      esac
      local ja_existe_v=0
      for p in "${plataformas[@]}"; do
        [ "$p" = "$nome" ] && ja_existe_v=1 && break
      done
      [ $ja_existe_v -eq 0 ] && plataformas+=("$nome")
    done
  fi

  banner
  printf "${WHITE}╔══════════════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "${WHITE}║        ${PURPLE}SELECIONE QUAL PLATAFORMA DOCKER DESEJA DESINSTALAR${WHITE}           ║${WHITE}\n"
  printf "${WHITE}╚══════════════════════════════════════════════════════════════════════╝${WHITE}\n"
  echo

  if [ ${#plataformas[@]} -eq 0 ]; then
    printf "   ${GREEN}✔ ${WHITE}Nenhuma plataforma Docker instalada detectada no servidor!${WHITE}\n\n"
    printf "   [${BLUE}M${WHITE}] Informar manualmente outro nome de plataforma (para limpar resíduos)\n"
    printf "   [${BLUE}0${WHITE}] Cancelar e Voltar ao Menu\n\n"
    printf "${WHITE}   Escolha uma opção: ${PURPLE}"
    read -r op_plat
    case "$op_plat" in
      M|m)
        printf "\n${WHITE} >> Digite o nome exato da plataforma que deseja desinstalar: ${PURPLE}"
        read -r plataforma_escolhida
        plataforma_escolhida=$(echo "$plataforma_escolhida" | tr -d '[:space:]')
        [ -z "$plataforma_escolhida" ] && return 1
        echo
        printf "${GREEN} >> Plataforma informada para desinstalação: ${YELLOW}%s${WHITE}\n" "$plataforma_escolhida"
        sleep 1
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  fi

  printf "   ${WHITE}Plataformas Docker detectadas no servidor:${WHITE}\n\n"

  local idx=1
  for p in "${plataformas[@]}"; do
    printf "   [${BLUE}%d${WHITE}] ${YELLOW}%s${WHITE} (/home/deploy/%s)\n" "$idx" "$p" "$p"
    idx=$((idx + 1))
  done
  printf "   [${BLUE}M${WHITE}] Informar manualmente outro nome de plataforma\n"
  printf "   [${BLUE}0${WHITE}] Cancelar e Voltar ao Menu\n\n"
  printf "${WHITE}   Escolha uma opção: ${PURPLE}"
  read -r op_plat

  case "$op_plat" in
    0)
      return 1
      ;;
    M|m)
      printf "\n${WHITE} >> Digite o nome exato da plataforma que deseja desinstalar: ${PURPLE}"
      read -r plataforma_escolhida
      plataforma_escolhida=$(echo "$plataforma_escolhida" | tr -d '[:space:]')
      [ -z "$plataforma_escolhida" ] && return 1
      ;;
    *)
      if [[ "$op_plat" =~ ^[0-9]+$ ]] && [ "$op_plat" -ge 1 ] && [ "$op_plat" -le "${#plataformas[@]}" ]; then
        plataforma_escolhida="${plataformas[$((op_plat - 1))]}"
      else
        printf "${RED} >> Opção inválida!${WHITE}\n"
        sleep 2
        return 1
      fi
      ;;
  esac

  echo
  printf "${GREEN} >> Plataforma selecionada para desinstalação: ${YELLOW}%s${WHITE}\n" "$plataforma_escolhida"
  sleep 1
  return 0
}

desinstalar_amanda_preservando_dados() {
  local plataforma_escolhida=""
  selecionar_plataforma_desinstalacao || return 0
  local empresa_alvo="$plataforma_escolhida" confirmacao
  mf_validar_empresa "$empresa_alvo" || { printf '%s\n' 'Nome de instância inválido.' >&2; return 1; }
  printf 'Remover containers da instância %s, preservando volumes, arquivos e configurações? (S/N): ' "$empresa_alvo"
  read -r confirmacao
  [[ "$confirmacao" = [sS] ]] || return 0
  mf_remover_recursos_instancia "$empresa_alvo" 0 || return 1
  printf '%s\n' 'Containers identificados removidos. Dados, código, chaves e configuração foram preservados.'
  printf '%s\n' 'Recursos sem label de propriedade, imagens e configuração do proxy foram mantidos para revisão manual.'
}

desinstalar_amanda_apagando_dados() {
  local plataforma_escolhida=""
  selecionar_plataforma_desinstalacao || return 0
  local empresa_alvo="$plataforma_escolhida" confirmacao app_dir caminho_real
  mf_validar_empresa "$empresa_alvo" || { printf '%s\n' 'Nome de instância inválido.' >&2; return 1; }
  app_dir="/home/deploy/$empresa_alvo"
  caminho_real=$(realpath -m -- "$app_dir") || return 1
  if [ "$caminho_real" != "$app_dir" ] || [ -L "$app_dir" ]; then
    printf '%s\n' 'Diretório da instância fora do caminho permitido ou vinculado por symlink.' >&2
    return 1
  fi
  printf 'Apagar containers, volumes identificados e diretório %s? (S/N): ' "$app_dir"
  read -r confirmacao
  [[ "$confirmacao" = [sS] ]] || return 0
  printf 'Para confirmar a exclusão de %s, digite DELETAR TUDO: ' "$empresa_alvo"
  read -r confirmacao
  [ "$confirmacao" = 'DELETAR TUDO' ] || return 0
  mf_remover_recursos_instancia "$empresa_alvo" 1 || return 1
  [ "$(realpath -m -- "$app_dir")" = "$app_dir" ] && [ ! -L "$app_dir" ] || return 1
  rm -rf -- "$app_dir" || return 1
  rm -f -- "${MF_INSTALADOR_ROOT}/VARIAVEIS_INSTALACAO_INSTANCIA_${empresa_alvo}" \
    "${MF_INSTALADOR_ROOT}/ETAPA_INSTALACAO_${empresa_alvo}" || return 1
  printf '%s\n' 'Recursos com propriedade comprovada e diretório da instância removidos.'
  printf '%s\n' 'Volumes externos sem label, imagens, proxy e configurações compartilhadas foram mantidos para revisão manual.'
}

menu_desinstalar_plataforma() {
  while true; do
    banner
    printf "${WHITE}╔══════════════════════════════════════════════════════════════════════╗${WHITE}\n"
    printf "${WHITE}║             ${PURPLE}DESINSTALADOR OFICIAL DA PLATAFORMA ${nome_titulo:-AMANDA}${WHITE}             ║${WHITE}\n"
    printf "${WHITE}╚══════════════════════════════════════════════════════════════════════╝${WHITE}\n"
    echo
    printf "   ${WHITE}Escolha como deseja proceder com a desinstalação:${WHITE}\n\n"
    printf "   [${BLUE}1${WHITE}] ${GREEN}Desinstalar Plataforma PRESERVANDO os Bancos de Dados${WHITE}\n"
    printf "       ${GRAY}(Remove contêineres identificados da plataforma escolhida,${WHITE}\n"
    printf "       ${GRAY} MANTENDO volumes, arquivos, código e configuração)${WHITE}\n\n"
    printf "   [${BLUE}2${WHITE}] ${RED}Desinstalar Plataforma e APAGAR OS BANCOS DE DADOS (Destrutivo)${WHITE}\n"
    printf "       ${YELLOW}(Remove contêineres e volumes identificados, além do diretório da instância.${WHITE}\n"
    printf "       ${RED} ATENÇÃO: Todos os dados da plataforma serão PERDIDOS PERMANENTEMENTE!)${WHITE}\n\n"
    printf "   [${BLUE}0${WHITE}] Voltar ao Menu Principal\n\n"
    printf "${WHITE}   Escolha uma opção: ${PURPLE}"
    read -r op_desinstala

    case "$op_desinstala" in
      1)
        desinstalar_amanda_preservando_dados
        return
        ;;
      2)
        desinstalar_amanda_apagando_dados
        return
        ;;
      0)
        return
        ;;
      *)
        printf "${RED}Opção inválida!${WHITE}\n"
        sleep 2
        ;;
    esac
  done
}

# Menu principal (100% Docker)
menu() {
  while true; do
    banner
    printf "${WHITE} Selecione abaixo a opção desejada:\n"
    echo
    printf "   [${BLUE}1${WHITE}] Instalar ${nome_titulo} (Docker Compose Completo + APIs)\n"
    printf "   [${BLUE}2${WHITE}] Atualizar ${nome_titulo} (Docker Compose)\n"
    printf "   [${BLUE}3${WHITE}] Gerenciar URLs do Sistema (com Ping e Reinício Automático)\n"
    printf "   [${BLUE}4${WHITE}] Status e Reiniciar Contêineres Docker\n"
    printf "   [${BLUE}5${WHITE}] Ver Logs dos Contêineres\n"
    printf "   [${BLUE}6${WHITE}] Fazer Backup do Banco PostgreSQL\n"
    printf "   [${BLUE}7${WHITE}] Restaurar Backup do Banco PostgreSQL\n"
    printf "   [${BLUE}8${WHITE}] Menu de Ferramentas Adicionais\n"
    printf "   [${BLUE}9${WHITE}] Desinstalar Plataforma ${nome_titulo}\n"
    printf "   [${BLUE}10${WHITE}] Homologação GHCR / Configurar Watchtower\n"
    printf "   [${BLUE}11${WHITE}] Instalar ou Gerenciar API Oficial\n"
    printf "   [${BLUE}0${WHITE}] Sair\n"
    echo
    read -p "> " option
    case "${option}" in
    1)
      verificar_arquivos_existentes
      ;;
    2)
      atualizar_amanda_docker
      ;;
    3)
      gerenciar_urls_sistema
      ;;
    4)
      menu_status_reiniciar_containers
      ;;
    5)
      menu_logs_containers
      ;;
    6)
      exec_backup_banco_docker
      ;;
    7)
      exec_restaurar_banco_docker
      ;;
    8)
      menu_ferramentas
      ;;
    9)
      menu_desinstalar_plataforma
      ;;
    10)
      configurar_watchtower_homologacao
      ;;
    11)
      menu_gerenciar_api_oficial
      ;;
    0)
      sair
      ;;
    *)
      printf "${RED}Opção inválida. Tente novamente.${WHITE}\n"
      sleep 2
      ;;
    esac
  done
}

# Etapa de instalação
instalacao_base() {
  carregar_variaveis
  carregar_etapa
  if [ "$etapa" == "0" ]; then
    questoes_dns_base || trata_erro "questoes_dns_base"
    verificar_dns_base || trata_erro "verificar_dns_base"
    questoes_variaveis_base || trata_erro "questoes_variaveis_base"
    define_proxy_base || trata_erro "define_proxy_base"
    define_portas_base || trata_erro "define_portas_base"
    confirma_dados_instalacao_base || trata_erro "confirma_dados_instalacao_base"
    questoes_otimizacao_nativa || trata_erro "questoes_otimizacao_nativa"
    salvar_variaveis || trata_erro "salvar_variaveis"
    salvar_etapa 1
  fi
  if [ "$etapa" -le "1" ]; then
    atualiza_vps_base || trata_erro "atualiza_vps_base"
    salvar_etapa 2
  fi
  if [ "$etapa" -le "2" ]; then
    cria_deploy_base || trata_erro "cria_deploy_base"
    salvar_etapa 3
  fi
  if [ "$etapa" -le "3" ]; then
    config_timezone_base || trata_erro "config_timezone_base"
    salvar_etapa 4
  fi
  if [ "$etapa" -le "4" ]; then
    config_firewall_base || trata_erro "config_firewall_base"
    salvar_etapa 5
  fi
  if [ "$etapa" -le "5" ]; then
    instala_puppeteer_base || trata_erro "instala_puppeteer_base"
    salvar_etapa 6
  fi
  if [ "$etapa" -le "6" ]; then
    instala_ffmpeg_base || trata_erro "instala_ffmpeg_base"
    salvar_etapa 7
  fi
  if [ "$etapa" -le "7" ]; then
    if [ "${ALTA_PERFORMANCE}" = "1" ]; then
      printf "${GREEN} >> Modo Alta Performance: pulando instalação do Postgres nativo (uso de container).${WHITE}\n"
      salvar_etapa 8
    else
      instala_postgres_base || trata_erro "instala_postgres_base"
      aplicar_otimizacao_postgres_instalacao || trata_erro "aplicar_otimizacao_postgres_instalacao"
      salvar_etapa 8
    fi
  fi
  if [ "$etapa" -le "8" ]; then
    instala_node_base || trata_erro "instala_node_base"
    salvar_etapa 9
  fi
  if [ "$etapa" -le "9" ]; then
    if [ "${ALTA_PERFORMANCE}" = "1" ]; then
      printf "${GREEN} >> Modo Alta Performance: pulando instalação do Redis nativo (uso de container).${WHITE}\n"
      salvar_etapa 10
    else
      instala_redis_base || trata_erro "instala_redis_base"
      salvar_etapa 10
    fi
  fi
  if [ "$etapa" -le "10" ]; then
    printf "${GREEN} >> Modo 100%% Docker: PM2 nativo dispensado (todos os microsserviços rodam em contêineres).${WHITE}\n"
    salvar_etapa 11
  fi
  if [ "$etapa" -le "11" ]; then
    if [ "${proxy}" == "nginx" ]; then
      instala_nginx_base || trata_erro "instala_nginx_base"
      otimizar_nginx_instalacao || trata_erro "otimizar_nginx_instalacao"
      salvar_etapa 12
    elif [ "${proxy}" == "traefik" ]; then
      instala_traefik_base || trata_erro "instala_traefik_base"
      salvar_etapa 12
    fi
  fi
  if [ "$etapa" -le "12" ]; then
    if [ "${ALTA_PERFORMANCE}" = "1" ]; then
      printf "${GREEN} >> Modo Alta Performance: banco já criado pelo container Postgres.${WHITE}\n"
      salvar_etapa 13
    else
      cria_banco_base || trata_erro "cria_banco_base"
      salvar_etapa 13
    fi
  fi
  if [ "$etapa" -le "13" ]; then
    instala_git_base || trata_erro "instala_git_base"
    salvar_etapa 14
  fi
  if [ "$etapa" -le "14" ]; then
    codifica_clone_base || trata_erro "codifica_clone_base"
    baixa_codigo_base || trata_erro "baixa_codigo_base"
    salvar_etapa 15
  fi
  if [ "$etapa" -le "15" ]; then
    instala_backend_base || trata_erro "instala_backend_base"
    salvar_etapa 16
  fi
  if [ "$etapa" -le "16" ]; then
    instala_frontend_base || trata_erro "instala_frontend_base"
    salvar_etapa 17
  fi
  if [ "$etapa" -le "17" ]; then
    config_cron_base || trata_erro "config_cron_base"
    salvar_etapa 18
  fi
  if [ "$etapa" -le "18" ]; then
    if [ "${proxy}" == "nginx" ]; then
      config_nginx_base || trata_erro "config_nginx_base"
      salvar_etapa 19
    elif [ "${proxy}" == "traefik" ]; then
      config_traefik_base || trata_erro "config_traefik_base"
      salvar_etapa 19
    fi
  fi
  if [ "$etapa" -le "19" ]; then
    config_latencia_base || trata_erro "config_latencia_base"
    salvar_etapa 20
  fi
  if [ "$etapa" -le "20" ]; then
    fim_instalacao_base || trata_erro "fim_instalacao_base"
    salvar_etapa 21
  fi
}

# Função para detectar e listar todas as instâncias instaladas
detectar_instancias_instaladas() {
  local instancias=()
  local nomes_empresas=()
  INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  checar_e_adicionar_instancia() {
    local arq="$1"
    [ ! -f "$arq" ] && return 0
    case "$arq" in
      *.backup*|*.bak*|*.old*) return 0 ;;
    esac

    local emp=""
    emp=$(grep -E "^empresa=" "$arq" 2>/dev/null | cut -d'=' -f2- | tr -d '"\r ')
    [ -z "$emp" ] && return 0

    # Evitar duplicados no array
    local ja_tem=0
    for n in "${nomes_empresas[@]}"; do
      if [ "$n" = "$emp" ]; then
        ja_tem=1
        break
      fi
    done
    [ $ja_tem -eq 1 ] && return 0

    local app="/home/deploy/${emp}"
    if [ -d "$app" ] && { [ -d "${app}/backend" ] || [ -d "${app}/amanda" ] || [ -f "${app}/docker-compose.yml" ] || [ -f "${app}/amanda/docker-compose.yml" ] || [ -f "${app}/.env" ] || [ -f "${app}/amanda/.env" ]; }; then
      instancias+=("$arq")
      nomes_empresas+=("$emp")
    fi
  }

  # 1. Verificar instalação base (arquivo VARIAVEIS_INSTALACAO)
  if [ -f "${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS}" ]; then
    checar_e_adicionar_instancia "${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS}"
  elif [ -f "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO" ]; then
    checar_e_adicionar_instancia "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"
  fi

  # 2. Verificar instâncias adicionais (arquivos VARIAVEIS_INSTALACAO_INSTANCIA_*)
  if [ -d "${INSTALADOR_DIR}" ]; then
    for arquivo_instancia in "${INSTALADOR_DIR}"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
      [ -f "$arquivo_instancia" ] && checar_e_adicionar_instancia "$arquivo_instancia"
    done
  fi

  # 3. Varredura direta em /home/deploy/* como segurança adicional
  if [ -d "/home/deploy" ]; then
    for d in /home/deploy/*; do
      if [ -d "$d" ]; then
        local bname
        bname=$(basename "$d")
        case "$bname" in
          deploy|backup*|lost+found|personalizacoes|redis*) continue ;;
        esac
        local ja_tem=0
        for n in "${nomes_empresas[@]}"; do
          if [ "$n" = "$bname" ]; then
            ja_tem=1
            break
          fi
        done
        if [ $ja_tem -eq 0 ]; then
          if [ -f "${d}/amanda/docker-compose.yml" ] || [ -f "${d}/docker-compose.yml" ] || [ -f "${d}/.env" ] || [ -f "${d}/amanda/.env" ]; then
            if [ -f "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO_INSTANCIA_${bname}" ]; then
              instancias+=("${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO_INSTANCIA_${bname}")
              nomes_empresas+=("$bname")
            elif [ -f "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO" ] && grep -qw "empresa=${bname}" "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO" 2>/dev/null; then
              instancias+=("${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO")
              nomes_empresas+=("$bname")
            fi
          fi
        fi
      fi
    done
  fi

  # Retornar arrays (usando variáveis globais)
  declare -g INSTANCIAS_DETECTADAS=("${instancias[@]}")
  declare -g NOMES_EMPRESAS_DETECTADAS=("${nomes_empresas[@]}")
}

# Função para selecionar qual instância usar (atualização, importação de banco, etc.)
# $1 = texto da ação no menu (ex.: "atualizar", "importar o backup do banco")
selecionar_instancia_atualizar() {
  local rotulo_acao="${1:-atualizar}"
  local mostrar_api_oficial=0
  [[ "$rotulo_acao" == *"API Oficial"* ]] && mostrar_api_oficial=1
  banner
  printf "${WHITE} >> Detectando instâncias instaladas...\n"
  echo
  
  detectar_instancias_instaladas
  
  local total_instancias=${#INSTANCIAS_DETECTADAS[@]}
  
  if [ $total_instancias -eq 0 ]; then
    printf "${RED} >> ERRO: Nenhuma instância instalada detectada!${WHITE}\n"
    printf "${YELLOW} >> Não é possível ${rotulo_acao}. Verifique se há instâncias instaladas.${WHITE}\n"
    sleep 3
    return 1
  elif [ $total_instancias -eq 1 ]; then
    # Apenas uma instância, usar diretamente
    printf "${GREEN} >> Uma instância detectada: ${BLUE}${NOMES_EMPRESAS_DETECTADAS[0]}${WHITE}\n"
    echo
    sleep 2
    
    # Carregar variáveis da instância única
    mf_carregar_config "${INSTANCIAS_DETECTADAS[0]}"
    # Salvar arquivo usado em variável global para uso posterior
    declare -g ARQUIVO_VARIAVEIS_USADO="${INSTANCIAS_DETECTADAS[0]}"
    return 0
  else
    # Múltiplas instâncias, perguntar qual atualizar
    printf "${WHITE}═══════════════════════════════════════════════════════════\n"
    printf "  INSTÂNCIAS INSTALADAS DETECTADAS\n"
    printf "═══════════════════════════════════════════════════════════\n${WHITE}"
    echo
    
    local index=1
    for i in "${!NOMES_EMPRESAS_DETECTADAS[@]}"; do
      local empresa_nome="${NOMES_EMPRESAS_DETECTADAS[$i]}"
      local arquivo_instancia="${INSTANCIAS_DETECTADAS[$i]}"
      
      # Salvar variáveis atuais antes de carregar
      local empresa_original="${empresa:-}"
      local subdominio_backend_original="${subdominio_backend:-}"
      local subdominio_frontend_original="${subdominio_frontend:-}"
      
      # Tentar carregar informações adicionais da instância
      mf_carregar_config "$arquivo_instancia" 2>/dev/null
      
      local temp_subdominio_backend="${subdominio_backend:-}"
      local temp_subdominio_frontend="${subdominio_frontend:-}"
      
      # Restaurar variáveis originais
      empresa="${empresa_original}"
      subdominio_backend="${subdominio_backend_original}"
      subdominio_frontend="${subdominio_frontend_original}"
      
      printf "${BLUE}  [$index]${WHITE} Empresa: ${GREEN}${empresa_nome}${WHITE}\n"
      if [ -n "${temp_subdominio_backend}" ]; then
        printf "      Backend: ${YELLOW}${temp_subdominio_backend}${WHITE}\n"
      fi
      if [ -n "${temp_subdominio_frontend}" ]; then
        printf "      Frontend: ${YELLOW}${temp_subdominio_frontend}${WHITE}\n"
      fi
      if [ "$mostrar_api_oficial" -eq 1 ]; then
        local temp_db_of="" temp_sub_of=""
        if [ -f "/home/deploy/${empresa_nome}/api_oficial/.env" ]; then
          temp_db_of=$(grep -m1 '^DATABASE_NAME=' "/home/deploy/${empresa_nome}/api_oficial/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
          temp_sub_of=$(grep -m1 '^URL_API_OFICIAL=' "/home/deploy/${empresa_nome}/api_oficial/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
        fi
        if [ -n "$temp_db_of" ]; then
          printf "      API Oficial — banco: ${YELLOW}${temp_db_of}${WHITE}"
          [ -n "$temp_sub_of" ] && printf " | ${YELLOW}${temp_sub_of}${WHITE}"
          echo
        elif [ -d "/home/deploy/${empresa_nome}/api_oficial" ]; then
          printf "      API Oficial: ${YELLOW}pasta instalada (DATABASE_NAME não definido)${WHITE}\n"
        else
          printf "      API Oficial: ${RED}não instalada nesta instância${WHITE}\n"
        fi
      fi
      echo
      ((index++))
    done
    
    printf "${WHITE}═══════════════════════════════════════════════════════════\n${WHITE}"
    echo
    printf "${YELLOW} >> Qual instância deseja ${rotulo_acao}? (1-${total_instancias}):${WHITE}\n"
    read -p "> " escolha_instancia
    
    # Validar entrada
    if ! [[ "$escolha_instancia" =~ ^[0-9]+$ ]]; then
      printf "${RED} >> ERRO: Entrada inválida. Digite um número.${WHITE}\n"
      sleep 2
      return 1
    fi
    
    if [ "$escolha_instancia" -lt 1 ] || [ "$escolha_instancia" -gt $total_instancias ]; then
      printf "${RED} >> ERRO: Opção inválida. Escolha um número entre 1 e ${total_instancias}.${WHITE}\n"
      sleep 2
      return 1
    fi
    
    # Carregar variáveis da instância selecionada
    local indice_selecionado=$((escolha_instancia - 1))
    mf_carregar_config "${INSTANCIAS_DETECTADAS[$indice_selecionado]}"
    # Salvar arquivo usado em variável global para uso posterior
    declare -g ARQUIVO_VARIAVEIS_USADO="${INSTANCIAS_DETECTADAS[$indice_selecionado]}"
    
    printf "${GREEN} >> Instância selecionada: ${BLUE}${empresa}${WHITE}\n"
    echo
    sleep 2
    return 0
  fi
}

# Etapa de instalação
atualizar_base() {
  # Verificar e selecionar instância para atualizar
  if ! selecionar_instancia_atualizar; then
    printf "${RED} >> Erro ao selecionar instância. Voltando ao menu principal...${WHITE}\n"
    sleep 2
    menu
    return
  fi

  # Validar token antes de atualizar; se expirado, pedir novo e atualizar .git/config + variáveis
  if ! validar_e_atualizar_token_antes_atualizar; then
    printf "${RED} >> Atualização cancelada. Voltando ao menu principal...${WHITE}\n"
    sleep 2
    menu
    return
  fi

  if ! selecionar_versao_atualizacao; then
    printf "${RED} >> Atualização cancelada. Voltando ao menu principal...${WHITE}\n"
    sleep 2
    menu
    return
  fi

  backup_app_atualizar || trata_erro "backup_app_atualizar"
  instala_ffmpeg_base || trata_erro "instala_ffmpeg_base"
  config_cron_base || trata_erro "config_cron_base"
  baixa_codigo_atualizar || trata_erro "baixa_codigo_atualizar"
}

sair() {
  exit 0
}

################################################################
#                         INSTALAÇÃO                           #
################################################################

# Questões de Acesso e Rede (Com Domínio ou Sem Domínio / IP)
questoes_dns_base() {
  banner
  printf "${WHITE} Selecione como deseja acessar a plataforma AMANDA:\n\n"
  printf "   [${BLUE}1${WHITE}] Sem Domínio (Apenas IP / Localhost)\n"
  printf "       ${PURPLE}✓ Ideal para testes, ambiente local, WSL ou VPS sem domínio.${WHITE}\n"
  printf "       ${PURPLE}✓ Sem necessidade de apontar DNS nem emitir SSL.${WHITE}\n"
  printf "       ${PURPLE}✓ Acesso direto pelas portas 3000 (Frontend), 8080 (Backend) e 6000 (API Oficial).${WHITE}\n\n"
  printf "   [${BLUE}2${WHITE}] Com Domínios Próprios (SSL HTTPS + Proxy Reverso Nginx)\n"
  printf "       ${PURPLE}✓ Para produção com subdomínios (ex: app.meudominio.com e api.meudominio.com).${WHITE}\n\n"
  read -p " Selecione a opção [1 ou 2, padrão: 1]: " modo_rede
  modo_rede="${modo_rede:-1}"
  echo

  if [ "$modo_rede" = "1" ]; then
    declare -g INSTALACAO_SEM_DOMINIO="1"
    banner
    printf "${GREEN} >> Modo Sem Domínio (IP / Localhost) selecionado.${WHITE}\n\n"
    
    local is_local_env=0
    if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; then
      is_local_env=1
    elif [ -n "$ip_atual" ] && ! ip -o addr show 2>/dev/null | grep -qF "$ip_atual"; then
      is_local_env=1
    fi

    local ip_sugerido="${ip_atual}"
    if [ "$is_local_env" = "1" ]; then
      ip_sugerido="localhost"
      printf "${YELLOW} >> Detectado ambiente local/WSL ou IP atrás de NAT (${ip_atual}).${WHITE}\n"
      printf "${YELLOW}    Recomendado usar 'localhost' para testes na própria máquina.${WHITE}\n\n"
    elif [ -z "$ip_sugerido" ] || [ "$ip_sugerido" = "127.0.0.1" ]; then
      ip_sugerido=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    [ -z "$ip_sugerido" ] && ip_sugerido="localhost"

    printf "${WHITE} Insira o IP do servidor ou 'localhost' para acesso [Padrão: ${PURPLE}${ip_sugerido}${WHITE}]:\n"
    read -p "> " host_escolhido
    host_escolhido="${host_escolhido:-$ip_sugerido}"
    host_escolhido=$(echo "$host_escolhido" | sed -e 's|^[^/]*//||' -e 's|/.*$||' -e 's|:.*$||')
    [ -z "$host_escolhido" ] && host_escolhido="localhost"

    subdominio_backend="http://${host_escolhido}:8080"
    subdominio_frontend="http://${host_escolhido}:3000"
    subdominio_oficial="http://${host_escolhido}:6000"
    proxy="none"

    echo
    printf "${GREEN} >> URLs configuradas com sucesso:${WHITE}\n"
    printf "    Frontend (Web):   ${PURPLE}%s${WHITE}\n" "${subdominio_frontend}"
    printf "    Backend (API):    ${PURPLE}%s${WHITE}\n" "${subdominio_backend}"
    printf "    API Oficial Meta: ${PURPLE}%s${WHITE}\n\n" "${subdominio_oficial}"
    sleep 2
    return 0
  fi

  # Modo 2: Com domínios públicos
  declare -g INSTALACAO_SEM_DOMINIO="0"
  banner
  printf "${WHITE} >> Insira o domínio/URL do ${PURPLE}Backend${WHITE} (ex: api.seudominio.com.br):\n"
  printf "    ${YELLOW}(Ou pressione ENTER para modo Sem Domínio / IP)${WHITE}\n\n"
  read -p "> " subdominio_backend
  echo

  if [ -z "$subdominio_backend" ] || [ "$subdominio_backend" = "ip" ] || [ "$subdominio_backend" = "localhost" ]; then
    declare -g INSTALACAO_SEM_DOMINIO="1"
    local is_local_env=0
    if grep -qiE "microsoft|wsl" /proc/version 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; then
      is_local_env=1
    elif [ -n "$ip_atual" ] && ! ip -o addr show 2>/dev/null | grep -qF "$ip_atual"; then
      is_local_env=1
    fi
    local host_escolhido="localhost"
    if [ "$is_local_env" != "1" ] && [ -n "$ip_atual" ]; then
      host_escolhido="${ip_atual}"
    fi
    subdominio_backend="http://${host_escolhido}:8080"
    subdominio_frontend="http://${host_escolhido}:3000"
    subdominio_oficial=""
    proxy="none"
    printf "${GREEN} >> Campo em branco. Alternando para modo Sem Domínio (${host_escolhido}).${WHITE}\n"
    sleep 2
    return 0
  fi

  # ARMAZENA URL FRONTEND
  banner
  printf "${WHITE} >> Insira o domínio/URL do ${PURPLE}Frontend${WHITE} (ex: app.seudominio.com.br): \n"
  echo
  read -p "> " subdominio_frontend
  echo
  subdominio_oficial=""
}

# Valida se os domínios ou subdomínios estão acessíveis e apontados
verificar_dns_base() {
  if [ "${INSTALACAO_SEM_DOMINIO:-0}" = "1" ]; then
    banner
    printf "${GREEN} >> Modo Sem Domínio (Acesso Direto por IP / Localhost).${WHITE}\n"
    printf "${GREEN} >> Pulando verificação de DNS público e certificados SSL.${WHITE}\n\n"
    sleep 1
    return 0
  fi

  banner
  printf "${WHITE} >> Verificando conectividade e DNS dos domínios...\n"
  echo
  sleep 1

  if [ -n "${subdominio_backend}" ]; then
    case "${subdominio_backend}" in
      *localhost*|*127.0.0.1*|http://[0-9]*)
        ;;
      *)
        verificar_conectividade_url "${subdominio_backend}" "Backend" || return 1
        ;;
    esac
  fi
  if [ -n "${subdominio_frontend}" ]; then
    case "${subdominio_frontend}" in
      *localhost*|*127.0.0.1*|http://[0-9]*)
        ;;
      *)
        verificar_conectividade_url "${subdominio_frontend}" "Frontend" || return 1
        ;;
    esac
  fi
  if [ -n "${subdominio_oficial}" ]; then
    case "${subdominio_oficial}" in
      *localhost*|*127.0.0.1*|http://[0-9]*)
        ;;
      *)
        verificar_conectividade_url "${subdominio_oficial}" "API Oficial" || return 1
        ;;
    esac
  fi

  echo
  printf "${GREEN} >> Verificação de conectividade dos domínios concluída!${WHITE}\n"
  sleep 2
  return 0
}

questoes_variaveis_base() {
  # DEFINE EMAIL
  banner
  printf "${WHITE} >> Digite o seu melhor email: \n"
  echo
  read -p "> " email_deploy
  echo
  # DEFINE NOME DA EMPRESA
  banner
  local emp_padrao="${empresa:-amanda}"
  printf "${WHITE} >> Digite o nome da sua empresa (Letras minusculas e sem espaço) [padrão: ${GREEN}%s${WHITE}]: \n" "$emp_padrao"
  echo
  read -p "> " input_empresa
  empresa="${input_empresa:-$emp_padrao}"
  empresa=$(echo "$empresa" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')
  [ -z "$empresa" ] && empresa="amanda"
  echo
  # DEFINE SENHA BASE
  banner
  printf "${WHITE} >> Insira a senha para o usuario Deploy, Redis e Banco de Dados [padrão: Acertitech13@]: \n"
  echo
  read -p "> " senha_deploy
  senha_deploy="${senha_deploy:-Acertitech13@}"
  echo
  # DEFINE SENHA MASTER
  banner
  printf "${WHITE} >> Insira a senha para o MASTER [padrão: Acertitech13@M]: \n"
  echo
  read -p "> " senha_master
  senha_master="${senha_master:-Acertitech13@M}"
  echo
  # DEFINE TITULO DO APP NO NAVEGADOR
  banner
  printf "${WHITE} >> Insira o Titulo da Aplicação (Permitido Espaço) [padrão: AMANDA]: \n"
  echo
  read -p "> " nome_titulo
  nome_titulo="${nome_titulo:-AMANDA}"
  echo
  # DEFINE TELEFONE SUPORTE
  banner
  printf "${WHITE} >> Digite o numero de telefone para suporte: \n"
  echo
  read -p "> " numero_suporte
  echo
  # DEFINE FACEBOOK_APP_ID
  banner
  printf "${WHITE} >> Digite o FACEBOOK_APP_ID caso tenha: \n"
  echo
  read -p "> " facebook_app_id
  echo
  # DEFINE FACEBOOK_APP_SECRET
  banner
  printf "${WHITE} >> Digite o FACEBOOK_APP_SECRET caso tenha: \n"
  echo
  read -p "> " facebook_app_secret
  echo
  # DEFINE TOKEN GITHUB
  banner
  printf "${WHITE} >> Digite seu TOKEN de acesso pessoal do GitHub (deixe em branco se o repo for público): \n"
  printf "${WHITE} >> Passo a Passo para gerar o seu TOKEN no link ${BLUE}https://bit.ly/token-github ${WHITE} \n"
  echo
  read -p "> " github_token
  github_token=$(printf '%s' "${github_token}" | tr -d '\r\n ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  if [ -z "${github_token}" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
    github_token="${GITHUB_TOKEN}"
  fi
  echo
  # A confirmação inicial é obrigatória; configurações antigas não escolhem outro repo.
  repo_url="https://github.com/acerticonsulting/AMANDA.git"

  # Mostrar seleção de versão/commit apenas para o repositório multiflow-pro
  if echo "${repo_url}" | grep -q "scriptswhitelabel/multiflow-pro"; then
    selecionar_versao_instalacao
  else
    # Outros repositórios: sempre instalar a versão mais recente, sem menu
    declare -g versao_instalacao="Mais_Recente"
    declare -g commit_instalacao=""
  fi
}

# Define proxy usado
define_proxy_base() {
  if [ "${INSTALACAO_SEM_DOMINIO:-0}" = "1" ]; then
    proxy="none"
    export proxy
    return 0
  fi

  banner
  while true; do
    printf "${WHITE} >> Instalar usando Nginx ou Traefik? (Nginx/Traefik) [Padrão: Nginx]: ${WHITE}\n"
    echo
    read -p "> " proxy
    echo
    proxy="${proxy:-nginx}"
    proxy=$(echo "${proxy}" | tr '[:upper:]' '[:lower:]')

    if [ "${proxy}" = "nginx" ] || [ "${proxy}" = "traefik" ] || [ "${proxy}" = "none" ]; then
      sleep 1
      break
    else
      printf "${RED} >> Por favor, digite 'Nginx' ou 'Traefik' para continuar... ${WHITE}\n"
      echo
    fi
  done
  export proxy
}

# Define portas backend e frontend com exibição de status em tempo real
define_portas_base() {
  banner
  printf "${WHITE}╔══════════════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "${WHITE}║       ${PURPLE}EXIBIÇÃO DO STATUS DAS PORTAS EM TEMPO REAL NA VPS${WHITE}            ║${WHITE}\n"
  printf "${WHITE}╚══════════════════════════════════════════════════════════════════════╝${WHITE}\n"
  echo

  # Pré-calcular resolução automática das portas internas em modo silencioso
  resolver_portas_automaticas 1 >/dev/null 2>&1 || true

  local st_be st_fe st_db st_redis st_pgb st_transc st_wuzapi st_disp st_oficial
  testar_porta_tcp_ocupada 8080 && st_be="${RED}[Em uso - Requer alteração]${WHITE}" || st_be="${GREEN}[Livre - Pronto para uso]${WHITE}"
  testar_porta_tcp_ocupada 3000 && st_fe="${RED}[Em uso - Requer alteração]${WHITE}" || st_fe="${GREEN}[Livre - Pronto para uso]${WHITE}"

  if [ "$PORT_DB" = "5432" ]; then
    st_db="${GREEN}[Livre - Porta 5432]${WHITE}"
  else
    st_db="${YELLOW}[Em uso -> Alterado automaticamente para ${PORT_DB}]${WHITE}"
  fi

  if [ "$PORT_REDIS" = "6379" ]; then
    st_redis="${GREEN}[Livre - Porta 6379]${WHITE}"
  else
    st_redis="${YELLOW}[Em uso -> Alterado automaticamente para ${PORT_REDIS}]${WHITE}"
  fi

  if [ "$PORT_PGBOUNCER" = "6432" ]; then
    st_pgb="${GREEN}[Livre - Porta 6432]${WHITE}"
  else
    st_pgb="${YELLOW}[Em uso -> Alterado automaticamente para ${PORT_PGBOUNCER}]${WHITE}"
  fi

  if [ "$PORT_TRANSCRIBER" = "4002" ]; then
    st_transc="${GREEN}[Livre - Porta 4002]${WHITE}"
  else
    st_transc="${YELLOW}[Em uso -> Alterado automaticamente para ${PORT_TRANSCRIBER}]${WHITE}"
  fi

  if [ "$PORT_WUZAPI" = "8090" ]; then
    st_wuzapi="${GREEN}[Livre - Porta 8090]${WHITE}"
  else
    st_wuzapi="${YELLOW}[Em uso -> Alterado automaticamente para ${PORT_WUZAPI}]${WHITE}"
  fi

  if [ "$PORT_DISPATCHER" = "8095" ]; then
    st_disp="${GREEN}[Livre - Porta 8095]${WHITE}"
  else
    st_disp="${YELLOW}[Em uso -> Alterado automaticamente para ${PORT_DISPATCHER}]${WHITE}"
  fi

  printf "   ${WHITE}● ${CYAN}PORTAS EDITÁVEIS PELO USUÁRIO:${WHITE}\n"
  printf "     1) Backend AMANDA (API):       ${YELLOW}8080${WHITE}  ---> %b\n" "$st_be"
  printf "     2) Frontend AMANDA (Web):      ${YELLOW}3000${WHITE}  ---> %b\n\n" "$st_fe"

  printf "   ${WHITE}● ${CYAN}PORTAS COM AJUSTE 100%% AUTOMÁTICO (+1 ATÉ ACHAR LIVRE):${WHITE}\n"
  printf "     3) PostgreSQL (Database):      ${YELLOW}5432${WHITE}  ---> %b\n" "$st_db"
  printf "     4) Redis (Filas e Cache):      ${YELLOW}6379${WHITE}  ---> %b\n" "$st_redis"
  printf "     5) PgBouncer (Pool de Conexão): ${YELLOW}6432${WHITE}  ---> %b\n" "$st_pgb"
  printf "     6) API Transcrição de Áudio:   ${YELLOW}4002${WHITE}  ---> %b\n" "$st_transc"
  printf "     7) Wuzapi / WhatsApp Go:       ${YELLOW}8090${WHITE}  ---> %b\n" "$st_wuzapi"
  printf "     8) GoFlow Campaign Dispatcher: ${YELLOW}8095${WHITE}  ---> %b\n\n" "$st_disp"
  printf "   ${WHITE}ℹ️  ${YELLOW}Nota: PostgreSQL, Redis e PgBouncer serão alterados automaticamente caso em uso.${WHITE}\n"
  printf "   ${WHITE}ℹ️  ${YELLOW}As únicas portas personalizáveis nesta etapa são as do Frontend e Backend.${WHITE}\n\n"

  default_backend_port=8080
  default_frontend_port=3000

  printf "${WHITE} >> Usar as portas padrão para Backend (8080) e Frontend (3000) ? (S/N) [Padrão: S]: ${WHITE}\n"
  echo
  read -p "> " use_default_ports
  use_default_ports=${use_default_ports:-s}
  use_default_ports=$(echo "${use_default_ports}" | tr '[:upper:]' '[:lower:]')
  echo

  local custom_port_backend=0
  local custom_port_frontend=0

  if [ "${use_default_ports}" = "s" ]; then
    if testar_porta_tcp_ocupada "${default_backend_port}"; then
      backend_port=$(proxima_porta_livre "${default_backend_port}")
      printf "${YELLOW} >> Porta 8080 em uso na VPS. Backend alocado na porta livre ${backend_port} (8080 + $((backend_port - 8080))).${WHITE}\n"
    else
      backend_port=${default_backend_port}
    fi
    if testar_porta_tcp_ocupada "${default_frontend_port}" || [ "${default_frontend_port}" = "${backend_port}" ]; then
      frontend_port=$(proxima_porta_livre "${default_frontend_port}")
      while [ "${frontend_port}" = "${backend_port}" ]; do
        frontend_port=$((frontend_port + 1))
        frontend_port=$(proxima_porta_livre "${frontend_port}")
      done
      printf "${YELLOW} >> Porta 3000 em uso na VPS. Frontend alocado na porta livre ${frontend_port} (3000 + $((frontend_port - 3000))).${WHITE}\n"
    else
      frontend_port=${default_frontend_port}
    fi
  else
    custom_port_backend=1
    custom_port_frontend=1
    while true; do
      printf "${WHITE} >> Qual porta deseja para o Backend? [padrão: 8080]: ${WHITE}\n"
      echo
      read -p "> " backend_port
      backend_port=${backend_port:-8080}
      echo
      if ! testar_porta_tcp_ocupada "${backend_port}"; then
        break
      else
        printf "${RED} >> A porta ${backend_port} já está em uso na VPS. Por favor, escolha outra.${WHITE}\n\n"
      fi
    done

    while true; do
      printf "${WHITE} >> Qual porta deseja para o Frontend? [padrão: 3000]: ${WHITE}\n"
      echo
      read -p "> " frontend_port
      frontend_port=${frontend_port:-3000}
      echo
      if [ "${frontend_port}" = "${backend_port}" ]; then
        printf "${RED} >> A porta ${frontend_port} já foi escolhida para o Backend. Por favor, escolha outra.${WHITE}\n\n"
        continue
      fi
      if ! testar_porta_tcp_ocupada "${frontend_port}"; then
        break
      else
        printf "${RED} >> A porta ${frontend_port} já está em uso na VPS. Por favor, escolha outra.${WHITE}\n\n"
      fi
    done
  fi

  export backend_port frontend_port
  if [ "${INSTALACAO_SEM_DOMINIO:-0}" = "1" ]; then
    subdominio_backend=$(echo "${subdominio_backend}" | sed -E "s/:[0-9]+$/:${backend_port}/")
    subdominio_frontend=$(echo "${subdominio_frontend}" | sed -E "s/:[0-9]+$/:${frontend_port}/")
    export subdominio_backend subdominio_frontend
  fi

  # Recalcular resolução automática das portas internas com backend e frontend definidos
  resolver_portas_automaticas 1 >/dev/null 2>&1 || true

  # ================================================================
  # RE-EXIBIÇÃO DO STATUS ATUALIZADO DAS PORTAS APÓS DEFINIÇÃO
  # ================================================================
  banner
  printf "${WHITE}╔══════════════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "${WHITE}║       ${GREEN}STATUS ATUALIZADO DAS PORTAS APÓS DEFINIÇÃO DO USUÁRIO${WHITE}         ║${WHITE}\n"
  printf "${WHITE}╚══════════════════════════════════════════════════════════════════════╝${WHITE}\n"
  echo

  local st_be_final st_fe_final
  if [ "${custom_port_backend}" = "1" ]; then
    st_be_final="${GREEN}[Livre - Definida pelo usuário: ${backend_port}]${WHITE}"
  elif [ "${backend_port}" = "8080" ]; then
    st_be_final="${GREEN}[Livre - Porta Padrão 8080]${WHITE}"
  else
    st_be_final="${YELLOW}[Auto-alocada na porta ${backend_port} (8080 + $((backend_port - 8080)))]${WHITE}"
  fi

  if [ "${custom_port_frontend}" = "1" ]; then
    st_fe_final="${GREEN}[Livre - Definida pelo usuário: ${frontend_port}]${WHITE}"
  elif [ "${frontend_port}" = "3000" ]; then
    st_fe_final="${GREEN}[Livre - Porta Padrão 3000]${WHITE}"
  else
    st_fe_final="${YELLOW}[Auto-alocada na porta ${frontend_port} (3000 + $((frontend_port - 3000)))]${WHITE}"
  fi

  if [ "$PORT_DB" = "5432" ]; then
    st_db="${GREEN}[Livre - Porta 5432]${WHITE}"
  else
    st_db="${YELLOW}[Em uso -> Alocado automaticamente na porta ${PORT_DB} (5432 + $((PORT_DB - 5432)))]${WHITE}"
  fi

  if [ "$PORT_REDIS" = "6379" ]; then
    st_redis="${GREEN}[Livre - Porta 6379]${WHITE}"
  else
    st_redis="${YELLOW}[Em uso -> Alocado automaticamente na porta ${PORT_REDIS} (6379 + $((PORT_REDIS - 6379)))]${WHITE}"
  fi

  if [ "$PORT_PGBOUNCER" = "6432" ]; then
    st_pgb="${GREEN}[Livre - Porta 6432]${WHITE}"
  else
    st_pgb="${YELLOW}[Em uso -> Alocado automaticamente na porta ${PORT_PGBOUNCER} (6432 + $((PORT_PGBOUNCER - 6432)))]${WHITE}"
  fi

  if [ "$PORT_TRANSCRIBER" = "4002" ]; then
    st_transc="${GREEN}[Livre - Porta 4002]${WHITE}"
  else
    st_transc="${YELLOW}[Em uso -> Alocado automaticamente na porta ${PORT_TRANSCRIBER} (4002 + $((PORT_TRANSCRIBER - 4002)))]${WHITE}"
  fi

  if [ "$PORT_WUZAPI" = "8090" ]; then
    st_wuzapi="${GREEN}[Livre - Porta 8090]${WHITE}"
  else
    st_wuzapi="${YELLOW}[Em uso -> Alocado automaticamente na porta ${PORT_WUZAPI} (8090 + $((PORT_WUZAPI - 8090)))]${WHITE}"
  fi

  if [ "$PORT_DISPATCHER" = "8095" ]; then
    st_disp="${GREEN}[Livre - Porta 8095]${WHITE}"
  else
    st_disp="${YELLOW}[Em uso -> Alocado automaticamente na porta ${PORT_DISPATCHER} (8095 + $((PORT_DISPATCHER - 8095)))]${WHITE}"
  fi

  printf "   ${WHITE}● ${CYAN}PORTAS DEFINIDAS E VALIDADAS PARA A INSTALAÇÃO:${WHITE}\n"
  printf "     1) Backend AMANDA (API):       ${YELLOW}%-6s${WHITE} ---> %b\n" "${backend_port}" "$st_be_final"
  printf "     2) Frontend AMANDA (Web):      ${YELLOW}%-6s${WHITE} ---> %b\n\n" "${frontend_port}" "$st_fe_final"

  printf "   ${WHITE}● ${CYAN}PORTAS DE SERVIÇOS DOCKER AUXILIARES (100%% LIVRES):${WHITE}\n"
  printf "     3) PostgreSQL (Database):      ${YELLOW}%-6s${WHITE} ---> %b\n" "${PORT_DB}" "$st_db"
  printf "     4) Redis (Filas e Cache):      ${YELLOW}%-6s${WHITE} ---> %b\n" "${PORT_REDIS}" "$st_redis"
  printf "     5) PgBouncer (Pool de Conexão): ${YELLOW}%-6s${WHITE} ---> %b\n" "${PORT_PGBOUNCER}" "$st_pgb"
  printf "     6) API Transcrição de Áudio:   ${YELLOW}%-6s${WHITE} ---> %b\n" "${PORT_TRANSCRIBER}" "$st_transc"
  printf "     7) Wuzapi / WhatsApp Go:       ${YELLOW}%-6s${WHITE} ---> %b\n" "${PORT_WUZAPI}" "$st_wuzapi"
  printf "     8) GoFlow Campaign Dispatcher: ${YELLOW}%-6s${WHITE} ---> %b\n\n" "${PORT_DISPATCHER}" "$st_disp"

  printf "   ${GREEN}✔ ${WHITE}Todas as portas foram verificadas e validadas com sucesso na VPS!${WHITE}\n\n"
  printf "${WHITE} >> Pressione ${GREEN}[ENTER]${WHITE} para prosseguir para a confirmação dos dados...${WHITE}\n"
  read -r || true
}

# Informa os dados de instalação
dados_instalacao_base() {
  printf "   ${WHITE}Anote os dados abaixo\n\n"
  printf "   ${WHITE}Subdominio Backend: ---->> ${YELLOW}${subdominio_backend}\n"
  printf "   ${WHITE}Subdominiio Frontend: -->> ${YELLOW}${subdominio_frontend}\n"
  printf "   ${WHITE}Seu Email: ------------->> ${YELLOW}${email_deploy}\n"
  printf "   ${WHITE}Nome da Empresa: ------->> ${YELLOW}${empresa}\n"
  printf "   ${WHITE}Senha Deploy: ---------->> ${YELLOW}${senha_deploy}\n"
  # printf "   ${WHITE}Subdominio Perfex: ----->> ${YELLOW}${subdominio_perfex}\n"
  printf "   ${WHITE}Senha Master: ---------->> ${YELLOW}${senha_master}\n"
  printf "   ${WHITE}Titulo da Aplicação: --->> ${YELLOW}${nome_titulo}\n"
  printf "   ${WHITE}Numero de Suporte: ----->> ${YELLOW}${numero_suporte}\n"
  printf "   ${WHITE}FACEBOOK_APP_ID: ------->> ${YELLOW}${facebook_app_id}\n"
  printf "   ${WHITE}FACEBOOK_APP_SECRET: --->> ${YELLOW}${facebook_app_secret}\n"
  printf "   ${WHITE}Token GitHub: ---------->> ${YELLOW}${github_token}\n"
  printf "   ${WHITE}URL do Repositório: ---->> ${YELLOW}${repo_url}\n"
  printf "   ${WHITE}Proxy Usado: ----------->> ${YELLOW}${proxy}\n"
  printf "   ${WHITE}Porta Backend: --------->> ${YELLOW}${backend_port}\n"
  printf "   ${WHITE}Porta Frontend: -------->> ${YELLOW}${frontend_port}\n"
  printf "   ${WHITE}Porta PostgreSQL: ------>> ${YELLOW}${PORT_DB:-5432}\n"
  printf "   ${WHITE}Porta Redis: ----------->> ${YELLOW}${PORT_REDIS:-6379}\n"
  printf "   ${WHITE}Porta PgBouncer: ------->> ${YELLOW}${PORT_PGBOUNCER:-6432}\n"
  printf "   ${WHITE}Porta Transcrição: ----->> ${YELLOW}${PORT_TRANSCRIBER:-4002}\n"
  printf "   ${WHITE}Porta Wuzapi: ---------->> ${YELLOW}${PORT_WUZAPI:-8090}\n"
  printf "   ${WHITE}Porta GoFlow Dispatch: ->> ${YELLOW}${PORT_DISPATCHER:-8095}\n"
  if [ -n "${versao_instalacao}" ]; then
    printf "   ${WHITE}Versão Instalada: ------->> ${YELLOW}${versao_instalacao}${WHITE}\n"
    printf "   ${WHITE}Commit Instalado: ------->> ${YELLOW}${commit_instalacao}${WHITE}\n"
  fi
}

# Confirma os dados de instalação
confirma_dados_instalacao_base() {
  banner
  printf "${WHITE} >> Confira abaixo os dados dessa instalação! ${WHITE}\n\n"
  dados_instalacao_base
  echo
  printf "${WHITE} >> Os dados estão corretos? ${GREEN}S/${RED}N:${WHITE} \n"
  echo
  read -p "> " confirmacao
  echo
  confirmacao=$(echo "${confirmacao}" | tr '[:lower:]' '[:upper:]')
  if [ "${confirmacao}" == "S" ]; then
    printf "${GREEN} >> Continuando a Instalação... ${WHITE} \n"
    echo
  else
    printf "${GREEN} >> Retornando ao Menu Principal... ${WHITE} \n"
    echo
    sleep 2
    menu
  fi
}

# Define otimização do PostgreSQL nativo e do Nginx (instalação padrão)
questoes_otimizacao_nativa() {
  perfil_otimizacao_vps="0"

  if [ "${ALTA_PERFORMANCE}" = "1" ]; then
    return 0
  fi

  banner
  printf "${WHITE} >> Deseja aplicar a otimização do PostgreSQL nativo conforme o perfil da VPS?${WHITE}\n"
  if [ "${proxy}" = "nginx" ]; then
    printf "${WHITE} >> Com Nginx selecionado, o bloco events do nginx.conf também será ajustado após a instalação do Nginx.${WHITE}\n"
  fi
  echo
  printf "${WHITE} >> Escolha o perfil do servidor:${WHITE}\n"
  echo
  printf "   [${BLUE}1${WHITE}] VPS com 4 Core x 8 GB RAM\n"
  printf "   [${BLUE}2${WHITE}] VPS com 6 Core x 16 GB RAM\n"
  printf "   [${BLUE}3${WHITE}] VPS com 8 Core x 32 GB RAM\n"
  printf "   [${BLUE}0${WHITE}] Não otimizar\n"
  echo
  read -p "> " opcao_otimizacao
  echo

  case "${opcao_otimizacao}" in
  1|2|3)
    perfil_otimizacao_vps="${opcao_otimizacao}"
    printf "${GREEN} >> Otimização agendada para o perfil ${perfil_otimizacao_vps} após a instalação do PostgreSQL nativo.${WHITE}\n"
  ;;
  0)
    perfil_otimizacao_vps="0"
    printf "${YELLOW} >> Otimização não será aplicada nesta instalação.${WHITE}\n"
  ;;
  *)
    printf "${RED} >> Opção inválida. A otimização não será aplicada.${WHITE}\n"
    perfil_otimizacao_vps="0"
  ;;
  esac

  echo
  sleep 2
}

# PGDG (apt.postgresql.org): em Ubuntu 20.04 (focal) o sufixo focal-pgdg costuma retornar 404 — quebra "apt update".
# Em releases mais novas o PGDG pode ser válido; só removemos em focal ou linhas explícitas focal-pgdg.
mf_remover_repositorios_apt_postgresql_pgdg_quebrados() {
  local f removido=0 codename
  codename="$(lsb_release -cs 2>/dev/null || true)"
  if [ ! -d /etc/apt/sources.list.d ]; then
    return 0
  fi
  shopt -s nullglob
  for f in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [ -f "$f" ] || continue
    if grep -q "apt.postgresql.org" "$f" 2>/dev/null; then
      if [ "$codename" = "focal" ] || grep -q "focal-pgdg" "$f" 2>/dev/null; then
        printf "${YELLOW} >> Removendo fonte APT PostgreSQL.org incompatível (focal / focal-pgdg): ${f}${WHITE}\n"
        rm -f "$f"
        removido=1
      fi
    fi
  done
  shopt -u nullglob
  if [ -f /etc/apt/sources.list ] && grep -q "apt.postgresql.org" /etc/apt/sources.list 2>/dev/null; then
    if [ "$codename" = "focal" ] || grep -q "focal-pgdg" /etc/apt/sources.list 2>/dev/null; then
      sed -i '\|apt.postgresql.org|d' /etc/apt/sources.list 2>/dev/null || true
      removido=1
    fi
  fi
  if [ "$removido" = "1" ]; then
    printf "${WHITE} >> Dica: use os pacotes \"postgresql\" do Ubuntu nesta VPS ou atualize o SO para PGDG suportado.${WHITE}\n"
    sleep 1
  fi
  return 0
}

# Atualiza sistema operacional
atualiza_vps_base() {
  banner
  printf "${WHITE} >> Atualizando sistema operacional...\n"
  echo
  
  # Verificar conectividade antes de atualizar
  if ! verificar_conectividade; then
    printf "${YELLOW} >> Tentando corrigir problemas de DNS...${WHITE}\n"
    tentar_corrigir_dns
    
    # Verificar novamente
    if ! verificar_conectividade; then
      printf "${RED} >> ERRO: Problemas de conectividade não resolvidos.${WHITE}\n"
      printf "${YELLOW} >> Por favor, resolva os problemas de rede antes de continuar.${WHITE}\n"
      trata_erro "atualiza_vps_base"
    fi
  fi
  
  UPDATE_FILE="$(pwd)/update.x"
  {
    mf_remover_repositorios_apt_postgresql_pgdg_quebrados
    # Tentar atualizar, se falhar, corrigir DNS e tentar novamente
    if ! sudo DEBIAN_FRONTEND=noninteractive apt update -y; then
      printf "${YELLOW} >> Erro ao atualizar. Removendo fontes PGDG problemáticas (se ainda existirem) e tentando de novo...${WHITE}\n"
      mf_remover_repositorios_apt_postgresql_pgdg_quebrados
      if sudo DEBIAN_FRONTEND=noninteractive apt update -y; then
        :
      else
        printf "${YELLOW} >> Erro ao atualizar. Tentando corrigir DNS e tentar novamente...${WHITE}\n"
        tentar_corrigir_dns
        mf_remover_repositorios_apt_postgresql_pgdg_quebrados
        if ! sudo DEBIAN_FRONTEND=noninteractive apt update -y; then
          printf "${RED} >> ERRO: Falha ao atualizar lista de pacotes após correções.${WHITE}\n"
          printf "${YELLOW} >> Verifique sua conexão de internet e configuração de DNS.${WHITE}\n"
          trata_erro "atualiza_vps_base"
        fi
      fi
    fi
    
    sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" && sudo DEBIAN_FRONTEND=noninteractive apt-get install build-essential lsb-release -y && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y apparmor-utils
    touch "${UPDATE_FILE}"
    sleep 2
  } || trata_erro "atualiza_vps_base"
}

# Cria usuário deploy
cria_deploy_base() {
  banner
  printf "${WHITE} >> Agora, vamos criar o usuário para deploy...\n"
  echo
  {
    if ! id -u deploy >/dev/null 2>&1; then
      sudo useradd -m -p $(openssl passwd -1 "${senha_deploy}") -s /bin/bash -G sudo deploy 2>/dev/null || true
    fi
    sudo mkdir -p /home/deploy
    sudo chown deploy:deploy /home/deploy 2>/dev/null || true
    sudo chmod 755 /home/deploy 2>/dev/null || true
    sudo usermod -aG sudo deploy 2>/dev/null || true
    if getent group docker >/dev/null 2>&1; then
      sudo usermod -aG docker deploy 2>/dev/null || true
    fi
    sleep 1
  } || true
}

# Configura timezone
config_timezone_base() {
  banner
  printf "${WHITE} >> Configurando Timezone...\n"
  echo
  {
    timedatectl set-timezone America/Sao_Paulo 2>/dev/null || ln -sf /usr/share/zoneinfo/America/Sao_Paulo /etc/localtime 2>/dev/null || true
    sleep 1
  } || true
}

# Configura firewall
config_firewall_base() {
  banner
  printf "${WHITE} >> Configurando o firewall...\n"
  echo
  {
    if command -v ufw >/dev/null 2>&1; then
      ufw allow 80/tcp 2>/dev/null || true
      ufw allow 22/tcp 2>/dev/null || true
      ufw allow 443/tcp 2>/dev/null || true
      ufw allow 3000/tcp 2>/dev/null || true
      ufw allow 8080/tcp 2>/dev/null || true
      ufw allow 6000/tcp 2>/dev/null || true
    fi
    sleep 1
  } || true
}

# Instala dependência puppeteer
instala_puppeteer_base() {
  banner
  printf "${WHITE} >> Instalando puppeteer dependencies...\n"
  echo
  {
    sudo su - root <<EOF
apt-get install -y libaom-dev libass-dev libfreetype6-dev libfribidi-dev \
                   libharfbuzz-dev libgme-dev libgsm1-dev libmp3lame-dev \
                   libopencore-amrnb-dev libopencore-amrwb-dev libopenmpt-dev \
                   libopus-dev libfdk-aac-dev librubberband-dev libspeex-dev \
                   libssh-dev libtheora-dev libvidstab-dev libvo-amrwbenc-dev \
                   libvorbis-dev libvpx-dev libwebp-dev libx264-dev libx265-dev \
                   libxvidcore-dev libzmq3-dev libsdl2-dev build-essential \
                   yasm cmake libtool libc6 libc6-dev unzip wget pkg-config texinfo zlib1g-dev \
                   libxshmfence-dev libgcc1 libgbm-dev fontconfig locales gconf-service libasound2 \
                   libatk1.0-0 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgcc-s1 \
                   libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 libpango-1.0-0 \
                   libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 \
                   libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 \
                   libxss1 libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 \
                   lsb-release xdg-utils

if grep -q "20.04" /etc/os-release; then
    apt-get install -y libsrt-dev
else
    apt-get install -y libsrt-openssl-dev
fi

EOF
    sleep 2
  } || trata_erro "instala_puppeteer_base"
}

# Instala FFMPEG
instala_ffmpeg_base() {
  banner
  printf "${WHITE} >> Instalando FFMPEG 6...\n"
  echo

  if [ -f "${FFMPEG}" ]; then
    printf " >> FFMPEG já foi instalado. Continuando a instalação...\n"
    echo
  else

    sleep 2

    {
      sudo apt install ffmpeg -y
      # Dynamic fetch of latest FFmpeg build from BtbN/FFmpeg-Builds
      download_ok=false
      asset_url=""
      if [ "${ARCH}" = "x86_64" ]; then
        asset_url=$(curl -sL https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest | grep -oP '"browser_download_url":\s*"\K[^"]+' | grep -E 'linux64-gpl.*\.tar\.xz$' | head -n1)
      elif [ "${ARCH}" = "aarch64" ]; then
        asset_url=$(curl -sL https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest | grep -oP '"browser_download_url":\s*"\K[^"]+' | grep -E 'linuxarm64-gpl.*\.tar\.xz$' | head -n1)
      else
        echo "Arquitetura não suportada: ${ARCH}"
      fi

      if [ -n "${asset_url}" ]; then
        FFMPEG_FILE="${asset_url##*/}"
        wget -q "${asset_url}" -O "${FFMPEG_FILE}"
        if [ $? -eq 0 ]; then
          mkdir -p ${FFMPEG_DIR}
          tar -xvf ${FFMPEG_FILE} -C ${FFMPEG_DIR} >/dev/null 2>&1
          extracted_dir=$(tar -tf ${FFMPEG_FILE} | head -1 | cut -d/ -f1)
          if [ -n "${extracted_dir}" ] && [ -d "${FFMPEG_DIR}/${extracted_dir}/bin" ]; then
            sudo cp ${FFMPEG_DIR}/${extracted_dir}/bin/ffmpeg /usr/bin/ >/dev/null 2>&1
            sudo cp ${FFMPEG_DIR}/${extracted_dir}/bin/ffprobe /usr/bin/ >/dev/null 2>&1
            sudo cp ${FFMPEG_DIR}/${extracted_dir}/bin/ffplay /usr/bin/ >/dev/null 2>&1
            rm -rf ${FFMPEG_DIR} >/dev/null 2>&1
            rm -f ${FFMPEG_FILE} >/dev/null 2>&1
            download_ok=true
          fi
        fi
      fi

      if [ "${download_ok}" != true ]; then
        printf "${YELLOW} >> Não foi possível baixar o FFmpeg dos builds oficiais. Usando pacote da distribuição...${WHITE}\n"
      fi

      export PATH=/usr/bin:${PATH}
      echo 'export PATH=/usr/bin:${PATH}' >>~/.bashrc
      source ~/.bashrc >/dev/null 2>&1
      if command -v ffmpeg >/dev/null 2>&1; then
        touch "${FFMPEG}"
      fi
    } || trata_erro "instala_ffmpeg_base"
  fi
}

# Instala Postgres
instala_postgres_base() {
  banner
  printf "${WHITE} >> Instalando PostgreSQL 17...\n"
  echo

  local pg_major_instalado=""
  if command -v psql >/dev/null 2>&1; then
    pg_major_instalado=$(psql --version 2>/dev/null | awk '{print $3}' | cut -d. -f1)
    if [[ "$pg_major_instalado" =~ ^[0-9]+$ ]] && [ "$pg_major_instalado" -ge 17 ] && systemctl is-active --quiet postgresql 2>/dev/null; then
      printf "${GREEN} >> PostgreSQL ${pg_major_instalado} já está instalado e ativo.${WHITE}\n"
      sleep 2
      return 0
    fi
    if [[ "$pg_major_instalado" =~ ^[0-9]+$ ]] && [ "$pg_major_instalado" -lt 17 ]; then
      printf "${YELLOW} >> PostgreSQL ${pg_major_instalado} detectado, mas esta instalação exige PostgreSQL 17.${WHITE}\n"
    fi
  fi

  if ! sudo apt-get install gnupg wget ca-certificates -y; then
    printf "${RED} >> Falha ao instalar dependências do repositório PostgreSQL.${WHITE}\n"
    return 1
  fi

  local distro_codename distro_id distro_ver
  distro_codename="$(mf_detectar_codename_apt 2>/dev/null || true)"
  distro_id="?"
  distro_ver="?"
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    distro_id="${NAME:-${ID:-?}}"
    distro_ver="${VERSION_ID:-?}"
  fi

  if [ -n "$distro_codename" ]; then
    printf "${WHITE} >> Repositório PGDG: ${distro_codename}-pgdg (${distro_id} ${distro_ver})${WHITE}\n"
    sudo sh -c "echo 'deb http://apt.postgresql.org/pub/repos/apt ${distro_codename}-pgdg main' > /etc/apt/sources.list.d/pgdg.list"
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add - >/dev/null 2>&1 || true

    if sudo apt-get update -y && sudo apt-get -y install postgresql-17; then
      sudo systemctl enable postgresql >/dev/null 2>&1 || true
      sudo systemctl restart postgresql >/dev/null 2>&1 || true
    else
      printf "${RED} >> ERRO: não foi possível instalar PostgreSQL 17 via PGDG.${WHITE}\n"
      sudo rm -f /etc/apt/sources.list.d/pgdg.list
      if [ "$distro_codename" = "focal" ]; then
        printf "${YELLOW} >> Ubuntu 20.04 (focal) instala PostgreSQL 12 pelos repositórios padrão.${WHITE}\n"
        printf "${YELLOW} >> Como o sistema exige PostgreSQL 17, use Ubuntu 22.04/24.04, Debian 12+ ou Alta Performance (Docker Postgres 17).${WHITE}\n"
      else
        printf "${YELLOW} >> Verifique o repositório apt.postgresql.org para ${distro_codename}-pgdg.${WHITE}\n"
        printf "${YELLOW} >> Em SO muito novo, use Ubuntu 22.04/24.04 ou Alta Performance (Docker).${WHITE}\n"
      fi
      return 1
    fi
  else
    printf "${RED} >> Não foi possível detectar codename do SO (${distro_id} ${distro_ver}) para instalar PostgreSQL 17.${WHITE}\n"
    printf "${YELLOW} >> Tente: apt install -y lsb-release  |  ou use a opção Alta Performance (Docker Postgres 17).${WHITE}\n"
    return 1
  fi

  if ! command -v psql >/dev/null 2>&1; then
    printf "${RED} >> PostgreSQL não foi instalado corretamente (psql ausente).${WHITE}\n"
    return 1
  fi

  local pg_major_final
  pg_major_final=$(psql --version 2>/dev/null | awk '{print $3}' | cut -d. -f1)
  if ! [[ "$pg_major_final" =~ ^[0-9]+$ ]] || [ "$pg_major_final" -lt 17 ]; then
    printf "${RED} >> PostgreSQL instalado não é versão 17+ (detectado: ${pg_major_final:-desconhecido}).${WHITE}\n"
    printf "${YELLOW} >> Instalação interrompida para evitar banco em versão incompatível.${WHITE}\n"
    return 1
  fi

  printf "${GREEN} >> PostgreSQL ${pg_major_final} instalado com sucesso.${WHITE}\n"
  sleep 2
}

# Aplica tuning do PostgreSQL nativo escolhido na instalação
aplicar_otimizacao_postgres_instalacao() {
  if [ "${ALTA_PERFORMANCE}" = "1" ] || [ "${perfil_otimizacao_vps:-0}" = "0" ]; then
    return 0
  fi

  banner
  printf "${WHITE} >> Otimizando PostgreSQL nativo...\n"
  echo

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  OTIMIZAR_PG_SCRIPT="${SCRIPT_DIR}/tools/otimizar_postgres_nativo.sh"
  if [ ! -f "$OTIMIZAR_PG_SCRIPT" ]; then
    printf "${RED} >> Erro: Arquivo ${OTIMIZAR_PG_SCRIPT} não encontrado!${WHITE}\n"
    return 1
  fi

  chmod 775 "$OTIMIZAR_PG_SCRIPT"
  bash "$OTIMIZAR_PG_SCRIPT" --perfil "${perfil_otimizacao_vps}" || return 1
  sleep 2
}

# Ajusta worker_connections e multi_accept no nginx.conf
otimizar_nginx_instalacao() {
  if [ "${perfil_otimizacao_vps:-0}" = "0" ] || [ "${proxy}" != "nginx" ]; then
    return 0
  fi

  banner
  printf "${WHITE} >> Otimizando Nginx\n"
  echo
  {
    NGINX_CONF="/etc/nginx/nginx.conf"
    if [ ! -f "${NGINX_CONF}" ]; then
      printf "${RED} >> Arquivo ${NGINX_CONF} não encontrado.${WHITE}\n"
      return 1
    fi

    BACKUP_FILE="${NGINX_CONF}.bak.$(date +%Y%m%d_%H%M%S)"
    cp -a "${NGINX_CONF}" "${BACKUP_FILE}"
    printf "${YELLOW} >> Backup da configuração anterior: ${BACKUP_FILE}${WHITE}\n"

    perl -0777 -i -pe 's/\bevents\s*\{.*?\}/events {\n\tworker_connections 10768;\n\tmulti_accept on;\n}/s' "${NGINX_CONF}"

    if ! nginx -t >/dev/null 2>&1; then
      printf "${RED} >> Configuração do Nginx inválida após o ajuste. Restaurando backup...${WHITE}\n"
      cp -a "${BACKUP_FILE}" "${NGINX_CONF}"
      return 1
    fi

    if systemctl restart nginx 2>/dev/null || service nginx restart; then
      sleep 2
      printf "${GREEN} >> Nginx reiniciado com sucesso.${WHITE}\n"
    else
      printf "${RED} >> Falha ao reiniciar o Nginx.${WHITE}\n"
      return 1
    fi
  } || trata_erro "otimizar_nginx_instalacao"
}

# Instala NodeJS
instala_node_base() {
  banner
 printf "${WHITE} >> Instalando nodejs...\n"
 echo
  {
    sudo su - root <<'NODEINSTALL'
    # Remove repositórios antigos do NodeSource que podem estar causando problemas
    rm -f /etc/apt/sources.list.d/nodesource.list 2>/dev/null
    rm -f /etc/apt/sources.list.d/nodesource*.list 2>/dev/null
    
    # Tenta primeiro com Node.js 22.x (LTS atual disponível no repositório oficial)
    printf " >> Tentando instalar Node.js 22.x LTS (repositório oficial)...\n"
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - 2>&1 | grep -v "does not have a Release file" || {
      printf " >> Node.js 22.x não disponível. Tentando Node.js 20.x...\n"
      curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>&1 | grep -v "does not have a Release file" || {
        printf " >> Erro ao configurar repositório. Tentando método alternativo...\n"
        # Método alternativo: baixa e executa o script manualmente
        curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh 2>/dev/null || \
        curl -fsSL https://deb.nodesource.com/setup_20.x -o /tmp/nodesource_setup.sh
        bash /tmp/nodesource_setup.sh 2>&1 | grep -v "does not have a Release file" || {
          printf " >> Falha ao configurar repositório NodeSource.\n"
          exit 1
        }
      }
    }
    
    # Atualiza lista de pacotes (ignorando erros de outros repositórios)
    printf " >> Atualizando lista de pacotes...\n"
    apt-get update -y 2>&1 | grep -v "does not have a Release file" | grep -v "Key is stored in legacy" || true
    
    # Instala Node.js
    printf " >> Instalando Node.js...\n"
    apt-get install -y nodejs || {
      printf " >> Erro ao instalar Node.js via apt.\n"
      exit 1
    }
    
    # Verifica se Node.js foi instalado
    if ! command -v node &> /dev/null; then
      printf " >> Erro: Node.js não foi encontrado no PATH após instalação.\n"
      printf " >> Verificando localização...\n"
      find /usr -name node -type f 2>/dev/null | head -5
      exit 1
    fi
    
    # Verifica se npm está disponível
    if ! command -v npm &> /dev/null; then
      printf " >> Erro: npm não foi encontrado no PATH após instalação.\n"
      printf " >> Verificando localização...\n"
      find /usr -name npm -type f 2>/dev/null | head -5
      exit 1
    fi
    
    # Mostra versões instaladas
    printf " >> Node.js instalado: "
    node --version
    printf " >> npm instalado: "
    npm --version
    
    # Instala o gerenciador de versões 'n' e configura a versão específica 20.19.4
    printf " >> Instalando gerenciador de versões 'n'...\n"
    npm install -g n || {
      printf " >> Aviso: Não foi possível instalar 'n'. Continuando com versão padrão.\n"
    }
    
    # Tenta instalar versão específica se 'n' foi instalado
    if command -v n &> /dev/null; then
      printf " >> Configurando Node.js versão 20.19.4...\n"
      n 20.19.4 || {
        printf " >> Aviso: Não foi possível instalar versão específica. Usando versão padrão.\n"
      }
      
      # Garante que os binários estão no PATH do sistema
      if [ -f /usr/local/n/versions/node/20.19.4/bin/node ]; then
        ln -sf /usr/local/n/versions/node/20.19.4/bin/node /usr/bin/node
        ln -sf /usr/local/n/versions/node/20.19.4/bin/npm /usr/bin/npm
        ln -sf /usr/local/n/versions/node/20.19.4/bin/npx /usr/bin/npx 2>/dev/null || true
      fi
    fi
    
    # Cria links simbólicos para garantir acesso global
    NODE_BIN=$(which node 2>/dev/null || find /usr -name node -type f 2>/dev/null | head -1)
    NPM_BIN=$(which npm 2>/dev/null || find /usr -name npm -type f 2>/dev/null | head -1)
    
    if [ -n "$NODE_BIN" ] && [ "$NODE_BIN" != "/usr/bin/node" ]; then
      ln -sf "$NODE_BIN" /usr/bin/node
    fi
    
    if [ -n "$NPM_BIN" ] && [ "$NPM_BIN" != "/usr/bin/npm" ]; then
      ln -sf "$NPM_BIN" /usr/bin/npm
    fi
    
    # Atualiza o PATH no perfil do sistema
    if ! grep -q "/usr/local/n/versions/node" /etc/profile 2>/dev/null; then
      echo 'export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH' >> /etc/profile
    fi
    
    # Atualiza o PATH no bashrc do root e deploy
    for user_home in /root /home/deploy; do
      if [ -d "$user_home" ]; then
        if ! grep -q "/usr/local/n/versions/node" "$user_home/.bashrc" 2>/dev/null; then
          echo 'export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH' >> "$user_home/.bashrc"
        fi
      fi
    done
    
    # Verifica novamente se node e npm estão disponíveis
    printf " >> Verificando instalação final...\n"
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:$PATH
    node --version || exit 1
    npm --version || exit 1
NODEINSTALL
    
    sleep 2
  } || trata_erro "instala_node_base"
}

# Instala Redis
instala_redis_base() {
  {
    sudo su - root <<EOF
  apt install redis-server -y
  systemctl enable redis-server.service
  sed -i 's/# requirepass foobared/requirepass ${senha_deploy}/g' /etc/redis/redis.conf
  sed -i 's/^appendonly no/appendonly yes/g' /etc/redis/redis.conf
  systemctl restart redis-server.service
EOF
    sleep 2
  } || trata_erro "instala_redis_base"
}

# PM2 nativo desativado - a plataforma AMANDA opera 100% conteinerizada via Docker
instala_pm2_base() {
  printf "${GREEN} >> AMANDA 100%% Docker: PM2 nativo dispensado (todos os microsserviços rodam em contêineres Docker).${WHITE}\n"
  sleep 1
  return 0
}

# Instala Nginx e dependências
instala_nginx_base() {
  banner
  printf "${WHITE} >> Instalando Nginx...\n"
  echo
  
  # Verificar conectividade antes de continuar
  if ! verificar_conectividade; then
    printf "${YELLOW} >> Tentando corrigir problemas de DNS...${WHITE}\n"
    tentar_corrigir_dns
    
    # Verificar novamente
    if ! verificar_conectividade; then
      printf "${RED} >> ERRO: Problemas de conectividade não resolvidos.${WHITE}\n"
      printf "${YELLOW} >> Por favor, resolva os problemas de rede antes de continuar.${WHITE}\n"
      printf "${YELLOW} >> Você pode tentar:${WHITE}\n"
      printf "${YELLOW} >>   1. Verificar conexão de internet${WHITE}\n"
      printf "${YELLOW} >>   2. Configurar DNS manualmente${WHITE}\n"
      printf "${YELLOW} >>   3. Verificar firewall/proxy${WHITE}\n"
      trata_erro "instala_nginx_base"
    fi
  fi
  
  {
    # Atualizar lista de pacotes primeiro
    printf "${WHITE} >> Atualizando lista de pacotes...\n"
    sudo su - root <<EOF
apt update -y || {
  echo "Erro ao atualizar. Tentando corrigir DNS..."
  echo "nameserver 8.8.8.8" >> /etc/resolv.conf
  echo "nameserver 8.8.4.4" >> /etc/resolv.conf
  apt update -y
}
EOF

    sleep 2

    # Instalar Nginx
    printf "${WHITE} >> Instalando pacote Nginx...\n"
    sudo su - root <<EOF
if ! apt install -y nginx; then
  echo "Erro ao instalar Nginx. Verificando logs..."
  echo "Possíveis soluções:"
  echo "1. Verificar conectividade de internet"
  echo "2. Configurar DNS: echo 'nameserver 8.8.8.8' >> /etc/resolv.conf"
  echo "3. Tentar: apt-get update --fix-missing"
  exit 1
fi
rm /etc/nginx/sites-enabled/default 2>/dev/null || true
EOF

    sleep 2

    # Configurar client_max_body_size
    sudo su - root <<EOF
mkdir -p /etc/nginx/conf.d
echo 'client_max_body_size 100M;' > /etc/nginx/conf.d/${empresa}.conf
EOF

    sleep 2

    # Reiniciar Nginx
    sudo su - root <<EOF
if ! service nginx restart; then
  systemctl start nginx || systemctl restart nginx
fi
EOF

    sleep 2

    # Instalar snapd e certbot
    printf "${WHITE} >> Instalando Certbot...\n"
    sudo su - root <<EOF
if ! command -v snap &> /dev/null; then
  apt install -y snapd || {
    echo "Erro ao instalar snapd"
    exit 1
  }
  snap install core
  snap refresh core
fi

# Remover certbot antigo se existir
apt-get remove certbot -y 2>/dev/null || true

# Instalar certbot via snap
if ! snap install --classic certbot; then
  echo "Erro ao instalar Certbot via snap"
  exit 1
fi

# Criar link simbólico se não existir
if [ ! -f /usr/bin/certbot ]; then
  ln -s /snap/bin/certbot /usr/bin/certbot
fi
EOF

    sleep 2
    
    printf "${GREEN} >> Nginx e Certbot instalados com sucesso!${WHITE}\n"
  } || trata_erro "instala_nginx_base"
}

# Instala Traefik
instala_traefik_base() {
  useradd --system --shell /bin/false --user-group --no-create-home traefik
  cd /tmp
  mkdir traefik
  cd traefik/
  if [ "${ARCH}" = "x86_64" ]; then
    traefik_arch="amd64"
  elif [ "${ARCH}" = "aarch64" ]; then
    traefik_arch="arm64"
  else
    echo "Arquitetura não suportada: ${ARCH}"
    exit 1
  fi
  traefik_url="https://github.com/traefik/traefik/releases/download/v2.10.5/traefik_v2.10.5_linux_${traefik_arch}.tar.gz"
  curl --remote-name --location "${traefik_url}"
  tar -zxf traefik_v2.10.5_linux_${traefik_arch}.tar.gz
  cp traefik /usr/local/bin/traefik
  chmod a+x /usr/local/bin/traefik
  cd ..
  rm -rf traefik
  mkdir --parents /etc/traefik
  mkdir --parents /etc/traefik/conf.d

  sleep 2

  sudo su - root <<EOF
cat > /etc/traefik/traefik.toml << 'END'
################################################################
# Global configuration
################################################################
[global]
  checkNewVersion = "false"
  sendAnonymousUsage = "true"

################################################################
# Entrypoints configuration
################################################################
[entryPoints]
  [entryPoints.websecure]
    address = ":443"
  [entryPoints.web]
    address = ":80"

################################################################
# CertificatesResolvers configuration for Let's Encrypt
################################################################
[certificatesResolvers.letsencryptresolver.acme]
  email = "${email_deploy}"
  storage = "/etc/traefik/acme.json"
  [certificatesResolvers.letsencryptresolver.acme.httpChallenge]
    # Define the entrypoint which will receive the HTTP challenge
    entryPoint = "web"

################################################################
# Log configuration
################################################################
[log]
  level = "INFO"
  format = "json"
  filePath = "/var/log/traefik/traefik.log"

################################################################
# Access Log configuration
################################################################
[accessLog]
  filePath = "/var/log/traefik/access.log"
  format = "common"

################################################################
# API and Dashboard configuration
################################################################
[api]
  dashboard = false
  insecure = false
  # [entryPoints.dashboard]
  #   address = ":9090"

################################################################
# Providers configuration
################################################################
# Since the original setup was intended for Docker and this setup is for systemd,
# we don't use Docker provider settings but we keep file provider.
[providers]
  [providers.file]
    directory = "/etc/traefik/conf.d/"
    watch = "true"
END
EOF

  sleep 2

  sudo su - root <<EOF
cat > /etc/traefik/traefik.service << 'END'
# Systemd Traefik service
[Unit]
Description=Traefik - Proxy
Documentation=https://docs.traefik.io
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service
AssertFileIsExecutable=/usr/local/bin/traefik
AssertPathExists=/etc/traefik/traefik.toml
#RequiresMountsFor=/var/log

[Service]
User=traefik
AmbientCapabilities=CAP_NET_BIND_SERVICE
Type=notify
ExecStart=/usr/local/bin/traefik --configFile=/etc/traefik/traefik.toml
Restart=always
WatchdogSec=2s

LogsDirectory=traefik

[Install]
WantedBy=multi-user.target
END
EOF

  sleep 2

  sudo su - root <<EOF
cat > /etc/traefik/conf.d/tls.toml << 'END'
[tls.options]
  [tls.options.default]
    sniStrict = true
    minVersion = "VersionTLS12"
END
EOF
  sleep 2

  cp /etc/traefik/traefik.service /etc/systemd/system/
  chown -R traefik:traefik /etc/traefik/
  rm -rf /etc/traefik/traefik.service
  systemctl daemon-reload
  sleep 2
  systemctl enable --now traefik.service
  sleep 2
}

# Cria banco de dados
cria_banco_base() {
  banner
  printf "${WHITE} >> Criando Banco Postgres...\n"
  echo
  {
    sudo su - postgres <<EOF
    createdb ${empresa};
    psql
    CREATE USER ${empresa} SUPERUSER INHERIT CREATEDB CREATEROLE;
    ALTER USER ${empresa} PASSWORD '${senha_deploy}';
    \q
    exit
EOF

    sleep 2
  } || trata_erro "cria_banco_base"
}

# Instala Git
instala_git_base() {
  banner
  printf "${WHITE} >> Instalando o GIT...\n"
  echo
  {
    sudo su - root <<EOF
  apt install -y git
  apt -y autoremove
EOF
    sleep 2
  } || trata_erro "instala_git_base"
}

# True se a URL for HTTPS github.com (qualquer owner/repo — ultrawhats, multiflow-pro, etc.).
mf_repo_https_github() {
  echo "${1:-${repo_url:-}}" | grep -Eqi '^https://([^/@]+@)?github\.com/'
}

# Repos conhecidos OU package.json com TOKEN_GITHUB / Hineken (Baileys privado).
mf_repo_usa_token_baileys() {
  local repo="${1:-${repo_url:-}}"
  local emp="${2:-${empresa:-}}"
  echo "$repo" | grep -Eq "scriptswhitelabel/(multiflow-pro|ultrawhats)" && return 0
  local pkg="/home/deploy/${emp}/backend/package.json"
  [ -f "$pkg" ] || return 1
  grep -qE 'TOKEN_GITHUB|scriptswhitelabel/Hineken' "$pkg" 2>/dev/null
}

# Substitui TOKEN_GITHUB no backend/package.json (baileys/Hineken) pelo token da instalação.
# Não depende de um único repo: aplica se o package.json pedir o placeholder.
aplicar_token_baileys_package_json() {
  local emp="${1:-$empresa}"
  local tok="${2:-$github_token}"
  local repo="${3:-$repo_url}"
  local pkg="/home/deploy/${emp}/backend/package.json"
  [ ! -f "$pkg" ] && return 0
  if ! grep -qE 'TOKEN_GITHUB|scriptswhitelabel/Hineken' "$pkg" 2>/dev/null; then
    mf_repo_usa_token_baileys "$repo" "$emp" || return 0
    return 0
  fi
  [ -z "$tok" ] && return 1
  if grep -q "TOKEN_GITHUB" "$pkg" 2>/dev/null; then
    local tok_sed="${tok//&/\\&}"
    sed -i "s|TOKEN_GITHUB|${tok_sed}|g" "$pkg"
    printf "${GREEN} >> Token do GitHub aplicado no package.json (baileys/Hineken).${WHITE}\n"
  fi
  mf_baileys_fixar_branch_main_package_json "$pkg"
  printf "${GREEN} >> Baileys/Hineken fixado na branch main no package.json.${WHITE}\n"
  return 0
}

# Função para codificar URL de clone
codifica_clone_base() {
  local length="${#1}"
  for ((i = 0; i < length; i++)); do
    local c="${1:i:1}"
    case $c in
    [a-zA-Z0-9.~_-]) printf "$c" ;;
    *) printf '%%%02X' "'$c" ;;
    esac
  done
}

# Testa se o token tem acesso ao repositório (git ls-remote ou git clone).
# Usa só o token na URL; não pede senha (GIT_TERMINAL_PROMPT=0).
# $1 = token; $2 = "1" para guardar stderr em ERRO_GIT_VALIDACAO; $3 = URL do repo (opcional; default repo_url).
validar_token_git_clone() {
  local token="${1:-$github_token}"
  local mostrar_erro="${2:-0}"
  local repo_alvo="${3:-${repo_url:-}}"
  token=$(printf '%s' "${token}" | tr -d '\r\n ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -z "$token" ] && return 1
  local url_base
  url_base=$(echo "${repo_alvo}" | sed 's|^https://||' | sed 's|^http://||' | sed 's|^[^@]*@||')
  url_base="${url_base%/}"
  [ -z "$url_base" ] && return 1
  [[ "$url_base" != *.git ]] && url_base="${url_base}.git"
  local token_encoded
  token_encoded=$(codifica_clone_base "$token")
  local repo_url_com_token
  if echo "$url_base" | grep -Eqi 'github\.com'; then
    repo_url_com_token="https://x-access-token:${token_encoded}@${url_base}"
  else
    repo_url_com_token="https://${token_encoded}@${url_base}"
  fi
  export GIT_TERMINAL_PROMPT=0

  # 1) Tentar git ls-remote (leve, só testa acesso)
  local err_file
  err_file=$(mktemp)
  if git ls-remote --exit-code "${repo_url_com_token}" HEAD >/dev/null 2>"$err_file"; then
    rm -f "$err_file"
    unset GIT_TERMINAL_PROMPT 2>/dev/null || true
    return 0
  fi

  # 2) Fallback: git clone (mesmo teste usado no pull)
  local test_dir
  test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/test_clone_$(date +%s)"
  if git clone --depth 1 "${repo_url_com_token}" "${test_dir}" >/dev/null 2>>"$err_file"; then
    rm -rf "${test_dir}" >/dev/null 2>&1
    rm -f "$err_file"
    unset GIT_TERMINAL_PROMPT 2>/dev/null || true
    return 0
  fi
  rm -rf "${test_dir}" >/dev/null 2>&1

  [ "$mostrar_erro" = "1" ] && ERRO_GIT_VALIDACAO=$(head -3 "$err_file" 2>/dev/null | tr '\n' ' ')
  rm -f "$err_file"
  unset GIT_TERMINAL_PROMPT 2>/dev/null || true
  return 1
}

# Valida token antes da atualização; se expirado, pede novo, valida e atualiza .git/config + arquivo de variáveis.
# Usa o remote origin da pasta da instância (preferencial) ou repo_url — funciona com qualquer repo HTTPS GitHub.
validar_e_atualizar_token_antes_atualizar() {
  # Garantir que temos repo_url e github_token da instância selecionada
  if [ -n "${ARQUIVO_VARIAVEIS_USADO:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_USADO}" ]; then
    mf_carregar_config "${ARQUIVO_VARIAVEIS_USADO}" 2>/dev/null
  fi

  local app_root="/home/deploy/${empresa:-}"
  local origin_publico=""
  if [ -n "${empresa:-}" ] && [ -d "${app_root}/.git" ]; then
    origin_publico=$(git -c "safe.directory=${app_root}" -C "${app_root}" remote get-url origin 2>/dev/null \
      | sed -E 's#^(https?://)[^/@]+@#\1#' || true)
    if [ -n "$origin_publico" ] && [ -z "${repo_url:-}" ]; then
      repo_url="$origin_publico"
    fi
  fi

  local repo_validacao="${origin_publico:-${repo_url:-}}"
  if [ -z "${repo_validacao}" ] || [ -z "${github_token}" ]; then
    printf "${RED} >> ERRO: repo_url/origin ou github_token não encontrados no arquivo da instância.${WHITE}\n"
    return 1
  fi

  # Validação silenciosa com o token já gravado; só pede token se falhar
  if validar_token_git_clone "${github_token}" 0 "${repo_validacao}"; then
    # Reaplica token no origin atual (preserva o path do remote)
    if [ -n "${github_token:-}" ] && [ -d "${app_root}/.git" ]; then
      INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      # shellcheck source=/dev/null
      [ -f "${INSTALADOR_DIR}/tools/git_sincronizar_repositorio.sh" ] && . "${INSTALADOR_DIR}/tools/git_sincronizar_repositorio.sh"
      if type mf_git_aplicar_token_remote >/dev/null 2>&1; then
        mf_git_aplicar_token_remote "${app_root}" "${github_token}" >/dev/null 2>&1 || true
      fi
    fi
    return 0
  fi

  banner
  printf "${RED} >> O Token não está válido (expirado ou sem acesso).${WHITE}\n"
  echo
  printf "${WHITE} >> Repositório alvo (origin / variável de instalação):${WHITE}\n"
  printf "${BLUE}   %s${WHITE}\n" "${repo_validacao}"
  echo
  printf "${YELLOW} >> Deseja manter este repositório (s) ou digitar um novo link?${WHITE}\n"
  printf "${YELLOW}   Digite ${GREEN}s${YELLOW} para manter, ou cole o novo link do Git:${WHITE}\n"
  echo
  read -r -p "> " resposta_repo
  resposta_repo=$(printf '%s' "$resposta_repo" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\r')
  if [ -n "$resposta_repo" ] && [ "$resposta_repo" != "s" ] && [ "$resposta_repo" != "S" ]; then
    novo_repo="$resposta_repo"
    [[ "$novo_repo" != *.git ]] && [[ "$novo_repo" =~ github\.com ]] && novo_repo="${novo_repo}.git"
    repo_url="$novo_repo"
    repo_validacao="$novo_repo"
    printf "${GREEN} >> Repositório atualizado para: ${repo_url}${WHITE}\n"
    if [ -n "${ARQUIVO_VARIAVEIS_USADO:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_USADO}" ]; then
      if grep -q "^repo_url=" "$ARQUIVO_VARIAVEIS_USADO"; then
        novo_repo_sed="${novo_repo//&/\\&}"
        sed -i "s|^repo_url=.*|repo_url=${novo_repo_sed}|" "$ARQUIVO_VARIAVEIS_USADO"
      else
        echo "repo_url=${novo_repo}" >> "$ARQUIVO_VARIAVEIS_USADO"
      fi
      printf "${GREEN} >> Link do repositório salvo na variável de instalação.${WHITE}\n"
    fi
    echo
  else
    repo_url="${repo_validacao}"
  fi
  echo
  printf "${RED} >> Token inválido. Cole um novo GitHub PAT:${WHITE}\n"
  echo
  read -r -p "> " novo_token
  novo_token=$(printf '%s' "$novo_token" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\r\n')
  if [ -z "$novo_token" ]; then
    printf "${RED} >> Token não informado. Atualização cancelada.${WHITE}\n"
    sleep 2
    return 1
  fi

  printf "${WHITE} >> Validando token e repositório...\n"
  echo
  ERRO_GIT_VALIDACAO=""
  if ! validar_token_git_clone "$novo_token" 1 "${repo_validacao}"; then
    printf "${RED} >> O novo token não foi aceito. Atualização cancelada.${WHITE}\n"
    if [ -n "${ERRO_GIT_VALIDACAO:-}" ]; then
      printf "${YELLOW} >> Detalhe do Git: ${ERRO_GIT_VALIDACAO}${WHITE}\n"
    fi
    printf "${YELLOW} >> Confira: token correto, repositório ${repo_validacao:-?} e permissão 'repo'.${WHITE}\n"
    sleep 2
    return 1
  fi

  printf "${GREEN} >> Token e repositório validados. Atualizando configuração...${WHITE}\n"
  echo

  local git_config="/home/deploy/${empresa}/.git/config"
  if [ ! -f "$git_config" ]; then
    printf "${RED} >> ERRO: Arquivo não encontrado: ${git_config}${WHITE}\n"
    return 1
  fi

  cp "$git_config" "${git_config}.backup.$(date +%Y%m%d_%H%M%S)"
  local path_repo
  path_repo=$(echo "$repo_validacao" | sed 's|^https://||' | sed 's|^http://||' | sed 's|^[^@]*@||')
  path_repo="${path_repo%/}"
  [[ "$path_repo" != *.git ]] && path_repo="${path_repo}.git"
  local novo_token_encoded
  novo_token_encoded=$(codifica_clone_base "$novo_token")
  local nova_url
  if echo "$path_repo" | grep -Eqi 'github\.com'; then
    nova_url="https://x-access-token:${novo_token_encoded}@${path_repo}"
  else
    nova_url="https://${novo_token_encoded}@${path_repo}"
  fi
  local nova_url_sed="${nova_url//&/\\&}"
  sed -i "s|^[[:space:]]*url[[:space:]]*=.*|  url = ${nova_url_sed}|" "$git_config"
  printf "${GREEN} >> Token e URL atualizados em: ${git_config}${WHITE}\n"

  if [ -n "${ARQUIVO_VARIAVEIS_USADO:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_USADO}" ]; then
    if grep -q "^github_token=" "$ARQUIVO_VARIAVEIS_USADO"; then
      novo_token_sed="${novo_token//&/\\&}"
      sed -i "s|^github_token=.*|github_token=${novo_token_sed}|" "$ARQUIVO_VARIAVEIS_USADO"
    else
      echo "github_token=${novo_token}" >> "$ARQUIVO_VARIAVEIS_USADO"
    fi
    if grep -q "^repo_url=" "$ARQUIVO_VARIAVEIS_USADO"; then
      repo_sed="${repo_validacao//&/\\&}"
      sed -i "s|^repo_url=.*|repo_url=${repo_sed}|" "$ARQUIVO_VARIAVEIS_USADO"
    else
      echo "repo_url=${repo_validacao}" >> "$ARQUIVO_VARIAVEIS_USADO"
    fi
    printf "${GREEN} >> Token atualizado no arquivo de variáveis da instância.${WHITE}\n"
  fi

  github_token="$novo_token"
  repo_url="${repo_validacao}"
  echo
  sleep 2
  return 0
}

# Definir versões disponíveis para instalação/atualização (lista em tools/versoes_multiflow_pro.conf)
definir_versoes_instalacao() {
  local _mf_loader
  _mf_loader="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tools/carregar_versoes_multiflow_pro.sh"
  # shellcheck source=/dev/null
  source "$_mf_loader" || true
  if ! mf_carregar_versoes_no_array "VERSOES_INSTALACAO"; then
    printf "${RED} >> ERRO: não foi possível carregar versões. Verifique tools/versoes_multiflow_pro.conf (formato: versao|commit).${WHITE}\n"
    exit 1
  fi
}

# Mostrar lista de versões disponíveis para instalação
mostrar_lista_versoes_instalacao() {
  printf "${WHITE}═══════════════════════════════════════════════════════════\n"
  printf "  VERSÕES DISPONÍVEIS %s\n" "${TITULO_LISTA_VERSOES:-PARA INSTALAÇÃO}"
  printf "═══════════════════════════════════════════════════════════\n${WHITE}"
  echo
  
  printf "${BLUE}  [0]${WHITE} Mais Recente ${YELLOW}${MF_AVISO_OPCAO_MAIS_RECENTE}${WHITE}\n"
  printf "      Instala a versão mais recente disponível no repositório\n"
  echo
  
  local index=1
  for versao in $(printf '%s\n' "${!VERSOES_INSTALACAO[@]}" | sort -V -r); do
    printf "${BLUE}  [$index]${WHITE} "
    mf_exibir_rotulo_versao_menu "$versao" "VERSOES_INSTALACAO"
    printf "Versão ${GREEN}${versao}${WHITE}\n"
    printf "      Commit: ${YELLOW}${VERSOES_INSTALACAO[$versao]}${WHITE}\n"
    echo
    ((index++))
  done
  
  printf "${WHITE}═══════════════════════════════════════════════════════════\n${WHITE}"
  echo
}

# Selecionar versão para instalação
selecionar_versao_instalacao() {
  banner
  printf "${WHITE} >> Selecionando versão para instalação...\n"
  echo
  
  # Definir versões disponíveis
  definir_versoes_instalacao
  
  # Mostrar lista de versões
  mostrar_lista_versoes_instalacao
  
  local versoes_array=($(printf '%s\n' "${!VERSOES_INSTALACAO[@]}" | sort -V -r))
  local total_versoes=${#versoes_array[@]}
  
  if [ $total_versoes -eq 0 ]; then
    printf "${RED} >> ERRO: Nenhuma versão disponível na lista.\n${WHITE}"
    exit 1
  fi
  
  printf "${YELLOW} >> Selecione a versão desejada (0-${total_versoes}):${WHITE}\n"
  read -p "> " ESCOLHA
  
  # Validar entrada
  if ! [[ "$ESCOLHA" =~ ^[0-9]+$ ]]; then
    printf "${RED} >> ERRO: Entrada inválida. Digite um número.\n${WHITE}"
    exit 1
  fi
  
  if [ "$ESCOLHA" -lt 0 ] || [ "$ESCOLHA" -gt $total_versoes ]; then
    printf "${RED} >> ERRO: Opção inválida. Escolha um número entre 0 e ${total_versoes}.\n${WHITE}"
    exit 1
  fi
  
  # Tratar opção 0 - Mais Recente
  if [ "$ESCOLHA" -eq 0 ]; then
    declare -g versao_instalacao="Mais_Recente"
    declare -g commit_instalacao=""
    printf "\n${GREEN} >> Versão selecionada: ${BLUE}Mais Recente${WHITE} ${YELLOW}${MF_AVISO_OPCAO_MAIS_RECENTE}${WHITE}\n"
    printf "${GREEN} >> Será instalada a versão mais recente disponível no repositório${WHITE}\n"
    # Usar "Mais_Recente" internamente para evitar problemas com espaços no source
    echo
    sleep 2
  else
    # Obter versão e commit selecionados (variáveis globais)
    local index=$((ESCOLHA - 1))
    declare -g versao_instalacao="${versoes_array[$index]}"
    declare -g commit_instalacao="${VERSOES_INSTALACAO[$versao_instalacao]}"
    
    printf "\n${GREEN} >> Versão selecionada: ${BLUE}${versao_instalacao}${WHITE}\n"
    printf "${GREEN} >> Commit: ${BLUE}${commit_instalacao}${WHITE}\n"
    echo
    sleep 2
  fi
}

# Selecionar versão para atualização (mesma lista da instalação / rollback; só multiflow-pro)
selecionar_versao_atualizacao() {
  banner
  printf "${WHITE} >> Selecionando versão para atualização...\n"
  echo

  INSTALADOR_DIR="${INSTALADOR_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
  # shellcheck source=/dev/null
  source "${INSTALADOR_DIR}/tools/carregar_versoes_multiflow_pro.sh" 2>/dev/null || true

  if ! mf_repo_usa_menu_versoes "${repo_url:-}" "${empresa:-}"; then
    selecionar_canal_branch_amanda "a atualização"
    declare -g versao_atualizacao="${BRANCH_AMANDA_ESCOLHIDA:-Mais_Recente}"
    declare -g commit_atualizacao=""
    printf "${GREEN} >> Canal selecionado para atualização: ${BLUE}%s${WHITE}\n" "${BRANCH_AMANDA_ESCOLHIDA:-davi-alteracoes}"
    echo
    sleep 1
    return 0
  fi

  definir_versoes_instalacao
  TITULO_LISTA_VERSOES="PARA ATUALIZAÇÃO"
  mostrar_lista_versoes_instalacao
  unset TITULO_LISTA_VERSOES

  local versoes_array=($(printf '%s\n' "${!VERSOES_INSTALACAO[@]}" | sort -V -r))
  local total_versoes=${#versoes_array[@]}

  if [ $total_versoes -eq 0 ]; then
    printf "${RED} >> ERRO: Nenhuma versão disponível na lista.\n${WHITE}"
    sleep 2
    return 1
  fi

  printf "${YELLOW} >> Selecione a versão desejada (0-${total_versoes}):${WHITE}\n"
  read -p "> " ESCOLHA_ATUALIZACAO

  if ! [[ "$ESCOLHA_ATUALIZACAO" =~ ^[0-9]+$ ]]; then
    printf "${RED} >> ERRO: Entrada inválida. Digite um número.\n${WHITE}"
    sleep 2
    return 1
  fi

  if [ "$ESCOLHA_ATUALIZACAO" -lt 0 ] || [ "$ESCOLHA_ATUALIZACAO" -gt $total_versoes ]; then
    printf "${RED} >> ERRO: Opção inválida. Escolha um número entre 0 e ${total_versoes}.\n${WHITE}"
    sleep 2
    return 1
  fi

  if [ "$ESCOLHA_ATUALIZACAO" -eq 0 ]; then
    declare -g versao_atualizacao="Mais_Recente"
    declare -g commit_atualizacao=""
    printf "\n${GREEN} >> Versão selecionada: ${BLUE}Mais Recente${WHITE} ${YELLOW}${MF_AVISO_OPCAO_MAIS_RECENTE}${WHITE}\n"
    printf "${GREEN} >> Será usada a última revisão da branch main (ou padrão do repositório)${WHITE}\n"
  else
    local index=$((ESCOLHA_ATUALIZACAO - 1))
    declare -g versao_atualizacao="${versoes_array[$index]}"
    declare -g commit_atualizacao="${VERSOES_INSTALACAO[$versao_atualizacao]}"
    printf "\n${GREEN} >> Versão selecionada: ${BLUE}${versao_atualizacao}${WHITE}\n"
    printf "${GREEN} >> Commit: ${BLUE}${commit_atualizacao}${WHITE}\n"
  fi
  echo
  sleep 2
  return 0
}

# Clona código de repo privado
baixa_codigo_base() {
  mf_validar_repositorio_amanda "${repo_url:-}" || return 1
  banner
  printf "${WHITE} >> Fazendo download do ${nome_titulo}...\n"
  echo
  {
    if [ -z "${repo_url}" ]; then
      printf "${WHITE} >> Erro: URL do repositório não definida.\n"
      exit 1
    fi

    local repo_alvo="${repo_url%/}"
    [[ "$repo_alvo" != *.git ]] && repo_alvo="${repo_alvo}.git"
    local repo_limpo
    repo_limpo=$(echo "${repo_alvo}" | sed -E 's#^(https?://)[^/@]+@#\1#')

    if [ -n "${github_token}" ]; then
      github_token_encoded=$(codifica_clone_base "${github_token}")
      local url_sem_https="${repo_limpo#https://}"
      if echo "${url_sem_https}" | grep -Eqi 'github\.com'; then
        github_url="https://x-access-token:${github_token_encoded}@${url_sem_https}"
      else
        github_url="https://${github_token_encoded}@${url_sem_https}"
      fi
    else
      github_url="${repo_limpo}"
    fi

    dest_dir="/home/deploy/${empresa}/"

    if [ -d "${dest_dir}/.git" ]; then
      printf "${GREEN} >> Repositório já presente em ${dest_dir}. Sincronizando alterações...${WHITE}\n"
      cd "${dest_dir}" && GIT_TERMINAL_PROMPT=0 git fetch --all --prune 2>/dev/null || true
      git checkout -f 2>/dev/null || true
      git reset --hard 2>/dev/null || true
      git clean -fd 2>/dev/null || true
    else
      if [ -d "${dest_dir}" ] && [ -n "$(ls -A "${dest_dir}" 2>/dev/null)" ]; then
        printf "${YELLOW} >> Diretório ${dest_dir} existente sem repositório Git. Limpando para clone novo...${WHITE}\n"
        rm -rf "${dest_dir}"
      fi
      mkdir -p "${dest_dir}"
      GIT_TERMINAL_PROMPT=0 git clone -b davi-alteracoes "${github_url}" "${dest_dir}" 2>/dev/null || GIT_TERMINAL_PROMPT=0 git clone "${github_url}" "${dest_dir}"
      if [ $? -ne 0 ]; then
        echo
        printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
        printf "${RED}❌ ERRO: Falha ao baixar o código do repositório!${WHITE}\n"
        printf "${YELLOW}   Repositório: ${BLUE}${repo_limpo}${WHITE}\n"
        if [ -n "${github_token}" ]; then
          printf "${YELLOW}   O Token fornecido não possui permissão ou o repositório não existe.${WHITE}\n"
          printf "${YELLOW}   No GitHub, verifique se o Token tem permissão de LEITURA:${WHITE}\n"
          printf "${BLUE}   Repository permissions -> Contents -> Access: Read-only${WHITE}\n"
        else
          printf "${YELLOW}   O repositório é privado? Se for, informe o Token de Acesso Pessoal.${WHITE}\n"
        fi
        printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
        echo
        sleep 5
        exit 1
      fi
    fi

    # Verificar se foi selecionada a opção "Mais Recente"
    if [ -z "${commit_instalacao}" ] || [ "${versao_instalacao}" = "Mais_Recente" ] || [ "${versao_instalacao}" = "Mais Recente" ]; then
      banner
      printf "${WHITE} >> Instalando versão mais recente disponível no repositório...\n"
      echo
      
      cd ${dest_dir} || trata_erro "cd para diretório do projeto"
      
      # Fazer checkout para a branch principal (prioridade: davi-alteracoes > davi-alteraçoes > main > master)
      chown -R deploy:deploy "$dest_dir" || return 1
      if ! sudo -u deploy bash -s -- "$dest_dir" "${BRANCH_AMANDA_ESCOLHIDA:-}" <<'CHECKOUTRECENT'
set -e
cd -- "$1"
git fetch --all --prune
target_br="$2"
if [ -z "$target_br" ]; then
  target_br=$(git symbolic-ref --quiet --short HEAD) || exit 1
fi
git check-ref-format --branch "$target_br" >/dev/null
git show-ref --verify --quiet "refs/remotes/origin/$target_br" || {
  printf 'Branch remota não encontrada: %s\n' "$target_br" >&2
  exit 1
}
git checkout -B "$target_br" "origin/$target_br"
git reset --hard "origin/$target_br"
CHECKOUTRECENT
      then
        printf '%s\n' 'Falha ao selecionar a versão solicitada.' >&2
        return 1
      fi
      
      printf "${GREEN} >> Versão mais recente do repositório será instalada${WHITE}\n"
      echo
      sleep 2
    # Fazer checkout do commit específico se foi selecionado
    elif [ -n "${commit_instalacao}" ]; then
      banner
      printf "${WHITE} >> Fazendo checkout para o commit da versão ${versao_instalacao}...\n"
      echo
      
      cd ${dest_dir} || trata_erro "cd para diretório do projeto"
      
      # Corrigir permissões antes do checkout
      chown -R deploy:deploy ${dest_dir} 2>/dev/null || true
      chmod -R 755 ${dest_dir}/.git 2>/dev/null || true
      
      # Fazer fetch para garantir que temos todos os commits
      sudo su - deploy <<FETCHCOMMIT
cd ${dest_dir}
git fetch --all --prune 2>/dev/null || true
FETCHCOMMIT
      
      # Verificar se o commit existe
      sudo su - deploy <<VERIFYCOMMIT
cd ${dest_dir}
if git cat-file -e "${commit_instalacao}^{commit}" 2>/dev/null; then
  exit 0
else
  exit 1
fi
VERIFYCOMMIT
      
      if [ $? -eq 0 ]; then
        # Criar branch temporária para o commit
        BRANCH_INSTALACAO="instalacao-${versao_instalacao}-$(date +%Y%m%d-%H%M%S)"
        sudo su - deploy <<CHECKOUTCOMMIT
cd ${dest_dir}
git checkout -b "${BRANCH_INSTALACAO}" "${commit_instalacao}"
CHECKOUTCOMMIT
        
        if [ $? -eq 0 ]; then
          printf "${GREEN} >> Checkout para commit ${commit_instalacao} concluído com sucesso!${WHITE}\n"
          printf "${GREEN} >> Branch criada: ${BRANCH_INSTALACAO}${WHITE}\n"
          echo
        else
          printf "${RED} >> ERRO: Falha ao fazer checkout do commit ${commit_instalacao}${WHITE}\n"
          exit 1
        fi
      else
        printf "${RED} >> ERRO: Commit ${commit_instalacao} não encontrado no repositório.${WHITE}\n"
        printf "${YELLOW} >> Verifique se o commit hash está correto.${WHITE}\n"
        exit 1
      fi
    fi

    # Compatibilidade com a estrutura de diretórios AMANDA
    if [ -d "${dest_dir}/amanda/backend" ] && [ ! -d "${dest_dir}/backend" ]; then
      printf "${GREEN} >> Estrutura com pasta amanda/ detectada. Criando links de compatibilidade...${WHITE}\n"
      ln -sfn "${dest_dir}/amanda/backend" "${dest_dir}/backend"
      ln -sfn "${dest_dir}/amanda/frontend" "${dest_dir}/frontend"
      [ -d "${dest_dir}/amanda/wuzapi" ] && ln -sfn "${dest_dir}/amanda/wuzapi" "${dest_dir}/wuzapi"
      [ -d "${dest_dir}/amanda/goflow_dispatcher" ] && ln -sfn "${dest_dir}/amanda/goflow_dispatcher" "${dest_dir}/goflow_dispatcher"
      [ -d "${dest_dir}/amanda/api_transcricao" ] && ln -sfn "${dest_dir}/amanda/api_transcricao" "${dest_dir}/api_transcricao"
    fi

    mkdir -p /home/deploy/${empresa}/backend/public/
    chown deploy:deploy -R /home/deploy/${empresa}/
    chmod 775 -R /home/deploy/${empresa}/backend/public/
    sleep 2
  } || trata_erro "baixa_codigo_base"
}

# Instala e configura backend
instala_backend_base() {
  banner
  printf "${WHITE} >> Configurando variáveis de ambiente do ${BLUE}backend${WHITE}...\n"
  echo
  
  # Verifica se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    printf "${YELLOW} >> Carregando variáveis salvas...\n${WHITE}"
    carregar_variaveis
    if [ -z "${empresa}" ]; then
      printf "${RED} >> ERRO: Não foi possível carregar a variável 'empresa'. Abortando.\n${WHITE}"
      exit 1
    fi
  fi
  
  # Verifica se o diretório do código existe
  if [ ! -d "/home/deploy/${empresa}" ]; then
    printf "${RED} >> ERRO: Diretório /home/deploy/${empresa} não existe!\n${WHITE}"
    printf "${YELLOW} >> O código precisa ser clonado primeiro. Verifique a etapa anterior.\n${WHITE}"
    exit 1
  fi
  
  {
    sleep 2
    subdominio_backend=$(echo "${subdominio_backend/https:\/\//}")
    subdominio_backend=${subdominio_backend%%/*}
    subdominio_backend=https://${subdominio_backend}
    subdominio_frontend=$(echo "${subdominio_frontend/https:\/\//}")
    subdominio_frontend=${subdominio_frontend%%/*}
    subdominio_frontend=https://${subdominio_frontend}
    # subdominio_perfex=$(echo "${subdominio_perfex/https:\/\//}")
    # subdominio_perfex=${subdominio_perfex%%/*}
    # subdominio_perfex=https://${subdominio_perfex}
    if [ "${ALTA_PERFORMANCE}" = "1" ]; then
      db_host_instalador="127.0.0.1"
      db_port_instalador="6732"
      redis_uri_instalador="redis://127.0.0.1:1569"
    else
      db_host_instalador="localhost"
      db_port_instalador="5432"
      redis_uri_instalador="redis://:${senha_deploy}@127.0.0.1:6379"
    fi
    # ACK usa a mesma URI do Redis que REDIS_URI (em Alta Performance: redis://127.0.0.1:1569)
    redis_uri_ack_comentado="# REDIS_URI_ACK=${redis_uri_instalador}"
    sudo su - deploy <<EOF
  cat <<[-]EOF > /home/deploy/${empresa}/backend/.env
# Scripts WhiteLabel - All Rights Reserved - (18) 9 8802-9627
NODE_ENV=
BACKEND_URL=${subdominio_backend}
FRONTEND_URL=${subdominio_frontend}
PROXY_PORT=443
PORT=${backend_port}

# CREDENCIAIS BD
DB_HOST=${db_host_instalador}
DB_DIALECT=postgres
DB_PORT=${db_port_instalador}
DB_USER=${empresa}
DB_PASS=${senha_deploy}
DB_NAME=${empresa}

# DADOS REDIS
REDIS_URI=${redis_uri_instalador}
REDIS_OPT_LIMITER_MAX=10
REDIS_OPT_LIMITER_DURATION=1000
# Throughput filas de mensagem Baileys (-handleMessage) e WhatsMeow (-handleWuzapiMessage)
HANDLE_MESSAGE_QUEUE_CONCURRENCY=4
HANDLE_MESSAGE_LIMITER_MAX=15
HANDLE_MESSAGE_LIMITER_DURATION=1000
${redis_uri_ack_comentado}
# BULL_BOARD=true
# BULL_USER=${email_deploy}
# BULL_PASS=${senha_deploy}

# --- RabbitMQ ---
RABBITMQ_HOST=localhost
RABBITMQ_PORT=5672
RABBIT_USER=${empresa}
RABBIT_PASS=${senha_deploy}
RABBITMQ_URI=amqp://\${empresa}:\${senha_deploy}@localhost:5672/

TIMEOUT_TO_IMPORT_MESSAGE=1000

# SECRETS
JWT_SECRET=${jwt_secret}
JWT_REFRESH_SECRET=${jwt_refresh_secret}
MASTER_KEY=${senha_master}

# PERFEX_URL=${subdominio_perfex}
# PERFEX_MODULE=Multi100
VERIFY_TOKEN=whaticket
FACEBOOK_APP_ID=${facebook_app_id}
FACEBOOK_APP_SECRET=${facebook_app_secret}

#METODOS DE PAGAMENTO

STRIPE_PRIVATE=
STRIPE_OK_URL=BACKEND_URL/subscription/stripewebhook
STRIPE_CANCEL_URL=FRONTEND_URL/financeiro

# MERCADO PAGO

MPACCESSTOKEN=SEU TOKEN
MPNOTIFICATIONURL=https://SUB_DOMINIO_API/subscription/mercadopagowebhook

MP_ACCESS_TOKEN=SEU TOKEN
MP_NOTIFICATION_URL=https://SUB_DOMINIO_API/subscription/mercadopagowebhook

ASAAS_TOKEN=SEU TOKEN
MP_NOTIFICATION_URL=https://SUB_DOMINIO_API/subscription/asaaswebhook

MPNOTIFICATION_URL=https://SUB_DOMINIO_API/subscription/asaaswebhook
ASAASTOKEN=SEU TOKEN

GERENCIANET_SANDBOX=
GERENCIANET_CLIENT_ID=
GERENCIANET_CLIENT_SECRET=
GERENCIANET_PIX_CERT=
GERENCIANET_PIX_KEY=

# EMAIL
MAIL_HOST="smtp.gmail.com"
MAIL_USER="SEUGMAIL@gmail.com"
MAIL_PASS="SENHA DE APP"
MAIL_FROM="Recuperação de Senha <SEU GMAIL@gmail.com>"
MAIL_PORT="465"

# WAVOIP
WAVOIP_URL=https://api.wavoip.com
WAVOIP_USERNAME='seuemaildowavoip@email.com.br'
WAVOIP_PASSWORD='SUASENHA'

# WhatsApp Oficial
USE_WHATSAPP_OFICIAL=true
# URL_API_OFICIAL=https://SubDominioDaOficial.SEUDOMINIO.com.br
TOKEN_API_OFICIAL="adminpro"
OFFICIAL_CAMPAIGN_CONCURRENCY=10  # Processa até 10 campanhas ao mesmo tempo

# API de Transcrição de Audio
TRANSCRIBE_URL=http://localhost:4002

# Buffer Size Configuration
MAX_BUFFER_SIZE_MB=200

# Opcional: fixa a versão do WhatsApp Web usada pelo Baileys. Se vazio, busca automaticamente.
WHATSAPP_WEB_VERSION=2.3000.1042896555

# DISABLE_PUSH_NOTIFICATIONS=0

# Cron diário de recálculo de uso de disco (23h). Padrão: ativo. Para desativar: DISABLE_DISK_USAGE_CRON=1
# DISABLE_DISK_USAGE_CRON=1

ENABLE_LID_DEBUG=true
FIX_LID_JOB_ENABLED=true
# Opcional: horário do job (padrão: 3h da manhã)
FIX_LID_JOB_CRON=0 3 * * *

# Log opcional: defina LOG_MESSAGE_UPSERT=true no ambiente para linhas [MSG-UPSERT] com wid, stub, renderable, upsertType.
# Produção: ative LOG_MESSAGE_UPSERT=true só enquanto analisar; depois desligue para não encher log.
LOG_MESSAGE_UPSERT=false

# [fix LID] envio LID-first p/ contatos migrados (default do codigo ja e true)
BAILEYS_OUTBOUND_LID_FIRST=false
BAILEYS_SESSION_RESET_ENABLED=false
BAILEYS_STUB400_AUTO_RETRY=true
BAILEYS_LOG_LEVEL=warn
[-]EOF
EOF

    descomentar_env_redis_bull_ack "/home/deploy/${empresa}/backend/.env" "/home/deploy/${empresa}/backend/package.json"

    sleep 2

    banner
    printf "${WHITE} >> Instalando dependências do ${BLUE}backend${WHITE}...\n"
    echo
    aplicar_token_baileys_package_json
    sudo su - deploy <<BACKENDINSTALL
  if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
    . /root/instalador_single_oficial/tools/path_node_deploy.sh
  else
  export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
  elif [ -d /usr/local/n/versions/node ]; then
    _mf_nv=\$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
    if [ -n "\$_mf_nv" ] && [ -d "/usr/local/n/versions/node/\$_mf_nv/bin" ]; then
      export PATH="/usr/local/n/versions/node/\$_mf_nv/bin:\$PATH"
    fi
  elif [ -f /usr/bin/node ]; then
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  else
    NODE_DIR=\$(find /usr -type d -name "node" -o -type f -name "node" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
    if [ -n "\$NODE_DIR" ]; then
      export PATH=\$NODE_DIR:/usr/bin:\$PATH
    fi
  fi
  fi
  
  # Verifica se node e npm estão disponíveis
  if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
    echo "ERRO: Node.js ou npm não encontrado. PATH atual: \$PATH"
    which node || echo "node não encontrado"
    which npm || echo "npm não encontrado"
    exit 1
  fi
  
  # Verifica se o diretório existe antes de tentar acessar
  BACKEND_DIR="/home/deploy/${empresa}/backend"
  if [ ! -d "\$BACKEND_DIR" ]; then
    echo "ERRO: Diretório do backend não existe: \$BACKEND_DIR"
    echo "Verificando diretórios disponíveis em /home/deploy/${empresa}/..."
    ls -la /home/deploy/${empresa}/ 2>/dev/null || echo "Diretório /home/deploy/${empresa}/ não existe"
    exit 1
  fi
  
  cd "\$BACKEND_DIR"
  
  # Verifica se package.json existe
  if [ ! -f "package.json" ]; then
    echo "ERRO: package.json não encontrado em \$BACKEND_DIR"
    echo "Conteúdo do diretório:"
    ls -la
    exit 1
  fi
  
  export PUPPETEER_SKIP_DOWNLOAD=true
  rm -rf node_modules 2>/dev/null || true
  rm -f package-lock.json 2>/dev/null || true
  npm install --force
  npm install puppeteer-core --force
  npm i glob
  npm run build
BACKENDINSTALL

    sleep 2

    sudo su - deploy <<FFMPEGFIX
  BACKEND_DIR="/home/deploy/${empresa}/backend"
  FFMPEG_FILE="\${BACKEND_DIR}/node_modules/@ffmpeg-installer/ffmpeg/index.js"
  
  # Verifica se o arquivo existe antes de tentar modificá-lo
  if [ -f "\$FFMPEG_FILE" ]; then
    sed -i 's|npm3Binary = .*|npm3Binary = "/usr/bin/ffmpeg";|' "\$FFMPEG_FILE"
  else
    echo "Aviso: Arquivo ffmpeg-installer não encontrado. Pulando modificação."
  fi
  
  # Cria o diretório e arquivo se necessário
  mkdir -p "\${BACKEND_DIR}/node_modules/@ffmpeg-installer/linux-x64/" 2>/dev/null || true
  if [ -d "\${BACKEND_DIR}/node_modules/@ffmpeg-installer/linux-x64/" ]; then
    echo '{ "version": "1.1.0", "name": "@ffmpeg-installer/linux-x64" }' > "\${BACKEND_DIR}/node_modules/@ffmpeg-installer/linux-x64/package.json"
  fi
FFMPEGFIX

    sleep 2

    banner
    printf "${WHITE} >> Executando db:migrate...\n"
    echo
    sudo su - deploy <<MIGRATEINSTALL
  # Configura PATH para Node.js
  if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
    . /root/instalador_single_oficial/tools/path_node_deploy.sh
  else
    export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
    if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
      export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
    elif [ -d /usr/local/n/versions/node ]; then
      _mf_nv=\$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
      if [ -n "\$_mf_nv" ] && [ -d "/usr/local/n/versions/node/\$_mf_nv/bin" ]; then
        export PATH="/usr/local/n/versions/node/\$_mf_nv/bin:\$PATH"
      fi
    fi
    if ! command -v npm >/dev/null 2>&1; then
      echo "ERRO: npm não encontrado no PATH do usuário deploy."
      echo "      Atualize o instalador em /root/instalador_single_oficial (inclua tools/path_node_deploy.sh) ou, como root: n 20.19.4"
      echo "      Verifique: ls /usr/local/n/versions/node/  e  sudo ls -la /usr/bin/npm"
      exit 1
    fi
  fi
  
  BACKEND_DIR="/home/deploy/${empresa}/backend"
  if [ ! -d "\$BACKEND_DIR" ]; then
    echo "ERRO: Diretório do backend não existe: \$BACKEND_DIR"
    exit 1
  fi
  
  cd "\$BACKEND_DIR"
  npx sequelize db:migrate
MIGRATEINSTALL

    sleep 2

    banner
    printf "${WHITE} >> Executando db:seed...\n"
    echo
    sudo su - deploy <<SEEDINSTALL
  # Configura PATH para Node.js
  if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
    . /root/instalador_single_oficial/tools/path_node_deploy.sh
  else
    export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
    if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
      export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
    elif [ -d /usr/local/n/versions/node ]; then
      _mf_nv=\$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
      if [ -n "\$_mf_nv" ] && [ -d "/usr/local/n/versions/node/\$_mf_nv/bin" ]; then
        export PATH="/usr/local/n/versions/node/\$_mf_nv/bin:\$PATH"
      fi
    fi
    if ! command -v npm >/dev/null 2>&1; then
      echo "ERRO: npm não encontrado no PATH do usuário deploy."
      echo "      Atualize o instalador em /root/instalador_single_oficial (inclua tools/path_node_deploy.sh) ou, como root: n 20.19.4"
      echo "      Verifique: ls /usr/local/n/versions/node/  e  sudo ls -la /usr/bin/npm"
      exit 1
    fi
  fi
  
  BACKEND_DIR="/home/deploy/${empresa}/backend"
  if [ ! -d "\$BACKEND_DIR" ]; then
    echo "ERRO: Diretório do backend não existe: \$BACKEND_DIR"
    exit 1
  fi
  
  cd "\$BACKEND_DIR"
  npx sequelize db:seed:all
SEEDINSTALL

    sleep 2

    banner
    printf "${WHITE} >> Iniciando serviço ${BLUE}backend${WHITE}...\n"
    echo
    local compose_dir
    compose_dir=$(localizar_diretorio_compose "/home/deploy/${empresa}")
    if [ -f "${compose_dir}/docker-compose.yml" ]; then
      cd "${compose_dir}" && docker compose -p "${empresa}" up -d backend
    elif command -v pm2 >/dev/null 2>&1; then
      sudo su - deploy -c "cd /home/deploy/${empresa}/backend && pm2 start dist/server.js --name ${empresa}-backend 2>/dev/null || true"
    fi

    # Garantia extra: sed/comandos como root na etapa anterior não devem deixar .env como root (PM2 roda como deploy).
    garantir_permissoes_env_backend "/home/deploy/${empresa}/backend/.env"

    sleep 2
  } || trata_erro "instala_backend_base"
}

# Instala e configura frontend
instala_frontend_base() {
  banner
  printf "${WHITE} >> Instalando dependências do ${BLUE}frontend${WHITE}...\n"
  echo
  
  # Verifica se a variável empresa está definida
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    printf "${YELLOW} >> Carregando variáveis salvas...\n${WHITE}"
    carregar_variaveis
    if [ -z "${empresa}" ]; then
      printf "${RED} >> ERRO: Não foi possível carregar a variável 'empresa'. Abortando.\n${WHITE}"
      exit 1
    fi
  fi
  
  # Verifica se o diretório do código existe
  if [ ! -d "/home/deploy/${empresa}" ]; then
    printf "${RED} >> ERRO: Diretório /home/deploy/${empresa} não existe!\n${WHITE}"
    printf "${YELLOW} >> O código precisa ser clonado primeiro. Verifique a etapa anterior.\n${WHITE}"
    exit 1
  fi
  
  {
    sudo su - deploy <<FRONTENDINSTALL
  # Configura PATH para Node.js
  if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
    . /root/instalador_single_oficial/tools/path_node_deploy.sh
  else
    export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
    if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
      export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
    elif [ -d /usr/local/n/versions/node ]; then
      _mf_nv=\$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
      if [ -n "\$_mf_nv" ] && [ -d "/usr/local/n/versions/node/\$_mf_nv/bin" ]; then
        export PATH="/usr/local/n/versions/node/\$_mf_nv/bin:\$PATH"
      fi
    fi
    if ! command -v npm >/dev/null 2>&1; then
      echo "ERRO: npm não encontrado no PATH do usuário deploy."
      echo "      Atualize o instalador em /root/instalador_single_oficial (inclua tools/path_node_deploy.sh) ou, como root: n 20.19.4"
      echo "      Verifique: ls /usr/local/n/versions/node/  e  sudo ls -la /usr/bin/npm"
      exit 1
    fi
  fi
  
  FRONTEND_DIR="/home/deploy/${empresa}/frontend"
  if [ ! -d "\$FRONTEND_DIR" ]; then
    echo "ERRO: Diretório do frontend não existe: \$FRONTEND_DIR"
    exit 1
  fi
  
  cd "\$FRONTEND_DIR"
  
  # Verifica se package.json existe
  if [ ! -f "package.json" ]; then
    echo "ERRO: package.json não encontrado em \$FRONTEND_DIR"
    exit 1
  fi
  
  npm install --force
  npx browserslist@latest --update-db
FRONTENDINSTALL

    sleep 2

    banner
    printf "${WHITE} >> Configurando variáveis de ambiente ${BLUE}frontend${WHITE}...\n"
    echo
    subdominio_backend=$(echo "${subdominio_backend/https:\/\//}")
    subdominio_backend=${subdominio_backend%%/*}
    subdominio_backend=https://${subdominio_backend}
    frontend_chatbot_url=$(echo "${frontend_chatbot_url/https:\/\//}")
    frontend_chatbot_url=${frontend_chatbot_url%%/*}
    frontend_chatbot_url=https://${frontend_chatbot_url}
    sudo su - deploy <<EOF
  cat <<[-]EOF > /home/deploy/${empresa}/frontend/.env
REACT_APP_BACKEND_URL=${subdominio_backend}
REACT_APP_FACEBOOK_APP_ID=${facebook_app_id}
REACT_APP_REQUIRE_BUSINESS_MANAGEMENT=TRUE
REACT_APP_NAME_SYSTEM=${nome_titulo}
REACT_APP_NUMBER_SUPPORT=${numero_suporte}
SERVER_PORT=${frontend_port}
PORT=${frontend_port}
[-]EOF
EOF

    sleep 2

    banner
    printf "${WHITE} >> Compilando o código do ${BLUE}frontend${WHITE}...\n"
    echo
    sudo su - deploy <<FRONTENDBUILD
  # Configura PATH para Node.js
  if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
    . /root/instalador_single_oficial/tools/path_node_deploy.sh
  else
    export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
    if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
      export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
    elif [ -d /usr/local/n/versions/node ]; then
      _mf_nv=\$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
      if [ -n "\$_mf_nv" ] && [ -d "/usr/local/n/versions/node/\$_mf_nv/bin" ]; then
        export PATH="/usr/local/n/versions/node/\$_mf_nv/bin:\$PATH"
      fi
    fi
    if ! command -v npm >/dev/null 2>&1; then
      echo "ERRO: npm não encontrado no PATH do usuário deploy."
      echo "      Atualize o instalador em /root/instalador_single_oficial (inclua tools/path_node_deploy.sh) ou, como root: n 20.19.4"
      echo "      Verifique: ls /usr/local/n/versions/node/  e  sudo ls -la /usr/bin/npm"
      exit 1
    fi
  fi
  
  FRONTEND_DIR="/home/deploy/${empresa}/frontend"
  if [ ! -d "\$FRONTEND_DIR" ]; then
    echo "ERRO: Diretório do frontend não existe: \$FRONTEND_DIR"
    exit 1
  fi
  
  cd "\$FRONTEND_DIR"
  
  # Verifica se server.js existe
  if [ ! -f "server.js" ]; then
    echo "ERRO: Arquivo server.js não encontrado em \$FRONTEND_DIR"
    exit 1
  fi
  
  sed -i 's/3000/'"${frontend_port}"'/g' server.js
  NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider" npm run build
FRONTENDBUILD

    sleep 2

    banner
    printf "${WHITE} >> Iniciando serviço ${BLUE}frontend${WHITE}...\n"
    echo
    local compose_dir
    compose_dir=$(localizar_diretorio_compose "/home/deploy/${empresa}")
    if [ -f "${compose_dir}/docker-compose.yml" ]; then
      cd "${compose_dir}" && docker compose -p "${empresa}" up -d frontend
    elif command -v pm2 >/dev/null 2>&1; then
      sudo su - deploy -c "cd /home/deploy/${empresa}/frontend && pm2 start server.js --name ${empresa}-frontend 2>/dev/null && pm2 save 2>/dev/null || true"
    fi

    sleep 2
  } || trata_erro "instala_frontend_base"
}

# Configura cron de atualização de dados da pasta public
config_cron_base() {
  printf "${GREEN} >> Adicionando cron atualizar o uso da public às 3h da manhã...${WHITE} \n"
  echo
  {
    if ! command -v cron >/dev/null 2>&1; then
      sudo apt-get update
      sudo apt-get install -y cron
    fi
    sleep 2
    wget -O /home/deploy/atualiza_public.sh https://raw.githubusercontent.com/FilipeCamillo/busca_tamaho_pasta/main/busca_tamaho_pasta.sh >/dev/null 2>&1
    chmod +x /home/deploy/atualiza_public.sh >/dev/null 2>&1
    chown deploy:deploy /home/deploy/atualiza_public.sh >/dev/null 2>&1
    # Cron de pm2 restart às 1h removido — causava instabilidade (queda de sessões Wuzapi/Baileys)
    rm -f /home/deploy/reinicia_instancia.sh
    sudo su - deploy <<'EOF'
        CRON_JOB1="0 3 * * * wget -O /home/deploy/atualiza_public.sh https://raw.githubusercontent.com/FilipeCamillo/busca_tamaho_pasta/main/busca_tamaho_pasta.sh && bash /home/deploy/atualiza_public.sh >> /home/deploy/cron.log 2>&1"
        TMP_CRON=$(mktemp)
        crontab -l 2>/dev/null | grep -v 'reinicia_instancia.sh' | grep -v 'atualiza_public.sh' | grep -v '^$' > "${TMP_CRON}" || true
        if ! grep -qF "${CRON_JOB1}" "${TMP_CRON}" 2>/dev/null; then
            echo "${CRON_JOB1}" >> "${TMP_CRON}"
        fi
        crontab "${TMP_CRON}"
        rm -f "${TMP_CRON}"
EOF
    # Remove também do crontab root (instalações antigas duplicavam o job)
    crontab -l 2>/dev/null | grep -v 'reinicia_instancia.sh' | grep -v '^$' | crontab - 2>/dev/null || true

    sleep 2
  } || trata_erro "config_cron_base"
}

# Configura Nginx
config_nginx_base() {
  banner
  printf "${WHITE} >> Configurando proxy reverso Nginx para ${PURPLE}${empresa}${WHITE}...\n"
  echo
  {
    frontend_hostname=$(echo "${subdominio_frontend/https:\/\//}")
    frontend_hostname=$(echo "${frontend_hostname/http:\/\//}")
    frontend_hostname=${frontend_hostname%%/*}
    frontend_hostname=${frontend_hostname%%:*}

    backend_hostname=$(echo "${subdominio_backend/https:\/\//}")
    backend_hostname=$(echo "${backend_hostname/http:\/\//}")
    backend_hostname=${backend_hostname%%/*}
    backend_hostname=${backend_hostname%%:*}

    cat > "/etc/nginx/sites-available/${empresa}-frontend" <<EOF
server {
  server_name ${frontend_hostname};
  location / {
    proxy_pass http://127.0.0.1:${frontend_port};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
  }
}
EOF
    ln -sf "/etc/nginx/sites-available/${empresa}-frontend" "/etc/nginx/sites-enabled/${empresa}-frontend"

    sleep 1

    cat > "/etc/nginx/sites-available/${empresa}-backend" <<EOF
upstream ${empresa}_backend {
    server 127.0.0.1:${backend_port};
    keepalive 32;
}
server {
  server_name ${backend_hostname};
  location / {
    proxy_pass http://${empresa}_backend;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
    proxy_buffering on;
  }
}
EOF
    ln -sf "/etc/nginx/sites-available/${empresa}-backend" "/etc/nginx/sites-enabled/${empresa}-backend"

    sleep 1

    if [ -n "${subdominio_oficial}" ]; then
      oficial_hostname=$(echo "${subdominio_oficial/https:\/\//}")
      oficial_hostname=$(echo "${oficial_hostname/http:\/\//}")
      oficial_hostname=${oficial_hostname%%/*}
      oficial_hostname=${oficial_hostname%%:*}

      cat > "/etc/nginx/sites-available/${empresa}-oficial" <<EOF
server {
  server_name ${oficial_hostname};
  location / {
    proxy_pass http://127.0.0.1:${PORT_APIOFICIAL:-6000};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
  }
}
EOF
      ln -sf "/etc/nginx/sites-available/${empresa}-oficial" "/etc/nginx/sites-enabled/${empresa}-oficial"
      sleep 1
    fi

    # Remover default para liberar porta 80 e evitar conflitos
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true

    # Habilitar e iniciar/recarregar Nginx antes de invocar o Certbot
    systemctl enable nginx 2>/dev/null || true
    if nginx -t 2>/dev/null; then
      systemctl restart nginx 2>/dev/null || service nginx restart 2>/dev/null || true
    else
      printf "${YELLOW} >> Aviso: Validação de sintaxe Nginx antes do SSL:${WHITE}\n"
      nginx -t || true
      return 1
    fi

    local email_arg
    if [ -n "${email_deploy}" ]; then
      email_arg="-m ${email_deploy}"
    else
      email_arg="--register-unsafely-without-email"
    fi

    if [[ "$backend_hostname" == *.* ]]; then
      banner
      printf "${WHITE} >> Emitindo SSL do ${subdominio_backend}...\n"
      echo
      sudo certbot ${email_arg} --nginx --agree-tos --redirect -n -d "${backend_hostname}" 2>/dev/null || \
      sudo certbot ${email_arg} --nginx --agree-tos -n -d "${backend_hostname}" 2>/dev/null || true
    fi

    sleep 1

    if [[ "$frontend_hostname" == *.* ]]; then
      banner
      printf "${WHITE} >> Emitindo SSL do ${subdominio_frontend}...\n"
      echo
      sudo certbot ${email_arg} --nginx --agree-tos --redirect -n -d "${frontend_hostname}" 2>/dev/null || \
      sudo certbot ${email_arg} --nginx --agree-tos -n -d "${frontend_hostname}" 2>/dev/null || true
    fi

    sleep 1

    if [ -n "${subdominio_oficial}" ] && [[ "$oficial_hostname" == *.* ]]; then
      banner
      printf "${WHITE} >> Emitindo SSL da ${subdominio_oficial}...\n"
      echo
      sudo certbot ${email_arg} --nginx --agree-tos --redirect -n -d "${oficial_hostname}" 2>/dev/null || \
      sudo certbot ${email_arg} --nginx --agree-tos -n -d "${oficial_hostname}" 2>/dev/null || true
      sleep 1
    fi

    sudo systemctl reload nginx 2>/dev/null || service nginx reload 2>/dev/null || true
  } || trata_erro "config_nginx_base"
}

# Configura Traefik
config_traefik_base() {
  {
    mf_carregar_config /home/deploy/${empresa}/backend/.env
    subdominio_backend=$(echo ${BACKEND_URL} | sed 's|https://||')
    subdominio_frontend=$(echo ${FRONTEND_URL} | sed 's|https://||')
    sudo su - root <<EOF
cat > /etc/traefik/conf.d/routers-${subdominio_backend}.toml << 'END'
[http.routers]
  [http.routers.backend]
    rule = "Host(\`${subdominio_backend}\`)"
    service = "backend"
    entryPoints = ["web"]
    middlewares = ["https-redirect"]

  [http.routers.backend-secure]
    rule = "Host(\`${subdominio_backend}\`)"
    service = "backend"
    entryPoints = ["websecure"]
    [http.routers.backend-secure.tls]
      certResolver = "letsencryptresolver"

[http.services]
  [http.services.backend]
    [http.services.backend.loadBalancer]
      [[http.services.backend.loadBalancer.servers]]
        url = "http://127.0.0.1:${backend_port}"

[http.middlewares]
  [http.middlewares.https-redirect.redirectScheme]
    scheme = "https"
    permanent = true
END
EOF

    sleep 2

    sudo su - root <<EOF
cat > /etc/traefik/conf.d/routers-${subdominio_frontend}.toml << 'END'
[http.routers]
  [http.routers.frontend]
    rule = "Host(\`${subdominio_frontend}\`)"
    service = "frontend"
    entryPoints = ["web"]
    middlewares = ["https-redirect"]

  [http.routers.frontend-secure]
    rule = "Host(\`${subdominio_frontend}\`)"
    service = "frontend"
    entryPoints = ["websecure"]
    [http.routers.frontend-secure.tls]
      certResolver = "letsencryptresolver"

[http.services]
  [http.services.frontend]
    [http.services.frontend.loadBalancer]
      [[http.services.frontend.loadBalancer.servers]]
        url = "http://127.0.0.1:${frontend_port}"

[http.middlewares]
  [http.middlewares.https-redirect.redirectScheme]
    scheme = "https"
    permanent = true
END
EOF

    sleep 2
  } || trata_erro "config_traefik_base"
}

# Ajusta latência - necessita reiniciar a VPS para funcionar de fato
config_latencia_base() {
  banner
  printf "${WHITE} >> Reduzindo Latência...\n"
  echo
  {
    sudo su - root <<EOF
cat >> /etc/hosts << 'END'
127.0.0.1   ${subdominio_backend}
127.0.0.1   ${subdominio_frontend}
END
EOF

    sleep 2

    if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE "^${empresa}_(backend|frontend)"; then
      docker restart "${empresa}_backend" "${empresa}_frontend" "${empresa}_transcricao" "${empresa}_apioficial" 2>/dev/null || true
    elif command -v pm2 >/dev/null 2>&1; then
      sudo su - deploy -c "for _p in '${empresa}-backend' '${empresa}-frontend' '${empresa}-transcricao'; do pm2 restart \"\$_p\" 2>/dev/null || true; done"
    fi

    sleep 2
  } || trata_erro "config_latencia_base"
}

# Finaliza a instalação e mostra dados de acesso
fim_instalacao_base() {
  [ "${ALTA_PERFORMANCE}" = "1" ] && [ -f "ALTA_PERFORMANCE_MODE" ] && rm -f "ALTA_PERFORMANCE_MODE"

  # Instalar Portainer ao final quando Alta Performance (senha admin = senha_deploy)
  # Usa arquivo de senha PERSISTENTE para o container poder reiniciar (evita erro de mount com /tmp)
  if [ "${ALTA_PERFORMANCE}" = "1" ]; then
    [ -f "$ARQUIVO_VARIAVEIS" ] && mf_carregar_config "$ARQUIVO_VARIAVEIS" 2>/dev/null
    if [ -z "${senha_deploy}" ]; then
      senha_deploy=""
    fi
    # Se o container existe mas não inicia (ex.: mount do /tmp removido), remover para recriar
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx portainer; then
      if ! docker start portainer 2>/dev/null; then
        printf "   ${YELLOW}>> Container Portainer com erro de mount. Recriando com arquivo persistente...${WHITE}\n"
        docker rm -f portainer 2>/dev/null || true
      fi
    fi
    if [ -n "${senha_deploy}" ] && ! docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx portainer; then
      printf "   ${WHITE}>> Instalando Portainer (senha admin = senha do deploy)...${WHITE}\n"
      PW_FILE="/root/.portainer_admin_pw"
      printf '%s' "${senha_deploy}" > "${PW_FILE}"
      chmod 600 "${PW_FILE}"
      docker volume create portainer_data 2>/dev/null || true
      PORTAINER_PORTA=9443
      if docker run -d -p 9000:9000 -p ${PORTAINER_PORTA}:9443 --name portainer --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        -v "${PW_FILE}:/run/portainer_admin_pw:ro" \
        portainer/portainer-ce:latest --admin-password-file /run/portainer_admin_pw 2>/dev/null; then
        printf "   ${GREEN}>> Portainer instalado. Senha do admin: mesma do deploy. Acesso: https://IP:${PORTAINER_PORTA}${WHITE}\n"
        echo "portainer_porta=${PORTAINER_PORTA}" >> "$ARQUIVO_VARIAVEIS"
        echo "portainer_instalado=1" >> "$ARQUIVO_VARIAVEIS"
      else
        docker rm -f portainer 2>/dev/null || true
        if docker run -d -p 9000:9000 -p ${PORTAINER_PORTA}:9443 --name portainer --restart=always \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v portainer_data:/data \
          portainer/portainer-ce:latest 2>/dev/null; then
          printf "   ${YELLOW}>> Portainer instalado. Defina a senha no primeiro acesso (https://IP:${PORTAINER_PORTA}).${WHITE}\n"
          echo "portainer_porta=${PORTAINER_PORTA}" >> "$ARQUIVO_VARIAVEIS"
          echo "portainer_instalado=1" >> "$ARQUIVO_VARIAVEIS"
        fi
      fi
      echo
    fi
  fi

  [ -f "$ARQUIVO_VARIAVEIS" ] && mf_carregar_config "$ARQUIVO_VARIAVEIS" 2>/dev/null
  portainer_porta=${portainer_porta:-9443}

  banner
  printf "   ${GREEN} >> Instalação concluída...\n"
  echo
  printf "   ${WHITE}Backend:  ${BLUE}${subdominio_backend}\n"
  printf "   ${WHITE}Frontend: ${BLUE}${subdominio_frontend}\n"
  echo
  printf "   ${WHITE}Usuário:  ${BLUE}admin@amanda.com.br\n"
  printf "   ${WHITE}Senha:    ${BLUE}adminamanda\n"
  echo
  if [ "${ALTA_PERFORMANCE}" = "1" ] && (docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx portainer || [ "${portainer_instalado}" = "1" ]); then
    printf "   ${WHITE}Portainer: ${BLUE}https://${ip_atual}:${portainer_porta}${WHITE}\n"
    printf "   ${WHITE}Usuário   ${BLUE}admin${WHITE}\n"
    printf "   ${WHITE}Senha     ${BLUE}(mesma senha do deploy)${WHITE}\n"
    echo
  fi
  if [ "${ALTA_PERFORMANCE}" != "1" ]; then
    printf "${WHITE}>> Aperte qualquer tecla para voltar ao menu principal ou CTRL+C Para finalizar esse script\n"
    read -p ""
  fi
  echo
}

################################################################
#                         ATUALIZAÇÃO                          #
################################################################

ativar_tela_atualizacao_frontend() {
  local frontend_dir="/home/deploy/${empresa}/frontend"
  local build_dir="${frontend_dir}/build"
  local backup_dir="${frontend_dir}/.build_pre_update"
  local logo_url="${REACT_APP_LOGO_URL:-${REACT_APP_LOGO:-${LOGO_URL:-}}}"
  local cor_primaria="${REACT_APP_PRIMARY_COLOR:-${PRIMARY_COLOR:-#772E89}}"
  local cor_secundaria="${REACT_APP_SECONDARY_COLOR:-${SECONDARY_COLOR:-#9333EA}}"
  local nome_empresa="${nome_titulo:-${empresa}}"
  local logo_fallback_text
  logo_fallback_text=$(printf '%s' "${nome_empresa}" | awk '{a=toupper(substr($1,1,1)); b=toupper(substr($2,1,1)); if (b=="") b=toupper(substr($1,2,1)); printf "%s%s", a,b}')
  [ -z "${logo_fallback_text}" ] && logo_fallback_text="AM"

  rm -rf "${backup_dir}"
  if [ -d "${build_dir}" ]; then
    mv "${build_dir}" "${backup_dir}"
  fi
  mkdir -p "${build_dir}"

  cat > "${build_dir}/index.html" <<EOF
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${nome_empresa} | Atualizacao em andamento</title>
  <style>
    :root { --primary: ${cor_primaria}; --secondary: ${cor_secundaria}; --bg: #0f172a; --text: #e2e8f0; }
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; font-family: Inter, Arial, sans-serif; background: radial-gradient(circle at 20% 20%, var(--secondary), var(--bg) 60%); color: var(--text); display: flex; align-items: center; justify-content: center; padding: 24px; }
    .card { width: 100%; max-width: 520px; background: rgba(15, 23, 42, 0.78); border: 1px solid rgba(148,163,184,0.28); border-radius: 18px; padding: 36px 30px; text-align: center; box-shadow: 0 20px 50px rgba(0,0,0,0.45); backdrop-filter: blur(4px); }
    .logo { width: 74px; height: 74px; object-fit: contain; margin-bottom: 14px; }
    .logo-fallback { width: 74px; height: 74px; border-radius: 14px; margin: 0 auto 14px auto; display: grid; place-items: center; background: linear-gradient(135deg, var(--primary), var(--secondary)); color: #fff; font-weight: 700; font-size: 24px; }
    h1 { margin: 0 0 10px 0; font-size: 24px; color: #f8fafc; }
    p { margin: 0; color: #cbd5e1; line-height: 1.5; }
    .bar { margin-top: 24px; height: 10px; background: rgba(148,163,184,0.3); border-radius: 999px; overflow: hidden; }
    .bar span { display: block; height: 100%; width: 35%; border-radius: inherit; background: linear-gradient(90deg, var(--primary), #38bdf8, var(--secondary)); animation: loading 1.35s ease-in-out infinite; }
    .counter { margin-top: 14px; font-size: 13px; color: #94a3b8; }
    @keyframes loading { 0% { transform: translateX(-110%);} 100% { transform: translateX(320%);} }
  </style>
</head>
<body>
  <div class="card">
    __LOGO_BLOCK__
    <h1>Sistema em atualizacao</h1>
    <p>Estamos aplicando melhorias no <strong>${nome_empresa}</strong>.<br />Volte em instantes para continuar usando normalmente.</p>
    <div class="bar"><span></span></div>
    <div class="counter">Tempo estimado restante: <strong id="countdown">10:00</strong></div>
  </div>
  <script>
    const countdownEl = document.getElementById('countdown');
    const totalSeconds = 10 * 60;
    const storageKey = 'mf_update_countdown_end_' + window.location.host;
    const now = Date.now();
    let endAt = parseInt(localStorage.getItem(storageKey) || '0', 10);

    if (!endAt || endAt <= now) {
      endAt = now + (totalSeconds * 1000);
      localStorage.setItem(storageKey, String(endAt));
    }

    const formatTime = (value) => {
      const minutes = Math.floor(value / 60);
      const seconds = value % 60;
      return String(minutes).padStart(2, '0') + ':' + String(seconds).padStart(2, '0');
    };

    const tick = () => {
      const remainingSeconds = Math.max(0, Math.ceil((endAt - Date.now()) / 1000));
      countdownEl.textContent = formatTime(remainingSeconds);
      if (remainingSeconds <= 0) {
        localStorage.removeItem(storageKey);
      }
    };

    tick();
    setInterval(tick, 1000);
  </script>
</body>
</html>
EOF

  if [ -n "${logo_url}" ]; then
    sed -i "s|__LOGO_BLOCK__|<img class=\"logo\" src=\"${logo_url}\" alt=\"Logo ${nome_empresa}\" />|g" "${build_dir}/index.html"
  else
    sed -i "s|__LOGO_BLOCK__|<div class=\"logo-fallback\">${logo_fallback_text}</div>|g" "${build_dir}/index.html"
  fi

  chown -R deploy:deploy "${build_dir}"
  chmod -R 775 "${build_dir}"
}

publicar_build_frontend_atualizado() {
  local frontend_dir="/home/deploy/${empresa}/frontend"
  local build_dir="${frontend_dir}/build"
  local backup_dir="${frontend_dir}/.build_pre_update"
  local next_dir="${frontend_dir}/.build_nova"

  if [ ! -d "${next_dir}" ]; then
    printf "${RED} >> ERRO: build novo não encontrado em ${next_dir}.${WHITE}\n"
    return 1
  fi

  rm -rf "${build_dir}"
  mv "${next_dir}" "${build_dir}"
  rm -rf "${backup_dir}"
  chown -R deploy:deploy "${build_dir}"
  chmod -R 775 "${build_dir}"
}

restaurar_build_frontend_anterior() {
  local frontend_dir="/home/deploy/${empresa}/frontend"
  local build_dir="${frontend_dir}/build"
  local backup_dir="${frontend_dir}/.build_pre_update"
  local next_dir="${frontend_dir}/.build_nova"

  rm -rf "${next_dir}"
  rm -rf "${build_dir}"
  if [ -d "${backup_dir}" ]; then
    mv "${backup_dir}" "${build_dir}"
    chown -R deploy:deploy "${build_dir}"
    chmod -R 775 "${build_dir}"
  fi
}

backup_app_atualizar() {
  # Verifica se a variável empresa está definida (já foi carregada por selecionar_instancia_atualizar)
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    exit 1
  fi
  
  mf_carregar_config /home/deploy/${empresa}/backend/.env
  {
    banner
    printf "${WHITE} >> Antes de atualizar deseja fazer backup do banco de dados? ${GREEN}S/${RED}N:${WHITE}\n"
    echo
    read -p "> " confirmacao_backup
    echo
    confirmacao_backup=$(echo "${confirmacao_backup}" | tr '[:lower:]' '[:upper:]')
    if [ "${confirmacao_backup}" == "S" ]; then
      MF_BACKUP_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tools/mf_backup_banco_empresa.sh"
      [ -f "$MF_BACKUP_SCRIPT" ] || MF_BACKUP_SCRIPT="/root/instalador_single_oficial/tools/mf_backup_banco_empresa.sh"
      # shellcheck source=/dev/null
      source "$MF_BACKUP_SCRIPT"
      if mf_backup_banco_empresa "${empresa}"; then
        printf "${GREEN} >> Backup do banco concluído: ${MF_BACKUP_ARQUIVO}\n"
      else
        printf "${RED} >> Falha ao gerar backup em /home/deploy/backup-${empresa}/${WHITE}\n"
        exit 1
      fi
      sleep 2
    else
      printf " >> Continuando a atualização...\n"
      echo
    fi

    sleep 2
  } || trata_erro "backup_app_atualizar"
}

baixa_codigo_atualizar() {
  banner
  printf "${WHITE} >> Recuperando Permissões... \n"
  echo
  sleep 2
  chown deploy -R /home/deploy/${empresa}
  chmod 775 -R /home/deploy/${empresa}

  sleep 2

  banner
  printf "${WHITE} >> Parando Instancias da empresa ${empresa}... \n"
  echo
  sleep 2

  docker stop "${empresa}_backend" "${empresa}_frontend" "${empresa}_transcricao" "${empresa}_apioficial" 2>/dev/null || true
  if command -v pm2 >/dev/null 2>&1; then
    sudo su - deploy -c "for _p in '${empresa}-backend' '${empresa}-frontend' '${empresa}-transcricao'; do pm2 stop \"\$_p\" 2>/dev/null || true; done"
  fi

  sleep 2

  # otimiza_banco_atualizar  # desativado: VACUUM FULL bloqueia o banco e prolonga a atualização

  verificar_e_adicionar_max_buffer
  verificar_e_adicionar_handle_message_queue_env
  verificar_e_adicionar_disable_disk_usage_cron
  verificar_e_adicionar_whatsapp_web_version

  # Verifica se a variável empresa está definida (já foi carregada por selecionar_instancia_atualizar)
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    exit 1
  fi
  
  banner
  printf "${WHITE} >> Atualizando a Aplicação da Empresa ${empresa}... \n"
  echo
  sleep 2

  mf_carregar_config /home/deploy/${empresa}/frontend/.env 2>/dev/null || true
  frontend_port=${SERVER_PORT:-3000}
  ativar_tela_atualizacao_frontend
  # Carregar porta da transcrição da instância (após git reset --hard o main.py volta ao padrão)
  if [ -n "${ARQUIVO_VARIAVEIS_USADO:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_USADO}" ]; then
    mf_carregar_config "${ARQUIVO_VARIAVEIS_USADO}" 2>/dev/null
  fi
  porta_transcricao=${porta_transcricao:-4002}
  INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "${INSTALADOR_DIR}/tools/git_sincronizar_repositorio.sh" ]; then
    MF_GIT_SYNC_BODY=$(sed '/^#!/d' "${INSTALADOR_DIR}/tools/git_sincronizar_repositorio.sh")
  else
    MF_GIT_SYNC_BODY=$(cat <<'MF_GIT_SYNC_INLINE'

mf_git_clean_preservando_locais() {
  git clean -fd -e api_transcricao/run_transcricao.sh 2>/dev/null || true
}
mf_git_detectar_deploy_branch() {
  if [ -n "${BRANCH_AMANDA_ESCOLHIDA:-}" ] && git show-ref --verify --quiet "refs/remotes/origin/${BRANCH_AMANDA_ESCOLHIDA}"; then
    printf '%s\n' "${BRANCH_AMANDA_ESCOLHIDA}"
    return 0
  fi
  local _cur_branch
  _cur_branch=\$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [ -n "\$_cur_branch" ] && [ "\$_cur_branch" != "HEAD" ] && git show-ref --verify --quiet "refs/remotes/origin/\${_cur_branch}"; then
    printf '%s\n' "\$_cur_branch"
    return 0
  fi
  if git show-ref --verify --quiet refs/remotes/origin/davi-alteracoes; then
    printf '%s\n' davi-alteracoes
  elif git show-ref --verify --quiet refs/remotes/origin/davi-alteraçoes; then
    printf '%s\n' davi-alteraçoes
  elif git show-ref --verify --quiet refs/remotes/origin/alan-alteracoes; then
    printf '%s\n' alan-alteracoes
  elif git show-ref --verify --quiet refs/remotes/origin/main; then
    printf '%s\n' main
  elif git show-ref --verify --quiet refs/remotes/origin/master; then
    printf '%s\n' master
  elif git show-ref --verify --quiet refs/remotes/origin/MULTI100-OFICIAL-u21; then
    printf '%s\n' MULTI100-OFICIAL-u21
  fi
}
mf_git_sincronizar_repositorio() {
  local commit_alvo="\${1:-}"
  local branch_prefix="\${2:-atualizacao}"
  chmod -R u+w .git 2>/dev/null || true
  git fetch --all --tags --prune 2>/dev/null || git fetch origin 2>/dev/null || true
  mf_git_clean_preservando_locais
  if [ -n "\$commit_alvo" ]; then
    if ! git cat-file -e "\${commit_alvo}^{commit}" 2>/dev/null; then
      echo "ERRO: Commit \${commit_alvo} não encontrado após fetch."
      return 1
    fi
    git checkout -f "\${commit_alvo}" || return 1
    git reset --hard "\${commit_alvo}" || return 1
    local _br_atu="\${branch_prefix}-\$(date +%Y%m%d-%H%M%S)"
    git checkout -b "\$_br_atu" 2>/dev/null || git checkout "\$_br_atu" 2>/dev/null || true
    local _head_atu
    _head_atu=\$(git rev-parse HEAD 2>/dev/null)
    if [ "\$_head_atu" != "\$commit_alvo" ]; then
      echo "ERRO: Checkout falhou. Esperado \${commit_alvo}, atual \$_head_atu"
      return 1
    fi
    return 0
  fi
  MF_GIT_DEPLOY_BRANCH=\$(mf_git_detectar_deploy_branch)
  if [ -z "\$MF_GIT_DEPLOY_BRANCH" ]; then
    echo "ERRO: Nenhuma branch remota conhecida em origin."
    return 1
  fi
  git reset --hard "origin/\${MF_GIT_DEPLOY_BRANCH}" || return 1
  git checkout -B "\${MF_GIT_DEPLOY_BRANCH}" "origin/\${MF_GIT_DEPLOY_BRANCH}" 2>/dev/null || true
  mf_git_clean_preservando_locais
  git reset --hard "origin/\${MF_GIT_DEPLOY_BRANCH}" || return 1
  return 0
}
MF_GIT_SYNC_INLINE
)
  fi
  # /root é 700: injeta checagem sqlite3/GLIBC no heredoc.
  if [ -f "${INSTALADOR_DIR}/tools/mf_sqlite3_glibc_check.sh" ]; then
    MF_SQLITE_CHECK_BODY=$(sed '/^#!/d' "${INSTALADOR_DIR}/tools/mf_sqlite3_glibc_check.sh")
  else
    MF_SQLITE_CHECK_BODY=""
  fi
  _MF_FE_LOADER="${INSTALADOR_DIR}/tools/mf_frontend_carregar_lib.sh"
  [ -f "$_MF_FE_LOADER" ] && . "$_MF_FE_LOADER"
  mf_frontend_carregar_lib && mf_frontend_garantir_porta_env "$frontend_port" \
    || printf "${YELLOW} >> Aviso: nao foi possivel garantir PORT no .env do frontend.${WHITE}\n"

  # Sync ANTES do heredoc: se auth falhar, pede novo PAT no TTY, grava na instância, aplica origin e retenta.
  chmod a+rx "${INSTALADOR_DIR}/tools"/*.sh 2>/dev/null || true
  if [ -f "${INSTALADOR_DIR}/tools/git_sincronizar_repositorio.sh" ]; then
    # shellcheck source=/dev/null
    . "${INSTALADOR_DIR}/tools/git_sincronizar_repositorio.sh"
    type mf_garantir_tools_executaveis >/dev/null 2>&1 && mf_garantir_tools_executaveis "${INSTALADOR_DIR}/tools"
  fi
  if [ -z "${ARQUIVO_VARIAVEIS_USADO:-}" ] || [ ! -f "${ARQUIVO_VARIAVEIS_USADO}" ]; then
    printf "${RED} >> ERRO: arquivo de variáveis da instância não definido (ARQUIVO_VARIAVEIS_USADO).${WHITE}\n"
    trata_erro "arquivo_variaveis_ausente_git"
  fi
  printf "${WHITE} >> Sincronizando código com origin (recuperação de token se auth falhar)...${WHITE}\n"
  if ! type mf_git_sincronizar_com_recuperacao_token >/dev/null 2>&1 \
    || ! type mf_git_sincronizar_repositorio >/dev/null 2>&1; then
    printf "${RED} >> ERRO: funções mf_git_* indisponíveis (tools/git_sincronizar_repositorio.sh).${WHITE}\n"
    trata_erro "git_sync_lib_ausente"
  fi
  if [ -n "${commit_atualizacao}" ]; then
    mf_git_sincronizar_com_recuperacao_token "${commit_atualizacao}" "atualizacao" \
      "/home/deploy/${empresa}" "${ARQUIVO_VARIAVEIS_USADO}" \
      || trata_erro "git_sync_token"
  else
    mf_git_sincronizar_com_recuperacao_token "" "atualizacao" \
      "/home/deploy/${empresa}" "${ARQUIVO_VARIAVEIS_USADO}" \
      || trata_erro "git_sync_token"
  fi
  # Recarrega token (pode ter sido renovado no prompt)
  if [ -f "${ARQUIVO_VARIAVEIS_USADO}" ]; then
    # shellcheck source=/dev/null
    mf_carregar_config "${ARQUIVO_VARIAVEIS_USADO}" 2>/dev/null || true
  fi
  printf "${GREEN} >> Repositório sincronizado.${WHITE}\n"

  if ! sudo su - deploy <<UPDATEAPP
  # Configura PATH para Node.js e PM2
  _MF_PATH_NODE="${INSTALADOR_DIR}/tools/path_node_deploy.sh"
  if [ -f "\$_MF_PATH_NODE" ]; then
    . "\$_MF_PATH_NODE"
  elif [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
    . /root/instalador_single_oficial/tools/path_node_deploy.sh
  else
    export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
    if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
      export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
    elif [ -d /usr/local/n/versions/node ]; then
      _mf_nv=\$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
      if [ -n "\$_mf_nv" ] && [ -d "/usr/local/n/versions/node/\$_mf_nv/bin" ]; then
        export PATH="/usr/local/n/versions/node/\$_mf_nv/bin:\$PATH"
      fi
    fi
    if ! command -v npm >/dev/null 2>&1; then
      echo "ERRO: npm não encontrado no PATH do usuário deploy."
      echo "      Atualize o instalador (tools/path_node_deploy.sh) ou, como root: n 20.19.4"
      exit 1
    fi
  fi
${MF_SQLITE_CHECK_BODY}
  
  APP_DIR="/home/deploy/${empresa}"
  BACKEND_DIR="\${APP_DIR}/backend"
  FRONTEND_DIR="\${APP_DIR}/frontend"
  
  # Verifica se os diretórios existem
  if [ ! -d "\$APP_DIR" ]; then
    echo "ERRO: Diretório da aplicação não existe: \$APP_DIR"
    exit 1
  fi
  
  printf "${WHITE} >> Atualizando Backend da empresa ${empresa}...\n"
  echo
  cd "\$APP_DIR"

  # ==== PASTA ESTÁTICA DE PERSONALIZAÇÕES ====
  CUSTOM_DIR="/home/deploy/personalizacoes/${empresa}"

  # Criar pasta de personalizações se não existir
  if [ ! -d "\$CUSTOM_DIR" ]; then
    printf "${YELLOW} >> Criando pasta de personalizações: \$CUSTOM_DIR${WHITE}\n"
    mkdir -p "\$CUSTOM_DIR/assets"
    mkdir -p "\$CUSTOM_DIR/public"

    # Copiar arquivos atuais para a pasta de personalizações (primeira vez)
    if [ -d "\$FRONTEND_DIR/src/assets" ]; then
      cp -rf "\$FRONTEND_DIR/src/assets/"* "\$CUSTOM_DIR/assets/" 2>/dev/null || true
      echo "  - Assets salvos: \$(ls \$CUSTOM_DIR/assets/ 2>/dev/null | wc -l) arquivos"
    fi
    if [ -d "\$FRONTEND_DIR/public" ]; then
      pub_saved=0
      for item in "\$FRONTEND_DIR/public"/*; do
        [ -e "\$item" ] || continue
        base=\$(basename "\$item")
        [ "\$base" = "index.html" ] && continue
        cp -rf "\$item" "\$CUSTOM_DIR/public/" 2>/dev/null || true
        pub_saved=\$((pub_saved + 1))
      done
      echo "  - Public salvos (exceto index.html): \$pub_saved arquivos"
    fi
    printf "${GREEN} >> Pasta de personalizações criada com sucesso!${WHITE}\n"
    printf "${YELLOW} >> DICA: Edite os arquivos em \$CUSTOM_DIR para personalizar logos/favicon${WHITE}\n"
  else
    printf "${GREEN} >> Pasta de personalizações encontrada: \$CUSTOM_DIR${WHITE}\n"
  fi
  # ==== FIM PASTA ESTÁTICA ====

  printf "${WHITE} >> Código já sincronizado; seguindo com build...${WHITE}\n"

  # Reaplicar porta da transcrição (git reset reverte main.py para o padrão 4002)
  if [ -d "\$APP_DIR/api_transcricao" ] && [ -f "\$APP_DIR/api_transcricao/main.py" ]; then
    main_py_transc="\$APP_DIR/api_transcricao/main.py"
    sed -i "s|port=[0-9][0-9][0-9][0-9]|port=${porta_transcricao}|g" "\$main_py_transc" 2>/dev/null || true
    sed -i "s|port = [0-9][0-9][0-9][0-9]|port = ${porta_transcricao}|g" "\$main_py_transc" 2>/dev/null || true
    sed -i "s|porta [0-9][0-9][0-9][0-9]|porta ${porta_transcricao}|g" "\$main_py_transc" 2>/dev/null || true
    printf " >> Porta da transcrição reaplicada no main.py: ${porta_transcricao}\n"
  fi

  if [ ! -d "\$BACKEND_DIR" ]; then
    echo "ERRO: Diretório do backend não existe: \$BACKEND_DIR"
    exit 1
  fi
  
  cd "\$BACKEND_DIR"
  
  if [ ! -f "package.json" ]; then
    echo "ERRO: package.json não encontrado em \$BACKEND_DIR"
    exit 1
  fi

  # TOKEN_GITHUB / Baileys: aplica se o package.json pedir (qualquer repo)
  if grep -qE 'TOKEN_GITHUB|scriptswhitelabel/Hineken' package.json 2>/dev/null || echo "${repo_url}" | grep -Eqi 'github\.com'; then
    if grep -q "TOKEN_GITHUB" package.json 2>/dev/null; then
      sed -i "s|TOKEN_GITHUB|${github_token//&/\\&}|g" package.json
      echo " >> Token do GitHub aplicado no package.json (baileys/Hineken)."
    fi
    if grep -q 'scriptswhitelabel/Hineken' package.json 2>/dev/null; then
      sed -i -E 's|(github\.com/scriptswhitelabel/Hineken\.git)(#[^"]*)?|\1#main|g' package.json
      echo " >> Baileys/Hineken fixado na branch main no package.json."
    fi
  fi
  
  npm prune --force > /dev/null 2>&1
  export PUPPETEER_SKIP_DOWNLOAD=true
  rm -rf node_modules 2>/dev/null || true
  rm -f package-lock.json 2>/dev/null || true
  npm install --force
  npm install puppeteer-core --force
  npm i glob
  # sqlite3/GLIBC (Baileys OPENING): detecta ERR_DLOPEN_FAILED e rebuild se necessário
  if type mf_garantir_sqlite3_compativel_glibc >/dev/null 2>&1; then
    mf_garantir_sqlite3_compativel_glibc "\$(pwd)"
  fi
  npm run build
  sleep 2
  printf "${WHITE} >> Atualizando Banco da empresa ${empresa}...\n"
  echo
  sleep 2
  npx sequelize db:migrate
  sleep 2
  printf "${WHITE} >> Atualizando Frontend da empresa ${empresa}...\n"
  echo
  sleep 2
  
  if [ ! -d "\$FRONTEND_DIR" ]; then
    echo "ERRO: Diretório do frontend não existe: \$FRONTEND_DIR"
    exit 1
  fi
  
  cd "\$FRONTEND_DIR"
  
  if [ ! -f "package.json" ]; then
    echo "ERRO: package.json não encontrado em \$FRONTEND_DIR"
    exit 1
  fi
  
  npm prune --force > /dev/null 2>&1
  npm install --force

  # ==== RESTORE DE PERSONALIZAÇÕES (da pasta estática) ====
  if [ -d "\$CUSTOM_DIR" ]; then
    printf "${WHITE} >> Aplicando personalizações de \$CUSTOM_DIR...\n"
    # Splash/tela inicial vêm do repositório; index.html legado não deve sobrescrever o git reset
    rm -f "\$CUSTOM_DIR/public/index.html" 2>/dev/null || true

    # Restaurar assets
    if [ -d "\$CUSTOM_DIR/assets" ] && [ "\$(ls -A \$CUSTOM_DIR/assets 2>/dev/null)" ]; then
      cp -rf "\$CUSTOM_DIR/assets/"* "\$FRONTEND_DIR/src/assets/" 2>/dev/null || true
      echo "  - Assets aplicados: \$(ls \$CUSTOM_DIR/assets/ 2>/dev/null | wc -l) arquivos"
    fi

    # Restaurar public (favicon, manifest, etc. — nunca index.html)
    if [ -d "\$CUSTOM_DIR/public" ] && [ "\$(ls -A \$CUSTOM_DIR/public 2>/dev/null)" ]; then
      pub_applied=0
      for item in "\$CUSTOM_DIR/public"/*; do
        [ -e "\$item" ] || continue
        base=\$(basename "\$item")
        [ "\$base" = "index.html" ] && continue
        cp -rf "\$item" "\$FRONTEND_DIR/public/" 2>/dev/null || true
        pub_applied=\$((pub_applied + 1))
      done
      echo "  - Public aplicados (exceto index.html): \$pub_applied arquivos"
    fi

    printf "${GREEN} >> Personalizações aplicadas com sucesso!${WHITE}\n"
  fi
  # ==== FIM RESTORE ====

  rm -rf .build_nova 2>/dev/null || true
  build_ok=0
  for mem in 4096 3072 2048; do
    printf "${WHITE} >> Build do frontend com --max-old-space-size=${mem}...\n"
    if BUILD_PATH=.build_nova NODE_OPTIONS="--max-old-space-size=${mem} --openssl-legacy-provider" npm run build; then
      build_ok=1
      break
    fi
    printf "${YELLOW} >> Tentativa com ${mem} MB falhou. Tentando próximo limite...${WHITE}\n"
    sleep 2
  done
  if [ "\$build_ok" -ne 1 ]; then
    echo "ERRO: Falha no build do frontend mesmo após fallback de memória (4096/3072/2048)."
    exit 1
  fi
  sleep 2
UPDATEAPP
  then
    restaurar_build_frontend_anterior
    trata_erro "baixa_codigo_atualizar"
  fi

  if ! publicar_build_frontend_atualizado; then
    restaurar_build_frontend_anterior
    trata_erro "publicar_build_frontend_atualizado"
  fi

  descomentar_env_redis_bull_ack "/home/deploy/${empresa}/backend/.env" "/home/deploy/${empresa}/backend/package.json"

  _mf_transc_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tools/mf_transcricao_manutencao.sh"
  if [ -f "$_mf_transc_script" ]; then
    # shellcheck source=/dev/null
    source "$_mf_transc_script"
    MF_TRANSC_MAINT_SCRIPT="$_mf_transc_script"
    chmod 755 "$_mf_transc_script" 2>/dev/null || true
    printf "${WHITE} >> Recriando run_transcricao.sh e PM2 da transcrição após atualização do código...${WHITE}\n"
    mf_transcricao_pos_atualizacao_git "${empresa}" "${porta_transcricao}" \
      || printf "${YELLOW} >> Aviso: falha ao reconfigurar transcrição automaticamente.${WHITE}\n"
  fi

  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE "^${empresa}_(backend|frontend)"; then
    docker restart "${empresa}_backend" "${empresa}_frontend" "${empresa}_transcricao" "${empresa}_apioficial" 2>/dev/null || true
    printf "${GREEN} >> Contêineres Docker da empresa ${empresa} reiniciados com sucesso!${WHITE}\n"
  elif command -v pm2 >/dev/null 2>&1 || sudo su - deploy -c "command -v pm2" >/dev/null 2>&1; then
    sudo su - deploy <<RESTARTPM2ATUALIZACAO
  export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
  elif [ -d /usr/local/n/versions/node ]; then
    _mf_nv=\$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
    if [ -n "\$_mf_nv" ] && [ -d "/usr/local/n/versions/node/\$_mf_nv/bin" ]; then
      export PATH="/usr/local/n/versions/node/\$_mf_nv/bin:\$PATH"
    fi
  fi
  # Nomes fixos (pm2 list + awk na tabela com │/cores costuma falhar)
  pm2 restart "${empresa}-backend" 2>/dev/null || true
  PORT="$frontend_port" pm2 restart "${empresa}-frontend" --update-env 2>/dev/null \
    || pm2 restart "${empresa}-frontend" 2>/dev/null || true
  pm2 save
RESTARTPM2ATUALIZACAO
  fi

  sudo su - root <<EOF
    if systemctl is-active --quiet nginx; then
      sudo systemctl restart nginx
    elif systemctl is-active --quiet traefik; then
      sudo systemctl restart traefik.service
    else
      printf "${GREEN}Nenhum serviço de proxy (Nginx ou Traefik) está em execução.${WHITE}"
    fi
EOF

  echo
  printf "${WHITE} >> Atualização do ${nome_titulo} concluída...\n"
  echo
  sleep 5
  menu
}

# otimiza_banco_atualizar() {
#   # Verifica se a variável empresa está definida (já foi carregada por selecionar_instancia_atualizar)
#   if [ -z "${empresa}" ]; then
#     printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
#     return 0
#   fi
#
#   # Usar arquivo da instância SELECIONADA para não sobrescrever empresa com a primária (ex.: chat em vez de chat2)
#   if [ -n "${ARQUIVO_VARIAVEIS_USADO:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_USADO}" ]; then
#     source "${ARQUIVO_VARIAVEIS_USADO}" 2>/dev/null
#   elif [ -f "$ARQUIVO_VARIAVEIS" ]; then
#     source "$ARQUIVO_VARIAVEIS" 2>/dev/null
#   fi
#   if [ "${ALTA_PERFORMANCE}" = "1" ]; then
#     db_host_opt="127.0.0.1"
#     db_port_opt="7532"
#   else
#     db_host_opt="localhost"
#     db_port_opt="5432"
#   fi
#
#   banner
#   printf "${WHITE} >> Realizando Manutenção do Banco de Dados da empresa ${empresa}... \n"
#   echo
#   {
#     db_password=$(grep "DB_PASS=" /home/deploy/${empresa}/backend/.env | cut -d '=' -f2)
#     sudo su - root <<EOF
#     PGPASSWORD="$db_password" vacuumdb -U "${empresa}" -h ${db_host_opt} -p ${db_port_opt} -d "${empresa}" --full --analyze
#     PGPASSWORD="$db_password" psql -U ${empresa} -h ${db_host_opt} -p ${db_port_opt} -d ${empresa} -c "REINDEX DATABASE ${empresa};"
#     PGPASSWORD="$db_password" psql -U ${empresa} -h ${db_host_opt} -p ${db_port_opt} -d ${empresa} -c "ANALYZE;"
# EOF
#
#     sleep 2
#   } || trata_erro "otimiza_banco_atualizar"
# }

# Após qualquer alteração ao .env feita como root (sed -i, mktemp+mv), o arquivo pode ficar root:root;
# o PM2 roda como deploy e o dotenv não lê variáveis — garantir dono deploy.
garantir_permissoes_env_backend() {
  local env_file="$1"
  [ -z "$env_file" ] || [ ! -f "$env_file" ] && return 0
  chown deploy:deploy "$env_file" 2>/dev/null || true
  chmod 600 "$env_file" 2>/dev/null || true
}

# Iguala REDIS_URI_ACK ao valor de REDIS_URI (chamado só ao descomentar ou acrescentar ACK; se ACK já estava ativo, não alteramos).
copiar_redis_uri_para_redis_uri_ack() {
  local env_file="$1"
  [ ! -f "$env_file" ] && return 0
  local redis_main
  redis_main=$(grep -m1 '^REDIS_URI=' "$env_file" 2>/dev/null | cut -d= -f2- | tr -d '\r')
  [ -z "$redis_main" ] && return 0
  if ! grep -q '^REDIS_URI_ACK=' "$env_file" 2>/dev/null; then
    return 0
  fi
  local tmp
  tmp=$(mktemp)
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == REDIS_URI_ACK=* ]]; then
      printf 'REDIS_URI_ACK=%s\n' "$redis_main"
    else
      printf '%s\n' "$line"
    fi
  done < "$env_file" > "$tmp" && mv "$tmp" "$env_file"
  garantir_permissoes_env_backend "$env_file"
  return 0
}

# Ativa REDIS_URI_ACK e Bull Board no .env do backend (versão em backend/package.json >= 7.4.1).
# $3 opcional: valor explícito de REDIS_URI_ACK ao acrescentar bloco (ex.: nova instância com Redis dedicado); caso contrário copia só de REDIS_URI.
descomentar_env_redis_bull_ack() {
  local env_file="$1"
  local pkg_json="${2:-}"
  local redis_ack_val_append="${3:-}"
  [ -z "$pkg_json" ] && pkg_json="$(dirname "$env_file")/package.json"
  [ ! -f "$env_file" ] && return 0
  [ ! -f "$pkg_json" ] && return 0
  # Qualquer return da função reajusta dono (sed/append como root deixam .env ilegível para deploy)
  _mf_fix_env_owner_descomentar() { garantir_permissoes_env_backend "$env_file"; }
  trap '_mf_fix_env_owner_descomentar' RETURN
  local ver
  ver=$(grep -m1 '"version"' "$pkg_json" 2>/dev/null | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  [ -z "$ver" ] && return 0
  if [ "$(printf '%s\n' "$ver" "7.4.1" | sort -V | head -1)" != "7.4.1" ]; then
    return 0
  fi
  local redis_main_val
  redis_main_val=$(grep -m1 '^REDIS_URI=' "$env_file" 2>/dev/null | cut -d= -f2- | tr -d '\r')
  if grep -q '^REDIS_URI_ACK=' "$env_file" 2>/dev/null; then
    printf "${GREEN} >> REDIS_URI_ACK / Bull Board já ativos no .env (backend ${ver}).${WHITE}\n"
    return 0
  fi
  if grep -q '^# REDIS_URI_ACK=' "$env_file" 2>/dev/null; then
    sed -i 's/^# REDIS_URI_ACK=/REDIS_URI_ACK=/' "$env_file"
    sed -i 's/^# BULL_BOARD=/BULL_BOARD=/' "$env_file"
    sed -i 's/^# BULL_USER=/BULL_USER=/' "$env_file"
    sed -i 's/^# BULL_PASS=/BULL_PASS=/' "$env_file"
    copiar_redis_uri_para_redis_uri_ack "$env_file"
    printf "${GREEN} >> REDIS_URI_ACK / Bull Board ativados no .env (backend ${ver} >= 7.4.1).${WHITE}\n"
    return 0
  fi
  local db_pass bull_user
  db_pass=$(grep '^DB_PASS=' "$env_file" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
  bull_user=$(grep '^MAIL_USER=' "$env_file" 2>/dev/null | cut -d= -f2- | tr -d '"' | head -1)
  [ -z "$db_pass" ] && return 0
  [ -z "$bull_user" ] && bull_user="admin@localhost"
  if [ -z "$redis_ack_val_append" ] && [ -z "$redis_main_val" ]; then
    printf "${YELLOW} >> AVISO: REDIS_URI vazio no .env; REDIS_URI_ACK não foi gravado — defina manualmente se necessário.${WHITE}\n"
  fi
  {
    echo ""
    if [ -n "$redis_ack_val_append" ]; then
      echo "REDIS_URI_ACK=${redis_ack_val_append}"
    elif [ -n "$redis_main_val" ]; then
      echo "REDIS_URI_ACK=${redis_main_val}"
    fi
    echo "BULL_BOARD=true"
    echo "BULL_USER=${bull_user}"
    echo "BULL_PASS=${db_pass}"
  } >> "$env_file"
  if [ -z "$redis_ack_val_append" ]; then
    copiar_redis_uri_para_redis_uri_ack "$env_file"
  fi
  printf "${GREEN} >> REDIS_URI_ACK / Bull Board adicionados ao .env (backend ${ver} >= 7.4.1).${WHITE}\n"
}

# Verificar e adicionar MAX_BUFFER_SIZE_MB no .env do backend
verificar_e_adicionar_max_buffer() {
  # Verifica se a variável empresa está definida (já foi carregada por selecionar_instancia_atualizar)
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    return 0
  fi
  
  ENV_FILE="/home/deploy/${empresa}/backend/.env"
  
  if [ ! -f "$ENV_FILE" ]; then
    printf "${YELLOW} >> AVISO: Arquivo .env não encontrado em $ENV_FILE. Pulando verificação de MAX_BUFFER_SIZE_MB.\n${WHITE}"
    return 0
  fi
  
  if ! grep -q "^MAX_BUFFER_SIZE_MB=" "$ENV_FILE"; then
    printf "${WHITE} >> Adicionando MAX_BUFFER_SIZE_MB=200 no .env do backend...\n"
    echo "" >> "$ENV_FILE"
    echo "# Buffer Size Configuration" >> "$ENV_FILE"
    echo "MAX_BUFFER_SIZE_MB=200" >> "$ENV_FILE"
    printf "${GREEN} >> Variável MAX_BUFFER_SIZE_MB adicionada com sucesso!${WHITE}\n"
  else
    printf "${GREEN} >> Variável MAX_BUFFER_SIZE_MB já existe no .env do backend.${WHITE}\n"
  fi
  garantir_permissoes_env_backend "$ENV_FILE"
}

# Throughput Bull: Baileys + WhatsMeow (opção 2 / instalação)
_mf_tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tools"
if [ -f "${_mf_tools_dir}/mf_env_handle_message_queue.sh" ]; then
  # shellcheck source=tools/mf_env_handle_message_queue.sh
  source "${_mf_tools_dir}/mf_env_handle_message_queue.sh"
else
  verificar_e_adicionar_handle_message_queue_env() {
    printf "${YELLOW} >> tools/mf_env_handle_message_queue.sh não encontrado — pulando filas de mensagem.\n${WHITE}"
  }
fi

# Verificar e documentar DISABLE_DISK_USAGE_CRON no .env do backend (cron ativo por padrão)
verificar_e_adicionar_disable_disk_usage_cron() {
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    return 0
  fi

  ENV_FILE="/home/deploy/${empresa}/backend/.env"

  if [ ! -f "$ENV_FILE" ]; then
    printf "${YELLOW} >> AVISO: Arquivo .env não encontrado em $ENV_FILE. Pulando verificação de DISABLE_DISK_USAGE_CRON.\n${WHITE}"
    return 0
  fi

  if ! grep -qE '^(# )?DISABLE_DISK_USAGE_CRON=' "$ENV_FILE"; then
    printf "${WHITE} >> Adicionando DISABLE_DISK_USAGE_CRON (comentado, cron ativo por padrão) no .env do backend...\n"
    echo "" >> "$ENV_FILE"
    echo "# Cron diário de recálculo de uso de disco (23h). Padrão: ativo. Para desativar: DISABLE_DISK_USAGE_CRON=1" >> "$ENV_FILE"
    echo "# DISABLE_DISK_USAGE_CRON=1" >> "$ENV_FILE"
    printf "${GREEN} >> DISABLE_DISK_USAGE_CRON documentado no .env do backend.${WHITE}\n"
  else
    printf "${GREEN} >> DISABLE_DISK_USAGE_CRON já existe no .env do backend.${WHITE}\n"
  fi
  garantir_permissoes_env_backend "$ENV_FILE"
}

# Verificar e adicionar WHATSAPP_WEB_VERSION e variáveis LID/Baileys no .env do backend
verificar_e_adicionar_whatsapp_web_version() {
  if [ -z "${empresa}" ]; then
    printf "${RED} >> ERRO: Variável 'empresa' não está definida!\n${WHITE}"
    return 0
  fi

  ENV_FILE="/home/deploy/${empresa}/backend/.env"

  if [ ! -f "$ENV_FILE" ]; then
    printf "${YELLOW} >> AVISO: Arquivo .env não encontrado em $ENV_FILE. Pulando verificação de WHATSAPP_WEB_VERSION e variáveis LID/Baileys.\n${WHITE}"
    return 0
  fi

  # Versão padrão do instalador (atualize aqui quando a Meta invalidar a anterior).
  local MF_WHATSAPP_WEB_VERSION_PADRAO="2.3000.1042896555"
  local _mf_wa_ver_atual=""
  if grep -q '^WHATSAPP_WEB_VERSION=' "$ENV_FILE"; then
    _mf_wa_ver_atual=$(grep '^WHATSAPP_WEB_VERSION=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  fi

  if [ -z "$_mf_wa_ver_atual" ]; then
    printf "${WHITE} >> Adicionando WHATSAPP_WEB_VERSION ao .env do backend...\n"
    echo "" >> "$ENV_FILE"
    echo "# Opcional: fixa a versão do WhatsApp Web usada pelo Baileys. Se vazio, busca automaticamente." >> "$ENV_FILE"
    echo "WHATSAPP_WEB_VERSION=${MF_WHATSAPP_WEB_VERSION_PADRAO}" >> "$ENV_FILE"
    printf "${GREEN} >> WHATSAPP_WEB_VERSION=${MF_WHATSAPP_WEB_VERSION_PADRAO} adicionada ao .env do backend.${WHITE}\n"
  elif [ "$_mf_wa_ver_atual" != "$MF_WHATSAPP_WEB_VERSION_PADRAO" ]; then
    printf "${WHITE} >> Atualizando WHATSAPP_WEB_VERSION no .env: ${_mf_wa_ver_atual} → ${MF_WHATSAPP_WEB_VERSION_PADRAO}\n"
    sed -i "s|^WHATSAPP_WEB_VERSION=.*|WHATSAPP_WEB_VERSION=${MF_WHATSAPP_WEB_VERSION_PADRAO}|" "$ENV_FILE"
    printf "${GREEN} >> WHATSAPP_WEB_VERSION atualizada para ${MF_WHATSAPP_WEB_VERSION_PADRAO}.${WHITE}\n"
  else
    printf "${GREEN} >> WHATSAPP_WEB_VERSION já está em ${MF_WHATSAPP_WEB_VERSION_PADRAO}.${WHITE}\n"
  fi

  local _mf_lid_baileys_header=0
  if ! grep -q '^ENABLE_LID_DEBUG=' "$ENV_FILE" || \
     ! grep -q '^FIX_LID_JOB_ENABLED=' "$ENV_FILE" || \
     ! grep -q '^FIX_LID_JOB_CRON=' "$ENV_FILE" || \
     ! grep -q '^LOG_MESSAGE_UPSERT=' "$ENV_FILE" || \
     ! grep -q '^BAILEYS_OUTBOUND_LID_FIRST=' "$ENV_FILE" || \
     ! grep -q '^BAILEYS_SESSION_RESET_ENABLED=' "$ENV_FILE" || \
     ! grep -q '^BAILEYS_STUB400_AUTO_RETRY=' "$ENV_FILE" || \
     ! grep -q '^BAILEYS_LOG_LEVEL=' "$ENV_FILE"; then
    printf "${WHITE} >> Verificando variáveis LID/Baileys no .env do backend...\n"
  fi

  if ! grep -q '^ENABLE_LID_DEBUG=' "$ENV_FILE"; then
    [ "$_mf_lid_baileys_header" -eq 0 ] && { echo "" >> "$ENV_FILE"; echo "# DISABLE_PUSH_NOTIFICATIONS=0" >> "$ENV_FILE"; echo "" >> "$ENV_FILE"; _mf_lid_baileys_header=1; }
    echo "ENABLE_LID_DEBUG=true" >> "$ENV_FILE"
    printf "${GREEN} >> ENABLE_LID_DEBUG adicionada ao .env do backend.${WHITE}\n"
  fi
  if ! grep -q '^FIX_LID_JOB_ENABLED=' "$ENV_FILE"; then
    [ "$_mf_lid_baileys_header" -eq 0 ] && { echo "" >> "$ENV_FILE"; echo "# DISABLE_PUSH_NOTIFICATIONS=0" >> "$ENV_FILE"; echo "" >> "$ENV_FILE"; _mf_lid_baileys_header=1; }
    echo "FIX_LID_JOB_ENABLED=true" >> "$ENV_FILE"
    printf "${GREEN} >> FIX_LID_JOB_ENABLED adicionada ao .env do backend.${WHITE}\n"
  fi
  if ! grep -q '^FIX_LID_JOB_CRON=' "$ENV_FILE"; then
    [ "$_mf_lid_baileys_header" -eq 0 ] && { echo "" >> "$ENV_FILE"; echo "# DISABLE_PUSH_NOTIFICATIONS=0" >> "$ENV_FILE"; echo "" >> "$ENV_FILE"; _mf_lid_baileys_header=1; }
    echo "# Opcional: horário do job (padrão: 3h da manhã)" >> "$ENV_FILE"
    echo "FIX_LID_JOB_CRON=0 3 * * *" >> "$ENV_FILE"
    printf "${GREEN} >> FIX_LID_JOB_CRON adicionada ao .env do backend.${WHITE}\n"
  fi
  if ! grep -q '^LOG_MESSAGE_UPSERT=' "$ENV_FILE"; then
    [ "$_mf_lid_baileys_header" -eq 0 ] && { echo "" >> "$ENV_FILE"; echo "# DISABLE_PUSH_NOTIFICATIONS=0" >> "$ENV_FILE"; echo "" >> "$ENV_FILE"; _mf_lid_baileys_header=1; }
    echo "# Log opcional: defina LOG_MESSAGE_UPSERT=true no ambiente para linhas [MSG-UPSERT] com wid, stub, renderable, upsertType." >> "$ENV_FILE"
    echo "# Produção: ative LOG_MESSAGE_UPSERT=true só enquanto analisar; depois desligue para não encher log." >> "$ENV_FILE"
    echo "LOG_MESSAGE_UPSERT=false" >> "$ENV_FILE"
    printf "${GREEN} >> LOG_MESSAGE_UPSERT adicionada ao .env do backend.${WHITE}\n"
  fi
  if ! grep -q '^BAILEYS_OUTBOUND_LID_FIRST=' "$ENV_FILE"; then
    [ "$_mf_lid_baileys_header" -eq 0 ] && { echo "" >> "$ENV_FILE"; echo "# DISABLE_PUSH_NOTIFICATIONS=0" >> "$ENV_FILE"; echo "" >> "$ENV_FILE"; _mf_lid_baileys_header=1; }
    echo "# [fix LID] envio LID-first p/ contatos migrados (default do codigo ja e true)" >> "$ENV_FILE"
    echo "BAILEYS_OUTBOUND_LID_FIRST=false" >> "$ENV_FILE"
    printf "${GREEN} >> BAILEYS_OUTBOUND_LID_FIRST adicionada ao .env do backend.${WHITE}\n"
  fi
  if ! grep -q '^BAILEYS_SESSION_RESET_ENABLED=' "$ENV_FILE"; then
    [ "$_mf_lid_baileys_header" -eq 0 ] && { echo "" >> "$ENV_FILE"; echo "# DISABLE_PUSH_NOTIFICATIONS=0" >> "$ENV_FILE"; echo "" >> "$ENV_FILE"; _mf_lid_baileys_header=1; }
    echo "BAILEYS_SESSION_RESET_ENABLED=false" >> "$ENV_FILE"
    printf "${GREEN} >> BAILEYS_SESSION_RESET_ENABLED adicionada ao .env do backend.${WHITE}\n"
  fi
  if ! grep -q '^BAILEYS_STUB400_AUTO_RETRY=' "$ENV_FILE"; then
    [ "$_mf_lid_baileys_header" -eq 0 ] && { echo "" >> "$ENV_FILE"; echo "# DISABLE_PUSH_NOTIFICATIONS=0" >> "$ENV_FILE"; echo "" >> "$ENV_FILE"; _mf_lid_baileys_header=1; }
    echo "BAILEYS_STUB400_AUTO_RETRY=true" >> "$ENV_FILE"
    printf "${GREEN} >> BAILEYS_STUB400_AUTO_RETRY adicionada ao .env do backend.${WHITE}\n"
  fi
  if ! grep -q '^BAILEYS_LOG_LEVEL=' "$ENV_FILE"; then
    [ "$_mf_lid_baileys_header" -eq 0 ] && { echo "" >> "$ENV_FILE"; echo "# DISABLE_PUSH_NOTIFICATIONS=0" >> "$ENV_FILE"; echo "" >> "$ENV_FILE"; _mf_lid_baileys_header=1; }
    echo "BAILEYS_LOG_LEVEL=warn" >> "$ENV_FILE"
    printf "${GREEN} >> BAILEYS_LOG_LEVEL adicionada ao .env do backend.${WHITE}\n"
  fi

  garantir_permissoes_env_backend "$ENV_FILE"
}

# Adicionar função para instalar transcrição de áudio nativa
instalar_transcricao_audio_nativa() {
  banner
  printf "${WHITE} >> Instalando Transcrição de Áudio Nativa...\n"
  echo
  
  # Verificar e selecionar instância para instalar a transcrição
  if ! selecionar_instancia_atualizar; then
    printf "${RED} >> Erro ao selecionar instância. Voltando ao menu principal...${WHITE}\n"
    sleep 2
    menu
    return
  fi
  
  # Identificar o arquivo de variáveis usado (salvo pela função selecionar_instancia_atualizar)
  # A função já salva o arquivo em ARQUIVO_VARIAVEIS_USADO como variável global
  ARQUIVO_VARIAVEIS_INSTANCIA="${ARQUIVO_VARIAVEIS_USADO:-}"
  
  # Se não foi salvo pela função, tentar identificar agora baseado na empresa atual
  if [ -z "$ARQUIVO_VARIAVEIS_INSTANCIA" ] || [ ! -f "$ARQUIVO_VARIAVEIS_INSTANCIA" ]; then
    INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local empresa_atual="${empresa}"
    
    # Verificar se é a instalação base
    if [ -f "${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS}" ]; then
      local temp_empresa_base=""
      mf_carregar_config "${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS}" 2>/dev/null
      temp_empresa_base="${empresa:-}"
      empresa="${empresa_atual}"
      
      if [ "${temp_empresa_base}" = "${empresa_atual}" ]; then
        ARQUIVO_VARIAVEIS_INSTANCIA="${INSTALADOR_DIR}/${ARQUIVO_VARIAVEIS}"
      fi
    fi
    
    # Se não é a base, procurar em instâncias adicionais
    if [ -z "$ARQUIVO_VARIAVEIS_INSTANCIA" ] || [ ! -f "$ARQUIVO_VARIAVEIS_INSTANCIA" ]; then
      for arquivo_instancia in "${INSTALADOR_DIR}"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
        if [ -f "$arquivo_instancia" ]; then
          local temp_empresa_inst=""
          mf_carregar_config "$arquivo_instancia" 2>/dev/null
          temp_empresa_inst="${empresa:-}"
          empresa="${empresa_atual}"
          
          if [ "${temp_empresa_inst}" = "${empresa_atual}" ]; then
            ARQUIVO_VARIAVEIS_INSTANCIA="$arquivo_instancia"
            break
          fi
        fi
      done
    fi
  fi
  
  # Verificar se a instância existe
  if [ ! -d "/home/deploy/${empresa}" ]; then
    printf "${RED} >> ERRO: Diretório /home/deploy/${empresa} não existe!${WHITE}\n"
    sleep 2
    menu
    return
  fi
  
  # Verificar se a pasta api_transcricao existe
  if [ ! -d "/home/deploy/${empresa}/api_transcricao" ]; then
    printf "${RED} >> ERRO: Pasta api_transcricao não encontrada em /home/deploy/${empresa}/api_transcricao${WHITE}\n"
    printf "${YELLOW} >> A pasta api_transcricao deve existir no repositório da instância.${WHITE}\n"
    sleep 3
    menu
    return
  fi
  
  # Solicitar porta da transcrição
  banner
  printf "${WHITE} >> Configuração da Porta de Transcrição${WHITE}\n"
  echo
  printf "${YELLOW}══════════════════════════════════════════════════════════════════${WHITE}\n"
  echo
  printf "${WHITE} >> Digite a porta para o serviço de transcrição (padrão: 4002):${WHITE}\n"
  read -p "> " porta_transcricao
  
  # Validar porta
  if [ -z "$porta_transcricao" ]; then
    porta_transcricao="4002"
    printf "${YELLOW} >> Usando porta padrão: 4002${WHITE}\n"
  fi
  
  # Validar se é um número válido
  if ! [[ "$porta_transcricao" =~ ^[0-9]+$ ]]; then
    printf "${RED} >> ERRO: Porta inválida! Deve ser um número.${WHITE}\n"
    sleep 2
    menu
    return
  fi
  
  # Verificar se a porta está em uso
  if lsof -i:${porta_transcricao} &>/dev/null; then
    printf "${YELLOW} >> ATENÇÃO: A porta ${porta_transcricao} já está em uso.${WHITE}\n"
    printf "${WHITE} >> Deseja continuar mesmo assim? (S/N):${WHITE}\n"
    read -p "> " continuar_porta
    continuar_porta=$(echo "${continuar_porta}" | tr '[:lower:]' '[:upper:]')
    if [ "${continuar_porta}" != "S" ]; then
      printf "${GREEN} >> Operação cancelada. Voltando ao menu...${WHITE}\n"
      sleep 2
      menu
      return
    fi
  fi
  
  printf "${GREEN} >> Porta selecionada: ${BLUE}${porta_transcricao}${WHITE}\n"
  echo
  sleep 2
  
  # Instalar bibliotecas compartilhadas do ffmpeg necessárias para transcrição
  banner
  printf "${WHITE} >> Instalando bibliotecas compartilhadas do ffmpeg...\n"
  echo
  
  {
    sudo apt-get update -qq
    
    # Verificar se o ffmpeg está instalado, se não estiver, instalar
    if ! command -v ffmpeg >/dev/null 2>&1; then
      printf "${YELLOW} >> FFmpeg não encontrado. Instalando...${WHITE}\n"
      sudo apt-get install -y ffmpeg
    fi
    
    FFMPEG_PATH=$(command -v ffmpeg 2>/dev/null || true)
    SKIP_HEAVY_FFMPEG_APT=false
    if [ -n "$FFMPEG_PATH" ] && [ -f "$FFMPEG_PATH" ] && ffmpeg -version >/dev/null 2>&1; then
      LDD_PROBE=$(ldd "$FFMPEG_PATH" 2>&1 || true)
      if echo "$LDD_PROBE" | grep -qi 'not a dynamic executable'; then
        SKIP_HEAVY_FFMPEG_APT=true
      elif ! echo "$LDD_PROBE" | grep -q 'not found'; then
        SKIP_HEAVY_FFMPEG_APT=true
      fi
    fi
    
    if [ "$SKIP_HEAVY_FFMPEG_APT" = true ]; then
      printf "${GREEN} >> FFmpeg em ${FFMPEG_PATH} já executa (estático ou dependências satisfeitas).${WHITE}\n"
      printf "${WHITE} >> Pulando reinstalação apt, pacotes libav em massa e PPA (evita timeout de chave GPG / savoury1 em VPS).${WHITE}\n"
      sudo ldconfig 2>/dev/null || true
      if ffmpeg -version >/dev/null 2>&1; then
        printf "${GREEN} >> ✓ FFmpeg está funcionando corretamente!${WHITE}\n"
      fi
    else
    printf "${WHITE} >> Verificando dependências do ffmpeg instalado...${WHITE}\n"
    
    # Verificar quais bibliotecas o ffmpeg precisa usando ldd
    FFMPEG_PATH=$(command -v ffmpeg 2>/dev/null || true)
    if [ -n "$FFMPEG_PATH" ] && [ -f "$FFMPEG_PATH" ]; then
      printf "${WHITE} >> Analisando dependências de: $FFMPEG_PATH${WHITE}\n"
      MISSING_LIBS=$(ldd "$FFMPEG_PATH" 2>/dev/null | grep "not found" | awk '{print $1}' | sed 's/://' || true)
      
      if [ -n "$MISSING_LIBS" ]; then
        printf "${YELLOW} >> Bibliotecas faltantes detectadas:${WHITE}\n"
        echo "$MISSING_LIBS" | while read lib; do
          printf "${YELLOW}   - $lib${WHITE}\n"
        done
        
        # Extrair versão da biblioteca faltante e tentar instalar
        for lib in $MISSING_LIBS; do
          if echo "$lib" | grep -qE "libav(device|format|codec)"; then
            # Extrair número da versão (ex: libavdevice.so.62 -> 62)
            VERSION=$(echo "$lib" | grep -oE '[0-9]+' | head -1)
            LIB_NAME=$(echo "$lib" | sed 's/\.so.*//' | sed 's/lib//')
            
            if [ -n "$VERSION" ] && [ -n "$LIB_NAME" ]; then
              printf "${WHITE} >> Tentando instalar $LIB_NAME versão $VERSION...${WHITE}\n"
              # Tentar diferentes formatos de nome de pacote
              sudo apt-get install -y "lib${LIB_NAME}${VERSION}" 2>/dev/null || \
              sudo apt-get install -y "lib${LIB_NAME}${VERSION:0:2}" 2>/dev/null || \
              sudo apt-get install -y "lib${LIB_NAME}" 2>/dev/null || true
            fi
          fi
        done
      fi
    fi
    
    printf "${WHITE} >> Instalando todas as bibliotecas do ffmpeg...${WHITE}\n"
    
    # Primeiro, tentar corrigir dependências quebradas
    sudo apt-get install -f -y 2>/dev/null || true
    
    # Instalar ffmpeg e todas suas dependências de uma vez
    sudo apt-get install --reinstall -y ffmpeg 2>/dev/null || true
    
    # Instalar bibliotecas específicas - tentar todas as versões possíveis
    printf "${WHITE} >> Instalando bibliotecas libavdevice, libavformat e libavcodec (todas as versões)...${WHITE}\n"
    
    # Instalar todas as versões disponíveis (não usar elif, instalar todas que estiverem disponíveis)
    sudo apt-get install -y \
      libavdevice58 libavformat58 libavcodec58 \
      libavdevice59 libavformat59 libavcodec59 \
      libavdevice60 libavformat60 libavcodec60 \
      libavdevice61 libavformat61 libavcodec61 \
      libavdevice62 libavformat62 libavcodec62 \
      libavdevice63 libavformat63 libavcodec63 \
      libavdevice libavformat libavcodec \
      2>/dev/null || true
    
    # Instalar pacotes de desenvolvimento também (podem conter as bibliotecas necessárias)
    sudo apt-get install -y \
      libavdevice-dev libavformat-dev libavcodec-dev \
      libavutil-dev libswscale-dev libswresample-dev \
      2>/dev/null || true
    
    # PPA savoury1/ffmpeg* removido: keyservers costumam dar "retrieving gpg key timed out" em VPS.
    # FFmpeg estático (instala_ffmpeg_base / BtbN ou build manual em /usr/bin) cobre transcrição sem apt extra.
    
    # Atualizar cache do ldconfig para que o sistema encontre as bibliotecas
    printf "${WHITE} >> Atualizando cache de bibliotecas compartilhadas...${WHITE}\n"
    sudo ldconfig 2>/dev/null || true
    
    # Verificar novamente quais bibliotecas o ffmpeg precisa
    if [ -n "$FFMPEG_PATH" ] && [ -f "$FFMPEG_PATH" ]; then
      MISSING_LIBS_AFTER=$(ldd "$FFMPEG_PATH" 2>/dev/null | grep "not found" | awk '{print $1}' | sed 's/://' || true)
      
      if [ -z "$MISSING_LIBS_AFTER" ]; then
        printf "${GREEN} >> ✓ Todas as dependências do ffmpeg foram instaladas com sucesso!${WHITE}\n"
      else
        printf "${YELLOW} >> AVISO: Ainda há bibliotecas faltantes:${WHITE}\n"
        echo "$MISSING_LIBS_AFTER" | while read lib; do
          printf "${YELLOW}   - $lib${WHITE}\n"
        done
        
        # Se ainda faltam bibliotecas: binário estático não deve ser trocado pelo apt
        LDD_RMCHK=$(ldd "$FFMPEG_PATH" 2>&1 || true)
        if echo "$LDD_RMCHK" | grep -qi 'not a dynamic executable'; then
          printf "${YELLOW} >> FFmpeg estático detectado; não removendo em favor do pacote apt.${WHITE}\n"
          if ffmpeg -version >/dev/null 2>&1; then
            printf "${GREEN} >> ✓ FFmpeg responde; use binário estático em /usr/bin se precisar de codecs atualizados.${WHITE}\n"
          fi
        else
          printf "${WHITE} >> O ffmpeg pode ter sido instalado de fonte externa. Reinstalando do repositório do sistema...${WHITE}\n"
          sudo apt-get remove -y ffmpeg 2>/dev/null || true
          sudo apt-get install -y ffmpeg 2>/dev/null || true
          sudo apt-get install -f -y 2>/dev/null || true
          sudo ldconfig 2>/dev/null || true
          
          # Verificar novamente
          MISSING_LIBS_FINAL=$(ldd "$(command -v ffmpeg 2>/dev/null)" 2>/dev/null | grep "not found" | awk '{print $1}' | sed 's/://' || true)
          if [ -z "$MISSING_LIBS_FINAL" ]; then
            printf "${GREEN} >> ✓ FFmpeg reinstalado e funcionando!${WHITE}\n"
          else
            printf "${RED} >> ERRO: Ainda há bibliotecas faltantes após reinstalação.${WHITE}\n"
            printf "${YELLOW} >> Bibliotecas faltantes: $MISSING_LIBS_FINAL${WHITE}\n"
            printf "${YELLOW} >> Dica: instale ffmpeg/ffprobe estáticos em /usr/bin (ex.: BtbN ou johnvansickle) e rode esta opção de novo.${WHITE}\n"
          fi
        fi
      fi
    fi
    
    # Verificação final: libav no ldconfig não se aplica a ffmpeg totalmente estático
    FFMPEG_CMD=$(command -v ffmpeg 2>/dev/null || true)
    LDD_END=$([ -n "$FFMPEG_CMD" ] && ldd "$FFMPEG_CMD" 2>&1 || true)
    if echo "$LDD_END" | grep -qi 'not a dynamic executable'; then
      if ffmpeg -version >/dev/null 2>&1; then
        printf "${GREEN} >> ✓ FFmpeg estático OK (sem dependência de libav via sistema).${WHITE}\n"
      fi
    elif ldconfig -p 2>/dev/null | grep -q libavdevice && ldconfig -p 2>/dev/null | grep -q libavformat && ldconfig -p 2>/dev/null | grep -q libavcodec; then
      printf "${GREEN} >> ✓ Bibliotecas do ffmpeg verificadas no sistema!${WHITE}\n"
    else
      printf "${YELLOW} >> AVISO: Algumas bibliotecas podem não estar no cache do sistema.${WHITE}\n"
    fi
    
    # Teste final: tentar executar o ffmpeg para verificar se funciona
    if ffmpeg -version >/dev/null 2>&1; then
      printf "${GREEN} >> ✓ FFmpeg está funcionando corretamente!${WHITE}\n"
    else
      printf "${YELLOW} >> AVISO: FFmpeg pode ter problemas. Verifique manualmente.${WHITE}\n"
    fi
    
    fi
    
  } || {
    printf "${YELLOW} >> AVISO: Algumas bibliotecas podem não ter sido instaladas. Continuando...${WHITE}\n"
  }
  
  echo
  sleep 2
  
  # Atualizar .env do backend com a nova porta
  banner
  printf "${WHITE} >> Atualizando configuração do backend...\n"
  echo
  
  local env_file="/home/deploy/${empresa}/backend/.env"
  if [ -f "$env_file" ]; then
    # Verificar se TRANSCRIBE_URL já existe
    if grep -q "^TRANSCRIBE_URL=" "$env_file"; then
      # Atualizar porta existente
      sed -i "s|^TRANSCRIBE_URL=.*|TRANSCRIBE_URL=http://localhost:${porta_transcricao}|" "$env_file"
      printf "${GREEN} >> TRANSCRIBE_URL atualizado para http://localhost:${porta_transcricao}${WHITE}\n"
    else
      # Adicionar TRANSCRIBE_URL se não existir
      echo "" >> "$env_file"
      echo "# API de Transcrição de Audio" >> "$env_file"
      echo "TRANSCRIBE_URL=http://localhost:${porta_transcricao}" >> "$env_file"
      printf "${GREEN} >> TRANSCRIBE_URL adicionado: http://localhost:${porta_transcricao}${WHITE}\n"
    fi
  else
    printf "${RED} >> ERRO: Arquivo .env não encontrado em $env_file${WHITE}\n"
    sleep 2
    menu
    return
  fi
  
  echo
  sleep 2
  
  # IMPORTANTE: Reiniciar o PM2 do backend para aplicar a nova variável TRANSCRIBE_URL
  banner
  printf "${WHITE} >> Reiniciando backend para aplicar a nova configuração TRANSCRIBE_URL...\n"
  echo
  
  sudo su - deploy <<RESTARTBACKEND
  # Configura PATH para Node.js e PM2
  if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
    . /root/instalador_single_oficial/tools/path_node_deploy.sh
  else
    export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
    if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
      export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
    elif [ -d /usr/local/n/versions/node ]; then
      _mf_nv=\$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
      if [ -n "\$_mf_nv" ] && [ -d "/usr/local/n/versions/node/\$_mf_nv/bin" ]; then
        export PATH="/usr/local/n/versions/node/\$_mf_nv/bin:\$PATH"
      fi
    fi
    if ! command -v npm >/dev/null 2>&1; then
      echo "ERRO: npm não encontrado no PATH do usuário deploy."
      echo "      Atualize o instalador em /root/instalador_single_oficial (inclua tools/path_node_deploy.sh) ou, como root: n 20.19.4"
      echo "      Verifique: ls /usr/local/n/versions/node/  e  sudo ls -la /usr/bin/npm"
      exit 1
    fi
  fi
  
  # Reiniciar apenas o backend desta instância para carregar a nova variável TRANSCRIBE_URL
  if pm2 list | grep -qE "${empresa}-backend[[:space:]]"; then
    printf "Reiniciando backend ${empresa}-backend...\n"
    pm2 restart ${empresa}-backend
    pm2 save
    printf "${GREEN} >> Backend reiniciado com sucesso! Nova porta TRANSCRIBE_URL aplicada.${WHITE}\n"
  else
    printf "${YELLOW} >> AVISO: Backend ${empresa}-backend não encontrado no PM2${WHITE}\n"
    printf "${YELLOW} >> A configuração foi salva, mas será aplicada quando o backend for iniciado${WHITE}\n"
  fi
RESTARTBACKEND
  
  echo
  sleep 2
  
  # Verificar se há processos PM2 existentes desta instância (apenas se já estiver instalado)
  # Na primeira instalação, não haverá processos para parar
  banner
  printf "${WHITE} >> Verificando se há processos PM2 existentes da transcrição...\n"
  echo
  
  sudo su - deploy <<CHECKPM2TRANSC
  # Configura PATH para Node.js e PM2
  if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
    . /root/instalador_single_oficial/tools/path_node_deploy.sh
  else
    export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
    if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
      export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
    elif [ -d /usr/local/n/versions/node ]; then
      _mf_nv=\$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
      if [ -n "\$_mf_nv" ] && [ -d "/usr/local/n/versions/node/\$_mf_nv/bin" ]; then
        export PATH="/usr/local/n/versions/node/\$_mf_nv/bin:\$PATH"
      fi
    fi
    if ! command -v npm >/dev/null 2>&1; then
      echo "ERRO: npm não encontrado no PATH do usuário deploy."
      echo "      Atualize o instalador em /root/instalador_single_oficial (inclua tools/path_node_deploy.sh) ou, como root: n 20.19.4"
      echo "      Verifique: ls /usr/local/n/versions/node/  e  sudo ls -la /usr/bin/npm"
      exit 1
    fi
  fi
  
  # Verificar se existe processo PM2 desta instância ESPECÍFICA e parar apenas se existir
  # IMPORTANTE: Só para processos com o nome exato desta instância (${empresa}-transcricao)
  # NÃO afeta processos genéricos como "transcricao" ou processos de outras instâncias
  # Na primeira instalação, não haverá nada para parar
    if pm2 list | grep -qE "${empresa}-transcricao[[:space:]]"; then
    printf "Processos PM2 encontrados para a instância ${empresa}. Parando apenas processos desta instância...\n"
    # Parar APENAS processos com o nome exato desta instância
    # Não para processos genéricos ou de outras instâncias
    pm2 stop ${empresa}-transcricao 2>/dev/null || true
    pm2 delete ${empresa}-transcricao 2>/dev/null || true
    pm2 save 2>/dev/null || true
    printf "Processos da instância ${empresa} parados com sucesso.\n"
  else
    printf "Nenhum processo PM2 encontrado para esta instância (${empresa}). Primeira instalação ou processo não existe.\n"
    printf "Processos de outras instâncias (incluindo instalação principal) não serão afetados.\n"
  fi
CHECKPM2TRANSC
  
  echo
  sleep 2
  
  # Atualizar main.py com a nova porta
  banner
  printf "${WHITE} >> Atualizando configuração do main.py...\n"
  echo
  
  local main_py="/home/deploy/${empresa}/api_transcricao/main.py"
  if [ -f "$main_py" ]; then
    # Fazer backup do arquivo original
    cp "$main_py" "${main_py}.bak" 2>/dev/null || true
    
    # Atualizar porta no app.run com diferentes padrões usando Python para maior precisão
    python3 <<PYTHON_SCRIPT
import re
import sys

file_path = "$main_py"
new_port = "$porta_transcricao"

try:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original_content = content
    
    # Substituir port=XXXX ou port = XXXX (qualquer número de dígitos)
    # Padrão 1: app.run(host='0.0.0.0', port=4002, debug=True)
    # Padrão 2: app.run(host="0.0.0.0", port=4002, debug=True)
    # Padrão 3: app.run(host='0.0.0.0', port = 4002, debug=True)
    # Preservar o formato original (com ou sem espaços)
    def replace_port(match):
        # Manter o formato original (port= ou port =)
        original = match.group(0)
        if ' = ' in original:
            return f"port = {new_port}"
        else:
            return f"port={new_port}"
    
    content = re.sub(r"port\s*=\s*\d+", replace_port, content)
    
    # Atualizar mensagens de log (português) - qualquer porta
    content = re.sub(r"porta\s+\d+", f"porta {new_port}", content, flags=re.IGNORECASE)
    
    # Atualizar mensagens de log (inglês) - qualquer porta
    content = re.sub(r"Servidor iniciado na porta \d+", f"Servidor iniciado na porta {new_port}", content, flags=re.IGNORECASE)
    content = re.sub(r"Server started on port \d+", f"Server started on port {new_port}", content, flags=re.IGNORECASE)
    
    if content != original_content:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"SUCCESS: Porta atualizada para {new_port}")
        sys.exit(0)
    else:
        print(f"WARNING: Nenhuma alteração detectada. Verifique se a porta já está correta ou se o padrão é diferente.")
        sys.exit(1)
except Exception as e:
    print(f"ERROR: {str(e)}")
    sys.exit(1)
PYTHON_SCRIPT
    
    if [ $? -eq 0 ]; then
      printf "${GREEN} >> Porta atualizada no main.py para ${porta_transcricao}${WHITE}\n"
      
      # Verificar se a porta foi realmente alterada
      if grep -q "port=${porta_transcricao}\|port = ${porta_transcricao}" "$main_py"; then
        printf "${GREEN} >> Verificação: Porta ${porta_transcricao} confirmada no main.py${WHITE}\n"
      else
        printf "${YELLOW} >> AVISO: Não foi possível verificar a porta no main.py${WHITE}\n"
      fi
    else
      # Fallback para sed se Python falhar
      printf "${YELLOW} >> Tentando método alternativo (sed)...${WHITE}\n"
      
      # Substituir qualquer porta de 4 dígitos
      sed -i "s|port=[0-9][0-9][0-9][0-9]|port=${porta_transcricao}|g" "$main_py" 2>/dev/null || true
      sed -i "s|port = [0-9][0-9][0-9][0-9]|port = ${porta_transcricao}|g" "$main_py" 2>/dev/null || true
      sed -i "s|porta [0-9][0-9][0-9][0-9]|porta ${porta_transcricao}|g" "$main_py" 2>/dev/null || true
      
      # Verificar novamente
      if grep -q "port=${porta_transcricao}\|port = ${porta_transcricao}" "$main_py"; then
        printf "${GREEN} >> Porta atualizada com sucesso usando sed${WHITE}\n"
      else
        printf "${RED} >> ERRO: Não foi possível atualizar a porta no main.py${WHITE}\n"
        printf "${YELLOW} >> Por favor, verifique manualmente o arquivo: $main_py${WHITE}\n"
      fi
    fi
    
    # Mostrar a linha do app.run para confirmação
    printf "${WHITE} >> Linha app.run encontrada:${WHITE}\n"
    grep "app.run" "$main_py" | head -1 || printf "${YELLOW} >> Não foi possível encontrar app.run${WHITE}\n"
    
  else
    printf "${YELLOW} >> AVISO: Arquivo main.py não encontrado em $main_py${WHITE}\n"
    printf "${YELLOW} >> A porta será configurada apenas no .env do backend${WHITE}\n"
  fi
  
  echo
  sleep 2
  
  # Fazer backup do main.py atualizado ANTES de executar o script
  # O script pode fazer git checkout/reset que sobrescreve o main.py
  local main_py="/home/deploy/${empresa}/api_transcricao/main.py"
  local main_py_backup_protected="${main_py}.protected_backup"
  if [ -f "$main_py" ]; then
    printf "${WHITE} >> Criando backup protegido do main.py atualizado...${WHITE}\n"
    cp "$main_py" "$main_py_backup_protected" 2>/dev/null || true
    # Garantir que o backup tenha permissões corretas para deploy
    chown deploy:deploy "$main_py_backup_protected" 2>/dev/null || true
    chmod 644 "$main_py_backup_protected" 2>/dev/null || true
    printf "${GREEN} >> Backup criado: ${main_py_backup_protected}${WHITE}\n"
    echo
  fi
  
  # Executar script de instalação como usuário DEPLOY (não root)
  # Isso garante que o PM2 não será iniciado como root
  banner
  printf "${WHITE} >> Executando script de instalação da transcrição como usuário DEPLOY...\n"
  printf "${GREEN} >> Isso garante que o PM2 não será iniciado como root${WHITE}\n"
  echo
  
  local script_path="/home/deploy/${empresa}/api_transcricao/install-python-app.sh"
  if [ -f "$script_path" ]; then
    chmod 775 "$script_path"
    
    # Passar o nome do app como variável de ambiente (padrão: ${empresa}-transcricao)
    # O nome é obtido do arquivo de variáveis da instância
    export PM2_APP_NAME="${empresa}-transcricao"
    export APP_NAME="${empresa}-transcricao"
    export PM2_NAME="${empresa}-transcricao"
    
    # Executar o script como usuário DEPLOY para evitar que inicie PM2 como root
    # Criar um script temporário para executar como deploy
    local temp_script="/tmp/exec_install_transc_${empresa}.sh"
    cat > "$temp_script" <<TEMPSCRIPT
#!/bin/bash
if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
  . /root/instalador_single_oficial/tools/path_node_deploy.sh
else
export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
elif [ -d /usr/local/n/versions/node ]; then
  _mf_nv=\$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
  if [ -n "\$_mf_nv" ] && [ -d "/usr/local/n/versions/node/\$_mf_nv/bin" ]; then
    export PATH="/usr/local/n/versions/node/\$_mf_nv/bin:\$PATH"
  fi
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "ERRO: npm não encontrado no PATH do deploy. Como root: n 20.19.4  ou copie tools/path_node_deploy.sh"
  exit 1
fi
fi

cd /home/deploy/${empresa}/api_transcricao || exit 1

# Passar variáveis de ambiente
export PM2_APP_NAME="${empresa}-transcricao"
export APP_NAME="${empresa}-transcricao"
export PM2_NAME="${empresa}-transcricao"

# Executar o script passando o nome automaticamente quando ele pedir
# Redirecionar stderr para evitar mensagens de sudo que podem aparecer
echo "${empresa}-transcricao" | bash ${script_path} 2>/dev/null || {
  # Se falhar, tentar novamente sem redirecionar stderr para ver o erro real
  echo "${empresa}-transcricao" | bash ${script_path} || true
}
TEMPSCRIPT
    
    chmod +x "$temp_script"
    chown deploy:deploy "$temp_script" 2>/dev/null || true
    
    # Executar o script temporário como deploy
    # Redirecionar stderr para evitar mensagens de sudo que podem aparecer do script interno
    # O script install-python-app.sh pode tentar executar comandos sudo internamente
    # Esses avisos não impedem a instalação, então podemos ignorá-los
    sudo su - deploy -c "bash $temp_script" 2>&1 | grep -v "sudo: a terminal is required\|sudo: a password is required\|multiflcw" || true
    
    # Remover script temporário
    rm -f "$temp_script" 2>/dev/null || true
    
    printf "${GREEN} >> Script de instalação executado!${WHITE}\n"
    printf "${GREEN} >> Nome do app PM2 usado automaticamente: ${BLUE}${empresa}-transcricao${WHITE}\n"
    echo
    
    # Instalar dependências Python após o script de instalação
    banner
    printf "${WHITE} >> Verificando e instalando dependências Python...\n"
    echo
    
    # Tentar instalar pip3 primeiro (se não estiver disponível)
    if ! command -v pip3 &>/dev/null && ! python3 -m pip --version &>/dev/null; then
      printf "${YELLOW} >> pip3 não está disponível. Tentando instalar via apt-get...${WHITE}\n"
      if sudo -n apt-get update -qq && sudo -n apt-get install -y python3-pip 2>/dev/null; then
        printf "${GREEN} >> pip3 instalado com sucesso!${WHITE}\n"
      else
        printf "${YELLOW} >> Não foi possível instalar pip3 automaticamente (pode requerer senha)${WHITE}\n"
        printf "${YELLOW} >> Tentando instalar Flask diretamente via apt-get...${WHITE}\n"
        if sudo -n apt-get install -y python3-flask python3-flask-cors python3-requests 2>/dev/null; then
          printf "${GREEN} >> Flask instalado via apt-get!${WHITE}\n"
        else
          printf "${RED} >> AVISO: Não foi possível instalar pip3 ou Flask automaticamente${WHITE}\n"
          printf "${YELLOW} >> Execute manualmente: sudo apt-get install -y python3-pip python3-flask python3-flask-cors${WHITE}\n"
        fi
      fi
    fi
    
    # Verificar se Flask está disponível antes de continuar
    if ! sudo su - deploy -c "python3 -c 'import flask'" 2>/dev/null; then
      printf "${YELLOW} >> Flask não está disponível. Tentando instalar via apt-get...${WHITE}\n"
      if sudo -n apt-get install -y python3-flask python3-flask-cors python3-requests 2>/dev/null; then
        printf "${GREEN} >> Flask instalado via apt-get!${WHITE}\n"
      else
        printf "${YELLOW} >> Não foi possível instalar via apt-get sem senha. Continuando...${WHITE}\n"
      fi
    fi
    
    sudo su - deploy <<INSTALLPYTHONDEP
    if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
      . /root/instalador_single_oficial/tools/path_node_deploy.sh
    else
    export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
    if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
      export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
    elif [ -d /usr/local/n/versions/node ]; then
      _mf_nv=\$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
      if [ -n "\$_mf_nv" ] && [ -d "/usr/local/n/versions/node/\$_mf_nv/bin" ]; then
        export PATH="/usr/local/n/versions/node/\$_mf_nv/bin:\$PATH"
      fi
    fi
    if ! command -v npm >/dev/null 2>&1; then
      echo "ERRO: npm não encontrado no PATH do deploy. Como root: n 20.19.4"
      exit 1
    fi
    fi
    
    TRANSC_DIR="/home/deploy/${empresa}/api_transcricao"
    cd "\$TRANSC_DIR" || exit 1
    
    # Verificar se pip3 está disponível
    if ! command -v pip3 &> /dev/null; then
      printf "${YELLOW} >> pip3 não encontrado. Tentando instalar...${WHITE}\n"
      
      # Tentar instalar pip3 usando apt-get (requer sudo, mas tenta sem senha)
      if sudo -n apt-get install -y python3-pip 2>/dev/null; then
        printf "${GREEN} >> pip3 instalado com sucesso via apt-get${WHITE}\n"
      else
        printf "${YELLOW} >> Não foi possível instalar pip3 via apt-get (pode requerer senha)${WHITE}\n"
        printf "${YELLOW} >> Tentando métodos alternativos...${WHITE}\n"
        
        # Tentar usar python3 -m pip (geralmente disponível mesmo sem pip3 instalado)
        if python3 -m pip --version &>/dev/null; then
          printf "${GREEN} >> python3 -m pip está disponível${WHITE}\n"
          alias pip3="python3 -m pip"
        else
          # Tentar instalar pip3 usando get-pip.py (não requer sudo)
          printf "${YELLOW} >> Tentando instalar pip usando get-pip.py...${WHITE}\n"
          curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py 2>/dev/null || wget -q https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py 2>/dev/null || true
          if [ -f /tmp/get-pip.py ]; then
            python3 /tmp/get-pip.py --user --break-system-packages 2>&1 | grep -v "already installed\|Requirement already satisfied" || true
            rm -f /tmp/get-pip.py 2>/dev/null || true
            # Verificar se pip3 está disponível agora
            if command -v pip3 &>/dev/null || python3 -m pip --version &>/dev/null; then
              printf "${GREEN} >> pip instalado com sucesso${WHITE}\n"
              if ! command -v pip3 &>/dev/null; then
                alias pip3="python3 -m pip"
              fi
            fi
          fi
        fi
      fi
    fi
    
    # Se ainda não tiver pip3, usar python3 -m pip como fallback
    if ! command -v pip3 &> /dev/null && ! python3 -m pip --version &>/dev/null; then
      printf "${RED} >> ERRO CRÍTICO: pip3 e python3 -m pip não estão disponíveis!${WHITE}\n"
      printf "${YELLOW} >> Instalando pip3 manualmente...${WHITE}\n"
      printf "${YELLOW} >> Execute manualmente: sudo apt-get install -y python3-pip${WHITE}\n"
      printf "${YELLOW} >> Ou instale Flask via apt: sudo apt-get install -y python3-flask${WHITE}\n"
      
      # Tentar instalar Flask via apt-get como último recurso
      if sudo -n apt-get install -y python3-flask python3-flask-cors 2>/dev/null; then
        printf "${GREEN} >> Flask instalado via apt-get${WHITE}\n"
      else
        printf "${RED} >> Não foi possível instalar Flask automaticamente${WHITE}\n"
        printf "${RED} >> Por favor, execute manualmente: sudo apt-get install -y python3-pip python3-flask python3-flask-cors${WHITE}\n"
      fi
    fi
    
    # Obter o caminho do site-packages do usuário
    USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
    if [ -n "\$USER_SITE" ]; then
      export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
    fi
    
    # Determinar comando pip a usar
    PIP_CMD="pip3"
    if ! command -v pip3 &>/dev/null; then
      if python3 -m pip --version &>/dev/null; then
        PIP_CMD="python3 -m pip"
        printf "${GREEN} >> Usando python3 -m pip como alternativa${WHITE}\n"
      else
        printf "${RED} >> ERRO: pip3 e python3 -m pip não estão disponíveis!${WHITE}\n"
        printf "${YELLOW} >> Instale pip3 manualmente: sudo apt-get install -y python3-pip${WHITE}\n"
        exit 1
      fi
    fi
    
    # Instalar dependências (usar --break-system-packages para ambientes externally managed)
    if [ -f "\$TRANSC_DIR/requirements.txt" ]; then
      printf "${GREEN} >> Instalando dependências do requirements.txt...${WHITE}\n"
      # Tentar com --user primeiro
      INSTALL_OUTPUT=\$(\$PIP_CMD install --user -r "\$TRANSC_DIR/requirements.txt" 2>&1)
      INSTALL_STATUS=\$?
      if [ \$INSTALL_STATUS -eq 0 ] || echo "\$INSTALL_OUTPUT" | grep -q "already satisfied\|Requirement already satisfied"; then
        printf "${GREEN} >> ✓ Dependências instaladas${WHITE}\n"
      elif echo "\$INSTALL_OUTPUT" | grep -q "externally-managed-environment"; then
        # Se falhar por externally-managed, usar --break-system-packages com --user
        printf "${YELLOW} >> Ambiente externally-managed detectado. Usando --break-system-packages...${WHITE}\n"
        \$PIP_CMD install --user --break-system-packages -r "\$TRANSC_DIR/requirements.txt" 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
        printf "${GREEN} >> ✓ Dependências instaladas${WHITE}\n"
      else
        # Outro erro, mostrar e tentar com --break-system-packages
        printf "${YELLOW} >> Erro na instalação. Tentando com --break-system-packages...${WHITE}\n"
        \$PIP_CMD install --user --break-system-packages -r "\$TRANSC_DIR/requirements.txt" 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
        printf "${GREEN} >> ✓ Dependências instaladas${WHITE}\n"
      fi
      if [ -f /root/instalador_single_oficial/tools/mf_transcricao_manutencao.sh ]; then
        # shellcheck source=/dev/null
        . /root/instalador_single_oficial/tools/mf_transcricao_manutencao.sh
        mf_transcricao_pip_python313_compat "\$PIP_CMD"
      elif python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 13) else 1)' 2>/dev/null; then
        printf "${YELLOW} >> Python 3.13+: instalando standard-aifc e audioop-lts...${WHITE}\n"
        \$PIP_CMD install --user --break-system-packages standard-aifc audioop-lts 2>/dev/null || true
      fi
    else
      printf "${YELLOW} >> requirements.txt não encontrado. Instalando dependências básicas...${WHITE}\n"
      # Tentar com --user primeiro
      INSTALL_OUTPUT=\$(\$PIP_CMD install --user flask flask-cors requests 2>&1)
      INSTALL_STATUS=\$?
      if [ \$INSTALL_STATUS -eq 0 ] || echo "\$INSTALL_OUTPUT" | grep -q "already satisfied\|Requirement already satisfied"; then
        printf "${GREEN} >> ✓ Dependências básicas instaladas${WHITE}\n"
      elif echo "\$INSTALL_OUTPUT" | grep -q "externally-managed-environment"; then
        # Se falhar por externally-managed, usar --break-system-packages com --user
        printf "${YELLOW} >> Ambiente externally-managed detectado. Usando --break-system-packages...${WHITE}\n"
        \$PIP_CMD install --user --break-system-packages flask flask-cors requests 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
        printf "${GREEN} >> ✓ Dependências básicas instaladas (Flask, Flask-CORS, Requests)${WHITE}\n"
      else
        # Outro erro, mostrar e tentar com --break-system-packages
        printf "${YELLOW} >> Erro na instalação. Tentando com --break-system-packages...${WHITE}\n"
        \$PIP_CMD install --user --break-system-packages flask flask-cors requests 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
        printf "${GREEN} >> ✓ Dependências básicas instaladas${WHITE}\n"
      fi
    fi
    
    # Atualizar USER_SITE após instalação
    USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
    if [ -n "\$USER_SITE" ] && [ -d "\$USER_SITE" ]; then
      export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
      printf "${GREEN} >> PYTHONPATH configurado: \$USER_SITE${WHITE}\n"
    fi
    
    # Verificar se Flask está instalado
    if python3 -c "import flask" 2>/dev/null; then
      printf "${GREEN} >> ✓ Flask está instalado e acessível${WHITE}\n"
    else
      printf "${RED} >> ERRO: Flask não está instalado! Tentando instalar novamente...${WHITE}\n"
      # Tentar com --user primeiro
      INSTALL_OUTPUT=\$(\$PIP_CMD install --user --force-reinstall flask 2>&1)
      INSTALL_STATUS=\$?
      if [ \$INSTALL_STATUS -eq 0 ] || echo "\$INSTALL_OUTPUT" | grep -q "already satisfied\|Requirement already satisfied"; then
        printf "${GREEN} >> Flask reinstalado${WHITE}\n"
      elif echo "\$INSTALL_OUTPUT" | grep -q "externally-managed-environment"; then
        # Se falhar, usar --break-system-packages
        printf "${YELLOW} >> Usando --break-system-packages...${WHITE}\n"
        \$PIP_CMD install --user --break-system-packages --force-reinstall flask 2>&1 || true
      else
        # Tentar com --break-system-packages de qualquer forma
        \$PIP_CMD install --user --break-system-packages --force-reinstall flask 2>&1 || true
      fi
      # Atualizar USER_SITE novamente
      USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
      if [ -n "\$USER_SITE" ] && [ -d "\$USER_SITE" ]; then
        export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
      fi
      # Verificar novamente
      if python3 -c "import flask" 2>/dev/null; then
        printf "${GREEN} >> ✓ Flask instalado com sucesso${WHITE}\n"
      else
        printf "${RED} >> ERRO: Ainda não foi possível importar Flask!${WHITE}\n"
      fi
    fi
    echo
INSTALLPYTHONDEP
    
    echo
    sleep 2
    
    # RESTAURAR o main.py atualizado imediatamente após o script
    # O script pode ter feito git checkout/reset que sobrescreveu o main.py
    if [ -f "$main_py_backup_protected" ]; then
      printf "${WHITE} >> Restaurando main.py com a porta correta após execução do script...${WHITE}\n"
      cp "$main_py_backup_protected" "$main_py" 2>/dev/null || true
      
      # Garantir permissões corretas para deploy
      chown deploy:deploy "$main_py" 2>/dev/null || true
      chmod 644 "$main_py" 2>/dev/null || true
      
      # Verificar se a porta está correta após restaurar
      if grep -q "port=${porta_transcricao}\|port = ${porta_transcricao}" "$main_py"; then
        printf "${GREEN} >> ✓ main.py restaurado com porta ${porta_transcricao}${WHITE}\n"
      else
        printf "${YELLOW} >> AVISO: Porta não confirmada após restaurar. Corrigindo agora...${WHITE}\n"
        # Corrigir usando sed forçado
        sed -i "s|port=[0-9]\+|port=${porta_transcricao}|g" "$main_py" 2>/dev/null || true
        sed -i "s|port = [0-9]\+|port = ${porta_transcricao}|g" "$main_py" 2>/dev/null || true
        # Garantir permissões após modificar
        chown deploy:deploy "$main_py" 2>/dev/null || true
        chmod 644 "$main_py" 2>/dev/null || true
      fi
      echo
    fi
    
    # Parar qualquer PM2 que o script possa ter iniciado como DEPLOY
    # IMPORTANTE: Não vamos iniciar o PM2 agora, apenas depois de atualizar o main.py
    sleep 2
    banner
    printf "${WHITE} >> Parando qualquer PM2 iniciado pelo script de instalação...\n"
    echo
    
    # Limpar processos PM2 iniciados como DEPLOY (o script foi executado como deploy)
    sudo su - deploy <<CLEANDEPLOYAFTER
    if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
      . /root/instalador_single_oficial/tools/path_node_deploy.sh
    else
    export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
    if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
      export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
    elif [ -d /usr/local/n/versions/node ]; then
      _mf_nv=\$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
      if [ -n "\$_mf_nv" ] && [ -d "/usr/local/n/versions/node/\$_mf_nv/bin" ]; then
        export PATH="/usr/local/n/versions/node/\$_mf_nv/bin:\$PATH"
      fi
    fi
    if ! command -v npm >/dev/null 2>&1; then
      echo "ERRO: npm não encontrado no PATH do deploy."
      exit 1
    fi
    fi
    # Limpar processos desta instância se existirem
    pm2 stop ${empresa}-transcricao 2>/dev/null || true
    pm2 delete ${empresa}-transcricao 2>/dev/null || true
    pm2 stop transc-${empresa} 2>/dev/null || true
    pm2 delete transc-${empresa} 2>/dev/null || true
    pm2 save --force 2>/dev/null || true
CLEANDEPLOYAFTER
    
    printf "${GREEN} >> Processos PM2 parados. Agora vamos atualizar o main.py e iniciar o PM2 corretamente como DEPLOY.${WHITE}\n"
    echo
    sleep 2
    
    # Verificar e corrigir a porta no main.py novamente (caso o script tenha sobrescrito)
    # IMPORTANTE: Esta verificação é CRÍTICA - o script pode ter feito git checkout/reset
    banner
    printf "${WHITE} >> Verificando e corrigindo configuração final da porta...\n"
    printf "${YELLOW} >> (O script pode ter restaurado o main.py do repositório)${WHITE}\n"
    echo
    
    local main_py="/home/deploy/${empresa}/api_transcricao/main.py"
    if [ -f "$main_py" ]; then
      # Verificar qual porta está configurada atualmente
      current_port=$(grep -oP "port\s*=\s*\K\d+" "$main_py" | head -1 || echo "")
      
      if [ -n "$current_port" ]; then
        printf "${WHITE} >> Porta atual encontrada no main.py: ${YELLOW}${current_port}${WHITE}\n"
        printf "${WHITE} >> Porta esperada: ${GREEN}${porta_transcricao}${WHITE}\n"
      fi
      
      if grep -q "port=${porta_transcricao}\|port = ${porta_transcricao}" "$main_py"; then
        printf "${GREEN} >> ✓ Porta ${porta_transcricao} confirmada no main.py${WHITE}\n"
      else
        printf "${RED} >> ✗ ERRO: Porta não está correta no main.py!${WHITE}\n"
        printf "${RED} >> Porta encontrada: ${current_port:-'NÃO ENCONTRADA'}${WHITE}\n"
        printf "${RED} >> Porta esperada: ${porta_transcricao}${WHITE}\n"
        printf "${YELLOW} >> Corrigindo agora...${WHITE}\n"
        
        # Corrigir usando Python novamente
        python3 <<PYTHON_FIX
import re
import sys
import os
import pwd
import grp

file_path = "$main_py"
new_port = "$porta_transcricao"

try:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    original_content = content
    
    def replace_port(match):
        original = match.group(0)
        if ' = ' in original:
            return f"port = {new_port}"
        else:
            return f"port={new_port}"
    
    # Substituir TODAS as ocorrências de porta
    content = re.sub(r"port\s*=\s*\d+", replace_port, content)
    content = re.sub(r"porta\s+\d+", f"porta {new_port}", content, flags=re.IGNORECASE)
    content = re.sub(r"Servidor iniciado na porta \d+", f"Servidor iniciado na porta {new_port}", content, flags=re.IGNORECASE)
    content = re.sub(r"Server started on port \d+", f"Server started on port {new_port}", content, flags=re.IGNORECASE)
    
    if content != original_content:
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        # Ajustar permissões para deploy
        try:
            deploy_uid = pwd.getpwnam('deploy').pw_uid
            deploy_gid = grp.getgrnam('deploy').gr_gid
            os.chown(file_path, deploy_uid, deploy_gid)
            os.chmod(file_path, 0o644)
        except:
            pass  # Se não conseguir ajustar permissões, continua
        print(f"SUCCESS: Porta corrigida para {new_port}")
        sys.exit(0)
    else:
        print(f"WARNING: Nenhuma alteração necessária")
        sys.exit(0)
except Exception as e:
    print(f"ERROR: {str(e)}")
    sys.exit(1)
PYTHON_FIX
        
        # Garantir permissões após Python (mesmo se não modificou)
        chown deploy:deploy "$main_py" 2>/dev/null || true
        chmod 644 "$main_py" 2>/dev/null || true
        
        # Fallback para sed se Python falhar - substituir QUALQUER porta de 4 dígitos
        if [ $? -ne 0 ]; then
          printf "${YELLOW} >> Tentando correção com sed...${WHITE}\n"
          sed -i "s|port=[0-9][0-9][0-9][0-9]|port=${porta_transcricao}|g" "$main_py" 2>/dev/null || true
          sed -i "s|port = [0-9][0-9][0-9][0-9]|port = ${porta_transcricao}|g" "$main_py" 2>/dev/null || true
          sed -i "s|porta [0-9][0-9][0-9][0-9]|porta ${porta_transcricao}|g" "$main_py" 2>/dev/null || true
          # Garantir permissões após modificar
          chown deploy:deploy "$main_py" 2>/dev/null || true
          chmod 644 "$main_py" 2>/dev/null || true
        fi
        
        # Verificar novamente
        sleep 1
        if grep -q "port=${porta_transcricao}\|port = ${porta_transcricao}" "$main_py"; then
          printf "${GREEN} >> ✓ Porta corrigida com sucesso!${WHITE}\n"
          # Garantir permissões finais
          chown deploy:deploy "$main_py" 2>/dev/null || true
          chmod 644 "$main_py" 2>/dev/null || true
        else
          printf "${RED} >> ✗ ERRO CRÍTICO: Não foi possível corrigir automaticamente${WHITE}\n"
          printf "${YELLOW} >> Por favor, edite manualmente o arquivo: $main_py${WHITE}\n"
          printf "${YELLOW} >> Procure por 'app.run' e altere a porta para: ${porta_transcricao}${WHITE}\n"
          printf "${RED} >> Não será possível continuar sem corrigir a porta!${WHITE}\n"
        fi
      fi
      
      # Mostrar a linha atual do app.run para confirmação
      printf "${WHITE} >> Configuração atual do app.run:${WHITE}\n"
      grep "app.run" "$main_py" | head -1 || printf "${YELLOW} >> Não encontrado${WHITE}\n"
      
      # Verificação final antes de prosseguir
      if ! grep -q "port=${porta_transcricao}\|port = ${porta_transcricao}" "$main_py"; then
        printf "${RED} >> ERRO: Porta ainda não está correta após todas as tentativas!${WHITE}\n"
        printf "${RED} >> Abortando instalação para evitar conflitos.${WHITE}\n"
        return 1
      fi
      
      # Garantir permissões finais antes de iniciar PM2
      printf "${WHITE} >> Ajustando permissões finais dos arquivos para deploy...${WHITE}\n"
      chown deploy:deploy "$main_py" 2>/dev/null || true
      chmod 644 "$main_py" 2>/dev/null || true
      if [ -f "$main_py_backup_protected" ]; then
        chown deploy:deploy "$main_py_backup_protected" 2>/dev/null || true
        chmod 644 "$main_py_backup_protected" 2>/dev/null || true
      fi
      # Ajustar permissões do diretório também
      chown deploy:deploy "/home/deploy/${empresa}/api_transcricao" -R 2>/dev/null || true
      printf "${GREEN} >> ✓ Permissões ajustadas para deploy${WHITE}\n"
      echo
      
      printf "${GREEN} >> ✓ main.py atualizado com sucesso para porta ${porta_transcricao}${WHITE}\n"
      echo
      sleep 2
      
      # Agora sim, iniciar o PM2 DEPOIS de tudo estar instalado e o main.py estar correto
      banner
      printf "${WHITE} >> Iniciando PM2 com a porta correta (${porta_transcricao})...${WHITE}\n"
      printf "${GREEN} >> NOTA: A transcrição roda como DEPLOY (mesmo que backend e frontend)${WHITE}\n"
      echo
      
      # Iniciar o PM2 como usuário DEPLOY (consistente com backend e frontend)
      sudo su - deploy <<STARTPM2CORRECT
      if [ -f /root/instalador_single_oficial/tools/path_node_deploy.sh ]; then
        . /root/instalador_single_oficial/tools/path_node_deploy.sh
      else
      export PATH="/usr/local/bin:/usr/bin:\${PATH:-}"
      if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
        export PATH="/usr/local/n/versions/node/20.19.4/bin:\$PATH"
      elif [ -d /usr/local/n/versions/node ]; then
        _mf_nv=\$(ls -1 /usr/local/n/versions/node 2>/dev/null | sort -V | tail -1)
        if [ -n "\$_mf_nv" ] && [ -d "/usr/local/n/versions/node/\$_mf_nv/bin" ]; then
          export PATH="/usr/local/n/versions/node/\$_mf_nv/bin:\$PATH"
        fi
      fi
      if ! command -v npm >/dev/null 2>&1; then
        echo "ERRO: npm não encontrado no PATH do deploy."
        exit 1
      fi
      fi
      
      TRANSC_DIR="/home/deploy/${empresa}/api_transcricao"
      MAIN_PY_PATH="\$TRANSC_DIR/main.py"
      
      if [ ! -f "\$MAIN_PY_PATH" ]; then
        printf "${RED} >> ERRO: Arquivo main.py não encontrado em \$MAIN_PY_PATH${WHITE}\n"
        exit 1
      fi
      
      # Mudar para o diretório correto
      cd "\$TRANSC_DIR" || {
        printf "${RED} >> ERRO: Não foi possível acessar o diretório \$TRANSC_DIR${WHITE}\n"
        exit 1
      }
      
      # Limpar cache do Python antes de iniciar
      printf "${WHITE} >> Limpando cache do Python...${WHITE}\n"
      find "\$TRANSC_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
      find "\$TRANSC_DIR" -name "*.pyc" -delete 2>/dev/null || true
      find "\$TRANSC_DIR" -name "*.pyo" -delete 2>/dev/null || true
      
      # Instalar dependências Python
      printf "${WHITE} >> Instalando dependências Python...${WHITE}\n"
      
      # Determinar comando pip a usar
      PIP_CMD="pip3"
      if ! command -v pip3 &>/dev/null; then
        if python3 -m pip --version &>/dev/null; then
          PIP_CMD="python3 -m pip"
          printf "${GREEN} >> Usando python3 -m pip como alternativa${WHITE}\n"
        else
          printf "${YELLOW} >> AVISO: pip3 não está disponível. Tentando continuar...${WHITE}\n"
        fi
      fi
      
      # Obter o caminho do site-packages do usuário
      USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
      
      if [ -f "\$TRANSC_DIR/requirements.txt" ]; then
        printf "${GREEN} >> Arquivo requirements.txt encontrado. Instalando dependências...${WHITE}\n"
        # Tentar com --user primeiro
        INSTALL_OUTPUT=\$(\$PIP_CMD install --user -r "\$TRANSC_DIR/requirements.txt" 2>&1)
        INSTALL_STATUS=\$?
        if [ \$INSTALL_STATUS -eq 0 ] || echo "\$INSTALL_OUTPUT" | grep -q "already satisfied\|Requirement already satisfied"; then
          printf "${GREEN} >> ✓ Dependências instaladas${WHITE}\n"
        elif echo "\$INSTALL_OUTPUT" | grep -q "externally-managed-environment"; then
          printf "${YELLOW} >> Ambiente externally-managed detectado. Usando --break-system-packages...${WHITE}\n"
          \$PIP_CMD install --user --break-system-packages -r "\$TRANSC_DIR/requirements.txt" 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
          printf "${GREEN} >> ✓ Dependências instaladas${WHITE}\n"
        else
          printf "${YELLOW} >> Tentando com --break-system-packages...${WHITE}\n"
          \$PIP_CMD install --user --break-system-packages -r "\$TRANSC_DIR/requirements.txt" 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
          printf "${GREEN} >> ✓ Dependências instaladas${WHITE}\n"
        fi
      else
        printf "${YELLOW} >> Arquivo requirements.txt não encontrado. Instalando dependências básicas...${WHITE}\n"
        # Tentar com --user primeiro
        INSTALL_OUTPUT=\$(\$PIP_CMD install --user flask flask-cors requests 2>&1)
        INSTALL_STATUS=\$?
        if [ \$INSTALL_STATUS -eq 0 ] || echo "\$INSTALL_OUTPUT" | grep -q "already satisfied\|Requirement already satisfied"; then
          printf "${GREEN} >> ✓ Dependências básicas instaladas${WHITE}\n"
        elif echo "\$INSTALL_OUTPUT" | grep -q "externally-managed-environment"; then
          printf "${YELLOW} >> Ambiente externally-managed detectado. Usando --break-system-packages...${WHITE}\n"
          \$PIP_CMD install --user --break-system-packages flask flask-cors requests 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
          printf "${GREEN} >> ✓ Dependências básicas instaladas (Flask, Flask-CORS, Requests)${WHITE}\n"
        else
          printf "${YELLOW} >> Tentando com --break-system-packages...${WHITE}\n"
          \$PIP_CMD install --user --break-system-packages flask flask-cors requests 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
          printf "${GREEN} >> ✓ Dependências básicas instaladas${WHITE}\n"
        fi
      fi
      
      # Verificar se Flask está instalado e acessível
      if python3 -c "import flask" 2>/dev/null; then
        printf "${GREEN} >> ✓ Flask verificado e disponível${WHITE}\n"
      else
        printf "${RED} >> ERRO: Flask não está acessível! Tentando instalar novamente...${WHITE}\n"
        INSTALL_OUTPUT=\$(\$PIP_CMD install --user --force-reinstall flask 2>&1)
        INSTALL_STATUS=\$?
        if [ \$INSTALL_STATUS -ne 0 ] || echo "\$INSTALL_OUTPUT" | grep -q "externally-managed-environment"; then
          printf "${YELLOW} >> Usando --break-system-packages...${WHITE}\n"
          \$PIP_CMD install --user --break-system-packages --force-reinstall flask 2>&1 || true
        fi
        # Tentar novamente após reinstalar
        if python3 -c "import flask" 2>/dev/null; then
          printf "${GREEN} >> ✓ Flask instalado com sucesso${WHITE}\n"
        else
          printf "${RED} >> ERRO: Ainda não foi possível importar Flask!${WHITE}\n"
        fi
      fi
      echo
      
      # Verificar que a porta está correta no main.py
      final_port=\$(grep -oP "port\s*=\s*\K\d+" "\$MAIN_PY_PATH" | head -1 || echo "")
      if [ "\$final_port" != "${porta_transcricao}" ]; then
        printf "${RED} >> ERRO: Porta no arquivo (\$final_port) não corresponde à porta esperada (${porta_transcricao})!${WHITE}\n"
        exit 1
      fi
      printf "${GREEN} >> ✓ Porta ${porta_transcricao} confirmada no main.py${WHITE}\n"
      echo
      
      # Parar qualquer processo PM2 desta instância que possa existir
      pm2 stop ${empresa}-transcricao 2>/dev/null || true
      pm2 delete ${empresa}-transcricao 2>/dev/null || true
      pm2 stop transc-${empresa} 2>/dev/null || true
      pm2 delete transc-${empresa} 2>/dev/null || true
      
      # Obter o caminho do site-packages do usuário e configurar PYTHONPATH
      USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
      if [ -n "\$USER_SITE" ] && [ -d "\$USER_SITE" ]; then
        export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
        printf "${GREEN} >> PYTHONPATH configurado: \$USER_SITE${WHITE}\n"
      fi
      
      # Determinar comando pip a usar
      PIP_CMD="pip3"
      if ! command -v pip3 &>/dev/null; then
        if python3 -m pip --version &>/dev/null; then
          PIP_CMD="python3 -m pip"
        fi
      fi
      
      # Verificar Flask antes de iniciar
      if ! python3 -c "import flask" 2>/dev/null; then
        printf "${RED} >> ERRO: Flask não está disponível! Instalando...${WHITE}\n"
        INSTALL_OUTPUT=\$(\$PIP_CMD install --user flask 2>&1)
        INSTALL_STATUS=\$?
        if [ \$INSTALL_STATUS -ne 0 ] || echo "\$INSTALL_OUTPUT" | grep -q "externally-managed-environment"; then
          printf "${YELLOW} >> Usando --break-system-packages...${WHITE}\n"
          \$PIP_CMD install --user --break-system-packages flask 2>&1 || true
        fi
        # Atualizar USER_SITE após instalação
        USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
        if [ -n "\$USER_SITE" ] && [ -d "\$USER_SITE" ]; then
          export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
        fi
      fi
      
      # Configurar PYTHONPATH antes de iniciar PM2
      if [ -n "\$USER_SITE" ] && [ -d "\$USER_SITE" ]; then
        export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
        printf "${GREEN} >> PYTHONPATH configurado: \$USER_SITE${WHITE}\n"
      fi
      
      # Verificar Flask uma última vez antes de iniciar
      if ! python3 -c "import flask" 2>/dev/null; then
        printf "${RED} >> ERRO CRÍTICO: Flask ainda não está disponível!${WHITE}\n"
        printf "${YELLOW} >> Tentando instalação final...${WHITE}\n"
        
        # Tentar via pip primeiro
        if [ -n "\$PIP_CMD" ] && command -v \$PIP_CMD &>/dev/null 2>&1; then
          \$PIP_CMD install --user --break-system-packages flask flask-cors requests 2>&1 | grep -v "already satisfied\|Requirement already satisfied" || true
        fi
        
        # Atualizar USER_SITE após instalação
        USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
        if [ -n "\$USER_SITE" ] && [ -d "\$USER_SITE" ]; then
          export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
        fi
        
        # Verificar novamente
        if ! python3 -c "import flask" 2>/dev/null; then
          printf "${RED} >> ERRO: Não foi possível instalar Flask via pip!${WHITE}\n"
          printf "${YELLOW} >> Por favor, execute manualmente: sudo apt-get install -y python3-flask python3-flask-cors${WHITE}\n"
          printf "${YELLOW} >> Ou: sudo apt-get install -y python3-pip && pip3 install --user flask flask-cors${WHITE}\n"
          printf "${RED} >> O PM2 será iniciado, mas falhará sem Flask instalado.${WHITE}\n"
        else
          printf "${GREEN} >> ✓ Flask instalado com sucesso!${WHITE}\n"
        fi
      fi
      
      # Criar script wrapper para garantir PYTHONPATH correto
      WRAPPER_SCRIPT="\$TRANSC_DIR/run_transcricao.sh"
      cat > "\$WRAPPER_SCRIPT" <<WRAPPEREOF
#!/bin/bash
cd "\$TRANSC_DIR"
# Configurar PYTHONPATH
USER_SITE=\$(python3 -m site --user-site 2>/dev/null || echo "")
if [ -n "\$USER_SITE" ] && [ -d "\$USER_SITE" ]; then
  export PYTHONPATH="\$USER_SITE:\$PYTHONPATH"
fi
# Executar o main.py
exec python3 "\$MAIN_PY_PATH"
WRAPPEREOF
      chmod +x "\$WRAPPER_SCRIPT"
      chown deploy:deploy "\$WRAPPER_SCRIPT" 2>/dev/null || true
      
      # Iniciar PM2 com o wrapper script
      printf "${GREEN} >> Iniciando PM2 com wrapper script (garante PYTHONPATH correto)...${WHITE}\n"
      pm2 start "\$WRAPPER_SCRIPT" --name ${empresa}-transcricao --interpreter bash --cwd "\$TRANSC_DIR"
      pm2 save --force
      
      # Verificar se iniciou corretamente
      sleep 3
        if pm2 list | grep -q "${empresa}-transcricao.*online"; then
          printf "${GREEN} >> ✓ Processo ${empresa}-transcricao está ONLINE${WHITE}\n"
          # Verificar logs para confirmar porta
          sleep 2
          pm2 logs ${empresa}-transcricao --lines 10 --nostream 2>/dev/null | grep -i "porta\|port\|Servidor iniciado" | head -3 || true
        else
          printf "${YELLOW} >> ⚠ Verifique o status: pm2 list${WHITE}\n"
          printf "${YELLOW} >> Verifique os logs: pm2 logs ${empresa}-transcricao${WHITE}\n"
        fi
STARTPM2CORRECT
      
    else
      printf "${YELLOW} >> AVISO: Arquivo main.py não encontrado${WHITE}\n"
    fi
    
    echo
    sleep 2
  else
    printf "${RED} >> Script não encontrado em: $script_path${WHITE}\n"
    printf "${YELLOW} >> A configuração da porta foi atualizada, mas o script de instalação não foi encontrado.${WHITE}\n"
    sleep 2
  fi
  
  # Salvar a porta da transcrição no arquivo de variáveis da instância
  if [ -n "${ARQUIVO_VARIAVEIS_INSTANCIA:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_INSTANCIA}" ]; then
    banner
    printf "${WHITE} >> Salvando porta da transcrição no arquivo de variáveis...\n"
    echo
    
    # Verificar se já existe porta_transcricao no arquivo
    if grep -q "^porta_transcricao=" "$ARQUIVO_VARIAVEIS_INSTANCIA"; then
      # Atualizar porta existente
      sed -i "s|^porta_transcricao=.*|porta_transcricao=${porta_transcricao}|" "$ARQUIVO_VARIAVEIS_INSTANCIA"
      printf "${GREEN} >> Porta da transcrição atualizada no arquivo de variáveis: ${porta_transcricao}${WHITE}\n"
    else
      # Adicionar porta_transcricao se não existir
      echo "" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
      echo "# Porta do serviço de transcrição de áudio" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
      echo "porta_transcricao=${porta_transcricao}" >> "$ARQUIVO_VARIAVEIS_INSTANCIA"
      printf "${GREEN} >> Porta da transcrição salva no arquivo de variáveis: ${porta_transcricao}${WHITE}\n"
    fi
    
    printf "${GREEN} >> Arquivo: ${BLUE}$ARQUIVO_VARIAVEIS_INSTANCIA${WHITE}\n"
    echo
  sleep 2
  else
    printf "${YELLOW} >> AVISO: Não foi possível identificar o arquivo de variáveis para salvar a porta${WHITE}\n"
    printf "${YELLOW} >> A porta ${porta_transcricao} foi configurada, mas não foi salva no arquivo de variáveis${WHITE}\n"
    echo
  fi
  
  echo
  printf "${GREEN} >> Processo de instalação da transcrição finalizado!${WHITE}\n"
  printf "${GREEN} >> Porta configurada: ${BLUE}${porta_transcricao}${WHITE}\n"
  printf "${GREEN} >> Instância: ${BLUE}${empresa}${WHITE}\n"
  echo
  
  # Verificar se Flask está realmente instalado
  if ! sudo su - deploy -c "python3 -c 'import flask'" 2>/dev/null; then
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    printf "${RED} >> ATENÇÃO: Flask não está instalado!${WHITE}\n"
    printf "${RED}══════════════════════════════════════════════════════════════════${WHITE}\n"
    echo
    printf "${YELLOW} >> Para instalar Flask manualmente, execute:${WHITE}\n"
    printf "${BLUE}    sudo apt-get update${WHITE}\n"
    printf "${BLUE}    sudo apt-get install -y python3-pip python3-flask python3-flask-cors${WHITE}\n"
    echo
    printf "${YELLOW} >> Ou se preferir usar pip:${WHITE}\n"
    printf "${BLUE}    sudo apt-get install -y python3-pip${WHITE}\n"
    printf "${BLUE}    pip3 install --user --break-system-packages flask flask-cors requests${WHITE}\n"
    echo
    printf "${YELLOW} >> Após instalar, reinicie o serviço:${WHITE}\n"
    printf "${BLUE}    sudo su - deploy -c 'pm2 restart ${empresa}-transcricao'${WHITE}\n"
    echo
  else
    printf "${GREEN} >> ✓ Flask está instalado e disponível${WHITE}\n"
  fi
  
  printf "${YELLOW} >> IMPORTANTE: Verifique se o serviço está rodando corretamente${WHITE}\n"
  printf "${YELLOW} >> Use: pm2 list (para ver processos)${WHITE}\n"
  printf "${YELLOW} >> Use: pm2 logs ${empresa}-transcricao (para ver logs)${WHITE}\n"
  printf "${YELLOW} >> Use: lsof -i:${porta_transcricao} (para verificar a porta)${WHITE}\n"
  echo
  printf "${WHITE} >> Pressione Enter para voltar ao menu...${WHITE}\n"
  read -r
}

# ================================================================
# GERENCIAMENTO, INSTALAÇÃO E DESINSTALAÇÃO DA API OFICIAL
# ================================================================

# Helper para localizar container da API Oficial
mf_localizar_container_apioficial() {
  local emp="${1:-amanda}"
  local c
  c=$(docker ps --format '{{.Names}}' | grep -E "^${emp}_apioficial" | head -n 1)
  [ -z "$c" ] && c=$(docker ps --format '{{.Names}}' | grep -E "${emp}.*oficial" | head -n 1)
  [ -z "$c" ] && c=$(docker ps -a --format '{{.Names}}' | grep -E "^${emp}_apioficial" | head -n 1)
  [ -z "$c" ] && c=$(docker ps -a --format '{{.Names}}' | grep -E "${emp}.*oficial" | head -n 1)
  printf '%s' "$c"
}

# Menu de Gerenciamento da API Oficial
menu_gerenciar_api_oficial() {
  while true; do
    selecionar_instancia_atualizar "Instalar ou Gerenciar API Oficial" || return 0
    local emp="${empresa:-amanda}"
    local app_dir="/home/deploy/${emp}"
    local compose_dir
    compose_dir=$(localizar_diretorio_compose "${app_dir}")

    # Identificar status da API Oficial
    local status_texto="${RED}Não Instalada${WHITE}"
    local modo_execucao="Nenhum"
    local container_id
    container_id=$(docker ps --format '{{.Names}}' | grep -E "^${emp}_apioficial" | head -n 1)
    [ -z "$container_id" ] && container_id=$(docker ps --format '{{.Names}}' | grep -E "${emp}.*oficial" | head -n 1)

    if [ -n "$container_id" ]; then
      status_texto="${GREEN}Ativa em Contêiner Docker (${container_id})${WHITE}"
      modo_execucao="Docker"
    elif docker ps -a --format '{{.Names}}' | grep -qE "^${emp}_apioficial|${emp}.*oficial"; then
      local c_parado
      c_parado=$(docker ps -a --format '{{.Names}}' | grep -E "^${emp}_apioficial|${emp}.*oficial" | head -n 1)
      status_texto="${YELLOW}Parada em Contêiner Docker (${c_parado})${WHITE}"
      modo_execucao="Docker"
    elif sudo su - deploy -c "pm2 jlist 2>/dev/null | grep -qF 'api_oficial_${emp}'" 2>/dev/null; then
      status_texto="${YELLOW}Processo PM2 Legado Detectado (Recomendado migrar para Docker)${WHITE}"
      modo_execucao="PM2 (Legado)"
    elif [ -d "${compose_dir}/api_oficial" ] || [ -d "/home/deploy/${emp}/api_oficial" ]; then
      status_texto="${YELLOW}Arquivos presentes (Serviço inativo)${WHITE}"
      modo_execucao="Inativo"
    fi

    # Obter porta real do Host da API Oficial
    local porta_oficial=""
    if [ -n "$container_id" ]; then
      porta_oficial=$(docker port "$container_id" 6000/tcp 2>/dev/null | head -n 1 | awk -F: '{print $NF}' | tr -d '\r')
    fi
    if [ -z "$porta_oficial" ] && [ -f "${compose_dir}/.env" ]; then
      porta_oficial=$(grep -m1 '^PORT_APIOFICIAL=' "${compose_dir}/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
    fi
    if [ -z "$porta_oficial" ] && [ -f "${compose_dir}/backend/.env" ]; then
      porta_oficial=$(grep -m1 '^PORT_APIOFICIAL=' "${compose_dir}/backend/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
    fi
    [ -z "$porta_oficial" ] && porta_oficial="${PORT_APIOFICIAL:-6000}"

    # Obter URL configurada
    local url_oficial="${subdominio_oficial:-Não configurada}"
    if [ -f "${compose_dir}/.env" ]; then
      local u_env
      u_env=$(grep -m1 '^URL_API_OFICIAL=' "${compose_dir}/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
      [ -n "$u_env" ] && url_oficial="$u_env"
    fi

    banner
    printf "   ${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
    printf "   ${PURPLE}║${WHITE}             INSTALAR OU GERENCIAR API OFICIAL                ${PURPLE}║${WHITE}\n"
    printf "   ${PURPLE}║${WHITE}           (WhatsApp Meta Cloud API - Stack AMANDA)           ${PURPLE}║${WHITE}\n"
    printf "   ${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
    printf "   ${WHITE}Instância:       ${GREEN}%s${WHITE}\n" "$emp"
    printf "   ${WHITE}Status Atual:    %b\n" "$status_texto"
    printf "   ${WHITE}Modo:            ${CYAN}%s${WHITE}\n" "$modo_execucao"
    printf "   ${WHITE}Porta HTTP:      ${YELLOW}%s${WHITE}\n" "$porta_oficial"
    printf "   ${WHITE}URL Configurada: ${CYAN}%s${WHITE}\n\n" "$url_oficial"
    printf "   ${WHITE}Selecione a ação desejada:\n"
    printf "     [${BLUE}1${WHITE}] Instalar API Oficial (Contêiner Docker - Padrão AMANDA)\n"
    printf "     [${BLUE}2${WHITE}] Atualizar API Oficial (Contêiner Docker)\n"
    printf "     [${BLUE}3${WHITE}] Status Detalhado e Teste de Conexão\n"
    printf "     [${BLUE}4${WHITE}] Iniciar / Reiniciar API Oficial (Docker)\n"
    printf "     [${BLUE}5${WHITE}] Parar API Oficial (Docker)\n"
    printf "     [${BLUE}6${WHITE}] Ver Logs em Tempo Real da API Oficial (Docker)\n"
    printf "     [${BLUE}7${WHITE}] Sincronizar Integração com Backend AMANDA\n"
    printf "     [${BLUE}8${WHITE}] Configurar Nginx e Emitir Certificado SSL para API Oficial\n"
    printf "     [${BLUE}9${WHITE}] Desinstalar API Oficial\n"
    printf "     [${BLUE}0${WHITE}] Voltar ao Menu Principal\n\n"
    printf "${WHITE}   Escolha uma opção: ${PURPLE}"
    read -r op_oficial
    case "$op_oficial" in
      1) instalar_api_oficial_docker "$emp" "$compose_dir" ;;
      2) atualizar_api_oficial_gerenciador "$emp" "$compose_dir" ;;
      3) status_api_oficial "$emp" "$compose_dir" "$porta_oficial" "$url_oficial" ;;
      4) iniciar_reiniciar_api_oficial "$emp" "$compose_dir" ;;
      5) parar_api_oficial "$emp" "$compose_dir" ;;
      6) logs_api_oficial "$emp" "$compose_dir" ;;
      7) sincronizar_integracao_backend_api_oficial "$emp" "$compose_dir" "$porta_oficial" "$url_oficial" ;;
      8) configurar_nginx_e_ssl_api_oficial "$emp" "$porta_oficial" "$url_oficial" ;;
      9) desinstalar_api_oficial "$emp" "$compose_dir" ;;
      0) return 0 ;;
      *) printf "${RED}Opção inválida!${WHITE}\n"; sleep 2 ;;
    esac
  done
}

# 1. Instalação em Contêiner Docker integrada à Stack AMANDA
instalar_api_oficial_docker() {
  local emp="${1:-${empresa:-amanda}}"
  local compose_dir="${2:-}"
  local app_dir="/home/deploy/${emp}"
  [ -z "$compose_dir" ] && compose_dir=$(localizar_diretorio_compose "${app_dir}")

  banner
  printf "   ${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "   ${PURPLE}║${WHITE}     INSTALAÇÃO DA API OFICIAL EM CONTÊINER DOCKER            ${PURPLE}║${WHITE}\n"
  printf "   ${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
  printf "   ${WHITE}Instância alvo: ${GREEN}%s${WHITE}\n" "$emp"
  printf "   ${WHITE}Diretório Compose: ${BLUE}%s${WHITE}\n\n" "$compose_dir"

  # 1.1 Verificar/Obter código-fonte da API Oficial
  if [ ! -d "${compose_dir}/api_oficial" ]; then
    if [ -d "/home/deploy/${emp}/api_oficial" ]; then
      printf "${PURPLE} >> Vinculando diretório api_oficial para o compose_dir...${WHITE}\n"
      ln -sfn "/home/deploy/${emp}/api_oficial" "${compose_dir}/api_oficial" 2>/dev/null || true
    elif [ -d "${app_dir}/.git" ]; then
      printf "${WHITE} >> Restaurando diretório api_oficial do repositório Git...${WHITE}\n"
      git -C "${app_dir}" checkout -f HEAD -- api_oficial 2>/dev/null || true
    fi
  fi

  if [ ! -d "${compose_dir}/api_oficial" ]; then
    printf "${RED} >> ERRO: Diretório api_oficial não encontrado em ${compose_dir}/api_oficial!${WHITE}\n"
    printf "${YELLOW} >> Verifique se o repositório da AMANDA foi clonado corretamente.${WHITE}\n"
    sleep 3
    return 1
  fi

  # Limpar qualquer processo PM2 legado para liberar a porta e garantir 100% Docker
  sudo su - deploy -c "pm2 delete api_oficial_${emp} 2>/dev/null || pm2 delete api_oficial 2>/dev/null || true; pm2 save 2>/dev/null || true" 2>/dev/null || true

  # 1.2 Definir Porta Host para a API Oficial
  local sugestao_porta="${PORT_APIOFICIAL:-6000}"
  local porta_atual_uso=""
  porta_atual_uso=$(proxima_porta_livre "$sugestao_porta" "PORT_APIOFICIAL")
  if [ "$porta_atual_uso" != "$sugestao_porta" ]; then
    local container_atual
    container_atual=$(docker ps --format '{{.Names}}' | grep -E "^${emp}_apioficial" | head -n 1)
    if [ -z "$container_atual" ]; then
      sugestao_porta="$porta_atual_uso"
    fi
  fi

  printf "${WHITE} >> Informe a porta HTTP para a API Oficial [Padrão: ${YELLOW}${sugestao_porta}${WHITE}]: \n"
  read -r porta_escolhida
  porta_escolhida="${porta_escolhida:-$sugestao_porta}"
  while ! [[ "$porta_escolhida" =~ ^[0-9]+$ ]] || [ "$porta_escolhida" -lt 1024 ] || [ "$porta_escolhida" -gt 65535 ]; do
    printf "${RED} >> Porta inválida. Informe um valor numérico entre 1024 e 65535: ${WHITE}\n"
    read -r porta_escolhida
    porta_escolhida="${porta_escolhida:-$sugestao_porta}"
  done
  printf "${GREEN} >> Porta definida: ${BLUE}%s${WHITE}\n\n" "$porta_escolhida"

  # 1.3 Definir URL / Subdomínio
  local sugestao_url=""
  local host_ip
  host_ip=$(curl -s --max-time 6 http://checkip.amazonaws.com 2>/dev/null | tr -d '\r')
  [ -z "$host_ip" ] && host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [ -z "$host_ip" ] && host_ip="127.0.0.1"

  if [ -n "${subdominio_backend:-}" ] && ! echo "${subdominio_backend}" | grep -qE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
    local base_domain
    base_domain=$(echo "$subdominio_backend" | sed -E 's|^https?://||' | sed -E 's|^[^.]+\.||' | cut -d':' -f1 | cut -d'/' -f1)
    [ -n "$base_domain" ] && sugestao_url="https://oficial.${base_domain}"
  fi
  if [ -z "$sugestao_url" ]; then
    sugestao_url="http://${host_ip}:${porta_escolhida}"
  fi

  printf "${WHITE} >> Informe a URL ou Subdomínio da API Oficial [Padrão: ${YELLOW}${sugestao_url}${WHITE}]: \n"
  read -r url_escolhida
  url_escolhida="${url_escolhida:-$sugestao_url}"
  url_escolhida=$(echo "$url_escolhida" | tr -d '"\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  case "$url_escolhida" in
    http://*|https://*) ;;
    *) url_escolhida="https://${url_escolhida}" ;;
  esac
  url_escolhida="${url_escolhida%/}"
  printf "${GREEN} >> URL definida: ${BLUE}%s${WHITE}\n\n" "$url_escolhida"

  # 1.4 Obter credenciais reais do PostgreSQL a partir do backend/.env ou .env
  local db_pass_real=""
  local db_user_real="${emp}"
  if [ -f "${compose_dir}/backend/.env" ]; then
    db_pass_real=$(grep -m1 '^DB_PASS=' "${compose_dir}/backend/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r"' || true)
    local u_real
    u_real=$(grep -m1 '^DB_USER=' "${compose_dir}/backend/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r"' || true)
    [ -n "$u_real" ] && db_user_real="$u_real"
  elif [ -f "${compose_dir}/.env" ]; then
    db_pass_real=$(grep -m1 '^DB_PASS=' "${compose_dir}/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r"' || true)
  fi
  [ -z "$db_pass_real" ] && db_pass_real="${senha_deploy:-Acertitech13@}"

  printf "${PURPLE} >> Verificando e criando o banco de dados 'api_oficial' no PostgreSQL...${WHITE}\n"
  local pg_c
  pg_c=$(docker ps --format '{{.Names}}' | grep -E "^${emp}_postgres" | head -n 1)
  [ -z "$pg_c" ] && pg_c=$(docker ps --format '{{.Names}}' | grep -E "${emp}.*postgres" | head -n 1)
  [ -z "$pg_c" ] && pg_c=$(docker ps --format '{{.Names}}' | grep -E "postgres" | head -n 1)

  if [ -n "$pg_c" ]; then
    docker exec -e PGPASSWORD="${db_pass_real}" "$pg_c" psql -U "${db_user_real}" -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = 'api_oficial'" 2>/dev/null | grep -q 1 || \
      docker exec -e PGPASSWORD="${db_pass_real}" "$pg_c" psql -U "${db_user_real}" -d postgres -c "CREATE DATABASE api_oficial;" 2>/dev/null || \
      docker exec -e PGPASSWORD="${db_pass_real}" "$pg_c" psql -U "${db_user_real}" -d "${emp}" -c "CREATE DATABASE api_oficial;" 2>/dev/null || \
      docker exec "$pg_c" psql -U postgres -c "CREATE DATABASE api_oficial;" 2>/dev/null || true
    printf "${GREEN} >> Banco 'api_oficial' verificado no contêiner PostgreSQL (${pg_c})!${WHITE}\n"
  elif command -v psql >/dev/null 2>&1; then
    PGPASSWORD="${db_pass_real}" psql -h 127.0.0.1 -p "${PORT_DB:-5432}" -U "${db_user_real}" -d postgres -c "CREATE DATABASE api_oficial;" 2>/dev/null || true
    printf "${GREEN} >> Banco 'api_oficial' configurado via PostgreSQL local!${WHITE}\n"
  fi

  # 1.5 Assegurar Dockerfile, compatibilidade CommonJS (@nestjs/mapped-types@2.0.5) e pastas
  mkdir -p "${compose_dir}/api_oficial/public"
  touch "${compose_dir}/api_oficial/public/.gitkeep"
  for p_pkg in "${compose_dir}/api_oficial/package.json" "/home/deploy/${emp}/api_oficial/package.json" "/home/deploy/${emp}/${emp}/api_oficial/package.json"; do
    [ -f "$p_pkg" ] && sed -i 's|"@nestjs/mapped-types": "[^"]*"|"@nestjs/mapped-types": "2.0.5"|g' "$p_pkg" 2>/dev/null || true
  done
  for p_df in "${compose_dir}/api_oficial/Dockerfile" "/home/deploy/${emp}/api_oficial/Dockerfile" "/home/deploy/${emp}/${emp}/api_oficial/Dockerfile"; do
    [ -f "$p_df" ] && sed -i 's|prisma@5.14.0|prisma@5.14.0 @nestjs/mapped-types@2.0.5|g' "$p_df" 2>/dev/null || true
  done
  printf "${WHITE} >> Criando/atualizando Dockerfile da API Oficial (Node 20 + fix @nestjs/mapped-types CommonJS)...${WHITE}\n"
  cat << 'EOF_API_DF' > "${compose_dir}/api_oficial/Dockerfile"
FROM node:20-alpine
WORKDIR /app
RUN apk add --no-cache openssl
COPY package*.json ./
RUN sed -i 's/"@nestjs\/mapped-types": "[^"]*"/"@nestjs\/mapped-types": "2.0.5"/g' package.json 2>/dev/null || true
RUN npm install --production && npm install prisma@5.14.0 @nestjs/mapped-types@2.0.5
COPY . .
RUN mkdir -p /app/public
RUN npx prisma generate
EXPOSE 6000
CMD ["node", "dist/main.js"]
EOF_API_DF

  # 1.6 Configurar arquivo .env da API Oficial
  printf "${WHITE} >> Configurando arquivo .env da API Oficial...${WHITE}\n"
  cat <<EOF > "${compose_dir}/api_oficial/.env"
DATABASE_LINK=postgresql://${db_user_real}:${db_pass_real}@postgres:5432/api_oficial?schema=public
DATABASE_URL=postgres
DATABASE_PORT=5432
DATABASE_USER=${db_user_real}
DATABASE_PASSWORD=${db_pass_real}
DATABASE_NAME=api_oficial
PORT=6000
TOKEN_ADMIN=adminpro
NAME_ADMIN=SetupAutomatizado
EMAIL_ADMIN=admin@amanda.com.br
PASSWORD_ADMIN=${db_pass_real}
JWT_SECRET=${jwt_secret:-kZaOTd+YZpjRUyyuQUpigJaEMk4vcW4YOymKPZX0Ts8=}
JWT_REFRESH_SECRET=${jwt_refresh_secret:-kZaOTd+YZpjRUyyuQUpigJaEMk4vcW4YOymKPZX0Ts8=}
URL_BACKEND_MULT100=http://backend:8080
REDIS_URI=redis://redis:6379
URL_API_OFICIAL=${url_escolhida}
RABBITMQ_ENABLED_GLOBAL=false
TZ=America/Sao_Paulo
EOF
  chown -R deploy:deploy "${compose_dir}/api_oficial" 2>/dev/null || true
  chmod 600 "${compose_dir}/api_oficial/.env" 2>/dev/null || true

  # 1.7 Integrar api_oficial no docker-compose.yml
  if [ -f "${compose_dir}/docker-compose.yml" ]; then
    printf "${PURPLE} >> Integrando serviço api_oficial no docker-compose.yml...${WHITE}\n"
    if ! python3 - "${compose_dir}/docker-compose.yml" "${emp}" "${porta_escolhida}" "${db_pass_real}" "${db_user_real}" "${url_escolhida}" << 'PYINJECT'
import sys, re

compose_file = sys.argv[1]
proj = sys.argv[2]
port = sys.argv[3]
db_pass = sys.argv[4]
db_user = sys.argv[5] if len(sys.argv) > 5 else proj
url_escolhida = sys.argv[6]

with open(compose_file, "r", encoding="utf-8") as f:
    content = f.read()

# Remover bloco existente para evitar duplicatas
if "api_oficial:" in content:
    content = re.sub(r'\n[ ]{2}#?[^\n]*API OFICIAL[^\n]*\n[ ]{2}api_oficial:\n(?:[ ]{4,}.*\n)*', '\n', content)
    content = re.sub(r'^[ ]{2}api_oficial:\n(?:[ ]{4,}.*\n)*', '', content, flags=re.M)

# Identificar a rede dos serviços existentes
net_match = re.search(r'networks:\s*\n\s*-\s*([a-zA-Z0-9_-]+)', content)
net_name = net_match.group(1) if net_match else f"{proj}_net"

api_block = f"""
  # ==========================================================
  # 8. MICROSSERVIÇO: API OFICIAL (Meta WhatsApp Cloud API)
  # ==========================================================
  api_oficial:
    build:
      context: ./api_oficial
      dockerfile: Dockerfile
    container_name: {proj}_apioficial
    restart: always
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    environment:
      PORT: 6000
      DATABASE_LINK: postgresql://{db_user}:{db_pass}@postgres:5432/api_oficial?schema=public
      DATABASE_URL: postgres
      DATABASE_PORT: 5432
      DATABASE_USER: {db_user}
      DATABASE_PASSWORD: {db_pass}
      DATABASE_NAME: api_oficial
      NAME_ADMIN: SetupAutomatizado
      EMAIL_ADMIN: admin@amanda.com.br
      PASSWORD_ADMIN: {db_pass}
      JWT_SECRET: ${{JWT_SECRET:-kZaOTd+YZpjRUyyuQUpigJaEMk4vcW4YOymKPZX0Ts8=}}
      URL_BACKEND_MULT100: http://backend:8080
      REDIS_URI: redis://redis:6379
      TOKEN_ADMIN: adminpro
      URL_API_OFICIAL: ${{URL_API_OFICIAL:-}}
      RABBITMQ_ENABLED_GLOBAL: "false"
      TZ: America/Sao_Paulo
    ports:
      - "{port}:6000"
    networks:
      - {net_name}
"""

# Injetar URL_API_OFICIAL no servico backend se houver bloco environment
be_match = re.search(r'([ ]{2}backend:\n(?:[ ]{4,}.*\n)*)', content)
if be_match:
    be_block = be_match.group(1)
    if "environment:" in be_block and "URL_API_OFICIAL:" not in be_block:
        new_be_block = re.sub(
            r'([ ]{4}environment:\n)',
            r'\1      URL_API_OFICIAL: ${URL_API_OFICIAL:-' + url_escolhida + r'}\n      API_OFICIAL_URL: ${URL_API_OFICIAL:-' + url_escolhida + r'}\n      USE_WHATSAPP_OFICIAL: "true"\n      TOKEN_API_OFICIAL: "adminpro"\n',
            be_block,
            count=1
        )
        content = content.replace(be_block, new_be_block)

if re.search(r'\nvolumes:\s*\n', content):
    content = re.sub(r'\nvolumes:\s*\n', f"{api_block}\nvolumes:\n", content, count=1)
else:
    content = content.rstrip() + "\n" + api_block

with open(compose_file, "w", encoding="utf-8") as f:
    f.write(content)
PYINJECT
    then
      printf '%s\n' 'Falha ao integrar API Oficial no Compose.' >&2
      return 1
    fi
  fi

  # 1.8 Sincronizar variáveis no .env da AMANDA
  printf "${WHITE} >> Conectando API Oficial ao backend da AMANDA...${WHITE}\n"
  local env_files=(
    "${compose_dir}/.env"
    "${compose_dir}/backend/.env"
    "/home/deploy/${emp}/.env"
    "/home/deploy/${emp}/backend/.env"
    "/home/deploy/${emp}/${emp}/.env"
    "/home/deploy/${emp}/${emp}/backend/.env"
  )
  for env_f in "${env_files[@]}"; do
    if [ -f "$env_f" ]; then
      sincronizar_porta_env "PORT_APIOFICIAL" "${porta_escolhida}" "$env_f"
      sincronizar_porta_env "URL_API_OFICIAL" "${url_escolhida}" "$env_f" || return 1
      sincronizar_porta_env "API_OFICIAL_URL" "${url_escolhida}" "$env_f" || return 1
      sincronizar_porta_env "USE_WHATSAPP_OFICIAL" "true" "$env_f" || return 1
      sincronizar_porta_env "TOKEN_API_OFICIAL" "adminpro" "$env_f" || return 1
      sincronizar_porta_env "API_OFICIAL_TOKEN" "adminpro" "$env_f" || return 1
      chown deploy:deploy "$env_f" 2>/dev/null || true
      chmod 600 "$env_f" 2>/dev/null || true
    fi
  done

  if [ -n "${ARQUIVO_VARIAVEIS_USADO:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_USADO}" ]; then
    sincronizar_porta_env "subdominio_oficial" "${url_escolhida}" "${ARQUIVO_VARIAVEIS_USADO}" || return 1
    sincronizar_porta_env "PORT_APIOFICIAL" "${porta_escolhida}" "${ARQUIVO_VARIAVEIS_USADO}" || return 1
  fi

  # 1.9 Compilar e subir contêiner da API Oficial
  banner
  printf "${PURPLE} >> Construindo e iniciando o contêiner ${emp}_apioficial...${WHITE}\n"
  printf "${YELLOW} >> Esse processo pode levar de 1 a 3 minutos na primeira compilação...${WHITE}\n\n"
  (cd "${compose_dir}" && docker compose -p "${emp}" up -d --build api_oficial) || return 1
  sleep 6

  # 1.10 Executar migrações do Prisma no contêiner
  local c_oficial
  c_oficial=$(mf_container_servico "$emp" api_oficial) || return 1

  if [ -n "$c_oficial" ]; then
    printf "\n${PURPLE} >> Executando migrações do Prisma no contêiner ${c_oficial}...${WHITE}\n"
    docker exec "$c_oficial" npx prisma migrate deploy || return 1
    printf "${GREEN} >> Migrações e tabelas aplicadas com sucesso!${WHITE}\n"
  fi

  # 1.11 Recriar Backend AMANDA para aplicar novas variáveis de ambiente
  printf "${WHITE} >> Recriando e reiniciando backend AMANDA para estabelecer conexão com a API Oficial...${WHITE}\n"
  if [ -f "${compose_dir}/docker-compose.yml" ]; then
    (cd "${compose_dir}" && docker compose -p "${emp}" up -d --force-recreate backend 2>/dev/null || true)
  fi
  local be_c
  be_c=$(docker ps --format '{{.Names}}' | grep -E "^${emp}_backend" | head -n 1)
  [ -n "$be_c" ] && docker restart "$be_c" 2>/dev/null || true

  # 1.12 Configurar Nginx reverso e SSL com Certbot
  configurar_nginx_e_ssl_api_oficial "$emp" "$porta_escolhida" "$url_escolhida"

  # 1.13 Resumo da Instalação
  banner
  printf "   ${GREEN}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "   ${GREEN}║${WHITE}     API OFICIAL INSTALADA COM SUCESSO NO DOCKER!             ${GREEN}║${WHITE}\n"
  printf "   ${GREEN}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
  printf "   ${WHITE}Instância:          ${BLUE}%s${WHITE}\n" "$emp"
  printf "   ${WHITE}Contêiner Docker:   ${GREEN}%s${WHITE}\n" "${emp}_apioficial"
  printf "   ${WHITE}Porta Host:         ${YELLOW}%s${WHITE}\n" "$porta_escolhida"
  printf "   ${WHITE}URL API Oficial:    ${YELLOW}%s${WHITE}\n" "$url_escolhida"
  printf "   ${WHITE}Banco de Dados:     ${BLUE}api_oficial${WHITE}\n"
  printf "   ${WHITE}Token de Admin:     ${BLUE}adminpro${WHITE}\n"
  printf "   ${WHITE}Integrada à AMANDA: ${GREEN}SIM (USE_WHATSAPP_OFICIAL=true)${WHITE}\n\n"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "${emp}_apioficial|NAMES" || true
  echo
  printf "${WHITE}>> Pressione Enter para voltar ao menu de gerenciamento...${WHITE}\n"
  read -r
}

# 2. Atualizar API Oficial (Docker)
atualizar_api_oficial_gerenciador() {
  local emp="${1:-${empresa:-amanda}}"
  local compose_dir="${2:-}"
  local app_dir="/home/deploy/${emp}"
  [ -z "$compose_dir" ] && compose_dir=$(localizar_diretorio_compose "${app_dir}")

  banner
  printf "   ${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "   ${PURPLE}║${WHITE}           ATUALIZAR API OFICIAL (CONTÊINER DOCKER)           ${PURPLE}║${WHITE}\n"
  printf "   ${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
  printf "   ${WHITE}Instância: ${GREEN}%s${WHITE}\n\n" "$emp"

  # Parar qualquer processo PM2 legado para garantir 100% contêiner
  sudo su - deploy -c "pm2 delete api_oficial_${emp} 2>/dev/null || pm2 delete api_oficial 2>/dev/null || true; pm2 save 2>/dev/null || true" 2>/dev/null || true

  if [ -d "${app_dir}/.git" ]; then
    printf "${WHITE} >> Baixando atualizações do repositório Git...${WHITE}\n"
    sudo -u deploy git -C "${app_dir}" pull 2>/dev/null || true
  fi

  mkdir -p "${compose_dir}/api_oficial/public"
  touch "${compose_dir}/api_oficial/public/.gitkeep"
  if [ -f "${compose_dir}/api_oficial/package.json" ]; then
    sed -i 's|"@nestjs/mapped-types": "[^"]*"|"@nestjs/mapped-types": "2.0.5"|g' "${compose_dir}/api_oficial/package.json" 2>/dev/null || true
  fi
  cat << 'EOF_API_DF' > "${compose_dir}/api_oficial/Dockerfile"
FROM node:20-alpine
WORKDIR /app
RUN apk add --no-cache openssl
COPY package*.json ./
RUN sed -i 's/"@nestjs\/mapped-types": "[^"]*"/"@nestjs\/mapped-types": "2.0.5"/g' package.json 2>/dev/null || true
RUN npm install --production && npm install prisma@5.14.0 @nestjs/mapped-types@2.0.5
COPY . .
RUN mkdir -p /app/public
RUN npx prisma generate
EXPOSE 6000
CMD ["node", "dist/main.js"]
EOF_API_DF

  # Garantir serviço api_oficial no docker-compose.yml se não estiver
  if [ -f "${compose_dir}/docker-compose.yml" ] && ! grep -q "api_oficial:" "${compose_dir}/docker-compose.yml"; then
    printf "${WHITE} >> Integrando serviço api_oficial no docker-compose.yml...${WHITE}\n"
    instalar_api_oficial_docker "$emp" "$compose_dir"
    return $?
  fi

  printf "${PURPLE} >> Reconstruindo contêiner da API Oficial...${WHITE}\n"
  (cd "${compose_dir}" && docker compose -p "${emp}" up -d --build --force-recreate api_oficial) || return 1
  sleep 5

  printf "${WHITE} >> Executando migrações do banco de dados (Prisma)...${WHITE}\n"
  docker exec "${emp}_apioficial" npx prisma migrate deploy || return 1

  printf "\n${GREEN} >> API Oficial atualizada com sucesso no Docker!${WHITE}\n\n"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "${emp}_apioficial|NAMES" || true

  echo
  printf "${WHITE}>> Pressione Enter para continuar...${WHITE}\n"
  read -r
}

# 3. Status Detalhado e Teste de Conexão
status_api_oficial() {
  local emp="${1:-${empresa:-amanda}}"
  local compose_dir="${2:-}"
  local porta="${3:-6000}"
  local url="${4:-}"
  local app_dir="/home/deploy/${emp}"
  [ -z "$compose_dir" ] && compose_dir=$(localizar_diretorio_compose "${app_dir}")

  local c_oficial
  c_oficial=$(mf_localizar_container_apioficial "$emp")
  if [ -n "$c_oficial" ]; then
    local p_dock
    p_dock=$(docker port "$c_oficial" 6000/tcp 2>/dev/null | head -n 1 | awk -F: '{print $NF}' | tr -d '\r')
    [ -n "$p_dock" ] && porta="$p_dock"
  fi

  banner
  printf "   ${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "   ${PURPLE}║${WHITE}             STATUS E SAÚDE DA API OFICIAL                    ${PURPLE}║${WHITE}\n"
  printf "   ${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
  printf "   ${WHITE}Instância:         ${GREEN}%s${WHITE}\n" "$emp"
  printf "   ${WHITE}Porta configurada: ${YELLOW}%s${WHITE}\n" "$porta"
  printf "   ${WHITE}URL configurada:   ${CYAN}%s${WHITE}\n\n" "$url"

  printf "   ${CYAN}━━ [1] Status do Contêiner Docker ━━${WHITE}\n"
  if [ -n "$c_oficial" ]; then
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "$c_oficial|NAMES" || docker ps
  else
    printf "   ${YELLOW}Nenhum contêiner Docker ativo para a API Oficial (${emp}_apioficial).${WHITE}\n"
  fi
  echo

  if sudo su - deploy -c "pm2 jlist 2>/dev/null | grep -qF 'api_oficial'" 2>/dev/null; then
    printf "   ${YELLOW}━━ [Aviso Legado] Processo PM2 detectado no servidor ━━${WHITE}\n"
    sudo su - deploy -c "pm2 list | grep -E 'api_oficial|App name'" 2>/dev/null || true
    printf "   ${YELLOW}Recomendado migrar/reiniciar via Docker (Opção 1 ou 4).${WHITE}\n\n"
  fi

  printf "   ${CYAN}━━ [2] Teste de Porta Local (127.0.0.1:${porta}) ━━${WHITE}\n"
  if ss -tlnH 2>/dev/null | grep -qE ":${porta}([[:space:]]|$)"; then
    printf "   ${GREEN}✔ Porta ${porta} está em ESCUTA (LISTENING) no servidor.${WHITE}\n"
  elif netstat -tln 2>/dev/null | grep -qE ":${porta}[[:space:]]"; then
    printf "   ${GREEN}✔ Porta ${porta} está em ESCUTA (LISTENING) no servidor.${WHITE}\n"
  else
    printf "   ${RED}✘ Porta ${porta} NÃO está escutando no servidor.${WHITE}\n"
  fi
  echo

  printf "   ${CYAN}━━ [3] Teste HTTP Local ━━${WHITE}\n"
  local http_code
  http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:${porta}/" 2>/dev/null)
  http_code="${http_code:-000}"
  if [ "$http_code" != "000" ] && [ "$http_code" != "000000" ] && [ -n "$http_code" ]; then
    printf "   ${GREEN}✔ Resposta HTTP recebida: Código ${http_code}${WHITE}\n"
  else
    printf "   ${YELLOW}⚠ Sem resposta HTTP direta em http://127.0.0.1:${porta}/ (contêiner inativo ou inicializando).${WHITE}\n"
  fi
  echo

  printf "   ${CYAN}━━ [4] Integração com Backend AMANDA ━━${WHITE}\n"
  local use_oficial="false"
  if [ -f "${compose_dir}/backend/.env" ]; then
    use_oficial=$(grep -m1 '^USE_WHATSAPP_OFICIAL=' "${compose_dir}/backend/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  elif [ -f "${compose_dir}/.env" ]; then
    use_oficial=$(grep -m1 '^USE_WHATSAPP_OFICIAL=' "${compose_dir}/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
  fi
  if [ "$use_oficial" = "true" ]; then
    printf "   ${GREEN}✔ USE_WHATSAPP_OFICIAL está HABILITADO no Backend (true).${WHITE}\n"
  else
    printf "   ${YELLOW}⚠ USE_WHATSAPP_OFICIAL está DESABILITADO ou não definido (${use_oficial}).${WHITE}\n"
    printf "   ${WHITE}  (Use a Opção [7] no menu para sincronizar com o backend).${WHITE}\n"
  fi

  local be_c
  be_c=$(docker ps --format '{{.Names}}' | grep -E "^${emp}_backend" | head -n 1)
  if [ -n "$be_c" ]; then
    local url_be_ativa
    url_be_ativa=$(docker exec "$be_c" printenv URL_API_OFICIAL 2>/dev/null || true)
    if [ -n "$url_be_ativa" ]; then
      printf "   ${GREEN}✔ URL no Backend (em execução): ${CYAN}%s${WHITE}\n" "$url_be_ativa"
    else
      printf "   ${RED}✘ URL_API_OFICIAL NÃO carregada no contêiner do Backend!${WHITE}\n"
      printf "   ${YELLOW}  (Execute a Opção [7] no menu para sincronizar e recriar o backend).${WHITE}\n"
    fi
  fi
  echo

  printf "   ${CYAN}━━ [5] Teste de Certificado SSL e Nginx ━━${WHITE}\n"
  if [ -n "$url" ] && [[ "$url" == https://* ]]; then
    local ssl_test
    ssl_test=$(curl -s -I -o /dev/null -w "%{http_code}" --max-time 6 "$url" 2>/dev/null || echo "FAIL")
    if [ "$ssl_test" != "FAIL" ] && [ "$ssl_test" != "000" ] && [ "$ssl_test" != "000000" ]; then
      printf "   ${GREEN}✔ Certificado SSL válido e respondendo no domínio (HTTP %s).${WHITE}\n" "$ssl_test"
    else
      printf "   ${RED}✘ Falha ou certificado inválido ao acessar %s.${WHITE}\n" "$url"
      printf "   ${YELLOW}  (Execute a Opção [8] para emitir o certificado SSL pelo Nginx).${WHITE}\n"
    fi
  else
    printf "   ${WHITE}ℹ Teste ignorado (URL não usa HTTPS ou não definida: %s).${WHITE}\n" "${url:-Nenhuma}"
  fi

  echo
  printf "${WHITE}>> Pressione Enter para voltar ao menu...${WHITE}\n"
  read -r
}

# 4. Iniciar / Reiniciar API Oficial (Docker)
iniciar_reiniciar_api_oficial() {
  local emp="${1:-${empresa:-amanda}}"
  local compose_dir="${2:-}"
  local app_dir="/home/deploy/${emp}"
  [ -z "$compose_dir" ] && compose_dir=$(localizar_diretorio_compose "${app_dir}")

  # Parar e remover qualquer processo PM2 legado
  sudo su - deploy -c "pm2 delete api_oficial_${emp} 2>/dev/null || pm2 delete api_oficial 2>/dev/null || true; pm2 save 2>/dev/null || true" 2>/dev/null || true

  local c_oficial
  c_oficial=$(mf_localizar_container_apioficial "$emp")

  banner
  printf "${PURPLE} >> Reiniciando contêiner da API Oficial de [%s]...${WHITE}\n" "$emp"
  if [ -n "$c_oficial" ]; then
    docker restart "$c_oficial" 2>/dev/null || (cd "${compose_dir}" && docker compose -p "$emp" up -d api_oficial)
    printf "${GREEN} >> Contêiner ${c_oficial} reiniciado com sucesso!${WHITE}\n"
  elif [ -f "${compose_dir}/docker-compose.yml" ] && grep -q "api_oficial:" "${compose_dir}/docker-compose.yml" 2>/dev/null; then
    cd "${compose_dir}" && docker compose -p "$emp" up -d api_oficial
    printf "${GREEN} >> Serviço api_oficial iniciado no Docker Compose!${WHITE}\n"
  else
    printf "${YELLOW} >> Contêiner não encontrado. Executando instalação no Docker...${WHITE}\n"
    instalar_api_oficial_docker "$emp" "$compose_dir"
  fi
  sleep 2
}

# 5. Parar API Oficial (Docker)
parar_api_oficial() {
  local emp="${1:-${empresa:-amanda}}"
  local compose_dir="${2:-}"
  local app_dir="/home/deploy/${emp}"
  [ -z "$compose_dir" ] && compose_dir=$(localizar_diretorio_compose "${app_dir}")

  # Parar processo PM2 legado se existir
  sudo su - deploy -c "pm2 stop api_oficial_${emp} 2>/dev/null || pm2 stop api_oficial 2>/dev/null || true" 2>/dev/null || true

  local c_oficial
  c_oficial=$(mf_localizar_container_apioficial "$emp")

  banner
  printf "${YELLOW} >> Parando contêiner da API Oficial de [%s]...${WHITE}\n" "$emp"
  if [ -n "$c_oficial" ]; then
    docker stop "$c_oficial" 2>/dev/null || true
    printf "${GREEN} >> Contêiner ${c_oficial} parado com sucesso!${WHITE}\n"
  else
    printf "${YELLOW} >> Nenhum contêiner ativo encontrado.${WHITE}\n"
  fi
  sleep 2
}

# 6. Ver Logs em Tempo Real da API Oficial (Docker)
logs_api_oficial() {
  local emp="${1:-${empresa:-amanda}}"
  local compose_dir="${2:-}"
  local app_dir="/home/deploy/${emp}"
  [ -z "$compose_dir" ] && compose_dir=$(localizar_diretorio_compose "${app_dir}")

  local c_oficial
  c_oficial=$(mf_localizar_container_apioficial "$emp")

  banner
  printf "${PURPLE} >> Exibindo logs do contêiner da API Oficial de [%s] (CTRL+C para sair e voltar ao menu)...\n${WHITE}" "$emp"
  sleep 2

  if [ -n "$c_oficial" ]; then
    docker logs -f --tail=100 "$c_oficial"
  elif [ -f "${compose_dir}/docker-compose.yml" ] && grep -q "api_oficial:" "${compose_dir}/docker-compose.yml" 2>/dev/null; then
    cd "${compose_dir}" && docker compose -p "$emp" logs -f --tail=100 api_oficial
  else
    printf "${RED} >> Nenhum contêiner da API Oficial encontrado para exibir logs.${WHITE}\n"
    sleep 2
  fi
}

# 7. Sincronizar Integração com Backend AMANDA
sincronizar_integracao_backend_api_oficial() {
  local emp="${1:-${empresa:-amanda}}"
  local compose_dir="${2:-}"
  local porta="${3:-6000}"
  local url="${4:-}"
  local app_dir="/home/deploy/${emp}"
  [ -z "$compose_dir" ] && compose_dir=$(localizar_diretorio_compose "${app_dir}")

  banner
  printf "   ${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "   ${PURPLE}║${WHITE}       SINCRONIZAR INTEGRAÇÃO COM BACKEND AMANDA              ${PURPLE}║${WHITE}\n"
  printf "   ${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"

  if [ -z "$url" ] || [ "$url" = "Não configurada" ]; then
    printf "${WHITE} >> Informe a URL completa da API Oficial (ex.: https://oficial.dominio.com ou http://IP:${porta}): \n"
    read -r url
  fi

  # Sanitizar URL
  url=$(echo "$url" | tr -d '"\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  case "$url" in
    http://*|https://*) ;;
    *) url="https://${url}" ;;
  esac
  url="${url%/}"

  printf "${WHITE} >> Atualizando variáveis de ambiente no Backend AMANDA...${WHITE}\n"
  local env_files=(
    "${compose_dir}/.env"
    "${compose_dir}/backend/.env"
    "/home/deploy/${emp}/.env"
    "/home/deploy/${emp}/backend/.env"
    "/home/deploy/${emp}/${emp}/.env"
    "/home/deploy/${emp}/${emp}/backend/.env"
  )
  for env_f in "${env_files[@]}"; do
    if [ -f "$env_f" ]; then
      sincronizar_porta_env "PORT_APIOFICIAL" "${porta}" "$env_f"
      sincronizar_porta_env "URL_API_OFICIAL" "${url}" "$env_f" || return 1
      sincronizar_porta_env "API_OFICIAL_URL" "${url}" "$env_f" || return 1
      sincronizar_porta_env "USE_WHATSAPP_OFICIAL" "true" "$env_f" || return 1
      sincronizar_porta_env "TOKEN_API_OFICIAL" "adminpro" "$env_f" || return 1
      sincronizar_porta_env "API_OFICIAL_TOKEN" "adminpro" "$env_f" || return 1
      chown deploy:deploy "$env_f" 2>/dev/null || true
      chmod 600 "$env_f" 2>/dev/null || true
    fi
  done

  # Injetar variáveis de ambiente no serviço backend dentro do docker-compose.yml se aplicável
  if [ -f "${compose_dir}/docker-compose.yml" ]; then
    python3 - "${compose_dir}/docker-compose.yml" "${url}" << 'PYEOF'
import sys, re
compose_file = sys.argv[1]
url_oficial = sys.argv[2]
with open(compose_file, "r", encoding="utf-8") as f:
    content = f.read()

be_match = re.search(r'([ ]{2}backend:\n(?:[ ]{4,}.*\n)*)', content)
if be_match:
    be_block = be_match.group(1)
    if "environment:" in be_block and "URL_API_OFICIAL:" not in be_block:
        new_be_block = re.sub(
            r'([ ]{4}environment:\n)',
            r'\1      URL_API_OFICIAL: ${URL_API_OFICIAL:-' + url_oficial + r'}\n      API_OFICIAL_URL: ${URL_API_OFICIAL:-' + url_oficial + r'}\n      USE_WHATSAPP_OFICIAL: "true"\n      TOKEN_API_OFICIAL: "adminpro"\n',
            be_block,
            count=1
        )
        content = content.replace(be_block, new_be_block)
        with open(compose_file, "w", encoding="utf-8") as f:
            f.write(content)
PYEOF
  fi

  printf "${WHITE} >> Recriando e reiniciando contêiner do Backend AMANDA para aplicar novas variáveis...${WHITE}\n"
  if [ -f "${compose_dir}/docker-compose.yml" ]; then
    (cd "${compose_dir}" && docker compose -p "${emp}" up -d --force-recreate backend 2>/dev/null || true)
  fi
  local be_c
  be_c=$(docker ps --format '{{.Names}}' | grep -E "^${emp}_backend" | head -n 1)
  [ -n "$be_c" ] && docker restart "$be_c" 2>/dev/null || true

  # Configurar Nginx e emitir Certificado SSL se for domínio FQDN
  configurar_nginx_e_ssl_api_oficial "$emp" "$porta" "$url"

  # Garantir criação do banco e tabelas do Prisma se o contêiner estiver no ar
  local c_oficial
  c_oficial=$(docker ps --format '{{.Names}}' | grep -E "^${emp}_apioficial" | head -n 1)
  if [ -n "$c_oficial" ]; then
    printf "${WHITE} >> Garantindo tabelas e migrações do Prisma no banco de dados...${WHITE}\n"
    docker exec "$c_oficial" npx prisma migrate deploy || return 1
  fi

  printf "\n${GREEN} >> Integração sincronizada com sucesso! O Backend agora reconhece a API Oficial.${WHITE}\n\n"
  printf "${WHITE}>> Pressione Enter para voltar ao menu...${WHITE}\n"
  read -r
}

# 8. Configurar Nginx e Emitir Certificado SSL para API Oficial
configurar_nginx_e_ssl_api_oficial() {
  local emp="${1:-${empresa:-amanda}}"
  local porta="${2:-6000}"
  local url="${3:-}"
  local app_dir="/home/deploy/${emp}"
  [ -z "$compose_dir" ] && compose_dir=$(localizar_diretorio_compose "${app_dir}")

  if [ -z "$url" ] || [ "$url" = "Não configurada" ]; then
    if [ -f "${compose_dir}/.env" ]; then
      url=$(grep -m1 '^URL_API_OFICIAL=' "${compose_dir}/.env" 2>/dev/null | cut -d '=' -f2- | tr -d '\r')
    fi
  fi
  if [ -z "$url" ] || [ "$url" = "Não configurada" ]; then
    printf "${WHITE} >> Informe a URL ou Subdomínio da API Oficial (ex.: https://oficial.dominio.com): \n"
    read -r url
  fi

  url=$(echo "$url" | tr -d '"\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  local hostname_alvo
  hostname_alvo=$(echo "${url}" | sed -E 's|^https?://||' | cut -d':' -f1 | cut -d'/' -f1)

  if [ -z "$hostname_alvo" ] || echo "$hostname_alvo" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    printf "${YELLOW} >> Configuração de Nginx/SSL ignorada para IP puro ou domínio inválido (${hostname_alvo}).${WHITE}\n"
    sleep 2
    return 0
  fi

  banner
  printf "   ${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "   ${PURPLE}║${WHITE}     CONFIGURAÇÃO DE NGINX E CERTIFICADO SSL (CERTBOT)        ${PURPLE}║${WHITE}\n"
  printf "   ${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
  printf "   ${WHITE}Subdomínio alvo:    ${CYAN}%s${WHITE}\n" "$hostname_alvo"
  printf "   ${WHITE}Porta do contêiner: ${YELLOW}%s${WHITE}\n\n" "$porta"

  printf "${PURPLE} >> Criando arquivo de configuração Nginx para ${hostname_alvo}...${WHITE}\n"
  cat > "/etc/nginx/sites-available/${emp}-oficial" << EOF_NGX
upstream oficial_${emp} {
    server 127.0.0.1:${porta};
    keepalive 32;
}

server {
  listen 80;
  server_name ${hostname_alvo};

  location / {
    proxy_pass http://oficial_${emp};
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_cache_bypass \$http_upgrade;
    proxy_buffering on;
  }
}
EOF_NGX

  ln -sf "/etc/nginx/sites-available/${emp}-oficial" /etc/nginx/sites-enabled/ 2>/dev/null || true
  if nginx -t 2>/dev/null; then
    systemctl reload nginx 2>/dev/null || true
    printf "${GREEN} >> Nginx configurado e recarregado com sucesso na porta 80.${WHITE}\n"
  else
    printf "${RED} >> Erro na sintaxe do Nginx! Verifique a configuração.${WHITE}\n"
    nginx -t || true
    sleep 3
    return 1
  fi

  if command -v certbot >/dev/null 2>&1; then
    printf "${WHITE} >> Solicitando emissão do certificado SSL com Certbot para ${hostname_alvo}...${WHITE}\n"
    local email_arg
    if [ -n "${email_deploy:-}" ]; then
      email_arg="-m ${email_deploy}"
    else
      email_arg="--register-unsafely-without-email"
    fi
    certbot --nginx ${email_arg} --agree-tos --redirect -n -d "${hostname_alvo}" 2>/dev/null || \
      certbot --nginx ${email_arg} --agree-tos -n -d "${hostname_alvo}" 2>/dev/null || true
    systemctl reload nginx 2>/dev/null || true
    printf "${GREEN} >> Certificado SSL emitido e ativado no Nginx com sucesso!${WHITE}\n"
  else
    printf "${YELLOW} >> Certbot não encontrado. Certificado SSL não emitido automaticamente.${WHITE}\n"
  fi

  sleep 2
}

# 9. Desinstalar API Oficial
desinstalar_api_oficial() {
  local emp="${1:-${empresa:-amanda}}"
  local compose_dir="${2:-}"
  local app_dir="/home/deploy/${emp}"
  [ -z "$compose_dir" ] && compose_dir=$(localizar_diretorio_compose "${app_dir}")

  banner
  printf "   ${RED}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "   ${RED}║${WHITE}                 DESINSTALAR API OFICIAL                      ${RED}║${WHITE}\n"
  printf "   ${RED}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
  printf "   ${WHITE}Instância alvo: ${GREEN}%s${WHITE}\n\n" "$emp"
  printf "${RED} >> ATENÇÃO: Esta ação irá parar e desvincular a API Oficial da plataforma AMANDA.${WHITE}\n"
  printf "${WHITE} >> Deseja realmente prosseguir com a desinstalação? (S/N): ${WHITE}"
  read -r confirma_desinstalar
  confirma_desinstalar=$(echo "${confirma_desinstalar}" | tr '[:lower:]' '[:upper:]')
  if [ "${confirma_desinstalar}" != "S" ]; then
    printf "${GREEN} >> Operação cancelada. Nenhuma alteração realizada.${WHITE}\n"
    sleep 2
    return 0
  fi

  # 9.1 Parar e remover contêiner Docker (se existir)
  local c_oficial
  c_oficial=$(mf_localizar_container_apioficial "$emp")
  if [ -n "$c_oficial" ]; then
    printf "${PURPLE} >> Parando e removendo contêiner Docker ${c_oficial}...${WHITE}\n"
    docker stop "$c_oficial" 2>/dev/null || true
    docker rm -f "$c_oficial" 2>/dev/null || true
  fi

  # 9.2 Remover processo PM2 (se existir)
  sudo su - deploy -c "pm2 delete api_oficial_${emp} 2>/dev/null || pm2 delete api_oficial 2>/dev/null || true; pm2 save 2>/dev/null || true" 2>/dev/null || true

  # 9.3 Remover api_oficial do docker-compose.yml
  if [ -f "${compose_dir}/docker-compose.yml" ]; then
    printf "${PURPLE} >> Removendo serviço api_oficial do docker-compose.yml...${WHITE}\n"
    python3 - "${compose_dir}/docker-compose.yml" << 'PYREM'
import sys, re
compose_file = sys.argv[1]
with open(compose_file, "r", encoding="utf-8") as f:
    content = f.read()

if "api_oficial:" in content:
    content = re.sub(r'\n[ ]{2}#?[^\n]*API OFICIAL[^\n]*\n[ ]{2}api_oficial:\n(?:[ ]{4,}.*\n)*', '\n', content)
    content = re.sub(r'^[ ]{2}api_oficial:\n(?:[ ]{4,}.*\n)*', '', content, flags=re.M)

with open(compose_file, "w", encoding="utf-8") as f:
    f.write(content)
PYREM
  fi

  # 9.4 Desativar integração no backend da AMANDA
  printf "${PURPLE} >> Desativando integração da API Oficial no backend AMANDA...${WHITE}\n"
  sed -i "s|^USE_WHATSAPP_OFICIAL=.*|USE_WHATSAPP_OFICIAL=false|" "${compose_dir}/.env" 2>/dev/null || true
  sed -i "s|^URL_API_OFICIAL=.*|URL_API_OFICIAL=|" "${compose_dir}/.env" 2>/dev/null || true
  if [ -f "${compose_dir}/backend/.env" ]; then
    sed -i "s|^USE_WHATSAPP_OFICIAL=.*|USE_WHATSAPP_OFICIAL=false|" "${compose_dir}/backend/.env" 2>/dev/null || true
    sed -i "s|^URL_API_OFICIAL=.*|URL_API_OFICIAL=|" "${compose_dir}/backend/.env" 2>/dev/null || true
  fi

  # Reiniciar backend AMANDA
  local be_c
  be_c=$(docker ps --format '{{.Names}}' | grep -E "^${emp}_backend" | head -n 1)
  [ -n "$be_c" ] && docker restart "$be_c" 2>/dev/null || true

  # 9.5 Remover proxy reverso Nginx
  if [ -f "/etc/nginx/sites-available/${emp}-oficial" ] || [ -f "/etc/nginx/sites-enabled/${emp}-oficial" ]; then
    printf "${PURPLE} >> Removendo configuração Nginx...${WHITE}\n"
    rm -f "/etc/nginx/sites-available/${emp}-oficial" "/etc/nginx/sites-enabled/${emp}-oficial" 2>/dev/null || true
    systemctl reload nginx 2>/dev/null || true
  fi

  # 9.6 Perguntar se deseja apagar banco de dados
  printf "\n${YELLOW} >> Deseja também EXCLUIR o banco de dados 'api_oficial' do PostgreSQL? (S/N): ${WHITE}"
  read -r del_banco
  del_banco=$(echo "${del_banco}" | tr '[:lower:]' '[:upper:]')
  if [ "${del_banco}" = "S" ]; then
    local pg_c
    pg_c=$(mf_container_servico "$emp" postgres) || return 1
    if [ -n "$pg_c" ]; then
      docker exec -e PGPASSWORD="${senha_deploy:-Acertitech13@}" "$pg_c" psql -U "${emp}" -d postgres -c "DROP DATABASE \"api_oficial\";" 2>/dev/null || true
      printf "${GREEN} >> Banco 'api_oficial' removido do PostgreSQL Docker.${WHITE}\n"
    elif command -v psql >/dev/null 2>&1; then
      PGPASSWORD="${senha_deploy:-Acertitech13@}" psql -h 127.0.0.1 -p "${PORT_DB:-5432}" -U "${emp}" -d postgres -c "DROP DATABASE \"api_oficial\";" 2>/dev/null || true
      printf "${GREEN} >> Banco 'api_oficial' removido do PostgreSQL local.${WHITE}\n"
    fi
  else
    printf "${CYAN} >> Banco de dados 'api_oficial' preservado com segurança.${WHITE}\n"
  fi

  printf "\n${GREEN} >> API Oficial desinstalada com sucesso e plataforma AMANDA atualizada!${WHITE}\n\n"
  printf "${WHITE}>> Pressione Enter para voltar ao menu...${WHITE}\n"
  read -r
}

# Funções legadas/wrappers para compatibilidade com chamadas existentes
instalar_api_oficial() {
  menu_gerenciar_api_oficial
}

atualizar_api_oficial() {
  atualizar_api_oficial_gerenciador
}

# Adicionar função para migrar para Multiflow-PRO
migrar_multiflow_pro() {
  banner
  printf "${WHITE} >> Migrando para Multiflow-PRO...\n"
  echo
  local script_path="$(pwd)/atualizador_pro.sh"
  if [ -f "$script_path" ]; then
    chmod 775 "$script_path"
    bash "$script_path"
  else
    printf "${RED} >> Script não encontrado em: $script_path${WHITE}\n"
    printf "${RED} >> Certifique-se de que o arquivo atualizador_pro.sh está no mesmo diretório do instalador.${WHITE}\n"
    sleep 2
  fi
  printf "${GREEN} >> Processo de migração para Multiflow-PRO finalizado. Voltando ao menu...${WHITE}\n"
  sleep 2
}

# Opção 30: renovar github_token da instância (qualquer repo HTTPS GitHub) + aplicar no origin + FAST.
# Não força ultrawhats: usa remote origin já configurado ou repo_url da instância.
# Após set-url: fetch --prune e remove trackings [branch "..."] cujo upstream não existe mais no origin.
mf_git_limpar_trackings_orfaos() {
  local app_root="${1:-}"
  local removidos=0
  local cur="" br merge_ref short_ref linha
  [ -z "$app_root" ] || [ ! -d "${app_root}/.git" ] && return 1

  export GIT_TERMINAL_PROMPT=0
  printf "${WHITE} >> Limpando trackings de branches órfãs (fetch --prune)...${WHITE}\n"
  if ! git -c "safe.directory=${app_root}" -C "${app_root}" fetch origin --prune; then
    printf "${YELLOW} >> Aviso: git fetch --prune falhou; trackings órfãos podem permanecer.${WHITE}\n"
    unset GIT_TERMINAL_PROMPT 2>/dev/null || true
    return 1
  fi

  while IFS= read -r linha; do
    [ -z "$linha" ] && continue
    # Ex.: branch.MULTI100-OFICIAL-u21.merge refs/heads/MULTI100-OFICIAL-u21
    br="${linha%%.merge *}"
    br="${br#branch.}"
    merge_ref="${linha#* }"
    short_ref="${merge_ref#refs/heads/}"
    [ -z "$br" ] || [ -z "$short_ref" ] && continue
    if ! git -c "safe.directory=${app_root}" -C "${app_root}" show-ref --verify --quiet "refs/remotes/origin/${short_ref}" 2>/dev/null; then
      if git -c "safe.directory=${app_root}" -C "${app_root}" config --remove-section "branch.${br}" 2>/dev/null; then
        printf "${GREEN} >> Tracking removido: branch.${br} (sem origin/${short_ref})${WHITE}\n"
        removidos=$((removidos + 1))
      fi
    fi
  done < <(git -c "safe.directory=${app_root}" -C "${app_root}" config --get-regexp '^branch\..*\.merge$' 2>/dev/null || true)

  cur=$(git -c "safe.directory=${app_root}" -C "${app_root}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [ -n "$cur" ] && [ "$cur" != "HEAD" ] && [ "$cur" != "main" ] && [ "$cur" != "master" ]; then
    if ! git -c "safe.directory=${app_root}" -C "${app_root}" show-ref --verify --quiet "refs/remotes/origin/${cur}" 2>/dev/null; then
      if git -c "safe.directory=${app_root}" -C "${app_root}" show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null; then
        printf "${YELLOW} >> Branch atual (${cur}) não existe no novo origin; indo para main...${WHITE}\n"
        git -c "safe.directory=${app_root}" -C "${app_root}" checkout -B main origin/main >/dev/null 2>&1 || true
      elif git -c "safe.directory=${app_root}" -C "${app_root}" show-ref --verify --quiet refs/remotes/origin/master 2>/dev/null; then
        printf "${YELLOW} >> Branch atual (${cur}) não existe no novo origin; indo para master...${WHITE}\n"
        git -c "safe.directory=${app_root}" -C "${app_root}" checkout -B master origin/master >/dev/null 2>&1 || true
      fi
    fi
  fi

  unset GIT_TERMINAL_PROMPT 2>/dev/null || true
  if [ "$removidos" -eq 0 ]; then
    printf "${GREEN} >> Nenhum tracking órfão encontrado.${WHITE}\n"
  else
    printf "${GREEN} >> ${removidos} tracking(s) órfão(s) removido(s).${WHITE}\n"
  fi
  return 0
}

# Aplica token no remote origin da instância (e subpastas com .git próprio, se existirem).
# Se $3 (repo_canonico) estiver definido, set-url na raiz para esse repo + token.
# Caso contrário, só reaplica o token preservando o origin atual (update genérico).
mf_opcao30_aplicar_token_nos_gits() {
  local app_root="${1:-}"
  local token="${2:-}"
  local repo_canonico="${3:-}"
  local remotes_ok=0 remotes_fail=0 git_dir

  if [ -z "$app_root" ] || [ -z "$token" ]; then
    return 1
  fi

  # shellcheck source=/dev/null
  if [ -f "${INSTALADOR_DIR:-}/tools/git_sincronizar_repositorio.sh" ]; then
    . "${INSTALADOR_DIR}/tools/git_sincronizar_repositorio.sh"
  elif [ -f "/root/instalador_single_oficial/tools/git_sincronizar_repositorio.sh" ]; then
    . "/root/instalador_single_oficial/tools/git_sincronizar_repositorio.sh"
  fi

  for git_dir in \
    "${app_root}" \
    "${app_root}/frontend" \
    "${app_root}/backend" \
    "${app_root}/api_oficial" \
    "${app_root}/api_transcricao"; do
    [ -d "${git_dir}/.git" ] || continue

    if [ -f "${git_dir}/.git/config" ]; then
      cp "${git_dir}/.git/config" "${git_dir}/.git/config.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    fi

    if ! git -c "safe.directory=${git_dir}" -C "${git_dir}" remote get-url origin >/dev/null 2>&1; then
      printf "${YELLOW} >> Aviso: sem remote origin em ${git_dir}${WHITE}\n"
      continue
    fi

    if [ "$git_dir" = "$app_root" ] && [ -n "$repo_canonico" ]; then
      if type mf_git_aplicar_token_remote >/dev/null 2>&1 && mf_git_aplicar_token_remote "${git_dir}" "${token}" "${repo_canonico}"; then
        printf "${GREEN} >> Remote origin atualizado: ${BLUE}${repo_canonico}${WHITE} em ${BLUE}${git_dir}${WHITE}\n"
        remotes_ok=$((remotes_ok + 1))
        continue
      else
        printf "${RED} >> ERRO: git remote set-url falhou em ${git_dir}${WHITE}\n"
        remotes_fail=$((remotes_fail + 1))
        continue
      fi
    fi

    if type mf_git_aplicar_token_remote >/dev/null 2>&1; then
      if mf_git_aplicar_token_remote "${git_dir}" "${token}"; then
        printf "${GREEN} >> Token aplicado no remote origin: ${BLUE}${git_dir}${WHITE}\n"
        remotes_ok=$((remotes_ok + 1))
      else
        printf "${YELLOW} >> Aviso: não foi possível aplicar token em ${git_dir}${WHITE}\n"
        [ "$git_dir" = "$app_root" ] && remotes_fail=$((remotes_fail + 1))
      fi
    else
      printf "${YELLOW} >> Aviso: mf_git_aplicar_token_remote indisponível; ${git_dir} não atualizado.${WHITE}\n"
      [ "$git_dir" = "$app_root" ] && remotes_fail=$((remotes_fail + 1))
    fi
  done

  [ "$remotes_ok" -gt 0 ] && [ "$remotes_fail" -eq 0 ]
}

# Valida token contra um repositório HTTPS GitHub qualquer (ls-remote; fallback clone raso).
# $1 = token; $2 = host/path ou URL (ex.: github.com/org/repo.git ou https://github.com/org/repo.git)
mf_opcao30_validar_token() {
  local token="${1:-}"
  local repo_ref="${2:-}"
  local token_encoded url err_file test_dir repo_host

  [ -z "$token" ] || [ -z "$repo_ref" ] && return 1
  repo_host=$(echo "$repo_ref" | sed 's|^https://||' | sed 's|^http://||' | sed 's|^[^@]*@||')
  token_encoded=$(codifica_clone_base "$token")
  if echo "$repo_host" | grep -Eqi 'github\.com'; then
    url="https://x-access-token:${token_encoded}@${repo_host}"
  else
    url="https://${token_encoded}@${repo_host}"
  fi
  export GIT_TERMINAL_PROMPT=0
  export GIT_ASKPASS=true

  err_file=$(mktemp)
  if git ls-remote --exit-code "${url}" HEAD >/dev/null 2>"$err_file"; then
    rm -f "$err_file"
    unset GIT_TERMINAL_PROMPT GIT_ASKPASS 2>/dev/null || true
    return 0
  fi

  test_dir="${INSTALADOR_DIR:-/tmp}/test_clone_token_$(date +%s)"
  if git clone --depth 1 "${url}" "${test_dir}" >/dev/null 2>>"$err_file"; then
    rm -rf "${test_dir}" >/dev/null 2>&1
    rm -f "$err_file"
    unset GIT_TERMINAL_PROMPT GIT_ASKPASS 2>/dev/null || true
    return 0
  fi
  rm -rf "${test_dir}" >/dev/null 2>&1
  ERRO_GIT_VALIDACAO=$(head -3 "$err_file" 2>/dev/null | tr '\n' ' ')
  rm -f "$err_file"
  unset GIT_TERMINAL_PROMPT GIT_ASKPASS 2>/dev/null || true
  return 1
}

# Confirma que o remote local da pasta aceita o token (mesmo caminho do update).
mf_opcao30_validar_remote_local() {
  local app_root="${1:-}"
  [ -z "$app_root" ] || [ ! -d "${app_root}/.git" ] && return 1
  export GIT_TERMINAL_PROMPT=0
  export GIT_ASKPASS=true
  if git -c "safe.directory=${app_root}" -C "${app_root}" ls-remote --exit-code origin HEAD >/dev/null 2>&1; then
    unset GIT_TERMINAL_PROMPT GIT_ASKPASS 2>/dev/null || true
    return 0
  fi
  unset GIT_TERMINAL_PROMPT GIT_ASKPASS 2>/dev/null || true
  return 1
}

# Renova token GitHub da instância (genérico) e dispara Atualização FAST.
# Mantém o nome atualizar_ultrawhats por compatibilidade com menu / --exec-ferramenta 30.
atualizar_ultrawhats() {
  local repo_sed=""
  local TOKEN_AUTH=""
  local APP_ROOT=""
  local ARQUIVO_VARIAVEIS_ALVO=""
  local token_sed=""
  local empresa_alvo=""
  local arquivo_vars_preservado=""
  local REPO_ALVO=""
  local REPO_HOST=""
  local origin_publico=""
  local forcar_set_url=""
  local resposta_repo=""

  INSTALADOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  banner
  printf "${WHITE} >> Atualizar token GitHub + Atualização FAST${WHITE}\n"
  printf "${WHITE} >> Esta opção pede o PAT e já atualiza:${WHITE}\n"
  printf "${BLUE}   1)${WHITE} github_token (e repo_url se você trocar o link) no arquivo da instância${WHITE}\n"
  printf "${BLUE}   2)${WHITE} remote origin na pasta git (token no HTTPS — sem trocar de repo, salvo se você pedir)${WHITE}\n"
  printf "${BLUE}   3)${WHITE} em seguida inicia automaticamente a Atualização FAST (mesma da opção 8)${WHITE}\n"
  echo
  printf "${YELLOW} >> Funciona com qualquer repositório HTTPS GitHub (ultrawhats, multiflow-pro, etc.).${WHITE}\n"
  echo

  if ! selecionar_instancia_atualizar "renovar token GitHub / Atualização FAST"; then
    printf "${RED} >> Operação cancelada.${WHITE}\n"
    sleep 2
    return 1
  fi

  if [ -n "${ARQUIVO_VARIAVEIS_USADO:-}" ] && [ -f "${ARQUIVO_VARIAVEIS_USADO}" ]; then
    # shellcheck source=/dev/null
    mf_carregar_config "${ARQUIVO_VARIAVEIS_USADO}" 2>/dev/null
  fi

  if [ -z "${empresa:-}" ]; then
    printf "${RED} >> ERRO: variável 'empresa' não encontrada na instância.${WHITE}\n"
    sleep 2
    return 1
  fi

  empresa_alvo="${empresa}"
  arquivo_vars_preservado="${ARQUIVO_VARIAVEIS_USADO:-}"
  APP_ROOT="/home/deploy/${empresa_alvo}"
  if [ ! -d "${APP_ROOT}/.git" ]; then
    printf "${RED} >> ERRO: repositório git não encontrado em ${APP_ROOT}${WHITE}\n"
    sleep 2
    return 1
  fi

  origin_publico=$(git -c "safe.directory=${APP_ROOT}" -C "${APP_ROOT}" remote get-url origin 2>/dev/null \
    | sed -E 's#^(https?://)[^/@]+@#\1#' || true)
  REPO_ALVO="${origin_publico:-${repo_url:-}}"
  if [ -z "$REPO_ALVO" ]; then
    printf "${RED} >> ERRO: nem origin nem repo_url definidos. Informe o link do repositório.${WHITE}\n"
    sleep 2
    return 1
  fi
  [[ "$REPO_ALVO" != *.git ]] && [[ "$REPO_ALVO" =~ github\.com ]] && REPO_ALVO="${REPO_ALVO}.git"

  banner
  printf "${WHITE} >> Instância: ${BLUE}${empresa_alvo}${WHITE}\n"
  printf "${WHITE} >> Arquivo de variáveis: ${YELLOW}${arquivo_vars_preservado:- (não definido)}${WHITE}\n"
  printf "${WHITE} >> Origin atual: ${YELLOW}${origin_publico:- (não definido)}${WHITE}\n"
  printf "${WHITE} >> repo_url da instância: ${YELLOW}${repo_url:- (não definido)}${WHITE}\n"
  printf "${WHITE} >> Repositório alvo (validação): ${GREEN}${REPO_ALVO}${WHITE}\n"
  echo
  printf "${YELLOW} >> Manter este repositório (s) ou colar um novo link HTTPS?${WHITE}\n"
  echo
  read -r -p "> " resposta_repo
  resposta_repo=$(printf '%s' "$resposta_repo" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\r')
  if [ -n "$resposta_repo" ] && [ "$resposta_repo" != "s" ] && [ "$resposta_repo" != "S" ]; then
    REPO_ALVO="$resposta_repo"
    [[ "$REPO_ALVO" != *.git ]] && [[ "$REPO_ALVO" =~ github\.com ]] && REPO_ALVO="${REPO_ALVO}.git"
    forcar_set_url="1"
    printf "${GREEN} >> Novo repositório: ${REPO_ALVO}${WHITE}\n"
  fi
  echo
  printf "${WHITE} >> Digite o NOVO TOKEN (PAT) do GitHub com acesso a este repositório:${WHITE}\n"
  printf "${YELLOW} >> (o valor não é gravado no código do instalador — só no arquivo da instância e no remote)${WHITE}\n"
  echo
  read -r -p "> " TOKEN_AUTH
  TOKEN_AUTH=$(printf '%s' "$TOKEN_AUTH" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\r\n')

  if [ -z "$TOKEN_AUTH" ]; then
    printf "${RED} >> Token não informado. Operação cancelada.${WHITE}\n"
    sleep 2
    return 1
  fi

  REPO_HOST=$(echo "$REPO_ALVO" | sed 's|^https://||' | sed 's|^http://||' | sed 's|^[^@]*@||')
  [[ "$REPO_HOST" != *.git ]] && REPO_HOST="${REPO_HOST}.git"

  printf "${WHITE} >> Validando token contra ${BLUE}${REPO_ALVO}${WHITE}...${WHITE}\n"
  echo
  ERRO_GIT_VALIDACAO=""
  if mf_opcao30_validar_token "$TOKEN_AUTH" "$REPO_HOST"; then
    printf "${GREEN} >> Token validado com sucesso (acesso ao repositório OK).${WHITE}\n"
    echo
  else
    printf "${RED} >> Token inválido ou sem acesso ao repositório informado.${WHITE}\n"
    if [ -n "${ERRO_GIT_VALIDACAO:-}" ]; then
      printf "${YELLOW} >> Detalhe do Git: ${ERRO_GIT_VALIDACAO}${WHITE}\n"
    fi
    printf "${YELLOW} >> Confira o PAT (scopes/repo) e o link do repositório; tente novamente na opção 30.${WHITE}\n"
    sleep 2
    return 1
  fi

  ARQUIVO_VARIAVEIS_ALVO="${arquivo_vars_preservado}"
  if [ -z "$ARQUIVO_VARIAVEIS_ALVO" ] || [ ! -f "$ARQUIVO_VARIAVEIS_ALVO" ]; then
    printf "${RED} >> ERRO: arquivo de variáveis da instância não encontrado.${WHITE}\n"
    sleep 2
    return 1
  fi

  cp "$ARQUIVO_VARIAVEIS_ALVO" "${ARQUIVO_VARIAVEIS_ALVO}.backup.$(date +%Y%m%d_%H%M%S)"

  token_sed="${TOKEN_AUTH//&/\\&}"
  if grep -q "^github_token=" "$ARQUIVO_VARIAVEIS_ALVO"; then
    sed -i "s|^github_token=.*|github_token=${token_sed}|" "$ARQUIVO_VARIAVEIS_ALVO"
  else
    echo "github_token=${TOKEN_AUTH}" >> "$ARQUIVO_VARIAVEIS_ALVO"
  fi
  printf "${GREEN} >> github_token salvo em: ${BLUE}${ARQUIVO_VARIAVEIS_ALVO}${WHITE}\n"

  # Sempre alinha repo_url ao alvo validado (origin atual ou link novo)
  repo_sed="${REPO_ALVO//&/\\&}"
  if grep -q "^repo_url=" "$ARQUIVO_VARIAVEIS_ALVO"; then
    sed -i "s|^repo_url=.*|repo_url=${repo_sed}|" "$ARQUIVO_VARIAVEIS_ALVO"
  else
    echo "repo_url=${REPO_ALVO}" >> "$ARQUIVO_VARIAVEIS_ALVO"
  fi
  printf "${GREEN} >> repo_url = ${REPO_ALVO}${WHITE}\n"

  repo_url="${REPO_ALVO}"
  github_token="${TOKEN_AUTH}"
  empresa="${empresa_alvo}"
  ARQUIVO_VARIAVEIS_USADO="${ARQUIVO_VARIAVEIS_ALVO}"

  printf "${WHITE} >> Aplicando token no remote origin (pasta git)...${WHITE}\n"
  if [ "$forcar_set_url" = "1" ]; then
    if ! mf_opcao30_aplicar_token_nos_gits "${APP_ROOT}" "${TOKEN_AUTH}" "${REPO_ALVO}"; then
      printf "${RED} >> ERRO: não foi possível atualizar o remote origin com o novo token/repo.${WHITE}\n"
      sleep 2
      return 1
    fi
  else
    if ! mf_opcao30_aplicar_token_nos_gits "${APP_ROOT}" "${TOKEN_AUTH}"; then
      printf "${RED} >> ERRO: não foi possível aplicar o token no remote origin atual.${WHITE}\n"
      sleep 2
      return 1
    fi
  fi

  printf "${WHITE} >> Validando remote local (git ls-remote origin HEAD)...${WHITE}\n"
  if mf_opcao30_validar_remote_local "${APP_ROOT}"; then
    printf "${GREEN} >> Remote origin autenticado com sucesso — iniciando Atualização FAST.${WHITE}\n"
  else
    printf "${RED} >> ERRO: o remote foi gravado, mas git ls-remote origin ainda falhou.${WHITE}\n"
    printf "${YELLOW} >> Verifique: git -C ${APP_ROOT} remote -v${WHITE}\n"
    printf "${YELLOW} >> Token inválido/expirado ou sem acesso a este repositório — o refactor genérico não corrige PAT expirado.${WHITE}\n"
    sleep 2
    return 1
  fi

  mf_git_limpar_trackings_orfaos "${APP_ROOT}" || true

  if type aplicar_token_baileys_package_json >/dev/null 2>&1; then
    aplicar_token_baileys_package_json "${empresa_alvo}" "${TOKEN_AUTH}" "${REPO_ALVO}" || true
  fi

  echo
  printf "${GREEN} >> Instância ${BLUE}${empresa_alvo}${GREEN} pronta com o novo token (repo: ${REPO_ALVO}).${WHITE}\n"
  printf "${GREEN} >> Atualizado:${WHITE}\n"
  printf "   - variáveis: github_token + repo_url (${ARQUIVO_VARIAVEIS_ALVO})${WHITE}\n"
  printf "   - git remote origin em ${APP_ROOT} (e subpastas com .git, se existirem)${WHITE}\n"
  echo
  printf "${WHITE} >> Iniciando Atualização FAST automaticamente (mesma função da opção 8)...${WHITE}\n"
  sleep 2

  export ARQUIVO_VARIAVEIS_USADO="${ARQUIVO_VARIAVEIS_ALVO}"
  export MF_OPCAO30_INSTANCIA_PRESET="${ARQUIVO_VARIAVEIS_ALVO}"
  atualizar_base_fast
  unset MF_OPCAO30_INSTANCIA_PRESET 2>/dev/null || true

  return 0
}

# Atualização FAST (sem reinstalar node_modules/Baileys)
atualizar_base_fast() {
  banner
  printf "${YELLOW} >> Essa atualização não realiza a reinstalação da pasta node_modules, nem afeta o Baileys, pois esses componentes só precisam ser atualizados quando há alterações específicas neles.${WHITE}\n"
  echo

  local script_path="$(pwd)/atualizador_remoto_FAST.sh"
  if [ -f "$script_path" ]; then
    chmod 775 "$script_path"
    bash "$script_path"
  else
    printf "${RED} >> Script não encontrado em: $script_path${WHITE}\n"
    printf "${RED} >> Certifique-se de que o arquivo atualizador_remoto_FAST.sh está no mesmo diretório do instalador.${WHITE}\n"
    sleep 2
  fi

  printf "${GREEN} >> Processo de atualização FAST finalizado. Voltando ao menu...${WHITE}\n"
  sleep 2
}

# Instalação em modo Alta Performance (Redis, Postgres, PgBouncer via Docker)
exec_instalador_alta_performance() {
  local script_path="$(pwd)/tools/instalador_alta_performance.sh"
  if [ ! -f "$script_path" ]; then
    printf "${RED} >> Script não encontrado: $script_path${WHITE}\n"
    sleep 2
    return
  fi
  chmod 775 "$script_path"
  bash "$script_path"
  # Se o script sair sem exec do instalador (cancelamento), volta ao menu
  printf "${GREEN} >> Voltando ao menu...${WHITE}\n"
  sleep 2
}

# Modo: executar instalação completa Alta Performance sem menu (chamado pelo instalador_alta_performance.sh)
if [ "${1:-}" = "--executar-instalacao-alta-performance" ]; then
  [ -f "ALTA_PERFORMANCE_MODE" ] && mf_carregar_config "ALTA_PERFORMANCE_MODE" 2>/dev/null
  [ -f "$ARQUIVO_VARIAVEIS" ] && mf_carregar_config "$ARQUIVO_VARIAVEIS" 2>/dev/null
  export ALTA_PERFORMANCE=1
  instalar_amanda_docker_stack || exit 1
  exit 0
fi

# Modo: apenas coletar variáveis para instalação Alta Performance (chamado pelo instalador_alta_performance.sh)
if [ "${1:-}" = "--coletar-variaveis-alta-performance" ]; then
  [ -f "ALTA_PERFORMANCE_MODE" ] && mf_carregar_config "ALTA_PERFORMANCE_MODE" 2>/dev/null
  export ALTA_PERFORMANCE=1
  questoes_dns_base || trata_erro "questoes_dns_base"
  verificar_dns_base || trata_erro "verificar_dns_base"
  questoes_variaveis_base || trata_erro "questoes_variaveis_base"
  define_proxy_base || trata_erro "define_proxy_base"
  define_portas_base || trata_erro "define_portas_base"
  confirma_dados_instalacao_base || trata_erro "confirma_dados_instalacao_base"
  salvar_variaveis || trata_erro "salvar_variaveis"
  salvar_etapa 1
  exit 0
fi

# Modo: executar ferramenta do menu sem abrir o menu principal (painel Multiflow Control)
exec_ferramenta_direta() {
  carregar_variaveis
  case "${1:-}" in
    8) backup_redis_ferramentas ;;
    9) restaurar_redis_ferramentas ;;
    10) importar_backup_banco_ferramentas ;;
    11) backup_banco_ferramentas ;;
    12) importar_backup_banco_api_oficial_ferramentas ;;
    13) listar_bancos_ferramentas ;;
    14) restaurar_backup_banco_alta_performance_ferramentas ;;
    17) atualizar_whatsmeow ;;
    22) backup_whatsmeow_ferramentas ;;
    23) restaurar_whatsmeow_ferramentas ;;
    30) atualizar_ultrawhats ;;
    *)
      printf "${RED} >> Ferramenta inválida ou não suportada: ${1}${WHITE}\n"
      return 1
      ;;
  esac
}

if [ "${1:-}" = "--exec-ferramenta" ] && [ -n "${2:-}" ]; then
  exec_ferramenta_direta "$2"
  exit $?
fi

if [ "${1:-}" = "--desinstalar" ]; then
  carregar_variaveis
  menu_desinstalar_plataforma
  exit 0
fi

if [ "${1:-}" = "--atualizar" ] || [ "${1:-}" = "atualizar" ] || [ "${1:-}" = "2" ]; then
  carregar_variaveis
  atualizar_amanda_docker
  exit $?
fi

carregar_variaveis
menu
