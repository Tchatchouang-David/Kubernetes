# Kubernetes
Repository to store Kubernetes projects

# HOW TO USE    
# On the master:
sudo bash install-k8s.sh master

# On each worker:
sudo bash install-k8s.sh worker JOIN_COMMAND
# where JOIN_COMMAND is the full output of `kubeadm token create --print-join-command`
# EXAMPLE ON WORKER: sudo bash install-k8s.sh worker kubeadm join x.x.x.x:xxxx --token lloucg.chakh6qawa84teo5 --discovery-token-ca-cert-hash sha256:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx 
