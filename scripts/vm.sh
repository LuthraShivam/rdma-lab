#!/usr/bin/env bash
# Two Ubuntu VMs with a Soft-RoCE device (rxe0) each, for RDMA experiments.
#
# Usage: vm.sh up | down | status | ssh <node> [command...]
#
# Runs as your user through the libvirt group, not sudo. Environment:
#   SSH_PUBKEY=path    key installed for user lab (default: ~/.ssh/id_ed25519.pub
#                      or ~/.ssh/id_rsa.pub)
#   LAB_PASSWORD=pw    at "up", also allow console login for user lab
#   KEEP_IMAGE=0       at "down", also delete the downloaded base image

set -euo pipefail

NODES=(rdma-a rdma-b)
VCPUS=2
MEMORY_MB=2048
DISK_GB=10
NETWORK=default
POOL=default
# Full server cloud image (not minimal): NoCloud CD-ROM seeds work reliably here.
IMAGE_URL=https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
BASE_VOL=rdma-lab-ubuntu-24.04.qcow2
SSH_USER=lab

export LIBVIRT_DEFAULT_URI=qemu:///system
CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/rdma-lab"
TEMPLATE="$(cd "$(dirname "$0")" && pwd)/cloud-init/user-data.yaml"

if [[ -z "${SSH_PUBKEY:-}" ]]; then
  SSH_PUBKEY="${HOME}/.ssh/id_ed25519.pub"
  [[ -f "${SSH_PUBKEY}" ]] || SSH_PUBKEY="${HOME}/.ssh/id_rsa.pub"
fi
SSH_OPTS=(-i "${SSH_PUBKEY%.pub}" -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5)

log() { printf '[vm.sh] %s\n' "$*" >&2; }
die() { log "error: $*"; exit 1; }

vol_exists() { virsh vol-info --pool "${POOL}" "$1" &>/dev/null; }
vol_delete() { vol_exists "$1" && virsh vol-delete --pool "${POOL}" "$1" >/dev/null || true; }

# qemu cannot read files under $HOME, so disks and seeds live in a libvirt pool.
upload() {
  local file="$1" vol="$2" format="$3"
  vol_delete "${vol}"
  virsh vol-create-as "${POOL}" "${vol}" "$(stat -c %s "${file}")" --format "${format}" >/dev/null
  virsh vol-upload --pool "${POOL}" "${vol}" "${file}"
}

node_ip() {
  virsh domifaddr "$1" --source lease 2>/dev/null \
    | awk '$3 == "ipv4" {sub(/\/.*/, "", $4); print $4; exit}'
}

# Builds the cloud-init NoCloud seed: an ISO labelled cidata. virt-install's
# own --cloud-init is avoided because the guest ignored it (seed=dmi).
make_seed() {
  local node="$1" dir="${CACHE_DIR}/${node}"
  mkdir -p "${dir}"
  sed -e "s|@HOSTNAME@|${node}|" -e "s|@SSH_KEY@|$(<"${SSH_PUBKEY}")|" \
    "${TEMPLATE}" >"${dir}/user-data"
  if [[ -n "${LAB_PASSWORD:-}" ]]; then
    printf '\nchpasswd:\n  expire: false\n  users:\n    - {name: lab, password: "%s", type: text}\n' \
      "${LAB_PASSWORD}" >>"${dir}/user-data"
  fi
  printf 'instance-id: %s-%s\nlocal-hostname: %s\n' "${node}" "$(date +%s)" "${node}" \
    >"${dir}/meta-data"
  genisoimage -quiet -output "${dir}/seed.iso" -volid cidata -joliet -rock \
    "${dir}/user-data" "${dir}/meta-data"
}

wait_ready() {
  local node="$1" ip="" deadline=$((SECONDS + 900))
  log "waiting for ${node}: address, ssh, then package install (a few minutes)"
  until ip="$(node_ip "${node}")" && [[ -n "${ip}" ]] \
    && ssh -n -o BatchMode=yes "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" true 2>/dev/null; do
    ((SECONDS < deadline)) || die "${node} not reachable after 15 minutes; check: virsh console ${node}"
    sleep 5
  done
  ssh -n "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" cloud-init status --wait >/dev/null \
    || log "warning: ${node}: cloud-init reported errors; check: vm.sh ssh ${node} cloud-init status --long"
  if ! ssh -n "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" \
      'test -d /sys/class/infiniband/rxe0 && command -v ibv_devices >/dev/null'; then
    log "warning: ${node}: Soft-RoCE not ready (guest often cannot reach the internet)."
    log "  test:  vm.sh ssh ${node} 'ping -c2 1.1.1.1'"
    log "  host:  firewall-cmd --get-active-zones; sysctl net.ipv4.ip_forward"
    log "  then:  vm.sh ssh ${node} 'sudo /usr/local/sbin/rdma-lab-firstboot'"
  fi
  log "${node} ready at ${ip}"
  ssh -n "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" 'rdma link show || true'
}

cmd_up() {
  local node img
  [[ -f "${SSH_PUBKEY}" ]] || die "no SSH key at ${SSH_PUBKEY}; set SSH_PUBKEY"

  if ! vol_exists "${BASE_VOL}"; then
    img="${CACHE_DIR}/$(basename "${IMAGE_URL}")"
    if [[ ! -f "${img}" ]]; then
      mkdir -p "${CACHE_DIR}"
      curl -fL --progress-bar -o "${img}.part" "${IMAGE_URL}"
      mv "${img}.part" "${img}"
    fi
    log "uploading base image"
    upload "${img}" "${BASE_VOL}" qcow2
  fi

  for node in "${NODES[@]}"; do
    if virsh dominfo "${node}" &>/dev/null; then
      log "${node} already exists; run 'vm.sh down' to recreate it"
      continue
    fi
    vol_delete "${node}.qcow2"
    virsh vol-create-as "${POOL}" "${node}.qcow2" "${DISK_GB}G" --format qcow2 \
      --backing-vol "${BASE_VOL}" --backing-vol-format qcow2 >/dev/null
    make_seed "${node}"
    upload "${CACHE_DIR}/${node}/seed.iso" "${node}-seed.iso" raw
    virt-install --name "${node}" --memory "${MEMORY_MB}" --vcpus "${VCPUS}" \
      --osinfo ubuntu24.04 --import \
      --disk "vol=${POOL}/${node}.qcow2,bus=virtio" \
      --disk "vol=${POOL}/${node}-seed.iso,device=cdrom" \
      --network "network=${NETWORK},model=virtio" \
      --graphics none --noautoconsole </dev/null
  done

  for node in "${NODES[@]}"; do
    wait_ready "${node}"
  done
}

cmd_down() {
  local node
  for node in "${NODES[@]}"; do
    if virsh dominfo "${node}" &>/dev/null; then
      virsh destroy "${node}" &>/dev/null || true
      virsh undefine "${node}" >/dev/null
      log "removed ${node}"
    fi
    vol_delete "${node}.qcow2"
    vol_delete "${node}-seed.iso"
    rm -rf "${CACHE_DIR:?}/${node}"
  done
  if [[ "${KEEP_IMAGE:-1}" == 0 ]]; then
    vol_delete "${BASE_VOL}"
    rm -f "${CACHE_DIR}/$(basename "${IMAGE_URL}")"
    log "removed base image"
  else
    log "kept base image ${BASE_VOL}; KEEP_IMAGE=0 removes it"
  fi
}

cmd_status() {
  local node
  for node in "${NODES[@]}"; do
    printf '%-8s %-12s %s\n' "${node}" \
      "$(virsh domstate "${node}" 2>/dev/null || echo 'not created')" "$(node_ip "${node}")"
  done
}

cmd_ssh() {
  local node="${1:?usage: vm.sh ssh <node> [command...]}" ip
  shift
  ip="$(node_ip "${node}" || true)"
  [[ -n "${ip}" ]] || die "${node} has no address yet"
  exec ssh "${SSH_OPTS[@]}" "${SSH_USER}@${ip}" "$@"
}

[[ "${EUID}" -ne 0 ]] || die "run without sudo (uses the libvirt group)"
for cmd in virsh virt-install genisoimage curl ssh; do
  command -v "${cmd}" >/dev/null || die "missing command: ${cmd}"
done

case "${1:-}" in
  up | down | status) "cmd_$1" ;;
  ssh) shift && cmd_ssh "$@" ;;
  *) sed -n '2,10s/^# \{0,1\}//p' "$0" >&2 && exit 1 ;;
esac
