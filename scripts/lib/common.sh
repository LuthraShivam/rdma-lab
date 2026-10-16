# Shared helpers. Source this file; do not execute it.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SETUPS_DIR="${REPO_ROOT}/setups"
SCRIPTS_DIR="${REPO_ROOT}/scripts"

# DRY_RUN=1 prints mutating commands instead of running them.
DRY_RUN="${DRY_RUN:-0}"

log() { printf '[%s] %s\n' "$(basename "$0")" "$*" >&2; }
die() { log "error: $*"; exit 1; }

require_root() {
  [[ "${DRY_RUN}" == 1 || "${EUID}" -eq 0 ]] || die "must run as root (try sudo)"
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    command -v "${cmd}" >/dev/null 2>&1 || die "missing command: ${cmd}"
  done
}

run() {
  if [[ "${DRY_RUN}" == 1 ]]; then
    printf '+ %s\n' "$*"
  else
    "$@"
  fi
}

# Resolves a setup name (softroce-2netns) or path to a YAML file.
setup_file() {
  local arg="${1:?setup name required}"
  if [[ -f "${arg}" ]]; then
    printf '%s\n' "${arg}"
  elif [[ -f "${SETUPS_DIR}/${arg}.yaml" ]]; then
    printf '%s\n' "${SETUPS_DIR}/${arg}.yaml"
  else
    die "no such setup: ${arg}"
  fi
}
