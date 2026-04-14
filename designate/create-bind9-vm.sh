#!/bin/bash
#
# Creates a libvirt VM running BIND9 (named) on the default virbr0 network.
# Uses a CentOS Stream 9 cloud image with cloud-init for provisioning.
#
# Prerequisites: libvirt, qemu-kvm, virt-install, genisoimage
# Usage: sudo ./create-bind9-vm.sh [--teardown]
#

set -euo pipefail

VM_NAME="bind9-server"
IMAGE_DIR="/var/lib/libvirt/images"
CLOUD_IMAGE_URL="https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
CLOUD_IMAGE="${IMAGE_DIR}/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
VM_DISK="${IMAGE_DIR}/${VM_NAME}.qcow2"
CLOUDINIT_DIR="${IMAGE_DIR}/${VM_NAME}-cloudinit"
CLOUDINIT_ISO="${IMAGE_DIR}/${VM_NAME}-cloudinit.iso"
DISK_SIZE="20G"
MEMORY=1024
VCPUS=1
NETWORK="default"

# Find the invoking user's SSH public key (works even when run via sudo)
REAL_USER="${SUDO_USER:-$(whoami)}"
REAL_HOME=$(eval echo "~${REAL_USER}")
SSH_PUBKEY=""
for keyfile in "${REAL_HOME}/.ssh/id_ed25519.pub" "${REAL_HOME}/.ssh/id_rsa.pub" "${REAL_HOME}/.ssh/id_ecdsa.pub"; do
    if [[ -f "${keyfile}" ]]; then
        SSH_PUBKEY=$(cat "${keyfile}")
        break
    fi
done
if [[ -z "${SSH_PUBKEY}" ]]; then
    echo "ERROR: No SSH public key found in ${REAL_HOME}/.ssh/" >&2
    exit 1
fi

teardown() {
    echo "Tearing down ${VM_NAME}..."
    virsh destroy "${VM_NAME}" 2>/dev/null || true
    virsh undefine "${VM_NAME}" 2>/dev/null || true
    rm -f "${VM_DISK}" "${CLOUDINIT_ISO}"
    rm -rf "${CLOUDINIT_DIR}"
    echo "Done. Cloud base image preserved at ${CLOUD_IMAGE}"
}

if [[ "${1:-}" == "--teardown" ]]; then
    teardown
    exit 0
fi

# Bail out if VM already exists
if virsh dominfo "${VM_NAME}" &>/dev/null; then
    echo "VM '${VM_NAME}' already exists. Use --teardown first to recreate." >&2
    exit 1
fi

# Download cloud image if not already cached
if [[ ! -f "${CLOUD_IMAGE}" ]]; then
    echo "Downloading CentOS Stream 9 cloud image..."
    curl -L -o "${CLOUD_IMAGE}" "${CLOUD_IMAGE_URL}"
else
    echo "Cloud image already present, skipping download."
fi

# Create overlay disk backed by the cloud image
echo "Creating VM disk..."
qemu-img create -f qcow2 -b "${CLOUD_IMAGE}" -F qcow2 "${VM_DISK}" "${DISK_SIZE}"

# Build cloud-init data
echo "Building cloud-init config..."
mkdir -p "${CLOUDINIT_DIR}"

cat > "${CLOUDINIT_DIR}/meta-data" << EOF
instance-id: ${VM_NAME}
local-hostname: ${VM_NAME}
EOF

cat > "${CLOUDINIT_DIR}/user-data" << EOF
#cloud-config
ssh_pwauth: false
ssh_authorized_keys:
  - ${SSH_PUBKEY}

users:
  - name: root
    lock_passwd: true
    ssh_authorized_keys:
      - ${SSH_PUBKEY}
  - default

packages:
  - bind
  - bind-utils

runcmd:
  - sed -i 's/listen-on port 53 { 127.0.0.1; };/listen-on port 53 { any; };/' /etc/named.conf
  - sed -i 's/listen-on-v6 port 53 { ::1; };/listen-on-v6 port 53 { any; };/' /etc/named.conf
  - sed -i 's/allow-query     { localhost; };/allow-query     { localhost; 192.168.122.0\/24; };/' /etc/named.conf
  - systemctl enable named
  - systemctl start named
EOF

genisoimage -output "${CLOUDINIT_ISO}" -volid cidata -joliet -rock \
    "${CLOUDINIT_DIR}/meta-data" "${CLOUDINIT_DIR}/user-data"

# Create and start the VM
echo "Creating VM..."
virt-install \
    --name "${VM_NAME}" \
    --memory "${MEMORY}" \
    --vcpus "${VCPUS}" \
    --disk "path=${VM_DISK},format=qcow2" \
    --disk "path=${CLOUDINIT_ISO},device=cdrom" \
    --os-variant centos-stream9 \
    --network "network=${NETWORK}" \
    --import \
    --noautoconsole \
    --graphics none

# Wait for the VM to get an IP address
echo "Waiting for VM to obtain an IP address..."
VM_IP=""
for i in $(seq 1 60); do
    VM_IP=$(virsh domifaddr "${VM_NAME}" 2>/dev/null | awk '/ipv4/ {split($4,a,"/"); print a[1]}')
    if [[ -n "${VM_IP}" ]]; then
        break
    fi
    sleep 2
done

if [[ -z "${VM_IP}" ]]; then
    echo "ERROR: VM did not obtain an IP address within 120 seconds." >&2
    exit 1
fi

echo "VM IP: ${VM_IP}"

# Wait for cloud-init to finish
echo "Waiting for cloud-init to complete (this may take a minute)..."
for i in $(seq 1 60); do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o UserKnownHostsFile=/dev/null \
        "cloud-user@${VM_IP}" 'sudo cloud-init status' 2>/dev/null | grep -q 'done'; then
        break
    fi
    sleep 5
done

# Verify BIND is running
echo "Verifying BIND (named) service..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "cloud-user@${VM_IP}" 'sudo systemctl is-active named' 2>/dev/null

echo ""
echo "=========================================="
echo " BIND9 VM is ready"
echo "=========================================="
echo " VM Name:  ${VM_NAME}"
echo " IP:       ${VM_IP}"
echo " SSH:      ssh cloud-user@${VM_IP}"
echo " DNS test: dig @${VM_IP} version.bind chaos txt"
echo " Teardown: sudo $0 --teardown"
echo "=========================================="
