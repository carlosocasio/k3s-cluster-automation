#!/usr/bin/env bash

# ------------------------------------------------------------------
# Node Preparation Script for K3s Cluster
# ------------------------------------------------------------------
# Author: Carlos Ocasio
#
# Purpose:
#   Prepares a MicroOS/SLES node for participation in a K3s cluster.
#   This script performs minimal required setup before cluster
#   automation can run.
#
# Actions:
#   - Sets system hostname
#   - Enables and starts SSH
#   - Installs git using transactional-update
#
# Usage:
#   ./node-prep.sh <node-name> or
#   /root/k3s-cluster-automation/scripts
# Example:
#   ./node-prep.sh node-1 <node-name> or
#   /root/k3s-cluster-automation/scripts/node-prep.sh node-1
#
# Notes:
#   - A reboot is required after git installation on MicroOS
#   - This script should be run once per node
# ------------------------------------------------------------------

set -e

NODE_NAME="$1"

if [[ -z "$NODE_NAME" ]]; then
  echo "ERROR: No node name provided."
  echo "Usage: $0 <node-name>"
  exit 1
fi

hostnamectl set-hostname "$1"
systemctl enable --now sshd
transactional-update pkg install git
reboot