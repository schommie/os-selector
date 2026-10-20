
set shell := ["bash", "-euo", "pipefail", "-c"]

# Configuration
target := "x86_64-unknown-uefi"
binary := "os-selector"
usb := "/dev/sda1"
mountpoint := "/mnt/os-selector"

# Show available commands
default:
    @just --list

# Build the UEFI application
build:
    cargo build --target {{target}}

# Build and deploy to USB
deploy: build
    #!/usr/bin/env bash
    set -euo pipefail

    USB="{{usb}}"
    MOUNT="{{mountpoint}}"
    EFI="target/{{target}}/debug/{{binary}}.efi"

    if [[ ! -f "$EFI" ]]; then
        echo "EFI executable not found: $EFI"
        exit 1
    fi

    # Validate the destination before mounting
    if [[ "$(lsblk -dn -o TYPE "$USB")" != "part" ]]; then
        echo "Error: $USB is not a partition"
        exit 1
    fi

    if [[ "$(lsblk -dn -o FSTYPE "$USB")" != "vfat" ]]; then
        echo "Error: $USB is not FAT32/vfat"
        exit 1
    fi

    if [[ "$(lsblk -dn -o TRAN "$(lsblk -no PKNAME "$USB" | head -1 | xargs -r -I{} echo /dev/{})")" != "usb" ]]; then
        echo "Error: $USB does not appear to be on a USB device"
        exit 1
    fi

    if findmnt -rn --source "$USB" >/dev/null; then
        echo "Error: $USB is already mounted. Unmount it first."
        exit 1
    fi

    echo "Deploying $EFI to $USB"
    lsblk -o NAME,SIZE,MODEL,FSTYPE "$USB"

    sudo mkdir -p "$MOUNT"
    sudo mount "$USB" "$MOUNT"

    # Ensure cleanup even if the copy fails
    cleanup() {
        sudo umount "$MOUNT"
    }
    trap cleanup EXIT

    sudo mkdir -p "$MOUNT/EFI/BOOT"
    sudo cp "$EFI" "$MOUNT/EFI/BOOT/BOOTX64.EFI"

    # Flush writes to the USB
    sync

    echo "Deployment successful!"
    echo "Installed: EFI/BOOT/BOOTX64.EFI"


# Build and run the UEFI application in QEMU
qemu-run: build
    #!/usr/bin/env bash
    set -euo pipefail

    ESP="target/qemu-esp"
    VARS="target/OVMF_VARS.fd"
    EFI="target/{{target}}/debug/{{binary}}.efi"

    OVMF_CODE="/usr/share/OVMF/OVMF_CODE.fd"
    OVMF_VARS="/usr/share/OVMF/OVMF_VARS.fd"

    # Create a virtual EFI System Partition
    mkdir -p "$ESP/EFI/BOOT"
    cp "$EFI" "$ESP/EFI/BOOT/BOOTX64.EFI"

    # Create persistent writable UEFI variable storage
    if [[ ! -f "$VARS" ]]; then
        cp "$OVMF_VARS" "$VARS"
    fi

    qemu-system-x86_64 \
        -enable-kvm \
        -m 512M \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$VARS" \
        -drive format=raw,file="fat:rw:$ESP"
