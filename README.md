# K3s Multi-Node Cluster Automation
This repository automates the deployment of a lightweight K3s cluster with multiple master and worker nodes, including Rancher for cluster management. It also includes a sample 3-node Apache2 deployment to validate the cluster.

## Features
- K3s cluster bootstrap (1–3 master nodes, multiple workers)
- Flannel CNI, Helm, Longhorn, and cert-manager setup
- Rancher installation with configurable HA replicas
- Sample Apache2 3-node deployment to validate the cluster

## Folder Structure
``` text
k3s-cluster-automation/
├── scripts/
│   └── cluster-install.sh
│   └── node-prep.sh
├── configs/
│   └── cluster-config.env
├── examples/
│   └── apache2-deployment.yaml
├── docs/
│   └── cluster-layout.png
├── README.md
├── LICENSE
└── .gitignore
```

## Prerequisites
- configs/cluster-config.env configured with node IPs and roles
- git installation on all nodes (node-prep.sh will install git)
- Internet access on all nodes
- local account k3s for SSH access from your workstation to nodes
- local DNS resolution of nodes outside of the VM environment
- Linux VMs (openSUSE MicroOS, or similar) with root access
- SSH key-based authentication between nodes (installation will configure SSH)
- VMware Workstation or similar virtualization platform


## Cluster Configuration
### Node Array
Nodes are defined in configs/cluster-config.env:
``` text
NODES=(
"node-1:192.168.154.210:master"
"node-2:192.168.154.211:master"
"node-3:192.168.154.212:master"
"node-4:192.168.154.213:worker"
)
```
- Format: NODE_NAME:NODE_IP:ROLE
- Role can be master or worker
- Comment out nodes to exclude them temporarily
- Add more nodes as necessary

### K3s Settings
K3S_CLUSTER_INIT_NODE = "node-1" <br>
K3S_SERVER_PORT = 6443 <br>
- K3S_CLUSTER_INIT_NODE: Node to initialize the cluster
- K3S_SERVER_PORT: K3s API server port

### Rancher Settings
RANCHER_HOSTNAME = "myrancher.com" <br>
RANCHER_REPLICAS = 3 <br>
- RANCHER_HOSTNAME: DNS hostname to access Rancher UI
- RANCHER_REPLICAS: Number of Rancher instances for HA
```diff
+ ⚠️ Bootstrap password is `admin`. Change it immediately after first login.
```

## Installation
Download openSUSE microOS (x86_64) from
``` text
https://get.opensuse.org/microos/#download
```

Use a virtualization software like VMware to install openSUSE microOS
Recommended minimum specs:
- 8 GB Ram (preferable 16GB) <br>
- 4 CPU cores <br>
- 50 GB of Storage (more if you plan to install many deployments) <br>

Once your VMs are installed and running, sign in and go to a terminal / shell

Execute the following command to prep the node:
``` bash
curl -fsSL https://raw.githubusercontent.com/carlosocasio/k3s-cluster-automation/main/scripts/node-prep.sh | bash -s <node name>
```

Examples: <br>
#### Node 1
``` bash
curl -fsSL https://raw.githubusercontent.com/carlosocasio/k3s-cluster-automation/main/scripts/node-prep.sh | bash -s node-1
```

#### Node 2
``` bash
curl -fsSL https://raw.githubusercontent.com/carlosocasio/k3s-cluster-automation/main/scripts/node-prep.sh | bash -s node-2
```
#### Node 3
``` bash
curl -fsSL https://raw.githubusercontent.com/carlosocasio/k3s-cluster-automation/main/scripts/node-prep.sh | bash -s node-3
```
#### Node 4
``` bash
curl -fsSL https://raw.githubusercontent.com/carlosocasio/k3s-cluster-automation/main/scripts/node-prep.sh | bash -s node-4
```
```diff
- ⚠️ WARNING ⚠️ Reboot the system for changes to take effect.
```

Sign in as root if working in the VM <br>
Sign in as `k3s` if connecting remotely via SSH, then switch to root using `su -` <br>
```diff
+ The IP Address of the VM is displayed on the server console
```

Example:
```bash
ssh k3s@192.168.154.210
su -
```

Once signed in as root, Clone the Repository to download the necessary files:
```bash
git clone https://github.com/carlosocasio/k3s-cluster-automation.git
```

Execute the cluster installation script
```bash
/root/k3s-cluster-automation/scripts/cluster-install.sh
```

The installation will run through different Stages. Some stages will require a reboot. Wait for the prompt to return before rebooting.  
Reboot the node if necessary, and repeat the process. (Sign in as root and run cluster-install.sh). 
```diff
- ⚠️ WARNING ⚠️ For Stage 2, when the system is reconfiguring the network environment
- the terminal will not return to a prompt, because the SSH connection will be disconnected.
- Simply exit the terminal and open a new SSH conneciton to the new IP address.
```

Once you reach Stage 5, Kubernetes will be installed, configured and running on your environment. 

To access Rancher browse to: 
```text
http://myrancher.com
```
Make sure that your local DNS or hosts file resolves **myrancher.com** to the IP Address of node-1 (192.168.154.210)


The first master node generates a dynamic K3s cluster token. When installing the additional master nodes, you will be prompted for a password to fetch the token to join the cluster.   
Use the root password of Node-1 to fetch the token.


## Validation
To check cluster nodes:
```bash
kubectl get nodes
```
To check all pods
```bash
kubectl get pods -A
```
<br>

## Apache2 Deployment
To deploy a sample Apache2 application (execute on a node):
```bash
kubectl apply -f /root/k3s-cluster-automation/examples/apache2-deployment.yaml
```

Access the Apache2 service via NodePort or configured service.

On your browser, point to a node IP Address, or myrancher.com, and the Node Port to access Apache2:
```bash
http://myrancher.com:30080
```

## Notes
- Cluster Token: Automatically generated on the first master node. Never hardcode in repo.
- Rancher Password: Bootstrap password is admin. Must be changed after first login.
- Adding Nodes: Uncomment additional nodes in .env and rerun the bootstrap script.
- Network Adjustments: Update IPs in cluster-config.env if using a different VM network.

## License
This project is licensed under the MIT License. See the LICENSE file for details.
