#!/bin/bash

#=============================================================================
# NVIDIA System Log Collector
# Collects comprehensive system logs for debugging and analysis
#=============================================================================

#-----------------------------------------------------------------------------
# CONFIGURATION - Enable/disable collection modules (1=enabled, 0=disabled)
#-----------------------------------------------------------------------------
COLLECT_SYSTEM_INFO=1
COLLECT_HARDWARE_INFO=1
COLLECT_PCIE_TOPOLOGY=1
COLLECT_NVIDIA_INFO=1
COLLECT_USER_DATA=1
COLLECT_FILESYSTEM_TREES=1
COLLECT_SYSTEM_SUMMARY=1
CREATE_TARBALL=1

#-----------------------------------------------------------------------------
# GLOBAL VARIABLES
#-----------------------------------------------------------------------------
LOG_ID=""
OUTPUT_DIR=""
MANIFEST_FILE=""
START_TIME=""
COLLECTED_FILES=()
FAILED_COLLECTIONS=()

#-----------------------------------------------------------------------------
# HELPER FUNCTIONS
#-----------------------------------------------------------------------------
log_info() {
    echo "[INFO] $1"
}

log_warn() {
    echo "[WARN] $1"
}

log_error() {
    echo "[ERROR] $1"
}

add_to_manifest() {
    local file="$1"
    local description="$2"
    if [[ -f "$file" ]]; then
        local size
        size=$(stat -c%s "$file" 2>/dev/null || echo "unknown")
        echo "$(date '+%Y-%m-%d %H:%M:%S') | $file | $size bytes | $description" >> "$MANIFEST_FILE"
        COLLECTED_FILES+=("$file")
    fi
}

mark_failed() {
    local collection="$1"
    local reason="$2"
    FAILED_COLLECTIONS+=("$collection: $reason")
}

#-----------------------------------------------------------------------------
# DEPENDENCY MANAGEMENT
#-----------------------------------------------------------------------------
check_and_install_dependencies() {
    log_info "Checking dependencies..."

    # Check for tree
    if ! command -v tree &> /dev/null; then
        log_warn "'tree' not found. Attempting to install..."
        if command -v apt-get &> /dev/null; then
            apt-get update -y && apt-get install -y tree 2>/dev/null
        fi
    fi

    # Check for fastfetch/neofetch
    if ! command -v fastfetch &> /dev/null && ! command -v neofetch &> /dev/null; then
        log_warn "Neither 'fastfetch' nor 'neofetch' found. Attempting to install..."
        if command -v apt-get &> /dev/null; then
            apt-get update -y 2>/dev/null
            if ! apt-get install -y fastfetch 2>/dev/null; then
                apt-get install -y neofetch 2>/dev/null
            fi
        fi
    fi
}

#-----------------------------------------------------------------------------
# COLLECTION FUNCTIONS
#-----------------------------------------------------------------------------
collect_system_info() {
    log_info "Collecting system info (dmesg, journal, env, kernel configs)..."

    # dmesg
    if dmesg > "logs_${LOG_ID}_dmesg.txt" 2>&1; then
        add_to_manifest "logs_${LOG_ID}_dmesg.txt" "Kernel ring buffer"
    else
        mark_failed "dmesg" "Failed to capture"
    fi

    # journalctl
    if journalctl -b0 > "logs_${LOG_ID}_journalctl.txt" 2>&1; then
        add_to_manifest "logs_${LOG_ID}_journalctl.txt" "System journal (current boot)"
    else
        mark_failed "journalctl" "Failed to capture"
    fi

    # environment
    if env > "logs_${LOG_ID}_env.txt" 2>&1; then
        add_to_manifest "logs_${LOG_ID}_env.txt" "Environment variables"
    else
        mark_failed "env" "Failed to capture"
    fi

    # proc files
    cat /proc/iomem > "logs_${LOG_ID}_iomem.txt" 2>/dev/null
    add_to_manifest "logs_${LOG_ID}_iomem.txt" "I/O memory map"

    cat /proc/interrupts > "logs_${LOG_ID}_interrupts.txt" 2>/dev/null
    add_to_manifest "logs_${LOG_ID}_interrupts.txt" "IRQ assignments"

    sort /proc/modules > "logs_${LOG_ID}_modules.txt" 2>/dev/null
    add_to_manifest "logs_${LOG_ID}_modules.txt" "Loaded kernel modules (from /proc)"

    lsmod | sort > "logs_${LOG_ID}_lsmod.txt" 2>/dev/null
    add_to_manifest "logs_${LOG_ID}_lsmod.txt" "Loaded kernel modules (lsmod)"

    # kernel configs
    find /boot -name "config*" -exec cp {} ./ \; 2>/dev/null
    for cfg in config*; do
        [[ -f "$cfg" ]] && add_to_manifest "$cfg" "Kernel configuration"
    done

    # Device tree
    if [[ -f /sys/firmware/fdt ]]; then
        cp /sys/firmware/fdt "logs_${LOG_ID}_dtb.dtb" 2>/dev/null
        add_to_manifest "logs_${LOG_ID}_dtb.dtb" "Device tree blob"
    fi

    # Platform devices
    ls -lah /sys/bus/platform/devices/ > "logs_${LOG_ID}_devices.txt" 2>/dev/null
    add_to_manifest "logs_${LOG_ID}_devices.txt" "Platform devices listing"
}

collect_hardware_info() {
    log_info "Collecting hardware info (lshw, lscpu, lsblk, lsmem, lsusb)..."

    local HWTOOLS_LOG="logs_${LOG_ID}_hwtools.txt"
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
    add_to_manifest "$HWTOOLS_LOG" "Hardware tools output (lshw, lscpu, lsblk, lsmem, lsusb)"
}

collect_pcie_topology() {
    log_info "Collecting PCIe / NUMA topology..."

    if command -v lspci &> /dev/null; then
        lspci -tv > "logs_${LOG_ID}_lspci_tv.txt" 2>&1
        add_to_manifest "logs_${LOG_ID}_lspci_tv.txt" "PCI device tree"

        lspci -vv > "logs_${LOG_ID}_lspci_vv.txt" 2>&1
        add_to_manifest "logs_${LOG_ID}_lspci_vv.txt" "PCI devices (verbose)"
    else
        mark_failed "lspci" "Command not found"
    fi

    if command -v numactl &> /dev/null; then
        numactl --hardware > "logs_${LOG_ID}_numactl_hardware.txt" 2>&1
        add_to_manifest "logs_${LOG_ID}_numactl_hardware.txt" "NUMA hardware topology"
    else
        mark_failed "numactl" "Command not found"
    fi
}

collect_nvidia_info() {
    log_info "Collecting NVIDIA GPU info..."

    if command -v nvidia-smi &> /dev/null; then
        local NVIDIA_SMI_LOG="logs_${LOG_ID}_nvidia_smi.txt"
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
        } > "$NVIDIA_SMI_LOG" 2>&1
        add_to_manifest "$NVIDIA_SMI_LOG" "NVIDIA SMI output"
    else
        mark_failed "nvidia-smi" "Command not found"
    fi
}

collect_user_data() {
    log_info "Collecting user data (bash history)..."

    for user_home in /home/* /root; do
        if [[ -d "$user_home" ]]; then
            local username
            username=$(basename "$user_home")
            if [[ -f "$user_home/.bash_history" ]]; then
                cp "$user_home/.bash_history" "logs_${LOG_ID}_bash_history_${username}.txt" 2>/dev/null
                add_to_manifest "logs_${LOG_ID}_bash_history_${username}.txt" "Bash history for user: $username"
            fi
        fi
    done
}

collect_filesystem_trees() {
    log_info "Collecting filesystem trees..."

    if command -v tree &> /dev/null; then
        tree /sys > "logs_${LOG_ID}_tree_sys.txt" 2>&1
        add_to_manifest "logs_${LOG_ID}_tree_sys.txt" "Directory tree of /sys"

        tree /etc > "logs_${LOG_ID}_tree_etc.txt" 2>&1
        add_to_manifest "logs_${LOG_ID}_tree_etc.txt" "Directory tree of /etc"
    else
        mark_failed "tree" "Command not found"
    fi
}

collect_system_summary() {
    log_info "Collecting system summary (fastfetch/neofetch)..."

    if command -v fastfetch &> /dev/null; then
        {
            echo "===== fastfetch ====="
            fastfetch --pipe 2>/dev/null || fastfetch
        } > "logs_${LOG_ID}_fastfetch.txt" 2>&1
        add_to_manifest "logs_${LOG_ID}_fastfetch.txt" "System summary (fastfetch)"
    elif command -v neofetch &> /dev/null; then
        {
            echo "===== neofetch (--stdout) ====="
            neofetch --stdout
        } > "logs_${LOG_ID}_fastfetch.txt" 2>&1
        add_to_manifest "logs_${LOG_ID}_fastfetch.txt" "System summary (neofetch)"
    else
        mark_failed "system_summary" "Neither fastfetch nor neofetch available"
    fi
}

#-----------------------------------------------------------------------------
# SUMMARY AND PACKAGING
#-----------------------------------------------------------------------------
generate_summary() {
    local END_TIME
    END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    local SUMMARY_FILE="logs_${LOG_ID}_summary.txt"

    {
        echo "=============================================="
        echo "       LOG COLLECTION SUMMARY REPORT"
        echo "=============================================="
        echo
        echo "Log ID:        $LOG_ID"
        echo "Start Time:    $START_TIME"
        echo "End Time:      $END_TIME"
        echo "Output Dir:    $OUTPUT_DIR"
        echo
        echo "----------------------------------------------"
        echo "FILES COLLECTED: ${#COLLECTED_FILES[@]}"
        echo "----------------------------------------------"
        for f in "${COLLECTED_FILES[@]}"; do
            echo "  [OK] $f"
        done
        echo
        if [[ ${#FAILED_COLLECTIONS[@]} -gt 0 ]]; then
            echo "----------------------------------------------"
            echo "FAILED/SKIPPED: ${#FAILED_COLLECTIONS[@]}"
            echo "----------------------------------------------"
            for f in "${FAILED_COLLECTIONS[@]}"; do
                echo "  [FAIL] $f"
            done
        else
            echo "----------------------------------------------"
            echo "All collections completed successfully!"
            echo "----------------------------------------------"
        fi
        echo
    } > "$SUMMARY_FILE"
    add_to_manifest "$SUMMARY_FILE" "Collection summary report"

    cat "$SUMMARY_FILE"
}

create_tarball() {
    log_info "Creating compressed archive..."

    cd ..
    local TARBALL="${LOG_ID}_logs.tar.gz"
    if tar -czf "$TARBALL" "$LOG_ID"; then
        log_info "Archive created: $(pwd)/$TARBALL"
        echo "Archive size: $(du -h "$TARBALL" | cut -f1)"
    else
        log_error "Failed to create tarball"
    fi
}

#-----------------------------------------------------------------------------
# MAIN EXECUTION
#-----------------------------------------------------------------------------
main() {
    # Help / Usage Check
    if [[ -z "$1" ]]; then
        echo "Error: No identifier argument provided."
        echo "Usage: sudo $0 <identifier>"
        echo "Example: sudo $0 tray17"
        exit 1
    fi

    # Check for Root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root to capture full system logs."
        exit 1
    fi

    # Initialize
    LOG_ID="$1"
    OUTPUT_DIR="./${LOG_ID}"
    START_TIME=$(date '+%Y-%m-%d %H:%M:%S')

    echo "=============================================="
    echo "  NVIDIA System Log Collector"
    echo "  Log ID: $LOG_ID"
    echo "  Started: $START_TIME"
    echo "=============================================="

    # Create output directory
    if ! mkdir -p "$OUTPUT_DIR"; then
        log_error "Could not create directory $OUTPUT_DIR"
        exit 1
    fi

    cd "$OUTPUT_DIR" || { log_error "Could not enter directory $OUTPUT_DIR"; exit 1; }
    log_info "Saving logs to $(pwd)..."

    # Initialize manifest
    MANIFEST_FILE="logs_${LOG_ID}_manifest.txt"
    echo "# Log Collection Manifest - $LOG_ID" > "$MANIFEST_FILE"
    echo "# Generated: $START_TIME" >> "$MANIFEST_FILE"
    echo "# Format: timestamp | filename | size | description" >> "$MANIFEST_FILE"
    echo "---" >> "$MANIFEST_FILE"

    # Check and install dependencies first
    check_and_install_dependencies

    # Run collection modules
    [[ $COLLECT_SYSTEM_INFO -eq 1 ]] && collect_system_info
    [[ $COLLECT_HARDWARE_INFO -eq 1 ]] && collect_hardware_info
    [[ $COLLECT_PCIE_TOPOLOGY -eq 1 ]] && collect_pcie_topology
    [[ $COLLECT_NVIDIA_INFO -eq 1 ]] && collect_nvidia_info
    [[ $COLLECT_USER_DATA -eq 1 ]] && collect_user_data
    [[ $COLLECT_FILESYSTEM_TREES -eq 1 ]] && collect_filesystem_trees
    [[ $COLLECT_SYSTEM_SUMMARY -eq 1 ]] && collect_system_summary

    # Finalize manifest
    add_to_manifest "$MANIFEST_FILE" "Collection manifest"

    # Generate summary
    echo
    generate_summary

    # Create tarball if enabled
    [[ $CREATE_TARBALL -eq 1 ]] && create_tarball

    echo
    log_info "Log collection complete!"
}

# Run main with all arguments
main "$@"
