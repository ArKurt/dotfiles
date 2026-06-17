#!/usr/bin/env bash
# dotfiles dispatcher — install one or more tools by name.
#
#   ./install.sh                 list available tools
#   ./install.sh <tool> [<tool>] install those tools
#   ./install.sh all             install everything
#
# Each tool is a directory under claude/ (or any top dir) containing an
# executable install.sh. Adding a new tool = drop a folder with its own
# install.sh; this dispatcher finds it automatically.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# discover tools: any */install.sh except this top-level one
mapfile -t INSTALLERS < <(find "$ROOT" -mindepth 2 -maxdepth 3 -name install.sh | sort)

list() {
  echo "Available tools:"
  for inst in "${INSTALLERS[@]}"; do
    name="$(basename "$(dirname "$inst")")"
    printf "  %s\n" "$name"
  done
  echo
  echo "Usage: ./install.sh <tool> [<tool> ...]   |   ./install.sh all"
}

run_tool() {
  local want="$1" found=0
  for inst in "${INSTALLERS[@]}"; do
    name="$(basename "$(dirname "$inst")")"
    if [ "$name" = "$want" ]; then
      echo "── installing: $name ──"
      bash "$inst"
      found=1
      break
    fi
  done
  if [ "$found" -eq 0 ]; then
    echo "✗ unknown tool: $want" >&2
    return 1
  fi
}

if [ "$#" -eq 0 ]; then
  list
  exit 0
fi

if [ "$1" = "all" ]; then
  for inst in "${INSTALLERS[@]}"; do
    name="$(basename "$(dirname "$inst")")"
    echo "── installing: $name ──"
    bash "$inst"
  done
  exit 0
fi

for t in "$@"; do
  run_tool "$t"
done
