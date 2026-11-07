#!/usr/bin/env bash
# Credenciais de criação; nunca redefinir contas existentes durante atualizações.
mf_solicitar_admin_inicial() {
  local escolha email senha confirmacao
  MF_ADMIN_INICIAL_CONFIRMADO=0
  AMANDA_ADMIN_EMAIL='admin@amanda.com.br'
  AMANDA_ADMIN_PASSWORD='adminamanda'
  printf '%s\n' 'Acesso inicial padrão: admin@amanda.com.br / adminamanda'
  read -r -p 'Deseja personalizar o e-mail e a senha do administrador? [s/N]: ' escolha || return 1
  case "$escolha" in
    s|S|sim|SIM)
      read -r -p 'E-mail do administrador: ' email || return 1
      if [[ ! "$email" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
        printf '%s\n' 'E-mail inválido.' >&2; return 1
      fi
      read -r -s -p 'Senha do administrador: ' senha || return 1; printf '\n'
      read -r -s -p 'Confirme a senha: ' confirmacao || return 1; printf '\n'
      if [ -z "$senha" ] || [ "$senha" != "$confirmacao" ]; then
        printf '%s\n' 'Senha vazia ou confirmação diferente.' >&2; return 1
      fi
      AMANDA_ADMIN_EMAIL="${email,,}"
      AMANDA_ADMIN_PASSWORD="$senha"
      ;;
    ''|n|N|nao|não|NAO) ;;
    *) printf '%s\n' 'Escolha inválida; use s ou n.' >&2; return 1 ;;
  esac
  MF_ADMIN_INICIAL_CONFIRMADO=1
  export AMANDA_ADMIN_EMAIL AMANDA_ADMIN_PASSWORD MF_ADMIN_INICIAL_CONFIRMADO
}

mf_mostrar_admin_inicial() {
  printf '%s\n' 'Acesso para banco novo (bancos existentes mantêm as credenciais atuais):'
  printf 'Usuário Administrador: %s\n' "${AMANDA_ADMIN_EMAIL:-admin@amanda.com.br}"
  if [ "${AMANDA_ADMIN_PASSWORD:-adminamanda}" = 'adminamanda' ]; then
    printf '%s\n' 'Senha padrão: adminamanda'
  else
    printf '%s\n' 'Senha: a senha personalizada informada na instalação (não exibida).'
  fi
}
