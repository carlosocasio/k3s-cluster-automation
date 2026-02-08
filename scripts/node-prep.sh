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
K3S_USER="k3s"
K3S_PASSWORD="ChangeMe123!"

if [[ -z "$NODE_NAME" ]]; then
  echo "ERROR: No node name provided."
  echo "Usage: $0 <node-name>"
  exit 1
fi

echo "Setting hostname to '$NODE_NAME'..."
hostnamectl set-hostname "$NODE_NAME"

if id "$K3S_USER" >/dev/null 2>&1; then
  echo "User '$K3S_USER' already exists. Skipping user creation."
else
  echo "Creating user '$K3S_USER'..."
  useradd -m -s /bin/bash "$K3S_USER"
  echo "$K3S_USER:$K3S_PASSWORD" | chpasswd
fi

if ! command -v git >/dev/null 2>&1; then
  echo "Git not found. Installing git using transactional-update..."
  transactional-update pkg install git
  echo "Git installation scheduled. Reboot required."
  REBOOT_REQUIRED=true
else
  echo "Git already installed."
  REBOOT_REQUIRED=false
fi

echo "Node preparation complete."

if [[ "$REBOOT_REQUIRED" == true ]]; then
  echo "Rebooting system to complete setup..."
  reboot
else
  echo "No reboot required."
fi