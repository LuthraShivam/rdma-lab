# rdma-lab

Local Soft-RoCE lab: two Ubuntu KVM guests (`rdma-a`, `rdma-b`), each with an
`rxe0` device, for RDMA verbs experiments (Week 1+ of the AI programming plan).

Network namespaces on Soft-RoCE do **not** work for RDMA traffic on current
Fedora kernels (`rdma_rxe` is not namespace-aware). Two VMs, each with its own
kernel, do.

## Prerequisites (host)

- Fedora (or similar) with KVM/libvirt: `libvirt`, `virt-install`, `qemu-kvm`,
  `genisoimage`
- User in the `libvirt` group (no need to run `vm.sh` as root)
- Always use the **system** libvirt URI for manual `virsh` commands:

  ```bash
  virsh -c qemu:///system …
  ```

  Plain `virsh` without `-c` may talk to `qemu:///session`, which has different
  networks and no lab VMs.

## Bring the lab up

```bash
chmod +x scripts/vm.sh
LAB_PASSWORD=lab scripts/vm.sh up    # LAB_PASSWORD optional (console login)
scripts/vm.sh status
```

`up` downloads the Ubuntu 24.04 **server** cloud image once (~630 MB), boots
two VMs on libvirt’s `default` NAT network, waits for SSH and first-boot
setup, then prints `rdma link show`.

Useful commands:

```bash
scripts/vm.sh ssh rdma-a                 # shell
scripts/vm.sh ssh rdma-a 'rdma link show'
scripts/vm.sh down                       # remove VMs; keeps base image
KEEP_IMAGE=0 scripts/vm.sh down          # also delete the cached base image
```

## Guest outbound internet (required for first boot)

First boot installs `rdma-core`, `perftest`, and `linux-modules-extra` via
`apt`. Guests need IPv4 egress through the host.

### 1. firewalld libvirt zone

```bash
sysctl net.ipv4.ip_forward   # must be 1
sudo firewall-cmd --permanent --zone=libvirt --add-masquerade
sudo firewall-cmd --permanent --zone=libvirt --add-forward
sudo firewall-cmd --reload
firewall-cmd --zone=libvirt --list-all | grep -E 'forward:|masquerade:'
# expect: forward: yes  and  masquerade: yes
```

### 2. Docker and FORWARD (common on this host)

If Docker is installed, it often sets the filter **FORWARD** policy to
**DROP**. firewalld masquerade alone is not enough; VM packets die in
`DOCKER-USER` / `DOCKER-FORWARD`.

Check:

```bash
sudo iptables -L FORWARD -n -v | head -20
# policy DROP + DOCKER-USER → this is the conflict
```

Allow only libvirt bridge traffic (safe, scoped to `virbr0`; does not change
host Wi‑Fi or Docker’s own rules):

```bash
sudo iptables -C DOCKER-USER -i virbr0 -j ACCEPT 2>/dev/null \
  || sudo iptables -I DOCKER-USER -i virbr0 -j ACCEPT
sudo iptables -C DOCKER-USER -o virbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
  || sudo iptables -I DOCKER-USER -o virbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

Undo:

```bash
sudo iptables -D DOCKER-USER -i virbr0 -j ACCEPT
sudo iptables -D DOCKER-USER -o virbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

These `iptables` inserts are **not** persistent across Docker restarts or
reboot. Re-run them after Docker comes back, or add a small oneshot unit later.

### 3. Verify from a guest

```bash
scripts/vm.sh ssh rdma-a 'ping -c2 -4 1.1.1.1'
scripts/vm.sh ssh rdma-a 'curl -4 -I --connect-timeout 5 http://archive.ubuntu.com/ubuntu/ | head -3'
```

If ping fails: ICMP on `virbr0` but not on the uplink (`wlp9s0` / `eno1`)
means FORWARD/NAT is still blocked. ICMP on both with no replies points past
the host.

### 4. Finish Soft-RoCE if first boot already failed

After egress works, either recreate (`scripts/vm.sh down` then `up`) or install
manually on existing guests:

```bash
scripts/vm.sh ssh rdma-a 'sudo bash -c "
  echo \"Acquire::ForceIPv4 \\\"true\\\";\" >/etc/apt/apt.conf.d/99force-ipv4
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    rdma-core ibverbs-utils rdmacm-utils perftest linux-modules-extra-\$(uname -r)
  modprobe rdma_rxe
  systemctl daemon-reload
  systemctl enable --now rxe.service
  rdma link show
  ibv_devices
"'
# same for rdma-b
```

## Soft-RoCE smoke test

Two terminals:

```bash
scripts/vm.sh ssh rdma-a 'ibv_rc_pingpong -d rxe0 -g 1'
scripts/vm.sh ssh rdma-b "ibv_rc_pingpong -d rxe0 -g 1 $(scripts/vm.sh status | awk '/rdma-a/{print \$3}')"
```

If `-g 1` is wrong, list GIDs and pick the `::ffff:` IPv4-mapped index:

```bash
scripts/vm.sh ssh rdma-a 'cat /sys/class/infiniband/rxe0/ports/1/gids/*'
```

Then run `ib_write_bw` / `ib_send_lat` the same way and record numbers as the
Soft-RoCE baseline.

## Layout

```text
scripts/vm.sh                      # up | down | status | ssh
scripts/cloud-init/user-data.yaml  # first boot: lab user, apt, Soft-RoCE rxe0
```

## Notes

- Use the **server** cloud image, not Ubuntu minimal: minimal did not apply
  NoCloud CD-ROM user-data reliably here.
- Do not use Soft-RoCE across host network namespaces for this lab on current
  kernels; RDMA traffic will not complete even when TCP setup exchange works.
