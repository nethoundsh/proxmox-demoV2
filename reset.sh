#!/usr/bin/env bash
set -euo pipefail
PVE_HOST="192.168.1.11"
PVE_USER="pippi"
SNAPSHOT="clean"

declare -A TARGETS=(
      ["target-01"]="102"
    )

reset_vm() {
  local name="$1"
  local vm_id="${TARGETS[${name}]}"
  echo "Rolling ${name} (VM ${vm_id}) back to ${SNAPSHOT}..."
  ssh "${PVE_USER}@${PVE_HOST}" "sudo qm rollback ${vm_id} ${SNAPSHOT} --start"
  echo "${name} reset complete."
}

if [[ $# -eq 0 ]]; then
  for name in "${!TARGETS[@]}"; do
    reset_vm "${name}"
  done
else
  for name in "$@"; do
    reset_vm "${name}"
  done
fi
