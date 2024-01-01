#!/bin/bash
#
# Setup for Control Plane (Master) servers

set -euxo pipefail

# If you need public access to API server using the servers Public IP adress, change PUBLIC_IP_ACCESS to true.

PUBLIC_IP_ACCESS="false"
NODENAME=$(hostname -s)
POD_CIDR="10.1.0.0/16"

# Pull required images

sudo kubeadm config images pull

# Initialize kubeadm based on PUBLIC_IP_ACCESS

if [[ "$PUBLIC_IP_ACCESS" == "false" ]]; then
    IFACE=$(ip route show to match default | perl -nle 'if ( /dev\s+(\S+)/ ) {print $1}')
    MASTER_PRIVATE_IP=$(ip addr show $IFACE | awk '/inet / {print $2}' | cut -d/ -f1)
    sudo kubeadm init --apiserver-advertise-address="$MASTER_PRIVATE_IP" --apiserver-cert-extra-sans="$MASTER_PRIVATE_IP" --pod-network-cidr="$POD_CIDR" --node-name "$NODENAME" --ignore-preflight-errors Swap

elif [[ "$PUBLIC_IP_ACCESS" == "true" ]]; then

    MASTER_PUBLIC_IP=$(curl ifconfig.me && echo "")
    sudo kubeadm init --control-plane-endpoint="$MASTER_PUBLIC_IP" --apiserver-cert-extra-sans="$MASTER_PUBLIC_IP" --pod-network-cidr="$POD_CIDR" --node-name "$NODENAME" --ignore-preflight-errors Swap

else
    echo "Error: MASTER_PUBLIC_IP has an invalid value: $PUBLIC_IP_ACCESS"
    exit 1
fi

# Configure kubeconfig
mkdir -p "$HOME"/.kube
sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
sudo chown "$(id -u)":"$(id -g)" "$HOME"/.kube/config

# Allow scheduling of pods on Kubernetes master
kubectl taint nodes --all node-role.kubernetes.io/control-plane-

# install helm
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm

# install Network Plugin
echo "Which Network Plugin do you want to install?"
echo "1. Calico"
echo "2. Flannel"
echo "3. Weave"
echo "4. Cilium"
echo "Please enter your choice (1/2/3/4):"

read choice

case $choice in
    1)
        echo "Installing Calico..."
	# Install Claico Network Plugin Network
	curl https://raw.githubusercontent.com/projectcalico/calico/v3.25.0/manifests/calico.yaml -O

	kubectl apply -f calico.yaml

        ;;
    2)
        echo "Installing Flannel..."
        # Add commands to install Flannel here
        ;;
    3)
        echo "Installing Weave..."
        # Add commands to install Weave here
        ;;
    4)
        echo "Installing  Cilium..."
	# Install the Cilium CLI
	CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
	CLI_ARCH=amd64
	if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
	curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
	sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
	sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
	rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
	# Install Cilium
	cilium install --version 1.14.5
	# Validate the Installation
	cilium status --wait
	cilium connectivity test
        ;;

    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

kubectl cluster-info
kubectl get po -n kube-system
kubectl get nodes

