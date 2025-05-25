#!/usr/bin/env bash
set -euo pipefail

# ─── CONFIG ────────────────────────────────────────────────────────────────
POD_CIDR="10.244.0.0/16"             # Pod network CIDR for CNI plugin
K8S_VERSION="v1.32"                  # Kubernetes version
CNI_PLUGIN_URL="https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"

# ──────────────────────────────────────────────────────────────────────────

if [[ $(id -u) -ne 0 ]]; then
  echo "⚠️ Please run this script as root or with sudo"
  exit 1
fi

role="${1:-}"                      # master or worker
join_cmd="${2:-}"                  # full kubeadm join command for workers

if [[ -z "$role" ]]; then
  echo "Usage: $0 master"
  echo "   or: $0 worker \"kubeadm join <args>\""
  exit 1
fi

echo "👉  Starting Kubernetes install as '$role' on $(hostname)"

# 1) System update + disable swap
apt update -y
apt upgrade -y
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/' /etc/fstab

# 2) Load kernel modules & sysctl settings
cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/99-k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# 3) Install containerd
apt install -y curl gnupg2 ca-certificates apt-transport-https software-properties-common

# Add Docker's repo for containerd
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt update
apt install -y containerd.io

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# 4) Install kubeadm, kubelet, kubectl
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/$K8S_VERSION/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/$K8S_VERSION/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

apt update
apt install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

# 5) Role-specific logic
case "$role" in
  master)
    echo "🚀 Initializing Kubernetes master node..."
    kubeadm init --pod-network-cidr="$POD_CIDR"

    # Configure kubectl for the invoking user
    if [[ -n "$SUDO_USER" ]]; then
      user="$SUDO_USER"
    else
      user="$(whoami)"
    fi
    mkdir -p /home/$user/.kube
    cp -i /etc/kubernetes/admin.conf /home/$user/.kube/config
    chown $user:$user /home/$user/.kube/config

    # Install CNI plugin (Flannel)
    echo "🌐 Installing Flannel CNI plugin..."
    su - $user -c "kubectl apply -f $CNI_PLUGIN_URL"

    echo "🎉 Master setup complete!"
    echo "To join worker nodes, run on each worker:"
    kubeadm token create --print-join-command
    ;;

  worker)
    if [[ -z "$join_cmd" ]]; then
      echo "⚠️ Worker role requires the join command as argument."
      exit 1
    fi
    echo "🛠 Joining the cluster as worker node..."
    $join_cmd
    echo "✅ Worker has joined the cluster"
    ;;

  *)
    echo "Invalid role: $role"
    echo "Usage: $0 master"
    echo "   or: $0 worker \"kubeadm join <args>\""
    exit 1
    ;;
esac

exit 0
