#!/usr/bin/env bash
# Installs host packages needed for Soft-RoCE and perftest (Fedora).

source "$(dirname "$0")/../lib/common.sh"

require_root
require_cmd dnf

run dnf install -y \
  rdma-core \
  libibverbs-utils \
  perftest \
  iproute \
  python3-pyyaml
