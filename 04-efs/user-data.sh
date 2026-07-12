#!/bin/bash

# Update packages
apt update -y

# Install NFS client
apt install -y nfs-common

# Create EFS mount directory
mkdir -p /mnt/efs

# Mount EFS
mount -t nfs4 ${efs_ip}:/ /mnt/efs

# Make the mount persistent after reboot
echo "${efs_ip}:/ /mnt/efs nfs4 defaults,_netdev 0 0" >> /etc/fstab