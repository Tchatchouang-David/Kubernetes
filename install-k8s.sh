#!/usr/bin/env bash
set -euo pipefail

# ─── CONFIG ────────────────────────────────────────────────────────────────
POD_CIDR="10.244.0.0/16"
K8S_VERSION="v1.32"         # adjust as needed
# ──────────────────────────────────────────────────────────────────────────

if [[ $(id -u) -ne 0 ]]; then
  echo "⚠️  Please run as root or with sudo" >&2
  exit 1
fi

role="${1:-}"
join_cmd="${2:-}"

echo "👉  Running install-k8s.sh as $(whoami) on $(hostname) [role=$role]"

# 1) System update + disable swap
apt update -y
apt upgrade -y

swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 2) Load kernel modules & sysctl params
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/99-k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system

# 3) Install containerd
apt install -y curl gnupg2 ca-certificates apt-transport-https software-properties-common

# Use Docker's repo to get containerd.io
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
   https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt update
apt install -y containerd.io

# Configure containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# switch cgroup driver to systemd
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable  containerd

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

# 5) Role-specific actions
case "$role" in
  master)
    echo "🚀 Initializing Kubernetes master..."
    kubeadm init --pod-network-cidr="${POD_CIDR}"
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config

    echo
    echo "🎉 Master is up. Now install a Pod network, e.g.:"
    echo "   kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
    echo
    echo "To join workers, run on each worker node:"
    kubeadm token create --print-join-command
    ;;
  worker)
    if [[ -z "$join_cmd" ]]; then
      echo "⚠️  Worker role requires the join command as argument." >&2
      exit 1
    fi
    echo "🛠  Joining cluster as worker..."
    bash -c "${join_cmd}"
    ;;
  *)
    echo "Usage: $0 master"
    echo "   or: $0 worker \"kubeadm join <args>\""
    exit 1
    ;;
esac

echo "✅ Done!"
