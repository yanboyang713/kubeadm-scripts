#!/bin/bash

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
    sudo mv "$file" "$file.backup"
    # Overwrite the original file with the modified content
    sudo mv "$temp_file" "$file"
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
        sudo swapoff -a
    fi

}

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
            sudo swapoff -a
            ;;
        *)
            echo "Invalid input. Please enter 'yes' or 'no'."
            ;;
    esac
}

disable_swap
