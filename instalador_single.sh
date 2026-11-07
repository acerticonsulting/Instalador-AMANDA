#!/bin/sh
# Official entry: only POSIX shell built-ins and the Docker CLI run on the host.
set -eu
case "$0" in */*) script_dir=${0%/*} ;; *) script_dir=. ;; esac
installer_dir=$(CDPATH= cd -P "$script_dir" && pwd)
target=${AMANDA_INSTALL_DIR:-${HOME:-$PWD}/amanda}
config=
action=menu
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
os=$(docker info --format '{{.OSType}}') || exit 1
[ "$os" = linux ] || { printf '%s\n' 'É necessário um Docker Engine com containers Linux.' >&2; exit 1; }
endpoint=${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}')}
case "$endpoint" in unix://*) socket=${endpoint#unix://} ;; *) printf '%s\n' 'Selecione um daemon Docker local com socket Unix (inclui Docker rootless).' >&2; exit 1 ;; esac
image=amanda-installer:local
docker build -f "$installer_dir/docker/installer/Dockerfile" -t "$image" "$installer_dir"
terminal=-i
if [ -t 0 ] && [ -t 1 ]; then terminal=-it; fi
set -- run --rm "$terminal" --mount "type=bind,source=$socket,target=/var/run/docker.sock" -e DOCKER_HOST=unix:///var/run/docker.sock -e "AMANDA_INSTALL_DIR=$target"
case "$action" in help|doctor) ;; *) set -- "$@" -v "$target:$target" ;; esac
if [ -n "$config" ]; then
  case "$config" in /*) ;; *) config=$PWD/$config ;; esac
  set -- "$@" --mount "type=bind,source=$config,target=/run/amanda-setup.json,readonly"
fi
set -- "$@" "$image" "$action"
if [ -n "$config" ]; then set -- "$@" --config /run/amanda-setup.json; fi
exec docker "$@"
