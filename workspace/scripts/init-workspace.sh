#!/usr/bin/env bash

set -ax
trap 'kill 0' EXIT

script_dir="$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )"
KONTRAKCJA_ROOT=${KONTRAKCJA_ROOT:-`pwd -P`}
KONTRAKCJA_WORKSPACE=${KONTRAKCJA_WORKSPACE:-"$KONTRAKCJA_ROOT"}

init_file="$KONTRAKCJA_WORKSPACE/_local/.initialized"

echo "script_dir:" $script_dir

if [[ ! -e "$init_file" ]]; then
  echo "Initializing workspace"

  "$script_dir/generate-config.sh"

  "$script_dir/init-postgres.sh"
  echo "database initialized"

  touch "$init_file"

else
  echo "Workspace is already initialized"
fi
