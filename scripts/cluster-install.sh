#!/usr/bin/env bash

# ------------------------------------------------------------------
# K3s Multi-Node Cluster Bootstrap Script (4 Nodes)
# ------------------------------------------------------------------
# Author: Carlos Ocasio
#
# Description:
#   This script automates the deployment of a lightweight K3s cluster
#   with 1-3 master nodes and additional worker nodes. It installs
#   essential components including Flannel CNI, Helm, Longhorn, 
#   cert-manager, and Rancher.
#
# Requirements:
#   - SLES / openSUSE MicroOS or similar Linux distribution
#   - Root access to all nodes
#   - Config file at /etc/default/cluster-config.env
#
# Notes:
#   - Uses SSH key-based access to join additional nodes.
#   - Designed for 4-node clusters but can be extended.
# ------------------------------------------------------------------

set -euo pipefail # Strict mode for safer execution


# ---------------------------------------------------------------------------------
# Logging & Stage Control
# ---------------------------------------------------------------------------------

LOG_FILE="/var/log/k3s-bootstrap.log"
GREEN="\033[0;32m"
RED="\033[0;31m"
RESET="\033[0m"

# Send all stdout/stderr to log file, keep console clean
exec >> "$LOG_FILE" 2>&1

stage() {
    echo " " > /dev/tty
    echo -e "${GREEN}=======================================================================${RESET}" > /dev/tty
    echo -e ">>> $1" >/dev/tty
    echo -e "${GREEN}=======================================================================${RESET}" > /dev/tty
    echo " " > /dev/tty
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')][$NODE_NAME][$NODE_ROLE] $1"
}


# ------------------------------------------------------------------
# Function: enable_root_ssh
# Purpose:
#   Enable root SSH access on the K3s cluster initialization (master) node.
#   This is required to allow additional nodes to securely retrieve the
#   node-token for joining the cluster.
#
# Notes:
#   - Only runs on the node designated as $K3S_CLUSTER_INIT_NODE.
#   - Backs up existing SSH configuration before modifying it.
#   - Enables root login and password authentication temporarily.
#   - Restarts the SSH daemon to apply changes.
# ------------------------------------------------------------------
enable_root_ssh() {
    [[ "$NODE_NAME" != "$K3S_CLUSTER_INIT_NODE" ]] && return

    log "Copy root SSH login on init node"

    # Backup sshd_config
    cp /usr/etc/ssh/sshd_config /etc/ssh/sshd_config

    # Permit root login and password authentication
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

    # Restart SSH daemon
    systemctl restart sshd || systemctl restart ssh
    log "Root SSH login enabled"
}



# ------------------------------------------------------------------
# Function: install_flannel
# Purpose:
#   Install Flannel as the CNI (Container Network Interface) plugin
#   for Kubernetes networking on the K3s cluster.
#
# Notes:
#   - Flannel is required for pod-to-pod communication across nodes.
#   - Adjusts default Flannel network CIDR to match K3s default (10.42.0.0/16).
#   - Waits until all Flannel pods are ready before proceeding.
# ------------------------------------------------------------------
install_flannel() {
    log "Installing Flannel CNI network ..."
    echo "Installing Flannel CNI network ..." > /dev/tty
    echo " " > /dev/tty
    echo "Once Flannel CNI Network is installed ..." > /dev/tty
    echo "... reboot and run installation script to continue on to Stage 4" > /dev/tty
    echo " " > /dev/tty

    # Download the official Flannel manifest
    curl -sSL -o /tmp/kube-flannel.yml https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml \
    >> "$LOG_FILE" 2>&1

    # Adjust the Pod network CIDR to match K3s (10.42.0.0/16)
    sed -i 's/10.244.0.0\/16/10.42.0.0\/16/' /tmp/kube-flannel.yml

    # Apply Flannel manifest
    kubectl apply -f /tmp/kube-flannel.yml >> "$LOG_FILE" 2>&1

    # Wait until all Flannel pods are ready
    log "Waiting for Flannel pods to be ready..."
    echo "Waiting for Flannel pods to be ready..." > /dev/tty
    until [ "$(kubectl get ds -n kube-flannel kube-flannel-ds -o jsonpath='{.status.numberReady}')" = \
          "$(kubectl get ds -n kube-flannel kube-flannel-ds -o jsonpath='{.status.desiredNumberScheduled}')" ]; do
        log "Flannel not ready yet..."
        sleep 5
    done
    log "Flannel CNI is ready!"
}


# ------------------------------------------------------------------
# Section: Load Cluster Configuration
# Purpose:
#   Load environment variables and node definitions for the K3s
#   cluster from an external configuration file. Also, initialize
#   key variables for node identification.
#
# Notes:
#   - The config file should define:
#       * NODES array with format "name:ip:role"
#       * K3S_CLUSTER_INIT_NODE (hostname or IP of initial master)
#       * Any other cluster-wide variables (e.g., RANCHER_HOSTNAME)
#   - Ensures the script has access to standard system binaries.
# ------------------------------------------------------------------
CONFIG_FILE="/root/k3s-cluster-automation/configs/cluster-config.env"

[ -f "$CONFIG_FILE" ] || { echo "Missing $CONFIG_FILE"; exit 1; }
source "$CONFIG_FILE"

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
NODE_NAME=$(hostname)
NODE_ROLE=""
NODE_IP=""

# ------------------------------------------------------------------
# Section: Determine Node Role
# Purpose:
#   Identify the current node's IP address and role (master or worker)
#   by matching the hostname against entries in the NODES array
#   defined in the cluster configuration file.
#
# Notes:
#   - NODES array entries must follow the format: "name:ip:role"
#       Example: "Node-1:192.168.154.210:master"
#   - Exits the script if the current node is not found in the configuration.
# ------------------------------------------------------------------
for NODE in "${NODES[@]}"; do
    # Split each entry into name, IP, and role
    IFS=':' read -r name ip role <<< "$NODE"

    # Check if the current hostname matches this entry
    if [[ "$name" == "$NODE_NAME" ]]; then
        NODE_IP=$ip                         # Assign node IP
        NODE_ROLE=$role                     # Assign node role (master/worker)
        break                               # Stop searching once a match is found
    fi
done

# Exit if the current node is not listed in the configuration
if [[ -z "$NODE_ROLE" ]]; then
    echo "Node $NODE_NAME not found in config"
    exit 1
fi

# ------------------------------------------------------------------
# Logging helper function
# Purpose:
#   Standardized logging with node name and role for clarity in output.
# ------------------------------------------------------------------
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')][$NODE_NAME][$NODE_ROLE] $1"; }



# ------------------------------------------------------------------
# Function: install_base
# Purpose:
#   Install essential base packages required for K3s and cluster
#   operations, and ensure necessary services are running.
#
# Notes:
#   - Uses transactional-update (specific to MicroOS/SLES) to install packages.
#   - Installs:
#       * curl      : for downloading manifests and scripts
#       * openssl   : required for secure communication and certificates
#       * open-iscsi: iSCSI support if persistent storage requires it
#   - Enables and starts the iSCSI daemon for storage operations
# ------------------------------------------------------------------
install_base() {
    log "Installing base packages" 
    echo "Installing base packages ... " > /dev/tty
    echo " " > /dev/tty
    echo "Once base packages are installed ..." > /dev/tty
    echo "... reboot and run installation script to continue on to Stage 2" > /dev/tty
    transactional-update pkg install -y curl openssl open-iscsi >> "$LOG_FILE" 2>&1
    systemctl enable --now iscsid >> "$LOG_FILE" 2>&1    
}



# ------------------------------------------------------------------
# Function: configure_network
# Purpose:
#   Configure the network settings for the current node.
#   Sets a static IP, gateway, DNS, hostname, and updates /etc/hosts
#   for proper intra-cluster communication.
#
# Notes:
#   - Uses nmcli (NetworkManager CLI) to configure network interface 'ens33'.
#   - Adjusts /etc/hostname for the node.
#   - Populates /etc/hosts with all cluster nodes to avoid DNS issues.
#   - Assumes a 24-bit subnet and specific gateway for this lab environment.
# ------------------------------------------------------------------
configure_network() {
    log "Configuring network"
    echo "Configuring network with new IP Addresses ... " > /dev/tty
    echo " " > /dev/tty
    # echo "Reboot required for configurations to take effect" > /dev/tty
    # echo " " >/dev/tty
    echo "SSH connection no longer valid. Close terminal and reboot system" > /dev/tty
    echo " " > /dev/tty
    echo "After reboot ... SSH to ${NODE_IP} ..." > /dev/tty 
    echo "... and run installation script to continue to Stage 3" > /dev/tty
    # Configure static IP, gateway, and DNS
    nmcli con mod ens33 \
        ipv4.method manual \
        ipv4.addresses ${NODE_IP}/24 \
        ipv4.gateway 192.168.154.2 \
        ipv4.dns 1.1.1.1 >> "$LOG_FILE" 2>&1

    # Bring the interface up
    nmcli con up ens33 >> "$LOG_FILE" 2>&1

    # Set the hostname for this node
    echo "$NODE_NAME" > /etc/hostname

    # Update /etc/hosts with cluster nodes for name resolution
    cat <<EOF > /etc/hosts
127.0.0.1 localhost
192.168.154.210 Node-1 myrancher.org
192.168.154.211 Node-2
192.168.154.212 Node-3
192.168.154.213 Node-4
EOF
}



# ------------------------------------------------------------------
# Function: setup_ssh
# Purpose:
#   Configure passwordless SSH access from the current node to the
#   K3s cluster initialization (master) node. This allows the node
#   to securely retrieve the node-token or join the cluster without
#   manual intervention.
#
# Notes:
#   - Only runs on non-init nodes (workers or additional masters).
#   - Generates an SSH key pair if one does not already exist.
#   - Copies the public key to the init node using ssh-copy-id.
#   - Disables strict host key checking to avoid interactive prompts.
# ------------------------------------------------------------------
setup_ssh() {
    # Skip on the init/master node
    [[ "$NODE_NAME" == "$K3S_CLUSTER_INIT_NODE" ]] && return

    log "Setting up SSH keys"
    echo "Setting up the SSH keys" > /dev/tty

    # Generate SSH key pair if it doesn't exist
    [[ -f ~/.ssh/id_rsa.pub ]] || ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa

    # Copy public key to init node for passwordless SSH
    ssh-copy-id -o StrictHostKeyChecking=no root@$K3S_CLUSTER_INIT_NODE \
    >> "$LOG_FILE" 2>&1
}



# ------------------------------------------------------------------
# Function: install_k3s_master
# Purpose:
#   Install K3s on the current node as a control-plane (master) node.
#   Handles both:
#       1. Initial cluster node (init node)
#       2. Additional control-plane nodes joining the cluster
#
# Notes:
#   - Uses official K3s installation script.
#   - For init node:
#       * Installs K3s with --cluster-init
#       * Installs Flannel CNI network
#   - For additional control-plane nodes:
#       * Retrieves node-token from init node via SSH
#       * Joins the cluster using the retrieved token
#   - Ensures K3s service is enabled and running
#   - Waits for kubeconfig to exist and persists KUBECONFIG for the user
# ------------------------------------------------------------------
install_k3s_master() {
    log "Installing K3s on $NODE_NAME"
    echo "Installing K3s on $NODE_NAME" > /dev/tty
    if [[ "$NODE_NAME" == "$K3S_CLUSTER_INIT_NODE" ]]; then
        # ----------------------------------------------------------
        # Initial cluster node (first master)
        # ----------------------------------------------------------
        log "Installing INIT k3s control plane on node: $NODE_NAME"
        echo "Installing INIT k3s control plane on $NODE_NAME" > /dev/tty
        # Install K3s control plane and initialize cluster
        curl -sfL https://get.k3s.io | sh -s - server --cluster-init \
        >> "$LOG_FILE" 2>&1

        # Install Flannel CNI for pod networking
        install_flannel
    else
        # ----------------------------------------------------------
        # Additional control-plane node
        # ----------------------------------------------------------
        K3S_CLUSTER_INIT_NODE="${K3S_CLUSTER_INIT_NODE:-192.168.154.210}"  # Node-1 IP or hostname
        K3S_SERVER_PORT="${K3S_SERVER_PORT:-6443}"

        # Ensure SSH access to init node
        setup_ssh

        # Wait until node-token is available on init node
        log "Waiting for node-token on $K3S_CLUSTER_INIT_NODE..."
        echo "Waiting for node-token on $K3S_CLUSTER_INIT_NODE..." > /dev/tty
        until ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$K3S_CLUSTER_INIT_NODE" "test -f /var/lib/rancher/k3s/server/node-token"; do
            sleep 5
        done

        # Fetch the node-token for cluster join
        TOKEN=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$K3S_CLUSTER_INIT_NODE" "cat /var/lib/rancher/k3s/server/node-token")
        log "Token retrieved: $TOKEN"
        echo "Token retrieved" > /dev/tty

        # Join this node as an additional control-plane
        curl -sfL https://get.k3s.io | K3S_TOKEN="$TOKEN" sh -s - server --server "https://192.168.154.210:6443" \
        >> "$LOG_FILE" 2>&1

    fi


    # ----------------------------------------------------------
    # Enable and start K3s service
    # ----------------------------------------------------------
    echo 'Enabling and Starting the K3S service'
    systemctl enable k3s >> "$LOG_FILE" 2>&1
    systemctl start k3s >> "$LOG_FILE" 2>&1
    
    # Wait for kubeconfig file to exist
    log "Waiting for kubeconfig to be created..."
    echo "Waiting for kubeconfig to be created..."
    until [[ -f /etc/rancher/k3s/k3s.yaml ]]; do
        sleep 5
    done

    # Persist KUBECONFIG environment variable for current user
    if ! grep -qxF 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' ~/.bashrc; then
        echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
    fi

    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    log "KUBECONFIG set and persisted"

    log "K3s installation/join completed on $NODE_NAME"
    echo "K3s installation/join completed on $NODE_NAME" > /dev/tty
}



# ------------------------------------------------------------------
# Function: join_worker
# Purpose:
#   Join the current node as a worker node to the existing K3s cluster.
#
# Notes:
#   - Ensures passwordless SSH access to the cluster init node.
#   - Waits for the cluster node-token to be available before joining.
#   - Uses the official K3s install script with K3S_URL and K3S_TOKEN
#     to securely join the cluster as a worker.
#   - Enables and starts the k3s-agent service for cluster participation.
# ------------------------------------------------------------------
join_worker() {
    # Ensure SSH access to init node
    setup_ssh
    log "Joining as worker"

    # Wait until node-token is available on init node
    until ssh root@$K3S_CLUSTER_INIT_NODE \
        "test -f /var/lib/rancher/k3s/server/node-token"; do
        sleep 5
    done

    # Retrieve node-token from init node
    TOKEN=$(ssh root@$K3S_CLUSTER_INIT_NODE \
        "cat /var/lib/rancher/k3s/server/node-token")

    # Join the cluster using the token and init node URL
    curl -sfL https://get.k3s.io | K3S_URL="https://192.168.154.210:6443" K3S_TOKEN="$TOKEN" sh - \
    >> "$LOG_FILE" 2>&1

    # Enable and start K3s agent service
    systemctl enable k3s-agent >> "$LOG_FILE" 2>&1
    systemctl start k3s-agent >> "$LOG_FILE" 2>&1
}



# ------------------------------------------------------------------
# Function: wait_for_k3s
# Purpose:
#   Wait for the K3s cluster to be fully initialized and ready.
#   Ensures kubeconfig exists and the Kubernetes API is responsive
#   before continuing with further setup.
#
# Notes:
#   - Blocks execution until /etc/rancher/k3s/k3s.yaml exists.
#   - Exports KUBECONFIG environment variable for kubectl access.
#   - Waits for the Kubernetes API to respond to `kubectl get nodes`.
# ------------------------------------------------------------------
wait_for_k3s() {
    log "Waiting for kubeconfig"
    echo "Waiting for kubeconfig" > /dev/tty
    # Wait until kubeconfig is created by K3s
    until [ -f /etc/rancher/k3s/k3s.yaml ]; do
        sleep 3; 
    done

    # Export KUBECONFIG for current shell session
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

    log "Waiting for Kubernetes API"
    echo "Waiting for Kubernetes API" > /dev/tty

    # echo " " > /dev/tty
    # echo "Once Flannel CNI Network is installed ..." > /dev/tty
    # echo "... reboot and run installation script to continue on to Stage 4" > /dev/tty

    # Wait until Kubernetes API responds
    until kubectl get nodes >/dev/null 2>&1; do
        sleep 5; 
    done
}



# ------------------------------------------------------------------
# Function: install_helm
# Purpose:
#   Install Helm (v3) on the node if it is not already installed.
#   Helm is required to deploy Kubernetes applications and charts
#   like Longhorn, cert-manager, and Rancher.
#
# Notes:
#   - Checks if Helm is already available on the system to avoid
#     reinstallation.
#   - Uses the official Helm installation script from GitHub.
# ------------------------------------------------------------------
install_helm() {
    log "Installing Helm"
    echo "Installing Helm" > /dev/tty
    # Return early if Helm is already installed
    command -v helm >/dev/null 2>&1 && return

    # Download and run official Helm install script
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash \
    >> "$LOG_FILE" 2>&1
}



# ------------------------------------------------------------------
# Function: install_longhorn
# Purpose:
#   Deploy Longhorn, a cloud-native distributed block storage system,
#   onto the Kubernetes cluster using Helm.
#
# Notes:
#   - Adds the official Longhorn Helm repository if not already added.
#   - Updates Helm repositories to ensure latest charts are available.
#   - Installs Longhorn into the "longhorn" namespace, creating it if necessary.
#   - Uses `|| true` to prevent script exit if the repository already exists
#     or the release is already installed.
# ------------------------------------------------------------------
install_longhorn() {
    log "Installing Longhorn"
    echo "Installing Longhorn" > /dev/tty
    # Add Longhorn Helm repository (ignore error if already added)
    helm repo add longhorn https://charts.longhorn.io || true

    # Update Helm repositories
    helm repo update

    # Install Longhorn chart in 'longhorn' namespace
    helm install longhorn longhorn/longhorn \
        --namespace longhorn --create-namespace >> "$LOG_FILE" 2>&1 || true 
}



# ------------------------------------------------------------------
# Function: install_cert_manager
# Purpose:
#   Install cert-manager to manage TLS certificates within the
#   Kubernetes cluster. cert-manager is required by Rancher and
#   other workloads that rely on automated certificate provisioning.
#
# Notes:
#   - Adds the Jetstack Helm repository if not already present.
#   - Installs cert-manager into the "cert-manager" namespace.
#   - Installs Custom Resource Definitions (CRDs) required by cert-manager.
#   - Uses `|| true` to allow safe re-runs without failing the script.
# ------------------------------------------------------------------
install_cert_manager() {
    log "Installing cert-manager"
    echo "Installing cert-manager" > /dev/tty
    # Add Jetstack Helm repository (ignore error if already added)
    helm repo add jetstack https://charts.jetstack.io || true

    # Update Helm repositories
    helm repo update

    # Install cert-manager with CRDs enabled
    helm install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --set installCRDs=true >> "$LOG_FILE" 2>&1 || true        
}



# ------------------------------------------------------------------
# Function: install_rancher
# Purpose:
#   Deploy Rancher, a centralized Kubernetes management platform,
#   onto the K3s cluster using Helm.
#
# Notes:
#   - Adds the Rancher stable Helm repository if not already present.
#   - Installs Rancher into the "cattle-system" namespace.
#   - Uses a configurable hostname for external access.
#   - Supports configurable replica count for high availability.
#   - Sets an initial bootstrap password for first-time login.
#   - Uses `|| true` to allow idempotent re-runs of the script.
#
# Requirements:
#   - cert-manager must already be installed and running.
#   - DNS must resolve $RANCHER_HOSTNAME to this cluster.
# ------------------------------------------------------------------
install_rancher() {
    log "Installing Rancher"
    echo "Installing Rancher"  > /dev/tty
    # Add Rancher Helm repository (ignore error if already added)
    helm repo add rancher-stable https://releases.rancher.com/server-charts/stable || true

    # Update Helm repositories
    helm repo update

    # Install Rancher with configured hostname and replica count
    helm install rancher rancher-stable/rancher \
        --namespace cattle-system \
        --create-namespace \
        --set hostname=$RANCHER_HOSTNAME \
        --set replicas=$RANCHER_REPLICAS \
        --set bootstrapPassword=admin >> "$LOG_FILE" 2>&1 || true 
}



# ------------------------------------------------------------------
# Main Execution Flow
#
# Purpose:
#   Orchestrate node setup based on role (master or worker) and
#   ensure cluster-wide components are installed exactly once.
#
# Behavior:
#   - Installs base OS dependencies and network configuration
#   - Initializes or joins the K3s cluster depending on node role
#   - Ensures cluster-level services are only installed on the
#     designated cluster-init master node
#
# Design Principles:
#   - Idempotent execution (safe to re-run)
#   - Role-aware behavior (master vs worker)
#   - Single-responsibility for cluster bootstrap tasks
# ------------------------------------------------------------------

# Install required base packages and configure networking
clear > /dev/tty

echo -e "=======================================================================" > /dev/tty
echo -e "${RED}            Kubernetes Multi-Node Cluster Bootstrap Script${RESET}" > /dev/tty
echo -e "${RED}=======================================================================${RESET}" > /dev/tty


stage "${RED}Stage 1${RESET} - Base OS preparation"
install_base

stage "${RED}Stage 2${RESET} - Configuring network interfaces"
configure_network

# Master node logic
if [[ "$NODE_ROLE" == "master" ]]; then

    # stage "Stage 3 - Kubernetes control plane (please reboot when stage completed)"
    stage "${RED}Stage 3${RESET} - Kubernetes control plane"
    # Enable root SSH access only on the cluster-init master
    # (useful for initial bootstrap and emergency access)
    if [[ "$NODE_NAME" == "$K3S_CLUSTER_INIT_NODE" ]]; then
        enable_root_ssh
    fi

    # Install and configure K3s control plane
    install_k3s_master

    # Block until the Kubernetes API is available
    wait_for_k3s

    # Cluster-wide components should be installed once,
    # and only from the designated init master node
    if [[ "$NODE_NAME" == "$K3S_CLUSTER_INIT_NODE" ]]; then
        stage "${RED}Stage 4${RESET} - Platform services"
        install_helm
        install_longhorn
        install_cert_manager
        install_rancher
    fi
# Worker node logic
else
    stage "${RED}Stage 3${RESET} - Kubernetes worker join"
    join_worker
fi

# Final log message indicating successful completion
stage "${RED}Stage 5${RESET} - Installation of Kubernetes and Rancher completed!"
log "Node setup complete"
echo "Active Nodes" > /dev/tty
kubectl get nodes > /dev/tty
echo " " > /dev/tty
echo "Once all the pods are running you may access Rancher by " > /dev/tty
echo "browsing to  http://myrancher.org (bootstrap password: admin)" > /dev/tty
echo "The BootStrap password is admin" > /dev/tty
echo " " > /dev/tty
echo "Give it a few minutes ... then have some fun!" > /dev/tty





