#!/bin/bash
# vbfix.sh - VirtualBox compatibility fix for Parrot OS
#
# Temporarily unloads KVM kernel modules so VirtualBox can run without
# permanent changes to the OS.  Supports both Intel (kvm_intel) and
# AMD (kvm_amd) processors.
#
# Usage:
#   sudo ./vbfix.sh             # unload KVM and refresh VirtualBox drivers
#   sudo ./vbfix.sh --restore   # reload KVM modules after you're done with VB
#   ./vbfix.sh --help           # show usage information
#
# Requirements: VirtualBox must be installed.

set -euo pipefail

VERSION="2.0.0"

# ── Colour helpers ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[+]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
log_step()  { echo -e "${CYAN}[*]${NC} $*"; }
log_error() { echo -e "${RED}[-]${NC} $*" >&2; }

# ── Usage / help ─────────────────────────────────────────────────────
usage() {
    cat << EOF
vbfix.sh - VirtualBox compatibility fix for Parrot OS  v${VERSION}

Usage:
  sudo ./vbfix.sh [OPTIONS]

Options:
  -h, --help        Show this help message and exit
  -v, --version     Print version and exit
  --restore         Reload KVM modules (undo the fix)

Default behaviour (no flags):
  1. Detect CPU vendor (Intel / AMD)
  2. Check if KVM modules are in use by other VMs
  3. Unload KVM kernel modules
  4. Refresh VirtualBox kernel drivers via /sbin/vboxconfig
  5. Detect Secure Boot and warn if it may block unsigned modules

After you are done using VirtualBox, run:
  sudo ./vbfix.sh --restore
to reload the KVM modules for QEMU / libvirt.
EOF
}

# ── Detect CPU vendor ────────────────────────────────────────────────
detect_cpu() {
    if grep -q vmx /proc/cpuinfo; then
        CPU_VENDOR="intel"
        KVM_MODULE="kvm_intel"
    elif grep -q svm /proc/cpuinfo; then
        CPU_VENDOR="amd"
        KVM_MODULE="kvm_amd"
    else
        CPU_VENDOR="unknown"
        KVM_MODULE=""
    fi
}

# ── Check if a module is in use ──────────────────────────────────────
module_in_use() {
    local mod="$1"
    if ! lsmod | grep -q "^${mod} "; then
        return 1  # not loaded at all
    fi
    local used_by
    used_by=$(lsmod | awk -v m="${mod}" '$1 == m {print $3}')
    if [[ "${used_by}" -gt 0 ]] 2>/dev/null; then
        return 0  # in use
    fi
    return 1  # loaded but not in use
}

# ── Check for Secure Boot ───────────────────────────────────────────
check_secure_boot() {
    if command -v mokutil &>/dev/null; then
        if mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
            log_warn "Secure Boot is ENABLED."
            log_warn "VirtualBox kernel modules may fail to load if they are not signed."
            log_warn "If VirtualBox does not start, consider:"
            echo "         - Disabling Secure Boot in BIOS/UEFI"
            echo "         - Signing the vboxdrv module with your own MOK key"
            echo "         - Running: sudo mokutil --disable-validation"
            return 0
        fi
    fi
    return 1
}

# ── Check VirtualBox installation ────────────────────────────────────
check_virtualbox() {
    if ! command -v VBoxManage &>/dev/null; then
        log_error "VirtualBox does not appear to be installed."
        log_error "Install it first:  sudo apt install virtualbox"
        exit 1
    fi
    log_info "VirtualBox detected: $(VBoxManage --version 2>/dev/null || echo 'unknown version')"
}

# ── Unload KVM modules ──────────────────────────────────────────────
unload_kvm() {
    detect_cpu

    if [[ -z "${KVM_MODULE}" ]]; then
        log_warn "Could not detect Intel VT-x (vmx) or AMD-V (svm) in /proc/cpuinfo."
        log_warn "Skipping KVM module unload -- VirtualBox may still work."
        return
    fi

    log_info "${CPU_VENDOR^^} CPU detected."

    # Unload vendor-specific module
    if lsmod | grep -q "^${KVM_MODULE} "; then
        if module_in_use "${KVM_MODULE}"; then
            log_error "${KVM_MODULE} is currently in use by another VM or process."
            log_error "Please shut down any QEMU/KVM virtual machines first."
            exit 1
        fi
        log_step "Unloading ${KVM_MODULE}..."
        if ! modprobe -r "${KVM_MODULE}"; then
            log_error "Failed to unload ${KVM_MODULE}.  Is a VM still running?"
            exit 1
        fi
        log_info "${KVM_MODULE} unloaded."
    else
        log_info "${KVM_MODULE} is not loaded -- skipping."
    fi

    # Unload base kvm module
    if lsmod | grep -q "^kvm "; then
        if module_in_use "kvm"; then
            log_warn "Base kvm module is still in use -- skipping."
        else
            log_step "Unloading base kvm module..."
            if ! modprobe -r kvm; then
                log_warn "Could not unload base kvm module (may be held by other modules)."
            else
                log_info "Base kvm module unloaded."
            fi
        fi
    else
        log_info "Base kvm module is not loaded -- skipping."
    fi
}

# ── Reload KVM modules (--restore) ──────────────────────────────────
reload_kvm() {
    detect_cpu

    log_step "Reloading KVM modules..."

    if ! modprobe kvm; then
        log_error "Failed to load base kvm module."
        exit 1
    fi
    log_info "Base kvm module loaded."

    if [[ -n "${KVM_MODULE}" ]]; then
        if ! modprobe "${KVM_MODULE}"; then
            log_error "Failed to load ${KVM_MODULE}."
            exit 1
        fi
        log_info "${KVM_MODULE} loaded."
    else
        log_warn "Could not detect CPU vendor -- loaded base kvm only."
    fi

    echo ""
    log_info "KVM modules restored.  QEMU/libvirt VMs can run again."
}

# ── Refresh VirtualBox drivers ───────────────────────────────────────
refresh_vbox() {
    if [[ -x /sbin/vboxconfig ]]; then
        log_step "Refreshing VirtualBox kernel drivers..."
        if ! /sbin/vboxconfig; then
            log_error "vboxconfig failed.  Check the output above for details."
            if check_secure_boot; then
                log_warn "This may be caused by Secure Boot (see above)."
            fi
            exit 1
        fi
        log_info "VirtualBox kernel drivers refreshed."
    else
        log_warn "/sbin/vboxconfig not found.  Skipping driver refresh."
        log_warn "You may need to run: sudo /sbin/vboxconfig manually."
    fi
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
    local mode="fix"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                echo "vbfix.sh v${VERSION}"
                exit 0
                ;;
            --restore)
                mode="restore"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Root check
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "Please run with sudo: sudo ./vbfix.sh"
        exit 1
    fi

    if [[ "${mode}" == "restore" ]]; then
        echo ""
        echo "=============================================="
        echo "  VirtualBox Fix - Restore KVM Modules"
        echo "=============================================="
        echo ""
        reload_kvm
    else
        echo ""
        echo "=============================================="
        echo "  VirtualBox Fix for Parrot OS  v${VERSION}"
        echo "=============================================="
        echo ""

        check_virtualbox
        check_secure_boot || true
        unload_kvm
        refresh_vbox

        echo ""
        log_info "Done! You can now start VirtualBox."
        log_info "When finished, run: sudo ./vbfix.sh --restore"
        echo ""
    fi
}

main "$@"
