#!/bin/bash

# Historical archive: never execute native provisioning on the host.
printf '%s\n' 'Receita histórica bloqueada. Use instalador_single.sh da raiz (100% Docker).' >&2
return 1 2>/dev/null || exit 1
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/mf_operacoes_seguras.sh" || exit 1

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

# O arquivo VARIAVEIS_INSTALACAO está na pasta anterior (raiz do instalador)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALADOR_DIR="${SCRIPT_DIR}/.."
ARQUIVO_VARIAVEIS="${INSTALADOR_DIR}/VARIAVEIS_INSTALACAO"

# Função para detectar e listar todas as instâncias instaladas
detectar_instancias_instaladas() {
  local instancias=()
  local nomes_empresas=()
  local temp_empresa=""
  
  # Verificar instalação base (arquivo VARIAVEIS_INSTALACAO)
  if [ -f "${ARQUIVO_VARIAVEIS}" ]; then
    # Salvar variáveis atuais
    local empresa_original="${empresa:-}"
    
    # Carregar variáveis do arquivo
    mf_carregar_config "${ARQUIVO_VARIAVEIS}" 2>/dev/null
    temp_empresa="${empresa:-}"
    
    if [ -n "${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}/backend" ]; then
      instancias+=("${ARQUIVO_VARIAVEIS}")
      nomes_empresas+=("${temp_empresa}")
    fi
    
    # Restaurar variáveis originais
    empresa="${empresa_original}"
  fi
  
  # Verificar instâncias adicionais (arquivos VARIAVEIS_INSTALACAO_INSTANCIA_*)
  if [ -d "${INSTALADOR_DIR}" ]; then
    for arquivo_instancia in "${INSTALADOR_DIR}"/VARIAVEIS_INSTALACAO_INSTANCIA_*; do
      if [ -f "$arquivo_instancia" ]; then
        # Salvar variáveis atuais
        local empresa_original="${empresa:-}"
        
        # Carregar variáveis do arquivo
        mf_carregar_config "$arquivo_instancia" 2>/dev/null
        temp_empresa="${empresa:-}"
        
        if [ -n "${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}" ] && [ -d "/home/deploy/${temp_empresa}/backend" ]; then
          instancias+=("$arquivo_instancia")
          nomes_empresas+=("${temp_empresa}")
        fi
        
        # Restaurar variáveis originais
        empresa="${empresa_original}"
      fi
    done
  fi
  
  # Retornar arrays (usando variáveis globais)
  declare -g INSTANCIAS_DETECTADAS=("${instancias[@]}")
  declare -g NOMES_EMPRESAS_DETECTADAS=("${nomes_empresas[@]}")
}

# Função para selecionar qual instância usar
selecionar_instancia() {
  printf "${WHITE} >> Detectando instâncias instaladas...\n"
  echo
  
  detectar_instancias_instaladas
  
  local total_instancias=${#INSTANCIAS_DETECTADAS[@]}
  
  if [ $total_instancias -eq 0 ]; then
    printf "${RED} >> ERRO: Nenhuma instância instalada detectada!${WHITE}\n"
    printf "${YELLOW} >> Não é possível instalar Push Notifications. Verifique se há instâncias instaladas.${WHITE}\n"
    exit 1
  elif [ $total_instancias -eq 1 ]; then
    # Apenas uma instância, usar diretamente
    printf "${GREEN} >> Uma instância detectada: ${BLUE}${NOMES_EMPRESAS_DETECTADAS[0]}${WHITE}\n"
    echo
    sleep 2
    
    # Carregar variáveis da instância única
    mf_carregar_config "${INSTANCIAS_DETECTADAS[0]}"
    return 0
  else
    # Múltiplas instâncias, perguntar qual usar
    printf "${WHITE}═══════════════════════════════════════════════════════════\n"
    printf "  INSTÂNCIAS INSTALADAS DETECTADAS\n"
    printf "═══════════════════════════════════════════════════════════\n${WHITE}"
    echo
    
    local index=1
    for i in "${!NOMES_EMPRESAS_DETECTADAS[@]}"; do
      local empresa_nome="${NOMES_EMPRESAS_DETECTADAS[$i]}"
      local arquivo_instancia="${INSTANCIAS_DETECTADAS[$i]}"
      
      # Carregar variáveis temporariamente para obter URLs
      local empresa_original="${empresa:-}"
      local subdominio_backend_original="${subdominio_backend:-}"
      local subdominio_frontend_original="${subdominio_frontend:-}"
      
      mf_carregar_config "$arquivo_instancia" 2>/dev/null
      local temp_backend="${subdominio_backend:-}"
      local temp_frontend="${subdominio_frontend:-}"
      
      empresa="${empresa_original}"
      subdominio_backend="${subdominio_backend_original}"
      subdominio_frontend="${subdominio_frontend_original}"
      
      printf "   [${BLUE}${index}${WHITE}] ${BLUE}${empresa_nome}${WHITE}\n"
      if [ -n "$temp_backend" ]; then
        printf "       Backend: ${YELLOW}https://${temp_backend}${WHITE}\n"
      fi
      if [ -n "$temp_frontend" ]; then
        printf "       Frontend: ${YELLOW}https://${temp_frontend}${WHITE}\n"
      fi
      echo
      
      index=$((index + 1))
    done
    
    printf "${WHITE} >> Selecione a instância para instalar Push Notifications:${WHITE}\n"
    read -p "> " opcao_selecionada
    
    # Validar entrada
    if ! [[ "$opcao_selecionada" =~ ^[0-9]+$ ]] || [ "$opcao_selecionada" -lt 1 ] || [ "$opcao_selecionada" -gt $total_instancias ]; then
      printf "${RED} >> Opção inválida!${WHITE}\n"
      exit 1
    fi
    
    local indice_selecionado=$((opcao_selecionada - 1))
    
    # Carregar variáveis da instância selecionada
    mf_carregar_config "${INSTANCIAS_DETECTADAS[$indice_selecionado]}"
    printf "${GREEN} >> Instância selecionada: ${BLUE}${empresa}${WHITE}\n"
    echo
    sleep 2
    return 0
  fi
}

# Selecionar instância antes de continuar
selecionar_instancia

BACKEND_ENV="/home/deploy/${empresa}/backend/.env"
FRONTEND_ENV="/home/deploy/${empresa}/frontend/.env"

printf "${BLUE}"
printf "\n"
printf "██████╗ ██╗   ██╗███████╗██╗  ██╗\n"
printf "██╔══██╗██║   ██║██╔════╝██║  ██║\n"
printf "██████╔╝██║   ██║███████╗███████║\n"
printf "██╔═══╝ ██║   ██║╚════██║██╔══██║\n"
printf "██║     ╚██████╔╝███████║██║  ██║\n"
printf "╚═╝      ╚═════╝ ╚══════╝╚═╝  ╚═╝\n"
printf "    INSTALADOR PUSH NOTIFICATIONS\n"
printf "${WHITE}\n"
printf "${WHITE} >> Instância selecionada: ${BLUE}${empresa}${WHITE}\n"
echo

# Verificar se o diretório do backend existe
if [ ! -d "/home/deploy/${empresa}/backend" ]; then
  printf "${RED} >> Erro: Diretório /home/deploy/${empresa}/backend não encontrado!${WHITE}\n"
  printf "${RED} >> Certifique-se de que a instalação principal foi concluída.${WHITE}\n"
  exit 1
fi

# Verificar se o arquivo .env do backend existe
if [ ! -f "$BACKEND_ENV" ]; then
  printf "${RED} >> Erro: Arquivo .env do backend não encontrado!${WHITE}\n"
  exit 1
fi

printf "${WHITE} >> Verificando se as chaves VAPID já estão configuradas...\n"
echo

# Verificar se as variáveis VAPID já existem e têm valores
VAPID_PUBLIC=$(grep "^VAPID_PUBLIC_KEY=" "$BACKEND_ENV" | cut -d '=' -f2)
VAPID_PRIVATE=$(grep "^VAPID_PRIVATE_KEY=" "$BACKEND_ENV" | cut -d '=' -f2)
VAPID_SUBJECT=$(grep "^VAPID_SUBJECT=" "$BACKEND_ENV" | cut -d '=' -f2)

if [ -n "$VAPID_PUBLIC" ] && [ -n "$VAPID_PRIVATE" ] && [ -n "$VAPID_SUBJECT" ]; then
  printf "${GREEN} >> ✅ Push Notifications já está instalado nesta instância!${WHITE}\n"
  echo
  printf "${WHITE} >> Chaves VAPID encontradas no arquivo .env:${WHITE}\n"
  printf "${YELLOW}    VAPID_PUBLIC_KEY=${VAPID_PUBLIC}${WHITE}\n"
  printf "${YELLOW}    VAPID_PRIVATE_KEY=${VAPID_PRIVATE}${WHITE}\n"
  printf "${YELLOW}    VAPID_SUBJECT=${VAPID_SUBJECT}${WHITE}\n"
  echo
  printf "${WHITE} >> Nenhuma ação necessária.${WHITE}\n"
  exit 0
fi

printf "${YELLOW} >> Chaves VAPID não encontradas. Iniciando instalação...${WHITE}\n"
echo

# Verificar se web-push está instalado
printf "${WHITE} >> Verificando dependência web-push...${WHITE}\n"
echo

sudo su - deploy <<CHECKWEBPUSH
# Configura PATH para Node.js
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi

cd /home/deploy/${empresa}/backend || exit 1

if ! npm list web-push >/dev/null 2>&1; then
  printf "${WHITE} >> Instalando web-push...${WHITE}\n"
  npm install web-push --save >/dev/null 2>&1
else
  printf "${GREEN} >> web-push já está instalado${WHITE}\n"
fi
CHECKWEBPUSH

echo

printf "${WHITE} >> 🔑 Gerando chaves VAPID para Push Notifications...${WHITE}\n"
echo

# Gerar chaves VAPID usando Node.js
VAPID_OUTPUT=$(sudo su - deploy <<GENERATEVAPID
# Configura PATH para Node.js
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi

cd /home/deploy/${empresa}/backend || exit 1

node -e "
const webpush = require('web-push');
const vapidKeys = webpush.generateVAPIDKeys();
console.log(JSON.stringify({
  publicKey: vapidKeys.publicKey,
  privateKey: vapidKeys.privateKey
}));
" 2>/dev/null
GENERATEVAPID
)

if [ -z "$VAPID_OUTPUT" ]; then
  printf "${RED} >> Erro ao gerar chaves VAPID!${WHITE}\n"
  printf "${RED} >> Verifique se o web-push está instalado corretamente.${WHITE}\n"
  exit 1
fi

# Extrair as chaves do JSON
VAPID_PUBLIC_KEY=$(echo "$VAPID_OUTPUT" | grep -oP '"publicKey":\s*"\K[^"]+')
VAPID_PRIVATE_KEY=$(echo "$VAPID_OUTPUT" | grep -oP '"privateKey":\s*"\K[^"]+')
VAPID_SUBJECT_VALUE="mailto:scriptswhitelabel@gmail.com"

if [ -z "$VAPID_PUBLIC_KEY" ] || [ -z "$VAPID_PRIVATE_KEY" ]; then
  printf "${RED} >> Erro ao extrair chaves VAPID do JSON!${WHITE}\n"
  exit 1
fi

printf "${GREEN} >> ✅ Chaves geradas com sucesso!${WHITE}\n"
echo

printf "${WHITE} >> 📋 Adicionando variáveis no arquivo .env do BACKEND...${WHITE}\n"
echo

# Remover linhas antigas se existirem (mesmo vazias)
sed -i '/^VAPID_PUBLIC_KEY=/d' "$BACKEND_ENV"
sed -i '/^VAPID_PRIVATE_KEY=/d' "$BACKEND_ENV"
sed -i '/^VAPID_SUBJECT=/d' "$BACKEND_ENV"

# Adicionar novas variáveis ao backend .env
echo "" >> "$BACKEND_ENV"
echo "# Push Notifications - VAPID Keys" >> "$BACKEND_ENV"
echo "VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}" >> "$BACKEND_ENV"
echo "VAPID_PRIVATE_KEY=${VAPID_PRIVATE_KEY}" >> "$BACKEND_ENV"
echo "VAPID_SUBJECT=${VAPID_SUBJECT_VALUE}" >> "$BACKEND_ENV"

# Garantir permissões corretas
chown deploy:deploy "$BACKEND_ENV" 2>/dev/null || true
chmod 600 "$BACKEND_ENV" 2>/dev/null || true

printf "${GREEN}    VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}${WHITE}\n"
printf "${GREEN}    VAPID_PRIVATE_KEY=${VAPID_PRIVATE_KEY}${WHITE}\n"
printf "${GREEN}    VAPID_SUBJECT=${VAPID_SUBJECT_VALUE}${WHITE}\n"
echo

printf "${WHITE} >> 📋 Adicionando variável no arquivo .env do FRONTEND...${WHITE}\n"
echo

# Verificar se o arquivo .env do frontend existe
if [ -f "$FRONTEND_ENV" ]; then
  # Remover linha antiga se existir
  sed -i '/^REACT_APP_VAPID_PUBLIC_KEY=/d' "$FRONTEND_ENV"
  
  # Adicionar nova variável ao frontend .env
  echo "" >> "$FRONTEND_ENV"
  echo "# Push Notifications - VAPID Public Key" >> "$FRONTEND_ENV"
  echo "REACT_APP_VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}" >> "$FRONTEND_ENV"
  
  # Garantir permissões corretas
  chown deploy:deploy "$FRONTEND_ENV" 2>/dev/null || true
  chmod 644 "$FRONTEND_ENV" 2>/dev/null || true
  
  printf "${GREEN}    REACT_APP_VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}${WHITE}\n"
  echo
  
  printf "${WHITE} >> 🔨 Compilando o Frontend...${WHITE}\n"
  echo
  
  sudo su - deploy <<BUILDFRONTEND
  # Configura PATH para Node.js
  if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
    export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
  else
    export PATH=/usr/bin:/usr/local/bin:\$PATH
  fi
  
  cd /home/deploy/${empresa}/frontend || exit 1
  NODE_OPTIONS="--max-old-space-size=4096 --openssl-legacy-provider" npm run build
BUILDFRONTEND
  
  sleep 5
else
  printf "${YELLOW} >> Aviso: Arquivo .env do frontend não encontrado. Adicione manualmente:${WHITE}\n"
  printf "${YELLOW}    REACT_APP_VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}${WHITE}\n"
  echo
fi

printf "${WHITE} >> 🔄 Reiniciando aplicações...${WHITE}\n"
echo

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qE "^${empresa}_(backend|frontend)"; then
  docker restart "${empresa}_backend" "${empresa}_frontend" 2>/dev/null || true
  printf "${GREEN} >> Contêineres backend e frontend reiniciados via Docker.${WHITE}\n"
elif command -v pm2 >/dev/null 2>&1 || sudo su - deploy -c "command -v pm2" >/dev/null 2>&1; then
  sudo su - deploy <<RESTARTPM2
if [ -d /usr/local/n/versions/node/20.19.4/bin ]; then
  export PATH=/usr/local/n/versions/node/20.19.4/bin:/usr/bin:/usr/local/bin:\$PATH
else
  export PATH=/usr/bin:/usr/local/bin:\$PATH
fi

pm2 flush 2>/dev/null || true
pm2 restart ${empresa}-backend 2>/dev/null || true
pm2 restart ${empresa}-frontend 2>/dev/null || true
pm2 reset all 2>/dev/null || true
pm2 save 2>/dev/null || true
RESTARTPM2
fi

echo
printf "${GREEN} >> ✨ Push Notifications instalado com sucesso na instância ${empresa}!${WHITE}\n"
echo
printf "${WHITE} >> Resumo da instalação:${WHITE}\n"
printf "${BLUE}    Instância: ${WHITE}${empresa}${WHITE}\n"
printf "${BLUE}    Backend .env:  ${WHITE}${BACKEND_ENV}${WHITE}\n"
printf "${BLUE}    Frontend .env: ${WHITE}${FRONTEND_ENV}${WHITE}\n"
echo
