#!/usr/bin/env bash
# Checks that the host can run Soft-RoCE experiments. Loads rdma_rxe; changes
# nothing else.

source "$(dirname "$0")/../lib/common.sh"

require_root
require_cmd ip rdma python3 modprobe
python3 -c 'import yaml' 2>/dev/null || die "python3 PyYAML missing (run install-deps.sh)"

run modprobe rdma_rxe
log "rdma_rxe loaded"
log "rdma subsystem: $(rdma system show)"

for cmd in ibv_devices ib_write_bw ib_send_lat; do
  command -v "${cmd}" >/dev/null 2>&1 || log "warning: ${cmd} not found (run install-deps.sh)"
done

# Memory registration pins pages; low RLIMIT_MEMLOCK makes ibv_reg_mr fail.
memlock="$(ulimit -l)"
if [[ "${memlock}" != unlimited ]]; then
  log "warning: memlock limit is ${memlock} KiB; consider 'ulimit -l unlimited'"
fi

log "preflight ok"
