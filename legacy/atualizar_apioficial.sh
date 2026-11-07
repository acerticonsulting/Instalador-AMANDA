#!/bin/bash
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/tools/mf_operacoes_seguras.sh" || exit 1

if [ -z "${PURPLE:-}" ]; then
  if [ "${COLORTERM:-}" = "truecolor" ] || [ "${COLORTERM:-}" = "24bit" ] || [ -n "${WT_SESSION:-}" ] || [[ "${TERM:-}" =~ (xterm|256color|screen|tmux|linux|alacritty|kitty) ]]; then
    PURPLE='\033[38;2;139;92;246m'
    purple='\033[38;2;139;92;246m'
    BLUE='\033[1;38;2;167;139;250m'
    MAGENTA='\033[38;2;192;132;252m'
    ROXO='\033[38;2;139;92;246m'
    GREEN='\033[1;38;2;74;222;128m'
    WHITE='\033[1;38;2;255;255;255m'
    RED='\033[1;38;2;248;113;113m'
    YELLOW='\033[1;38;2;250;204;21m'
    CYAN='\033[1;38;2;56;189;248m'
  else
    PURPLE='\033[38;5;99m'
    purple='\033[38;5;99m'
    BLUE='\033[1;94m'
    MAGENTA='\033[1;95m'
    ROXO='\033[38;5;99m'
    GREEN='\033[1;92m'
    WHITE='\033[1;97m'
    RED='\033[1;91m'
    YELLOW='\033[1;93m'
    CYAN='\033[1;96m'
  fi
  NC='\033[0m'
  RESET='\033[0m'
fi

# Variaveis Padrão
ARCH=$(uname -m)
UBUNTU_VERSION=$(lsb_release -sr)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALADOR_DIR="$SCRIPT_DIR"
# Caminho absoluto do VARIAVEIS da instância escolhida
ARQUIVO_VARIAVEIS=""
default_apioficial_port=6000

if [ "$EUID" -ne 0 ]; then
  echo
  printf "${WHITE} >> Este script precisa ser executado como root ${RED}ou com privilégios de superusuário${WHITE}.\n"
  echo
  sleep 2
  exit 1
fi

# Função para manipular erros e encerrar o script
trata_erro() {
  printf "${RED}Erro encontrado na etapa $1. Encerrando o script.${WHITE}\n"
  exit 1
}

# Banner
banner() {
  clear
  printf "${BLUE}"
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║                    ATUALIZADOR API OFICIAL                   ║"
  echo "║                                                              ║"
  echo "║                    MultiFlow System                          ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  printf "${WHITE}"
  echo
}

# Detectar instâncias (mesma lógica do instalador_single.sh)
detectar_instancias_instaladas() {
  local instancias=()
  local nomes_empresas=()
  local temp_empresa=""

  if [ -f "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO" ]; then
    local empresa_original="${empresa:-}"
    local subdominio_backend_original="${subdominio_backend:-}"
    local subdominio_frontend_original="${subdominio_frontend:-}"
    # shellcheck source=/dev/null
    mf_carregar_config "${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO" 2>/dev/null
    temp_empresa="${empresa:-}"
    if [ -n "${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}/backend" ] && [ -d "/home/deploy/${temp_empresa}/api_oficial" ]; then
      instancias+=("${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO")
      nomes_empresas+=("${temp_empresa}")
    fi
    empresa="${empresa_original}"
    subdominio_backend="${subdominio_backend_original}"
    subdominio_frontend="${subdominio_frontend_original}"
  fi

  if [ -d "${INSTALADOR_DIR}" ]; then
    shopt -s nullglob
    for arquivo_instancia in "${INSTALADOR_DIR}"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
      if [ -f "$arquivo_instancia" ]; then
        local empresa_original="${empresa:-}"
        local subdominio_backend_original="${subdominio_backend:-}"
        local subdominio_frontend_original="${subdominio_frontend:-}"
        # shellcheck source=/dev/null
        mf_carregar_config "$arquivo_instancia" 2>/dev/null
        temp_empresa="${empresa:-}"
        if [ -n "${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}/backend" ] && [ -d "/home/deploy/${temp_empresa}/api_oficial" ]; then
          instancias+=("$arquivo_instancia")
          nomes_empresas+=("${temp_empresa}")
        fi
        empresa="${empresa_original}"
        subdominio_backend="${subdominio_backend_original}"
        subdominio_frontend="${subdominio_frontend_original}"
      fi
    done
    shopt -u nullglob
  fi

  declare -g INSTANCIAS_DETECTADAS=("${instancias[@]}")
  declare -g NOMES_EMPRESAS_DETECTADAS=("${nomes_empresas[@]}")
}

selecionar_instancia_apioficial() {
  banner
  printf "${WHITE} >> Qual instância terá a API Oficial atualizada?\n\n"
  detectar_instancias_instaladas
  local total_instancias=${#INSTANCIAS_DETECTADAS[@]}

  if [ "$total_instancias" -eq 0 ]; then
    printf "${RED} >> Nenhuma instância com API Oficial instalada foi encontrada.${WHITE}\n"
    printf "${YELLOW} >> Instale a API Oficial em Ferramentas ou no menu principal antes de atualizar.${WHITE}\n"
    sleep 3
    exit 1
  elif [ "$total_instancias" -eq 1 ]; then
    printf "${GREEN} >> Instância: ${BLUE}${NOMES_EMPRESAS_DETECTADAS[0]}${WHITE}\n\n"
    ARQUIVO_VARIAVEIS="${INSTANCIAS_DETECTADAS[0]}"
    # shellcheck source=/dev/null
    mf_carregar_config "$ARQUIVO_VARIAVEIS"
    sleep 1
    return 0
  fi

  printf "${WHITE}═══════════════════════════════════════════════════════════\n"
  printf "  INSTÂNCIAS\n"
  printf "═══════════════════════════════════════════════════════════${WHITE}\n\n"
  local index=1
  for i in "${!NOMES_EMPRESAS_DETECTADAS[@]}"; do
    local empresa_nome="${NOMES_EMPRESAS_DETECTADAS[$i]}"
    local arquivo_instancia="${INSTANCIAS_DETECTADAS[$i]}"
    local empresa_original="${empresa:-}"
    local subdominio_backend_original="${subdominio_backend:-}"
    local subdominio_frontend_original="${subdominio_frontend:-}"
    # shellcheck source=/dev/null
    mf_carregar_config "$arquivo_instancia" 2>/dev/null
    local tb="${subdominio_backend:-}"
    local tf="${subdominio_frontend:-}"
    empresa="${empresa_original}"
    subdominio_backend="${subdominio_backend_original}"
    subdominio_frontend="${subdominio_frontend_original}"
    printf "  [${BLUE}%s${WHITE}] %s\n" "$index" "$empresa_nome"
    [ -n "$tb" ] && printf "      Backend:  ${YELLOW}%s${WHITE}\n" "$tb"
    [ -n "$tf" ] && printf "      Frontend: ${YELLOW}%s${WHITE}\n" "$tf"
    echo
    index=$((index + 1))
  done
  printf "${YELLOW} >> Escolha a instância (1-%s):${WHITE}\n" "$total_instancias"
  read -r escolha_instancia
  if ! [[ "$escolha_instancia" =~ ^[0-9]+$ ]] || [ "$escolha_instancia" -lt 1 ] || [ "$escolha_instancia" -gt "$total_instancias" ]; then
    printf "${RED} >> Opção inválida.${WHITE}\n"
    exit 1
  fi
  local indice_selecionado=$((escolha_instancia - 1))
  ARQUIVO_VARIAVEIS="${INSTANCIAS_DETECTADAS[$indice_selecionado]}"
  # shellcheck source=/dev/null
  mf_carregar_config "$ARQUIVO_VARIAVEIS"
  printf "${GREEN} >> Instância selecionada: ${BLUE}${empresa}${WHITE}\n\n"
  sleep 1
}

# Carregar variáveis
carregar_variaveis() {
  if [ -f "$ARQUIVO_VARIAVEIS" ]; then
    # shellcheck source=/dev/null
    mf_carregar_config "$ARQUIVO_VARIAVEIS"
  else
    empresa="multiflow"
    nome_titulo="MultiFlow"
  fi
}

# Verificar se a API Oficial já está instalada
verificar_instalacao_apioficial() {
  banner
  printf "${WHITE} >> Verificando instalação da API Oficial...\n"
  echo
  
  # Verificar se o diretório da API Oficial existe
  if [ ! -d "/home/deploy/${empresa}/api_oficial" ]; then
    printf "${RED} >> ERRO: API Oficial não está instalada nesta instância!${WHITE}\n"
    printf "${RED} >> Diretório /home/deploy/${empresa}/api_oficial não encontrado.${WHITE}\n"
    echo
    printf "${YELLOW} >> Execute primeiro a opção 'Instalar API Oficial' no instalador_single.sh.${WHITE}\n"
    echo
    sleep 5
    exit 1
  fi
  
  # Remover qualquer processo legado no PM2 para garantir que rode 100% em contêiner
  sudo su - deploy -c "pm2 delete api_oficial_${empresa} 2>/dev/null || pm2 delete api_oficial 2>/dev/null || true; pm2 save 2>/dev/null || true" 2>/dev/null || true

  # Verificar contêiner Docker
  local c_oficial
  c_oficial=$(docker ps --format '{{.Names}}' | grep -E "^${empresa}_apioficial" | head -n 1)
  
  if [ -z "$c_oficial" ]; then
    printf "${YELLOW} >> Contêiner da API Oficial (${empresa}_apioficial) não está em execução.${WHITE}\n"
    printf "${WHITE} >> O atualizador irá compilar e iniciar o contêiner Docker automaticamente.${WHITE}\n"
  else
    printf "${GREEN} >> API Oficial encontrada e ativa no Docker (${c_oficial})!${WHITE}\n"
  fi
  echo
  sleep 2
}

# Atualizar código da API Oficial via Docker Compose
atualizar_codigo_apioficial() {
  banner
  printf "${WHITE} >> Atualizando código e contêiner da API Oficial...\n"
  echo
  {
    local app_dir="/home/deploy/${empresa}"
    local compose_dir=""
    if [ -f "${app_dir}/amanda/docker-compose.yml" ]; then
      compose_dir="${app_dir}/amanda"
    elif [ -f "${app_dir}/docker-compose.yml" ]; then
      compose_dir="${app_dir}"
    else
      compose_dir="${app_dir}"
    fi

    printf "${WHITE} >> Fazendo pull das atualizações do repositório Git...\n"
    sudo -u deploy git -C "${app_dir}" pull 2>/dev/null || true

    mkdir -p "/home/deploy/${empresa}/api_oficial/public"
    touch "/home/deploy/${empresa}/api_oficial/public/.gitkeep"

    # Garantir fix de dependência CommonJS @nestjs/mapped-types@2.0.5
    if [ -f "/home/deploy/${empresa}/api_oficial/package.json" ]; then
      sed -i 's|"@nestjs/mapped-types": "[^"]*"|"@nestjs/mapped-types": "2.0.5"|g' "/home/deploy/${empresa}/api_oficial/package.json" 2>/dev/null || true
    fi

    # Garantir Dockerfile otimizado com fix @nestjs/mapped-types
    printf "${WHITE} >> Criando/atualizando Dockerfile da API Oficial...\n"
    cat << 'EOF_API_DF' > "/home/deploy/${empresa}/api_oficial/Dockerfile"
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

    # Recompilar e reiniciar contêiner da API Oficial
    printf "${PURPLE} >> Reconstruindo contêiner Docker da API Oficial...${WHITE}\n"
    (cd "${compose_dir}" && docker compose -p "${empresa}" up -d --build --force-recreate api_oficial) || return 1
    sleep 5

    printf "${WHITE} >> Executando migrações Prisma dentro do contêiner...${WHITE}\n"
    docker exec "${empresa}_apioficial" npx prisma migrate deploy || return 1

    printf "${GREEN} >> Código e contêiner da API Oficial atualizados com sucesso!${WHITE}\n"
    sleep 2
  } || trata_erro "atualizar_codigo_apioficial"
}

# Reiniciar API Oficial no Docker
reiniciar_apioficial() {
  banner
  printf "${WHITE} >> Verificando status final do contêiner Docker...\n"
  echo
  {
    docker restart "${empresa}_apioficial" || return 1
  } || trata_erro "reiniciar_apioficial"
  printf "${GREEN} >> Contêiner da API Oficial operacional e reiniciado!${WHITE}\n"
  echo
  sleep 2
}

# Função principal
main() {
  selecionar_instancia_apioficial || return 1
  carregar_variaveis
  verificar_instalacao_apioficial || return 1
  atualizar_codigo_apioficial || return 1
  reiniciar_apioficial || return 1
  
  banner
  printf "${GREEN} >> Atualização da API Oficial concluída com sucesso em Contêiner Docker!${WHITE}\n"
  echo
  printf "${WHITE} >> Instância:        ${YELLOW}${empresa}${WHITE}\n"
  printf "${WHITE} >> Contêiner Docker: ${GREEN}${empresa}_apioficial${WHITE}\n"
  printf "${WHITE} >> Porta HTTP:       ${YELLOW}${default_apioficial_port}${WHITE}\n"
  echo
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "${empresa}_apioficial|NAMES" || true
  echo
  sleep 5
}

# Executar função principal
main
