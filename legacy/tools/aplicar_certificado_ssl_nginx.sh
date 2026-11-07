#!/bin/bash

# Aplica certificado SSL no Nginx via Certbot (modo interativo).

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

if [ "$EUID" -ne 0 ]; then
  echo
  printf "${WHITE} >> Este script precisa ser executado como root.${WHITE}\n"
  exit 1
fi

banner() {
  printf " ${BLUE}\n"
  printf "  Certificado SSL no Nginx\n"
  printf " ${WHITE}\n"
}

validar_ambiente() {
  if ! command -v nginx >/dev/null 2>&1; then
    printf "${RED} >> Nginx não encontrado. Instale o Nginx antes de aplicar o certificado.${WHITE}\n"
    sleep 3
    return 1
  fi

  if ! command -v certbot >/dev/null 2>&1; then
    printf "${RED} >> Certbot não encontrado. Instale o Certbot antes de continuar.${WHITE}\n"
    sleep 3
    return 1
  fi

  if ! systemctl is-active --quiet nginx 2>/dev/null; then
    printf "${YELLOW} >> Nginx não está ativo. Tentando iniciar...${WHITE}\n"
    if ! systemctl start nginx 2>/dev/null && ! service nginx start 2>/dev/null; then
      printf "${RED} >> Não foi possível iniciar o Nginx.${WHITE}\n"
      sleep 3
      return 1
    fi
  fi

  return 0
}

main() {
  banner
  printf "${WHITE} >> Esta ferramenta executa o Certbot no modo Nginx para emitir ou renovar certificados SSL.${WHITE}\n"
  printf "${WHITE} >> Siga as perguntas do Certbot na sequência.${WHITE}\n"
  echo

  if ! validar_ambiente; then
    return 1
  fi

  printf "${GREEN} >> Executando: certbot --nginx${WHITE}\n"
  echo
  certbot --nginx
  local status=$?

  echo
  if [ "$status" -eq 0 ]; then
    printf "${GREEN} >> Certbot concluído com sucesso.${WHITE}\n"
  else
    printf "${RED} >> Certbot finalizou com erro (código ${status}).${WHITE}\n"
  fi

  sleep 2
  return "$status"
}

main "$@"
