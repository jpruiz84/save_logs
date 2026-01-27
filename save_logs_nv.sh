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
history -w "logs_${LOG_ID}_bash_history.txt" 2>/dev/null

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
    NVIDIA_SMI_LOG="logs_${LOG_ID}_nvidia_smi.txt"

    {
        echo "===== nvidia-smi ====="
        nvidia-smi
        echo

        echo "===== nvidia-smi --version ====="
        nvidia-smi --version
        echo

        echo "===== nvidia-smi topo -m ====="
        nvidia-smi topo -m
        echo

        echo "===== nvidia-smi -q ====="
        nvidia-smi -q
        echo

        echo "===== nvidia-smi conf-compute -f ====="
        nvidia-smi conf-compute -f
        echo

        echo "===== nvidia-smi conf-compute -q ====="
        nvidia-smi conf-compute -q
        echo

        echo "===== nvidia-smi conf-compute -grs ====="
        nvidia-smi conf-compute -grs
        echo

        echo "===== nvidia-smi conf-compute -e ====="
        nvidia-smi conf-compute -e
        echo
    } >> "$NVIDIA_SMI_LOG" 2>&1
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
if ! command -v tree &> /dev/null; then
    echo "Warning: 'tree' command not found. Attempting to install (apt)..."
    if command -v apt-get &> /dev/null; then
        apt-get update -y && apt-get install -y tree
    else
        echo "apt-get not found; cannot auto-install tree."
    fi
fi

if command -v tree &> /dev/null; then
    echo "Collecting directory trees..."
    tree /sys > "logs_${LOG_ID}_tree_sys.txt"
    tree /etc > "logs_${LOG_ID}_tree_etc.txt"
else
    echo "Warning: 'tree' still not available. Skipping tree logs."
    echo "Install via: apt install tree / yum install tree"
fi

# 7. Dependency Check for 'fastfetch' / 'neofetch'
# If either is already available, do not attempt installs.
if ! command -v fastfetch &> /dev/null && ! command -v neofetch &> /dev/null; then
    echo "Warning: Neither 'fastfetch' nor 'neofetch' found. Attempting to install (apt)..."
    if command -v apt-get &> /dev/null; then
        apt-get update -y
        if ! apt-get install -y fastfetch; then
            echo "Warning: Could not install 'fastfetch'. Trying 'neofetch' instead..."
            apt-get install -y neofetch || echo "Warning: Could not install 'neofetch' either."
        fi
    else
        echo "apt-get not found; cannot auto-install fastfetch/neofetch."
    fi
fi

if command -v fastfetch &> /dev/null; then
    echo "Collecting fastfetch system summary..."
    {
        echo "===== fastfetch ====="
        (fastfetch --pipe || fastfetch)
    } > "logs_${LOG_ID}_fastfetch.txt" 2>&1
elif command -v neofetch &> /dev/null; then
    echo "Collecting neofetch system summary (fastfetch fallback)..."
    {
        echo "===== neofetch (--stdout) ====="
        neofetch --stdout
    } > "logs_${LOG_ID}_fastfetch.txt" 2>&1
else
    echo "Warning: Neither 'fastfetch' nor 'neofetch' is available. Skipping system summary logs." > "logs_${LOG_ID}_fastfetch_warning.txt"
fi

echo "Collecting lshw/lscpu/lsblk/lsmem/lsusb (single file)..."
HWTOOLS_LOG="logs_${LOG_ID}_hwtools.txt"
{
    echo "===== lshw ====="
    if command -v lshw &> /dev/null; then
        lshw
    else
        echo "Warning: 'lshw' not found"
    fi
    echo

    echo "===== lscpu ====="
    if command -v lscpu &> /dev/null; then
        lscpu
    else
        echo "Warning: 'lscpu' not found"
    fi
    echo

    echo "===== lsblk ====="
    if command -v lsblk &> /dev/null; then
        lsblk -a -f
    else
        echo "Warning: 'lsblk' not found"
    fi
    echo

    echo "===== lsmem ====="
    if command -v lsmem &> /dev/null; then
        lsmem
    else
        echo "Warning: 'lsmem' not found"
    fi
    echo

    echo "===== lsusb ====="
    if command -v lsusb &> /dev/null; then
        lsusb
        echo
        echo "===== lsusb -t ====="
        lsusb -t
    else
        echo "Warning: 'lsusb' not found"
    fi
} > "$HWTOOLS_LOG" 2>&1

echo "Collecting environment..."
env > "logs_${LOG_ID}_env.txt"

echo "--- Success. Logs saved in ${OUTPUT_DIR} ---"