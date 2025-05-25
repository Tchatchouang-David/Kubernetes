# Kubernetes
Repository to store Kubernetes projects

# HOW TO USE    
# On the master:
sudo bash install-k8s.sh master

# On each worker:
sudo bash install-k8s.sh worker JOIN_COMMAND
# where JOIN_COMMAND is the full output of `kubeadm token create --print-join-command`
# EXAMPLE ON WORKER: sudo bash install-k8s.sh worker kubeadm join x.x.x.x:xxxx --token lloucg.chakh6qawa84teo5 --discovery-token-ca-cert-hash sha256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx 
sudo bash install-k8s.sh worker kubeadm join 10.0.1.31:6443 --token lloucg.chakh6qawa84teo5 --discovery-token-ca-cert-hash sha256:262295396f0e9a99d485cd7040af4f5640cfac219ba97c34a8b21c135e3b4fa4