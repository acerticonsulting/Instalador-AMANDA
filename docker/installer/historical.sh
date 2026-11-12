#!/bin/sh
# Apresentação extraída de 7a5b31da3ce48fb50fe451fbcbe840f725fa8838. Não contém operações de instalação.
# Gerado por tools/extrair_interface_historica.cjs; adaptações explícitas nesse arquivo.
historical_theme() {
  PURPLE= BLUE= MAGENTA= GREEN= WHITE= RED= YELLOW= CYAN= NC= RESET=
  if { [ -t 1 ] || [ "${AMANDA_UI_TTY:-}" = 1 ]; } && [ "${TERM:-}" != dumb ] && [ "${NO_COLOR+x}" != x ]; then
    PURPLE='\033[38;5;99m'; BLUE='\033[1;94m'; GREEN='\033[1;92m'; WHITE='\033[1;97m'; RED='\033[1;91m'; YELLOW='\033[1;93m'; CYAN='\033[1;96m'
    case "${COLORTERM:-}:${TERM:-}:${WT_SESSION:-}" in *truecolor*|*24bit*|*xterm*|*256color*|*screen*|*tmux*|*linux*|*alacritty*|*kitty*)
      PURPLE='\033[38;2;139;92;246m'; BLUE='\033[1;38;2;167;139;250m'; GREEN='\033[1;38;2;74;222;128m'; WHITE='\033[1;38;2;255;255;255m'; RED='\033[1;38;2;248;113;113m'; YELLOW='\033[1;38;2;250;204;21m'; CYAN='\033[1;38;2;56;189;248m' ;;
    esac
    NC='\033[0m'; RESET=$NC
  fi
}
banner() {
  if { [ -t 1 ] || [ "${AMANDA_UI_TTY:-}" = 1 ]; } && [ "${TERM:-}" != dumb ] && [ "${NO_COLOR+x}" != x ]; then printf '\033[2J\033[H'; fi
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

historical_main() {
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
    printf "   [${BLUE}10${WHITE}] Homologação GHCR / Configurar Atualização Agendada\n"
    printf "   [${BLUE}11${WHITE}] Instalar ou Gerenciar API Oficial\n"
    printf "   [${BLUE}0${WHITE}] Sair\n"
    echo

}
historical_tools() {
    banner
    printf "${WHITE} Selecione abaixo a ferramenta desejada:\n"
    echo
    printf "  ${BLUE}━━ Instalações e integrações ━━${WHITE}\n"
    printf "   [${BLUE}2${WHITE}] Instalar Push Notifications\n"
    printf "   [${BLUE}3${WHITE}] Instalar API WhatsMeow\n"
    printf "   [${BLUE}5${WHITE}] Instalar Nova Instância\n"
    printf "   [${BLUE}31${WHITE}] Instalar ou Gerenciar API Oficial (WhatsApp Meta Cloud)\n"
    printf "   [${BLUE}32${WHITE}] Atualizar API Oficial (Docker)\n"
    echo
    printf "  ${BLUE}━━ Versão da aplicação ━━${WHITE}\n"
    printf "   [${BLUE}4${WHITE}] Roolback Versão\n"
    printf "   [${BLUE}30${WHITE}] Atualizar token GitHub + FAST (repositório oficial)\n"
    echo
    printf "  ${BLUE}━━ Backups agendados ━━${WHITE}\n"
    printf "   [${BLUE}6${WHITE}] Agendar Backup Diário do Banco Alta Performance\n"
    printf "   [${BLUE}7${WHITE}] Agendar Backup Diário do Banco Nativo (indisponível neste modo)\n"
    echo
    printf "  ${BLUE}━━ Redis ━━${WHITE}\n"
    printf "   [${BLUE}8${WHITE}] Backup do Redis (instância / Docker)\n"
    printf "   [${BLUE}9${WHITE}] Restaurar Redis (backup da instância → container)\n"
    echo
    printf "  ${BLUE}━━ Banco de dados (PostgreSQL) ━━${WHITE}\n"
    printf "   [${BLUE}10${WHITE}] Importar backup do banco (instância + escolher banco)\n"
    printf "   [${BLUE}11${WHITE}] Backup do banco\n"
    printf "   [${BLUE}12${WHITE}] Importar backup do banco da API Oficial (Docker)\n"
    printf "   [${BLUE}13${WHITE}] Listar Bancos Existentes\n"
    printf "   [${BLUE}14${WHITE}] Restaurar backup do Banco Alta Performance (Docker)\n"
    echo
    printf "  ${BLUE}━━ WhatsMeow (WuzAPI) ━━${WHITE}\n"
    printf "   [${BLUE}22${WHITE}] Backup do WhatsMeow (volume WuzAPI / SQLite)\n"
    printf "   [${BLUE}23${WHITE}] Restaurar backup do banco WhatsMeow\n"
    echo
    printf "  ${BLUE}━━ Domínio, SSL e Docker ━━${WHITE}\n"
    printf "   [${BLUE}15${WHITE}] Trocar domínios (URL backend / frontend)\n"
    printf "   [${BLUE}21${WHITE}] Aplicar certificado SSL no Caddy (Docker)\n"
    printf "   [${BLUE}20${WHITE}] Domínio + porta + SSL no Caddy (Docker)\n"
    printf "   [${BLUE}19${WHITE}] Instalar Portainer (Docker)\n"
    echo
    printf "  ${BLUE}━━ Performance e dependências ━━${WHITE}\n"
    printf "   [${BLUE}16${WHITE}] Atualizar Baileys pela versão oficial da plataforma\n"
    printf "   [${BLUE}17${WHITE}] Atualizar API WhatsMeow (WuzAPI — imagem oficial)\n"
    printf "   [${BLUE}18${WHITE}] Otimizar Postgres em Docker\n"
    echo
    printf "  ${BLUE}━━ Menu ━━${WHITE}\n"
    printf "   [${BLUE}0${WHITE}] Voltar ao Menu Principal\n"
    echo

}
historical_api() {
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
    printf "     [${BLUE}8${WHITE}] Configurar Caddy e Emitir Certificado SSL para API Oficial\n"
    printf "     [${BLUE}9${WHITE}] Desinstalar API Oficial\n"
    printf "     [${BLUE}0${WHITE}] Voltar ao Menu Principal\n\n"
    printf "${WHITE}   Escolha uma opção: ${PURPLE}"
}
historical_channel() {
  banner
  printf "   ${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "   ${PURPLE}║${WHITE}           SELEÇÃO DE CANAL DE VERSÃO / BRANCH AMANDA         ${PURPLE}║${WHITE}\n"
  printf "   ${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
  printf "   ${WHITE}Escolha qual versão/branch você deseja utilizar para ${motivo}:${WHITE}\n\n"
  printf "   [${BLUE}1${WHITE}] ${GREEN}Versão Estável (main)${WHITE} - Recomendada para Produção / Clientes\n"
  printf "   [${BLUE}2${WHITE}] ${YELLOW}Versão de Desenvolvimento (davi-alteracoes)${WHITE} - Correções e recursos recentes (GLPI)\n"
  printf "   [${BLUE}3${WHITE}] ${PURPLE}Versão de Desenvolvimento (alan-alteracoes)${WHITE} - Recursos em homologação\n"
  printf "   [${BLUE}4${WHITE}] ${CYAN}Personalizada${WHITE} - Digitar o nome de outra branch específica\n\n"
  printf "   ${WHITE}Digite a opção desejada [1-4] (Padrão: 1): ${PURPLE}"

}
historical_status() {
  banner
  printf "   ${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "   ${PURPLE}║${WHITE}            STATUS E REINÍCIO DE CONTÊINERES                  ${PURPLE}║${WHITE}\n"
  printf "   ${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
  printf "   ${WHITE}Instância selecionada: ${GREEN}%s${WHITE}\n\n" "$emp"
  echo
  printf "   ${WHITE}Opções:\n"
  printf "     [1] Reiniciar TODOS os contêineres da instância [%s]\n" "$emp"
  printf "     [2] Reiniciar apenas Backend (${emp}_backend)\n"
  printf "     [3] Reiniciar apenas Frontend (${emp}_frontend)\n"
  printf "     [4] Reiniciar apenas API Oficial (${emp}_api_oficial)\n"
  printf "     [5] Reiniciar apenas WuzAPI (${emp}_wuzapi)\n"
  printf "     [6] Reiniciar apenas Transcrição (${emp}_api_transcricao)\n"
  printf "     [0] Voltar ao Menu Principal\n\n"
  printf "${WHITE}   Escolha uma opção: ${PURPLE}"
}
historical_update() {
  banner
  printf "   ${PURPLE}╔══════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "   ${PURPLE}║${WHITE}             ATUALIZAR AMANDA (DOCKER COMPOSE)                ${PURPLE}║${WHITE}\n"
  printf "   ${PURPLE}╚══════════════════════════════════════════════════════════════╝${WHITE}\n\n"
  printf "   ${WHITE}Instância selecionada: ${GREEN}%s${WHITE}\n\n" "${empresa:-amanda}"

}
historical_optimize() {
  banner
  printf "${WHITE} >> Deseja aplicar a otimização do PostgreSQL em container conforme o perfil da VPS?${WHITE}\n"
  echo
  printf "${WHITE} >> Escolha o perfil do servidor:${WHITE}\n"
  echo
  printf "   [${BLUE}1${WHITE}] VPS com 4 Core x 8 GB RAM\n"
  printf "   [${BLUE}2${WHITE}] VPS com 6 Core x 16 GB RAM\n"
  printf "   [${BLUE}3${WHITE}] VPS com 8 Core x 32 GB RAM\n"
  printf "   [${BLUE}0${WHITE}] Não otimizar\n"
  echo
}
historical_summary() {
  printf "   ${WHITE}Anote os dados abaixo\n\n"
  printf '   %bSubdominio Backend: ---->> %b%s\n' "$WHITE" "$YELLOW" "${subdominio_backend}"
  printf '   %bSubdominiio Frontend: -->> %b%s\n' "$WHITE" "$YELLOW" "${subdominio_frontend}"
  printf '   %bSeu Email: ------------->> %b%s\n' "$WHITE" "$YELLOW" "${email_deploy}"
  printf '   %bNome da Empresa: ------->> %b%s\n' "$WHITE" "$YELLOW" "${empresa}"
  printf '   %bSenha Deploy: ---------->> %b%s\n' "$WHITE" "$YELLOW" "[oculta]"
  printf '   %bSenha Master: ---------->> %b%s\n' "$WHITE" "$YELLOW" "[oculta]"
  printf '   %bTitulo da Aplicação: --->> %b%s\n' "$WHITE" "$YELLOW" "${nome_titulo}"
  printf '   %bNumero de Suporte: ----->> %b%s\n' "$WHITE" "$YELLOW" "${numero_suporte}"
  printf '   %bFACEBOOK_APP_ID: ------->> %b%s\n' "$WHITE" "$YELLOW" "${facebook_app_id}"
  printf '   %bFACEBOOK_APP_SECRET: --->> %b%s\n' "$WHITE" "$YELLOW" "[oculta]"
  printf '   %bToken GitHub: ---------->> %b%s\n' "$WHITE" "$YELLOW" "[oculta]"
  printf '   %bURL do Repositório: ---->> %b%s\n' "$WHITE" "$YELLOW" "${repo_url}"
  printf '   %bProxy Usado: ----------->> %b%s\n' "$WHITE" "$YELLOW" "${proxy}"
  printf '   %bPorta Backend: --------->> %b%s\n' "$WHITE" "$YELLOW" "${backend_port}"
  printf '   %bPorta Frontend: -------->> %b%s\n' "$WHITE" "$YELLOW" "${frontend_port}"
  printf '   %bPorta PostgreSQL: ------>> %b%s\n' "$WHITE" "$YELLOW" "${PORT_DB:-5432}"
  printf '   %bPorta Redis: ----------->> %b%s\n' "$WHITE" "$YELLOW" "${PORT_REDIS:-6379}"
  printf '   %bPorta Transcrição: ----->> %b%s\n' "$WHITE" "$YELLOW" "${PORT_TRANSCRIBER:-4002}"
  printf '   %bPorta Wuzapi: ---------->> %b%s\n' "$WHITE" "$YELLOW" "${PORT_WUZAPI:-8090}"
  printf '   %bVersão Instalada: ------->> %b%s\n' "$WHITE" "$YELLOW" "${versao_instalacao}"
  printf '   %bCommit Instalado: ------->> %b%s\n' "$WHITE" "$YELLOW" "${commit_instalacao}"
}
historical_question() {
  case "$1" in
    modo_rede)
  banner
  printf "${WHITE} Selecione como deseja acessar a plataforma AMANDA:\n\n"
  printf "   [${BLUE}1${WHITE}] Sem Domínio (Apenas IP / Localhost)\n"
  printf "       ${PURPLE}✓ Ideal para testes, ambiente local, WSL ou VPS sem domínio.${WHITE}\n"
  printf "       ${PURPLE}✓ Sem necessidade de apontar DNS nem emitir SSL.${WHITE}\n"
  printf "       ${PURPLE}✓ Acesso direto pelas portas 3000 (Frontend), 8080 (Backend) e 6000 (API Oficial).${WHITE}\n\n"
  printf "   [${BLUE}2${WHITE}] Com Domínios Próprios (SSL HTTPS + Proxy Reverso Caddy em Docker)\n"
  printf "       ${PURPLE}✓ Para produção com subdomínios (ex: app.meudominio.com e api.meudominio.com).${WHITE}\n\n"
  printf " Selecione a opção [1 ou 2, padrão: 1]: "
      ;;
    host_escolhido)
    banner
    printf "${GREEN} >> Modo Sem Domínio (IP / Localhost) selecionado.${WHITE}\n\n"
      printf "${YELLOW} >> Detectado ambiente local/WSL ou IP atrás de NAT (${ip_atual}).${WHITE}\n"
      printf "${YELLOW}    Recomendado usar 'localhost' para testes na própria máquina.${WHITE}\n\n"
    printf "${WHITE} Insira o IP do servidor ou 'localhost' para acesso [Padrão: ${PURPLE}${ip_sugerido}${WHITE}]:\n"
      ;;
    subdominio_backend)
  banner
  printf "${WHITE} >> Insira o domínio/URL do ${PURPLE}Backend${WHITE} (ex: api.seudominio.com.br):\n"
  printf "    ${YELLOW}(Ou pressione ENTER para modo Sem Domínio / IP)${WHITE}\n\n"
      ;;
    subdominio_frontend)
  banner
  printf "${WHITE} >> Insira o domínio/URL do ${PURPLE}Frontend${WHITE} (ex: app.seudominio.com.br): \n"
  echo
      ;;
    email_deploy)
  banner
  printf "${WHITE} >> Digite o seu melhor email: \n"
  echo
      ;;
    input_empresa)
  banner
  printf "${WHITE} >> Digite o nome da sua empresa (Letras minusculas e sem espaço) [padrão: ${GREEN}%s${WHITE}]: \n" "$emp_padrao"
  echo
      ;;
    senha_deploy)
  banner
  printf "${WHITE} >> Insira a senha do Banco de Dados [ENTER gera senha segura; Deploy nativo dispensado]: \n"
  echo
      ;;
    senha_master)
  banner
  printf "${WHITE} >> Insira a senha para o MASTER [ENTER gera chave segura]: \n"
  echo
      ;;
    nome_titulo)
  banner
  printf "${WHITE} >> Insira o Titulo da Aplicação (Permitido Espaço) [padrão: AMANDA]: \n"
  echo
      ;;
    numero_suporte)
  banner
  printf "${WHITE} >> Digite o numero de telefone para suporte: \n"
  echo
      ;;
    facebook_app_id)
  banner
  printf "${WHITE} >> Digite o FACEBOOK_APP_ID caso tenha: \n"
  echo
      ;;
    facebook_app_secret)
  banner
  printf "${WHITE} >> Digite o FACEBOOK_APP_SECRET caso tenha: \n"
  echo
      ;;
    github_token)
  banner
  printf "${WHITE} >> Digite seu TOKEN de acesso pessoal do GitHub (deixe em branco se o repo for público): \n"
  printf "${WHITE} >> Passo a Passo para gerar o seu TOKEN no link ${BLUE}https://bit.ly/token-github ${WHITE} \n"
  echo
      ;;
    repo_url)
  banner
  printf "${WHITE} >> Digite a URL do repositório Git [padrão: https://github.com/acerticonsulting/AMANDA.git]: \n"
  echo
      ;;
    proxy)
  banner
  printf "${WHITE} >> Proxy reverso HTTPS em container: Caddy (substitui Nginx/Traefik no host).${WHITE}\n"
      ;;
    use_default_ports)
  banner
  printf "${WHITE}╔══════════════════════════════════════════════════════════════════════╗${WHITE}\n"
  printf "${WHITE}║       ${PURPLE}EXIBIÇÃO DO STATUS DAS PORTAS EM TEMPO REAL NA VPS${WHITE}            ║${WHITE}\n"
  printf "${WHITE}╚══════════════════════════════════════════════════════════════════════╝${WHITE}\n"
  echo
  printf "   ${WHITE}● ${CYAN}PORTAS EDITÁVEIS PELO USUÁRIO:${WHITE}\n"
  printf "     1) Backend AMANDA (API):       ${YELLOW}8080${WHITE}  ---> %b\n" "$st_be"
  printf "     2) Frontend AMANDA (Web):      ${YELLOW}3000${WHITE}  ---> %b\n\n" "$st_fe"
  printf "   ${WHITE}ℹ️  ${YELLOW}As únicas portas personalizáveis nesta etapa são as do Frontend e Backend.${WHITE}\n\n"
  printf "${WHITE} >> Usar as portas padrão para Backend (8080) e Frontend (3000) ? (S/N) [Padrão: S]: ${WHITE}\n"
  echo
      ;;
    backend_port)
  echo
      printf "${WHITE} >> Qual porta deseja para o Backend? [padrão: 8080]: ${WHITE}\n"
      echo
      ;;
    frontend_port)
      echo
      printf "${WHITE} >> Qual porta deseja para o Frontend? [padrão: 3000]: ${WHITE}\n"
      echo
      ;;
    confirmacao)
  banner
  printf "${WHITE} >> Confira abaixo os dados dessa instalação! ${WHITE}\n\n"
  echo
  printf "${WHITE} >> Os dados estão corretos? ${GREEN}S/${RED}N:${WHITE} \n"
  echo
      ;;
    *) return 2 ;;
  esac
}
historical_theme
nome_titulo=${nome_titulo:-AMANDA}
case "${1:-}" in --main) historical_main ;; --tools) historical_tools ;; --api) historical_api ;; --channel) historical_channel ;; --status) historical_status ;; --update) historical_update ;; --optimize) historical_optimize ;; --summary) historical_summary ;; --question) historical_question "$2" ;; esac
