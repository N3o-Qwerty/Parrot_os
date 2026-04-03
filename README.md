# VirtualBox Fix for Parrot OS

A lightweight script that resolves the VirtualBox / KVM conflict on Parrot OS
by temporarily unloading the KVM kernel modules so VirtualBox can claim the
hardware virtualisation extensions (Intel VT-x / AMD-V).

No permanent changes are made to the OS -- once you're done with VirtualBox you
can reload the KVM modules with a single command.

## The Problem

Parrot OS ships with KVM modules loaded by default.  VirtualBox requires
exclusive access to the CPU virtualisation extensions, so it refuses to start
(or starts without hardware acceleration) while `kvm_intel` / `kvm_amd` is
loaded.

## Quick Start

```bash
# Clone the repo
git clone https://github.com/N3o-Qwerty/Parrot_os.git
cd Parrot_os

# Make the script executable
chmod +x vbfix.sh

# Run the fix (requires root)
sudo ./vbfix.sh

# Start VirtualBox and use it normally...

# When done, restore KVM modules for QEMU / libvirt
sudo ./vbfix.sh --restore
```

## Usage

```
vbfix.sh - VirtualBox compatibility fix for Parrot OS  v2.0.0

Usage:
  sudo ./vbfix.sh [OPTIONS]

Options:
  -h, --help        Show this help message and exit
  -v, --version     Print version and exit
  --restore         Reload KVM modules (undo the fix)
```

### Default behaviour (no flags)

1. Checks that VirtualBox is installed.
2. Detects Secure Boot and warns if it may block unsigned kernel modules.
3. Detects CPU vendor (Intel / AMD).
4. Checks if KVM modules are in use by running VMs -- exits safely if so.
5. Unloads the KVM kernel modules (`kvm_intel` or `kvm_amd` + `kvm`).
6. Refreshes VirtualBox kernel drivers via `/sbin/vboxconfig`.

### Restore mode (`--restore`)

Reloads the KVM modules so QEMU / libvirt virtual machines can run again:

```bash
sudo ./vbfix.sh --restore
```

## Features

- **Auto-detects CPU vendor** -- works on both Intel and AMD systems.
- **Safe unload** -- checks if KVM modules are in use before removing them;
  exits with a clear error if a QEMU/KVM VM is still running.
- **Secure Boot detection** -- warns you if Secure Boot is enabled (which can
  prevent unsigned VirtualBox modules from loading).
- **VirtualBox installation check** -- exits early with a helpful message if
  VirtualBox is not installed.
- **Restore flag** -- easily reload KVM modules when you're done with
  VirtualBox.
- **Proper exit codes** -- returns non-zero on errors for scripting/automation.
- **Colour-coded output** -- clear visual feedback on each step.

## Requirements

- Parrot OS (or any Debian-based distro with KVM)
- VirtualBox installed (`sudo apt install virtualbox`)
- Root privileges (`sudo`)

## License

[MIT](LICENSE) 
