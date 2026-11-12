#!/bin/sh
# Official entry: only POSIX shell built-ins and the Docker CLI run on the host.
set -eu
case "$0" in */*) script_dir=${0%/*} ;; *) script_dir=. ;; esac
installer_dir=$(CDPATH= cd -P "$script_dir" && pwd)
target=${AMANDA_INSTALL_DIR:-${HOME:-$PWD}/amanda}
config=
action=menu
initial=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dir) [ "$#" -ge 2 ] || { printf '%s\n' 'Falta o diretório.' >&2; exit 2; }; target=$2; shift 2 ;;
    --config) [ "$#" -ge 2 ] || { printf '%s\n' 'Falta o arquivo de configuração.' >&2; exit 2; }; config=$2; shift 2 ;;
    --atualizar|atualizar|2) action=update; shift ;;
    --help|-h|help) action=help; shift ;;
    menu|install|update|resume|adopt|start|stop|restart|status|logs|backup|doctor|build-token|unlock) action=$1; shift ;;
    *) printf 'Argumento não suportado: %s\nUse: sh instalador_single.sh help\n' "$1" >&2; exit 2 ;;
  esac
done
if [ "$action" = menu ] && [ -t 0 ]; then
  . "$installer_dir/docker/installer/historical.sh"
  historical_main
  printf "\nDiretório da instalação: %s\n> " "$target"
  read -r initial || exit 0
  case "$initial" in 0) exit 0 ;; 1|2|3|4|5|6|7|8|9|10|11) ;; *) printf '%s\n' 'Opção inválida.' >&2; exit 2 ;; esac
fi
case "$target" in
  /*) ;;
  *) target=$PWD/$target ;;
esac
parent=$target
suffix=
while [ ! -d "$parent" ]; do
  suffix=/${parent##*/}$suffix
  parent=${parent%/*}
  [ -n "$parent" ] || parent=/
done
target=$(CDPATH= cd -P "$parent" && pwd)$suffix
case "$target" in /|/etc|/usr|/bin|/sbin|/dev|/proc|/sys|/var/lib/docker) printf '%s\n' 'Escolha uma pasta exclusiva para a AMANDA.' >&2; exit 2 ;; esac
case "$target" in /etc/*|/usr/*|/bin/*|/sbin/*|/dev/*|/proc/*|/sys/*|/run|/run/*|/var/lib/docker/*|*/../*|*/..|*:*|*,*) printf '%s\n' 'Diretório protegido ou caminho não suportado.' >&2; exit 2 ;; esac
command -v docker >/dev/null 2>&1 || { printf '%s\n' 'Docker não encontrado. Disponibilize o Docker Engine e acesso ao daemon.' >&2; exit 1; }
os=$(docker info --format '{{.OSType}}') || { printf '%s\n' 'Docker inacessível. Use uma conta com acesso ao socket ou execute este comando com sudo. Nenhuma permissão do socket foi alterada.' >&2; exit 1; }
[ "$os" = linux ] || { printf '%s\n' 'É necessário um Docker Engine com containers Linux.' >&2; exit 1; }
endpoint=${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}')}
case "$endpoint" in unix://*) socket=${endpoint#unix://} ;; *) printf '%s\n' 'Selecione um daemon Docker local com socket Unix (inclui Docker rootless).' >&2; exit 1 ;; esac
image=amanda-installer:local
printf '%s\n' 'Preparando ferramentas em container. Na primeira execução, o download pode demorar; nenhuma aplicação será instalada antes da configuração.'
bootstrap=amanda_bootstrap_$$
docker run --rm --name "${bootstrap}_build" --mount "type=bind,source=$socket,target=/var/run/docker.sock" --mount "type=bind,source=$installer_dir,target=$installer_dir,readonly" -e DOCKER_HOST=unix:///var/run/docker.sock -e DOCKER_BUILDKIT=1 docker:27.5.1-cli docker build -f "$installer_dir/docker/installer/Dockerfile" -t "$image" "$installer_dir"
terminal=-i
if [ -t 0 ] && [ -t 1 ]; then terminal=-it; fi
set -- run --rm --name "$bootstrap" "$terminal" --mount "type=bind,source=$socket,target=/var/run/docker.sock" -e "AMANDA_MANAGER_CONTAINER=$bootstrap" -e TERM -e COLORTERM -e NO_COLOR -e WT_SESSION -e DOCKER_HOST=unix:///var/run/docker.sock -e "AMANDA_DOCKER_SOCKET=$socket" -e "AMANDA_INSTALL_DIR=$target" -e "AMANDA_MANAGER_IMAGE=$image"
case "$action" in help|doctor) ;; *) set -- "$@" -v "$target:$target" ;; esac
if [ -n "$config" ]; then
  case "$config" in /*) ;; *) config=$PWD/$config ;; esac
  set -- "$@" --mount "type=bind,source=$config,target=/run/amanda-setup.json,readonly"
fi
set -- "$@" "$image" "$action"
if [ -n "$initial" ]; then set -- "$@" --initial "$initial"; fi
if [ -n "$config" ]; then set -- "$@" --config /run/amanda-setup.json; fi
exec docker "$@"
