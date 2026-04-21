#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if (($# == 0)); then
  set -- auto
fi

if [[ "$1" == "auto" ]]; then
  formulae=()
  if [[ -n "${SHPIT_GH_TOKEN:-}" || -z "${GITHUB_ACTIONS:-}" ]]; then
    formulae+=(tabex)
    formulae+=(osyrra)
  fi
elif [[ "$1" == "all" ]]; then
  formulae=(
    tabex
    osyrra
  )
else
  formulae=("$@")
fi

for formula in "${formulae[@]}"; do
  case "${formula}" in
    tabex)
      if [[ "$1" == "auto" ]]; then
        "${repo_root}/scripts/update-tabex.sh" --optional
      else
        "${repo_root}/scripts/update-tabex.sh"
      fi
      ;;
    osyrra)
      if [[ "$1" == "auto" ]]; then
        "${repo_root}/scripts/update-osyrra.sh" --optional
      else
        "${repo_root}/scripts/update-osyrra.sh"
      fi
      ;;
    *)
      echo "unknown formula: ${formula}" >&2
      exit 1
      ;;
  esac
done
