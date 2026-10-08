#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
inventory="${INVENTORY:-$project_root/ansible/inventory.yaml}"

if [[ ! -f "$inventory" ]]; then
  printf 'Inventory not found: %s. Copy ansible/inventory.example.yaml first.\n' "$inventory" >&2
  exit 1
fi

"$project_root/scripts/build-image.sh"
if [[ "${SKIP_IMAGE_SAVE:-false}" == "true" ]]; then
  export SHARED_EXPENSES_IMAGE_ALREADY_LOADED=true
fi
ansible-playbook --inventory "$inventory" "$project_root/ansible/push.yaml" "$@"
