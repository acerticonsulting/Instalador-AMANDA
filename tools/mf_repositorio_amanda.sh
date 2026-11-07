#!/usr/bin/env bash
# Apenas define funções; não acessa rede nem altera o host.
mf_validar_repositorio_amanda() {
  local url="${1:-}"
  url="$(printf '%s' "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
  case "$url" in
    https://github.com/acerticonsulting/amanda|https://github.com/acerticonsulting/amanda/|https://github.com/acerticonsulting/amanda.git|https://github.com/acerticonsulting/amanda.git/)
      return 0 ;;
  esac
  printf '%s\n' 'Instalação bloqueada: informe https://github.com/acerticonsulting/AMANDA (sem credenciais na URL).' >&2
  return 1
}

mf_solicitar_repositorio_amanda() {
  local entrada
  printf '%s\n' 'Informe o link do código da AMANDA para continuar:' 'https://github.com/acerticonsulting/AMANDA'
  IFS= read -r entrada || return 1
  mf_validar_repositorio_amanda "$entrada" || return 1
  repo_url='https://github.com/acerticonsulting/AMANDA.git'
}
