#!/bin/bash

# 1. Help / Usage Check
if [[ -z "$1" ]]; then
    echo "Error: No identifier argument provided."
    echo "Usage: sudo $0 <identifier>"
    echo "Example: sudo $0 tray17"
    exit 1
fi

LOG_ID="$1"
OUTPUT_DIR="./${LOG_ID}"

# 2. Check for Root (Required for dmesg, sys, etc.)
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root to capture full system logs."
   exit 1
fi

echo "--- Starting Log Capture for: ${LOG_ID} ---"

# 3. Safe Directory Creation
if ! mkdir -p "$OUTPUT_DIR"; then
    echo "Error: Could not create directory $OUTPUT_DIR"
    exit 1
fi

# 4. Safe Change Directory
cd "$OUTPUT_DIR" || { echo "Error: Could not enter directory $OUTPUT_DIR"; exit 1; }

echo "Saving logs to $(pwd)..."

# 5. Log Collection (Using '|| true' ensures script doesn't stop if one log fails)
echo "Collecting dmesg..."
dmesg > "logs_${LOG_ID}_dmesg.txt"

echo "Collecting hardware info..."
cat /proc/iomem > "logs_${LOG_ID}_iomem.txt" 2>/dev/null
cat /proc/interrupts > "logs_${LOG_ID}_interrupts.txt" 2>/dev/null
sort /proc/modules > "logs_${LOG_ID}_modules.txt" 2>/dev/null
lsmod | sort > "logs_${LOG_ID}_lsmod.txt"

echo "Collecting PCIe / NUMA topology..."
if command -v lspci &> /dev/null; then
    lspci -tv > "logs_${LOG_ID}_lspci_tv.txt" 2>&1
    lspci -vv > "logs_${LOG_ID}_lspci_vv.txt" 2>&1
else
    echo "Warning: 'lspci' not found. Skipping lspci logs." > "logs_${LOG_ID}_lspci_warning.txt"
fi

if command -v numactl &> /dev/null; then
    numactl --hardware > "logs_${LOG_ID}_numactl_hardware.txt" 2>&1
else
    echo "Warning: 'numactl' not found. Skipping NUMA logs." > "logs_${LOG_ID}_numactl_warning.txt"
fi

if command -v nvidia-smi &> /dev/null; then
    nvidia-smi topo -m > "logs_${LOG_ID}_nvidia_smi_topo_m.txt" 2>&1
else
    echo "Warning: 'nvidia-smi' not found. Skipping NVIDIA topology logs." > "logs_${LOG_ID}_nvidia_smi_warning.txt"
fi

# Handle Device Tree (Check if exists first to avoid error spam)
if [[ -f /sys/firmware/fdt ]]; then
    cp /sys/firmware/fdt "logs_${LOG_ID}_dtb.dtb"
fi

ls -lah /sys/bus/platform/devices/ > "logs_${LOG_ID}_devices.txt" 2>/dev/null

echo "Collecting journal..."
journalctl -b0 > "logs_${LOG_ID}_journalctl.txt"

echo "Collecting kernel configs..."
# usage of find is safer than cp with wildcards if no file exists
find /boot -name "config*" -exec cp {} ./ \;

# 6. Dependency Check for 'tree'
if command -v tree &> /dev/null; then
    echo "Collecting directory trees..."
    tree /sys > "logs_${LOG_ID}_tree_sys.txt"
    tree /etc > "logs_${LOG_ID}_tree_etc.txt"
else
    echo "Warning: 'tree' command not found. Skipping tree logs."
    echo "Install via: apt install tree / yum install tree"
fi

echo "Collecting environment..."
env > "logs_${LOG_ID}_env.txt"

echo "--- Success. Logs saved in ${OUTPUT_DIR} ---"