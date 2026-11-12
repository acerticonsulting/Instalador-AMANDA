#!/bin/sh
# Caminho histórico 7a5b31d: operação adaptada ao Compose oficial, sem ferramentas nativas.
set -eu
case "$0" in */*) entry_dir=${0%/*} ;; *) entry_dir=. ;; esac
installer_root=$(CDPATH= cd -P "$entry_dir/.." && pwd)
exec sh "$installer_root/instalador_single.sh" configure "$@"
