#!/bin/bash
#
# Common setup for all servers (Control Plane and Nodes)
#
# Function to comment out lines containing the keyword
comment_lines_with_keyword() {
    local keyword=$1
    local file=$2

    # Create a temporary file
    local temp_file=$(mktemp)

    while IFS= read -r line; do
        if [[ $line == *"$keyword"* ]]; then
            echo "# $line" >> "$temp_file"
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$file"
    # Make file backup
    mv "$file" "$file.backup"
    # Overwrite the original file with the modified content
    mv "$temp_file" "$file"
    echo "Modified content written back to $file"
}

# check swap size, if swap great than 1 bytes, disable Swap permanently
disable_swap_permanently() {
    # Get swap size in bytes
    swap_size=$(grep 'SwapTotal' /proc/meminfo | awk '{print $2}')

    # Check if the variable is less than 1
    if (( $(echo "$swap_size < 1" | bc -l) )); then
        echo "The Swap size is less than 1 bytes."
    else
        # Print the swap size
        echo "Swap Size: $swap_size"
        # disable swap permanently
        comment_lines_with_keyword "swap" "/etc/fstab"
        # apply the new swap setting
        mount -a
        # Disable Swap
        swapoff -a
    fi

}

# Disable Swap
disable_swap(){
    echo "K8S required Disable Swap"
    read -p "Do you want to Disable Swap Permanently? Otherwise Disable Temporarily (yes/no): " answer

    case "$answer" in
        [Yy][Ee][Ss]|[Yy])
            echo "Disable Swap Permanently"
            disable_swap_permanently
            ;;
        [Nn][Oo]|[Nn])
            echo "Disable Swap Temporarily"
            swapoff -a
            ;;
        *)
            echo "Invalid input. Please enter 'yes' or 'no'."
            ;;
    esac
}

# Enable iptables Bridged Traffic on all the Nodes
enable_iptables_bridged_traffic(){

# Create the .conf file to load the modules at bootup
cat <<EOF | tee /etc/modules-load.d/crio.conf
overlay
br_netfilter
EOF

# Execute the following commands to enable overlayFS & VxLan pod communication.
modprobe overlay
modprobe br_netfilter

# Set up required sysctl params, these persist across reboots.
cat <<EOF | tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Reload the parameters.
sysctl --system

}

# Install CRI-O Runtime
install_CRI_O_runtime(){

    dist_id=$(lsb_release -is)   # This gets the distributor ID (e.g., Ubuntu)
    version=$(lsb_release -rs)   # This gets the release version of the OS

    if [ "$dist_id" = "Ubuntu" ]; then
	echo "Operating system is Ubuntu."

	if [ "$version" = "22.04" ]; then
            # Set variable if Ubuntu version is 22.04
	    OS="xUbuntu_22.04"
            echo "Ubuntu version is 22.04."
	elif [ "$version" = "21.10" ]; then
	    OS="xUbuntu_21.10"
            echo "Ubuntu version is 21.10."
	else
            echo "Ubuntu version: $version, is not support"
	fi
    else
	echo "Operating system is not Ubuntu. Detected: $dist_id"
    fi

    VERSION="$(echo $1 | grep -oE '[0-9]+\.[0-9]+')"

    echo $VERSION

    # Add CRI source and key
    echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
    echo "deb [signed-by=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list

    mkdir -p /usr/share/keyrings
    curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-archive-keyring.gpg
    curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-crio-archive-keyring.gpg

    # Update and install crio and crio-tools.
    apt-get update
    apt-get install cri-o cri-o-runc

    # Reload the systemd configurations and enable cri-o.
    systemctl daemon-reload
    systemctl enable crio --now

    echo "CRI runtime installed susccessfully"
}

# Install kubelet, kubectl and Kubeadm
install_kubelet_kubectl_kubeadm(){
    # Install the required dependencies.
    apt-get update
    apt-get install -y apt-transport-https ca-certificates curl
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg

    # Add the GPG key and apt repository.
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | tee /etc/apt/sources.list.d/kubernetes.list

    # Update apt and install the latest version of kubelet, kubeadm, and kubectl.
    apt-get update -y
    apt-get install -y kubelet=$1 kubectl=$1 kubeadm=$1

    # Add hold to the packages to prevent upgrades.
    apt-mark hold kubelet kubeadm kubectl

}

#Add the node IP to KUBELET_EXTRA_ARGS.
set_node_IP(){
    apt-get update -y
    apt-get install -y jq

    IFACE=$(ip route show to match default | perl -nle 'if ( /dev\s+(\S+)/ ) {print $1}')
    local_ip=$(ip --json a s | jq -r --arg IFACE "$IFACE" '.[] | if .ifname == $IFACE then .addr_info[] | if .family == "inet" then .local else empty end else empty end')

    echo "$IFACE interface with IP: $local_ip"

    printf "KUBELET_EXTRA_ARGS=--node-ip=%s\n" "$local_ip" | tee -a /etc/default/kubelet

}

main() {
    # disable swap
    disable_swap

    apt-get update -y

    enable_iptables_bridged_traffic

    # Install CRI-O Runtime
    install_CRI_O_runtime $KUBERNETES_VERSION

    # Install kubelet, kubectl and Kubeadm
    install_kubelet_kubectl_kubeadm $KUBERNETES_VERSION

    # Add the node IP to KUBELET_EXTRA_ARGS.
    set_node_IP

}

set -euxo pipefail

# Variable Declaration
KUBERNETES_VERSION="1.28.1-00"

# Call the main function
main "$@"
