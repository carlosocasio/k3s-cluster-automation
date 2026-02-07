# K3s Multi-Node Cluster Automation

## Overview
This repository automates the deployment of a lightweight K3s cluster with multiple master and worker nodes, including the Rancher installation for cluster management. It also includes an example Apache2 deployment to validate the cluster.

The automation handles:
- K3s cluster bootstrap (1–3 master nodes, multiple workers)
- Flannel CNI, Helm, Longhorn, and cert-manager setup
- Rancher installation with configurable HA replicas

---

## Folder Structure

k3s-cluster-automation/
├── scripts/
│   └── cluster-install.sh            # Main bootstrap script
├── configs/
│   └── cluster-config.env            # Cluster configuration
├── examples/
│   └── apache-deployment.yaml        # Example application deployment
├── docs/
│   └── cluster-layout.png            # Optional diagram of cluster layout
├── os_image/
│   └── microOS.iso                   # microOS image for the node OS
├── README.md
├── LICENSE
└── .gitignore

---

## Prerequisites

- VMware Workstation or similar virtualization platform
- Linux VMs (SLES, openSUSE MicroOS, or similar) with root access
- SSH key-based authentication between nodes
- Internet access on all nodes
- `cluster-config.env` configured with node IPs and roles

---

## Cluster Configuration

### Node Array

Nodes are defined in `configs/cluster-config.env`:

NODES=(
  "node-1:192.168.154.210:master"
  "node-2:192.168.154.211:master"
  "node-3:192.168.154.212:master"
  "node-4:192.168.154.213:worker"
  # "node-5:192.168.154.214:worker"
  # "node-6:192.168.154.215:worker"
  # "node-7:192.168.154.216:worker"
)

- Format: `NODE_NAME:NODE_IP:ROLE`  
- Role can be `master` or `worker`  
- Comment out nodes to exclude them temporarily

### K3s Settings

K3S_CLUSTER_INIT_NODE="node-1"  
K3S_SERVER_PORT=6443

- `K3S_CLUSTER_INIT_NODE`: Node to initialize the cluster  
- `K3S_SERVER_PORT`: K3s API server port

### Rancher Settings

RANCHER_HOSTNAME="myrancher.com"  
RANCHER_REPLICAS=3

- `RANCHER_HOSTNAME`: DNS hostname to access Rancher UI  
- `RANCHER_REPLICAS`: Number of Rancher instances for HA  
- Bootstrap password is **`admin`** (must be changed on first login)

---

## Installation

1. Clone the repository:

git clone https://github.com/carlosocasio/k3s-cluster-automation.git  
cd k3s-cluster-automation

2. Source the environment file:

source configs/cluster-config.env

3. Make the bootstrap script executable:

chmod 755 scripts/cluster-install.sh

4. Run the bootstrap script:

./scripts/cluster-install.sh

- The first master node generates a **dynamic K3s cluster token**  
- Other nodes automatically fetch the token via SSH to join the cluster  
- Rancher is installed with the configured hostname and replicas

---

## Validation

Check cluster nodes:

kubectl get nodes

Check all pods:

kubectl get pods -A

Deploy example Apache2 application:

kubectl apply -f examples/apache-deployment.yaml  
kubectl get svc apache2

Access the Apache2 service via NodePort or configured service.

---

## Notes

- **Cluster Token:** Automatically generated on the first master node. Never hardcode in repo.  
- **Rancher Password:** Bootstrap password is `admin`. Must be changed after first login.  
- **Adding Nodes:** Uncomment additional nodes in `.env` and rerun the bootstrap script.  
- **Network Adjustments:** Update IPs in `cluster-config.env` if using a different VM network.

---

## Optional Enhancements

- Include a diagram in `docs/cluster-layout.png` showing master/worker nodes and Rancher HA setup  
- Add more example applications in `examples/` to test cluster functionality  
- Add automation for scaling Rancher or worker nodes dynamically  

---

## License

Include your preferred license here (e.g., MIT, Apache 2.0).
