# K3s Multi-Node Cluster Automation
This repository automates the deployment of a lightweight K3s cluster with multiple master and worker nodes, including Rancher for cluster management. It also includes an example Apache2 deployment to validate the cluster.

## Features
- K3s cluster bootstrap (1–3 master nodes, multiple workers)
- Flannel CNI, Helm, Longhorn, and cert-manager setup
- Rancher installation with configurable HA replicas
- Example Apache2 deployment to validate the cluster

## Folder Structure
k3s-cluster-automation/
├── scripts/
│   └── cluster-install.sh
│   └── node-prep.sh
├── configs/
│   └── cluster-config.env
├── examples/
│   └── apache-deployment.yaml
├── docs/
│   └── cluster-layout.png
├── README.md
├── LICENSE
└── .gitignore

## Prerequisites
- VMware Workstation or similar virtualization platform
- Linux VMs (SLES, openSUSE MicroOS, or similar) with root access
- SSH key-based authentication between nodes
- Internet access on all nodes
- configs/cluster-config.env configured with node IPs and roles
- local account k3s for SSH access from your workstation to nodes
- git installation on nodes

## Cluster Configuration
### Node Array
Nodes are defined in configs/cluster-config.env:
NODES=(
"node-1:192.168.154.210:master"
"node-2:192.168.154.211:master"
"node-3:192.168.154.212:master"
"node-4:192.168.154.213:worker"
)

- Format: NODE_NAME:NODE_IP:ROLE
- Role can be master or worker
- Comment out nodes to exclude them temporarily
- Add more nodes as necessary

### K3s Settings
K3S_CLUSTER_INIT_NODE="node-1"
K3S_SERVER_PORT=6443
- K3S_CLUSTER_INIT_NODE: Node to initialize the cluster
- K3S_SERVER_PORT: K3s API server port

### Rancher Settings
RANCHER_HOSTNAME="myrancher.com"
RANCHER_REPLICAS=3
- RANCHER_HOSTNAME: DNS hostname to access Rancher UI
- RANCHER_REPLICAS: Number of Rancher instances for HA
- **Warning:** Bootstrap password is `admin`. Change it immediately after first login.

## Installation
Once your node is installed sign in and go to a terminal / shell

Execute the following command to prep the node:
   curl -fsSL https://raw.githubusercontent.com/carlosocasio/k3s-cluster-automation/main/scripts/node-prep.sh | bash -s <node name>

Example: 
    For Node 1 - 
    curl -fsSL https://raw.githubusercontent.com/carlosocasio/k3s-cluster-automation/main/scripts/node-prep.sh | bash -s node-1

    For Node 2 - 
    curl -fsSL https://raw.githubusercontent.com/carlosocasio/k3s-cluster-automation/main/scripts/node-prep.sh | bash -s node-2

**Reboot the system for changes to take effect.**

Sign in as root if local VM; sign in as `k3s` if connecting remotely via SSH, then switch to root using `su -`.

Example:
    ssh k3s@192.168.154.210
    su -

Once signed in as root, Clone the Repository to download the necessary files:

    git clone https://github.com/carlosocasio/k3s-cluster-automation.git
    
Execute the cluster installation script
    /root/k3s-cluster-automation/scripts/cluster-install.sh

The installation will run through different Stages. Some stages will require a reboot.
Reboot the node if necessary, and repeat the process. (Sign in as root and run cluster-install.sh).
Once you reach Stage 5, kubernetes will be installed, configured and running on your environment.

To access Rancher, browse to http://myrancher.com
**Your local hosts file should resolve myrancher.com to the IP Address of node-1**


The first master node generates a dynamic K3s cluster token.
Other nodes fetch the token via SSH to join the cluster. When asked to enter a password to acquire the TOKEN use the root password of Node-1

Rancher is installed with the configured hostname and replicas.

## Validation
Check cluster nodes:
kubectl get nodes

Check all pods:
kubectl get pods -A

## Apache2 Deployment
To deploy a sample Apache2 application:
    kubectl apply -f examples/apache2-deployment.yaml

Access the Apache2 service via NodePort or configured service.

On your browser, point to a node IP Address and the Node Port to access Apache2
Example:
    http://node-1:30080

## Notes
- Cluster Token: Automatically generated on the first master node. Never hardcode in repo.
- Rancher Password: Bootstrap password is admin. Must be changed after first login.
- Adding Nodes: Uncomment additional nodes in .env and rerun the bootstrap script.
- Network Adjustments: Update IPs in cluster-config.env if using a different VM network.

## License
This project is licensed under the MIT License. See the LICENSE file for details.
