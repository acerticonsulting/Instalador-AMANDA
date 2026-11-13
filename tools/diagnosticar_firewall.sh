#!/usr/bin/env bash
# Somente leitura. Execute na própria VPS; não instala ferramentas ou altera regras.
set -u
printf '%s\n' 'AMANDA — FIREWALL E ACESSO ADMINISTRATIVO (SOMENTE LEITURA)'
if [ -n "${SSH_CONNECTION:-}" ]; then
  read -r client_ip client_port server_ip ssh_port <<< "$SSH_CONNECTION"
  if [[ "$ssh_port" =~ ^[0-9]+$ ]]; then printf 'Porta da sessão SSH atual: %s\n' "$ssh_port"; fi
else
  printf '%s\n' 'Sessão SSH atual: não identificada; não presumir porta 22.'
fi
consultar(){
  local tool="$1"; shift
  printf '\nConsulta: %s\n' "$tool $*"
  if ! command -v "$tool" >/dev/null 2>&1; then printf '%s\n' 'Não disponível; não significa firewall inativo.'; return; fi
  if command -v timeout >/dev/null 2>&1; then timeout 10s "$tool" "$@" || printf '%s\n' 'Consulta incompleta/sem permissão ou serviço inativo; conferir saída.'
  else "$tool" "$@" || printf '%s\n' 'Consulta incompleta/sem permissão ou serviço inativo; conferir saída.'; fi
}
consultar ss -ltnp
consultar ufw status verbose
consultar firewall-cmd --state
consultar firewall-cmd --list-all-zones
consultar nft list ruleset
consultar iptables-save
consultar ip6tables-save
printf '\n%s\n' 'Firewall do provedor/NAT externo: NÃO VERIFICADO.' \
  'Não é possível atribuir timeout exclusivamente a firewall sem evidência de regras/roteamento.' \
  'Nenhuma regra alterada. Antes de qualquer liberação, preservar a porta/origens SSH reais e exigir autorização, regra proposta e reversão.'
