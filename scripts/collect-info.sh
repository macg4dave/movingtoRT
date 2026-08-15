#!/usr/bin/env bash
set -u
set -o pipefail
umask 077

OUTPUT_ROOT="${OUTPUT_ROOT:-./collected-info}"
RUN_ID="${RUN_ID:-$(hostname -s 2>/dev/null || echo unknown)-$(date +%Y%m%d-%H%M%S)-$$-${RANDOM}}"
OUTPUT_DIR="${OUTPUT_ROOT%/}/${RUN_ID}"

readonly SECRET_KEY_PATTERN='password|passwd|passphrase|psk|key|secret|token|credential|identity|private_key|client_secret|access_key|api_key'
readonly GPU_PATTERN='nvidia|amd|radeon|intel|vga|3d controller|display'
readonly VFIO_PATTERN='vfio|vfio-pci|ids=|driver_override|iommu|intel_iommu|amd_iommu|pcie_acs|nouveau|nvidia|rd.driver|modprobe|dracut|hostdev|vendor_id|device_id|pci-stub'
readonly STATUS_FILE_NAME='manifest-command-status.tsv'

usage() {
    cat <<'USAGE'
Usage: scripts/collect-info.sh [--output DIR]

Collect Rocky/RHEL host details into nested text files grouped by topic.
Run as root so protected system configuration can be collected.

Options:
  --output DIR          Base output directory. Default: ./collected-info
  -h, --help           Show this help.
USAGE
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --output)
                if [ "$#" -lt 2 ]; then
                    echo "Missing value for --output" >&2
                    exit 2
                fi
                OUTPUT_ROOT="$2"
                OUTPUT_DIR="${OUTPUT_ROOT%/}/${RUN_ID}"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown argument: $1" >&2
                usage >&2
                exit 2
                ;;
        esac
    done
}

prepare_output_dir() {
    local dirs=(
        system cpu gpu storage network virtualization security services
        packages containers kernel logs custom raw_config
    )

    mkdir -p "$OUTPUT_ROOT"
    if ! mkdir "$OUTPUT_DIR"; then
        echo "Output directory already exists or could not be created: $OUTPUT_DIR" >&2
        exit 1
    fi

    local dir
    for dir in "${dirs[@]}"; do
        mkdir "$OUTPUT_DIR/$dir"
    done

    chmod 700 "$OUTPUT_DIR" 2>/dev/null || true
}

require_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo "This script must be run as root to collect complete system information." >&2
        exit 1
    fi
}

write_manifest_start() {
    {
        echo "Collection started: $(date -Is 2>/dev/null || date)"
        echo "Hostname: $(hostname 2>/dev/null || echo unknown)"
        echo "Output directory: $OUTPUT_DIR"
        echo "Run user: $(id -un 2>/dev/null || echo unknown)"
        echo
        echo "WARNING: raw_config/ may contain secrets. Review before sharing."
    } >"$OUTPUT_DIR/manifest.txt"

    printf 'status\toutput_file\ttitle\n' >"$OUTPUT_DIR/$STATUS_FILE_NAME"
}

write_manifest_finish() {
    {
        echo
        echo "Collection finished: $(date -Is 2>/dev/null || date)"
        echo "Review output under: $OUTPUT_DIR"
        echo
        echo "Command status report:"
        cat "$OUTPUT_DIR/$STATUS_FILE_NAME" 2>/dev/null || true
        echo
        echo "Review before sharing:"
        echo "- Inspect raw_config/ for credentials, keys, certificates, tokens, and private host details."
        echo "- Prefer sharing redacted topic files first; share raw_config/ only with trusted recipients."
        echo "- Confirm VM XML, NetworkManager connections, repo files, and bootloader config do not expose secrets."
    } >>"$OUTPUT_DIR/manifest.txt"
}

record_capture_status() {
    local outfile="$1"
    local title="$2"
    local status="$3"

    printf '%s\t%s\t%s\n' "$status" "${outfile#"$OUTPUT_DIR"/}" "$title" >>"$OUTPUT_DIR/$STATUS_FILE_NAME"
}

capture_cmd() {
    local outfile="$1"
    local title="$2"
    local status
    shift 2

    {
        echo "========== ${title} =========="
        echo "Command: $*"
        echo
        "$@"
        status=$?
        echo
        echo "Exit status: ${status}"
    } >"$outfile" 2>&1

    record_capture_status "$outfile" "$title" "$status"
}

capture_shell() {
    local outfile="$1"
    local title="$2"
    local script="$3"
    local status

    {
        echo "========== ${title} =========="
        echo
        bash -c "$script"
        status=$?
        echo
        echo "Exit status: ${status}"
    } >"$outfile" 2>&1

    record_capture_status "$outfile" "$title" "$status"
}

capture_function() {
    local outfile="$1"
    local title="$2"
    local status
    shift 2

    {
        echo "========== ${title} =========="
        echo
        "$@"
        status=$?
        echo
        echo "Exit status: ${status}"
    } >"$outfile" 2>&1

    record_capture_status "$outfile" "$title" "$status"
}

copy_if_exists() {
    local source="$1"
    local target="$2"

    if [ -e "$source" ]; then
        mkdir -p "$(dirname "$target")"
        cp -a "$source" "$target" 2>"${target}.copy-error.txt" || true
    fi
}

redact_file() {
    local source="$1"
    local target="$2"

    if [ -f "$source" ]; then
        mkdir -p "$(dirname "$target")"
        redact_stream "$source" >"$target" 2>"${target}.redact-error.txt" || true
    fi
}

redact_stream() {
    sed -E \
        -e "s/((\"?(${SECRET_KEY_PATTERN})\"?[[:space:]]*[:=][[:space:]]*))\"[^\"]*\"/\\1\"<redacted>\"/Ig" \
        -e "s/((${SECRET_KEY_PATTERN})[[:space:]]*[:=][[:space:]]*)'[^']*'/\\1'<redacted>'/Ig" \
        -e "s/((${SECRET_KEY_PATTERN})[[:space:]]*[:=][[:space:]]*)[^[:space:],;}]+/\\1<redacted>/Ig" \
        -e 's/(802-1x\.password:).*/\1 <redacted>/Ig' \
        "$@" |
        awk '
            /-----BEGIN .*PRIVATE KEY-----/ { print "-----BEGIN REDACTED PRIVATE KEY-----"; in_pem=1; next }
            /-----END .*PRIVATE KEY-----/ { print "-----END REDACTED PRIVATE KEY-----"; in_pem=0; next }
            /-----BEGIN CERTIFICATE-----/ { print "-----BEGIN REDACTED CERTIFICATE-----"; in_pem=1; next }
            /-----END CERTIFICATE-----/ { print "-----END REDACTED CERTIFICATE-----"; in_pem=0; next }
            in_pem { next }
            { print }
        '
}

print_redacted_file() {
    local file="$1"

    echo "===== $file ====="
    redact_stream "$file" 2>/dev/null
    echo
}

grep_files_redacted() {
    local root="$1"
    local pattern="$2"
    shift 2

    [ -e "$root" ] || return 0

    find "$root" "$@" -type f -print 2>/dev/null | sort -u | while IFS= read -r file; do
        if grep -Eiq "$pattern" "$file" 2>/dev/null; then
            print_redacted_file "$file"
        fi
    done
}

command_availability_report() {
    local cmd
    local commands=(
        lspci virsh smartctl lsinitrd nmcli podman docker numactl
        lstopo-no-graphics dnf rpm ip ss journalctl firewall-cmd getenforce
        sestatus lsmod modinfo qemu-system-x86_64
    )

    printf '%-24s %s\n' "COMMAND" "PATH"
    for cmd in "${commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            printf '%-24s %s\n' "$cmd" "$(command -v "$cmd")"
        else
            printf '%-24s %s\n' "$cmd" "missing"
        fi
    done
}

bootloader_config_redacted() {
    local file path
    local paths=(
        /etc/default/grub
        /etc/grub.d
        /etc/kernel/cmdline
        /boot/grub2/grub.cfg
        /boot/efi/EFI
    )

    for path in "${paths[@]}"; do
        [ -e "$path" ] || continue
        find "$path" -type f -print 2>/dev/null
    done | sort -u |
        while IFS= read -r file; do
            if grep -Eiq "GRUB_CMDLINE|iommu|vfio|acs|nouveau|nvidia|amd_iommu|intel_iommu|rd.driver" "$file" 2>/dev/null; then
                print_redacted_file "$file"
            fi
        done
}

repo_files_redacted() {
    grep_files_redacted /etc/yum.repos.d '.*' -maxdepth 1
}

run_common_post_collection_copies() {
    redact_file /etc/default/grub "$OUTPUT_DIR/kernel/default_grub_redacted.txt"
    copy_if_exists /etc/fstab "$OUTPUT_DIR/storage/fstab.txt"
    copy_if_exists /etc/NetworkManager/system-connections "$OUTPUT_DIR/raw_config/NetworkManager-system-connections"
    copy_if_exists /etc/modprobe.d "$OUTPUT_DIR/raw_config/modprobe.d"
    copy_if_exists /etc/dracut.conf.d "$OUTPUT_DIR/raw_config/dracut.conf.d"
    copy_if_exists /etc/default/grub "$OUTPUT_DIR/raw_config/default-grub"
    copy_if_exists /etc/grub.d "$OUTPUT_DIR/raw_config/grub.d"
    copy_if_exists /etc/kernel/cmdline "$OUTPUT_DIR/raw_config/kernel-cmdline"
    copy_if_exists /boot/grub2/grub.cfg "$OUTPUT_DIR/raw_config/boot-grub2-grub.cfg"
    copy_if_exists /boot/efi/EFI "$OUTPUT_DIR/raw_config/boot-efi-efi"
    copy_if_exists /etc/yum.repos.d "$OUTPUT_DIR/raw_config/yum.repos.d"
    copy_if_exists /etc/fstab "$OUTPUT_DIR/raw_config/fstab"
}

collect_system_info() {
    capture_cmd "$OUTPUT_DIR/system/date.txt" "DATE" date
    capture_shell "$OUTPUT_DIR/system/os.txt" "OS RELEASE" 'cat /etc/redhat-release 2>/dev/null; cat /etc/os-release 2>/dev/null; uname -a; hostnamectl 2>/dev/null'
    capture_function "$OUTPUT_DIR/system/command_availability.txt" "COMMAND AVAILABILITY" command_availability_report
}

collect_kernel_info() {
    capture_shell "$OUTPUT_DIR/kernel/kernel.txt" "KERNEL" 'uname -r; echo; cat /proc/cmdline'
    capture_cmd "$OUTPUT_DIR/kernel/cmdline.txt" "KERNEL CMDLINE" cat /proc/cmdline
    capture_shell "$OUTPUT_DIR/kernel/modules.txt" "LOADED MODULES" 'lsmod | sort'
    capture_shell "$OUTPUT_DIR/kernel/iommu_settings.txt" "IOMMU KERNEL SETTINGS" 'cat /sys/module/intel_iommu/parameters/* 2>/dev/null; cat /sys/module/amd_iommu/parameters/* 2>/dev/null'
    capture_shell "$OUTPUT_DIR/kernel/dracut.txt" "DRACUT" 'ls -la /etc/dracut.conf.d/ 2>&1; echo; grep -RniE "vfio|nouveau|nvidia|pci" /etc/dracut.conf.d/ 2>/dev/null || true'
    capture_shell "$OUTPUT_DIR/kernel/initramfs.txt" "INITRAMFS" 'ls -lh /boot/initramfs-*.img 2>&1'
    capture_shell "$OUTPUT_DIR/kernel/grub.txt" "GRUB" 'grep -RniE "GRUB_CMDLINE|iommu|vfio|acs|nouveau" /etc/default/grub /etc/grub.d/ /etc/kernel/cmdline /boot/grub2/grub.cfg /boot/efi/EFI/ 2>/dev/null || true'
    capture_function "$OUTPUT_DIR/kernel/bootloader_config_redacted.txt" "BOOTLOADER CONFIG REDACTED" bootloader_config_redacted
    capture_function "$OUTPUT_DIR/kernel/module_config.txt" "KERNEL MODULE CONFIG" grep_files_redacted /etc/modprobe.d '.*' -maxdepth 1
}

collect_cpu_info() {
    capture_cmd "$OUTPUT_DIR/cpu/lscpu.txt" "CPU" lscpu
    capture_shell "$OUTPUT_DIR/cpu/topology.txt" "CPU TOPOLOGY" 'numactl --hardware 2>/dev/null; lstopo-no-graphics 2>/dev/null'
}

gpu_pci_addresses() {
    lspci -Dnn | grep -Ei "$GPU_PATTERN" || true
}

gpu_iommu_groups() {
    local dev group

    for dev in /sys/bus/pci/devices/*; do
        [ -e "$dev" ] || continue

        if lspci -s "$(basename "$dev")" 2>/dev/null | grep -Eiq "$GPU_PATTERN"; then
            echo "GPU: $(basename "$dev")"
            group="$(readlink -f "$dev/iommu_group" 2>/dev/null || true)"
            echo "$group"
            [ -n "$group" ] && ls -l "$(dirname "$group")"/devices 2>/dev/null
            echo
        fi
    done
}

gpu_driver_bindings() {
    local dev

    for dev in /sys/bus/pci/devices/*; do
        [ -e "$dev" ] || continue

        if lspci -s "$(basename "$dev")" 2>/dev/null | grep -Eiq "$GPU_PATTERN"; then
            echo "===== $(basename "$dev") ====="
            cat "$dev/vendor" 2>/dev/null
            cat "$dev/device" 2>/dev/null
            readlink "$dev/driver" 2>/dev/null || true
            echo
        fi
    done
}

gpu_vfio_custom_summary() {
    local dev

    echo "===== KERNEL CMDLINE ====="
    cat /proc/cmdline 2>/dev/null
    echo
    echo "===== GPU PCI IDS AND DRIVERS ====="

    for dev in /sys/bus/pci/devices/*; do
        [ -e "$dev" ] || continue

        if lspci -s "$(basename "$dev")" 2>/dev/null | grep -Eiq "${GPU_PATTERN}|audio"; then
            echo "--- $(basename "$dev") ---"
            lspci -nnk -s "$(basename "$dev")" 2>/dev/null
            echo "vendor=$(cat "$dev/vendor" 2>/dev/null)"
            echo "device=$(cat "$dev/device" 2>/dev/null)"
            echo "driver=$(readlink "$dev/driver" 2>/dev/null || true)"
            echo "iommu_group=$(readlink -f "$dev/iommu_group" 2>/dev/null || true)"
            echo
        fi
    done

    echo "===== VFIO / GPU CONFIG HITS ====="
    grep -RniE "${VFIO_PATTERN}|managed=.yes." \
        /etc/modprobe.d \
        /etc/modules-load.d \
        /etc/dracut.conf.d \
        /etc/default/grub \
        /etc/kernel \
        /etc/udev/rules.d \
        /etc/systemd/system \
        /usr/local/bin \
        /usr/local/sbin \
        /root \
        2>/dev/null || true
}

gpu_vfio_config_files_redacted() {
    local path file
    local paths=(
        /etc/modprobe.d
        /etc/modules-load.d
        /etc/dracut.conf.d
        /etc/udev/rules.d
        /etc/kernel
        /etc/default/grub
        /etc/libvirt/hooks
        /etc/systemd/system
    )

    for path in "${paths[@]}"; do
        [ -e "$path" ] || continue
        find "$path" -maxdepth 3 -type f 2>/dev/null
    done | sort -u | while IFS= read -r file; do
        if grep -Eiq "$VFIO_PATTERN" "$file" 2>/dev/null; then
            print_redacted_file "$file"
        fi
    done
}

libvirt_hooks_redacted() {
    grep_files_redacted /etc/libvirt/hooks '.*' -maxdepth 4
}

systemd_overrides_redacted() {
    local file

    find /etc/systemd/system \( -path "*.d/*.conf" -o -type f -name "*.service" \) -print 2>/dev/null |
        sort |
        while IFS= read -r file; do
            if grep -Eiq "vfio|gpu|nvidia|nouveau|qemu|libvirt|driver_override|pci|iommu" "$file" 2>/dev/null; then
                print_redacted_file "$file"
            fi
        done
}

initramfs_vfio_contents() {
    local img

    for img in /boot/initramfs-*.img; do
        [ -e "$img" ] || continue
        echo "===== $img ====="
        lsinitrd "$img" 2>/dev/null | grep -Ei "vfio|nvidia|nouveau|amdgpu|radeon|i915|modprobe|dracut" || true
        echo
    done
}

networkmanager_connections_redacted() {
    local file

    for file in /etc/NetworkManager/system-connections/*; do
        [ -f "$file" ] || continue
        echo "--- $file"
        sed -E -e "$REDACT_PATTERN" "$file"
        echo
    done
}

smart_summary() {
    local disk

    for disk in /dev/sd? /dev/nvme?n?; do
        [ -e "$disk" ] || continue
        echo "===== $disk ====="
        smartctl -H -i "$disk" 2>&1
        echo
    done
}

vm_xml_redacted() {
    local vm

    while IFS= read -r vm; do
        [ -n "$vm" ] || continue
        echo "===== VM: $vm ====="
        virsh dumpxml "$vm" 2>&1 | redact_stream
        echo
    done < <(virsh list --all --name 2>/dev/null)
}

vm_xml_raw_files() {
    local safe_name vm
    local target_dir="$OUTPUT_DIR/raw_config/libvirt/vms"

    mkdir -p "$target_dir"
    while IFS= read -r vm; do
        [ -n "$vm" ] || continue
        safe_name="$(printf '%s' "$vm" | tr -c '[:alnum:]_.-' '_')"
        virsh dumpxml "$vm" >"$target_dir/${safe_name}.xml" 2>"$target_dir/${safe_name}.xml.error.txt" || true
    done < <(virsh list --all --name 2>/dev/null)
}

vm_pci_devices() {
    local vm

    while IFS= read -r vm; do
        [ -n "$vm" ] || continue
        echo "===== $vm ====="
        virsh dumpxml "$vm" 2>/dev/null | grep -A15 -B5 -E "<hostdev|<address type=.pci" || true
        echo
    done < <(virsh list --all --name 2>/dev/null)
}

collect_gpu_info() {
    capture_cmd "$OUTPUT_DIR/gpu/pci_all.txt" "ALL PCI DEVICES" lspci -nn
    capture_cmd "$OUTPUT_DIR/gpu/pci_all_drivers.txt" "ALL PCI DEVICES AND DRIVERS" lspci -nnk
    capture_shell "$OUTPUT_DIR/gpu/pci_gpu.txt" "GPU PCI DEVICES" "lspci -nn | grep -Ei '$GPU_PATTERN' || true"
    capture_shell "$OUTPUT_DIR/gpu/pci_gpu_drivers.txt" "GPU PCI DEVICES AND DRIVERS" "lspci -nnk | grep -A4 -B2 -Ei '$GPU_PATTERN' || true"
    capture_function "$OUTPUT_DIR/gpu/pci_addresses.txt" "GPU PCI ADDRESSES" gpu_pci_addresses
    capture_shell "$OUTPUT_DIR/gpu/nvidia_smi.txt" "NVIDIA SMI" 'nvidia-smi 2>&1'
    capture_shell "$OUTPUT_DIR/gpu/iommu_groups.txt" "IOMMU GROUPS" "find /sys/kernel/iommu_groups/ -type l -printf '%p -> %l\n' 2>/dev/null | sort"
    capture_function "$OUTPUT_DIR/gpu/gpu_iommu_groups.txt" "GPU IOMMU GROUPS" gpu_iommu_groups
    capture_function "$OUTPUT_DIR/gpu/gpu_drivers.txt" "GPU DRIVER BINDINGS" gpu_driver_bindings
    capture_shell "$OUTPUT_DIR/gpu/vfio_modules.txt" "VFIO MODULES" 'lsmod | grep -E "vfio|iommu" || true; echo; modinfo vfio-pci 2>&1'
    capture_shell "$OUTPUT_DIR/gpu/vfio_config.txt" "VFIO CONFIG" "grep -RniE '$VFIO_PATTERN' /etc/modprobe.d /etc/dracut.conf.d /etc/default/grub /etc/kernel/cmdline 2>/dev/null || true"
}

collect_custom_gpu_vfio_info() {
    capture_function "$OUTPUT_DIR/custom/gpu_vfio_custom_summary.txt" "GPU VFIO CUSTOM SUMMARY" gpu_vfio_custom_summary
    capture_function "$OUTPUT_DIR/custom/gpu_vfio_config_files_redacted.txt" "GPU VFIO CONFIG FILE CONTENTS REDACTED" gpu_vfio_config_files_redacted
    capture_function "$OUTPUT_DIR/custom/libvirt_hooks.txt" "LIBVIRT HOOKS" libvirt_hooks_redacted
    capture_function "$OUTPUT_DIR/custom/systemd_overrides.txt" "SYSTEMD OVERRIDES AND DROP-INS" systemd_overrides_redacted
    capture_function "$OUTPUT_DIR/custom/initramfs_vfio_contents.txt" "INITRAMFS VFIO CONTENTS" initramfs_vfio_contents
}

collect_storage_info() {
    capture_cmd "$OUTPUT_DIR/storage/lsblk.txt" "BLOCK DEVICES" lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINTS,UUID,MODEL,SERIAL
    capture_cmd "$OUTPUT_DIR/storage/filesystems.txt" "FILESYSTEMS" df -hT
    capture_cmd "$OUTPUT_DIR/storage/mounts.txt" "MOUNTS" findmnt
    capture_shell "$OUTPUT_DIR/storage/lvm.txt" "LVM" 'pvs 2>/dev/null; echo; vgs 2>/dev/null; echo; lvs -a -o +devices 2>/dev/null'
    capture_function "$OUTPUT_DIR/storage/smart.txt" "SMART SUMMARY" smart_summary
}

collect_network_info() {
    capture_cmd "$OUTPUT_DIR/network/ip_addr.txt" "IP ADDRESSES" ip -br addr
    capture_cmd "$OUTPUT_DIR/network/ip_link.txt" "LINKS" ip -br link
    capture_cmd "$OUTPUT_DIR/network/routes_v4.txt" "IPV4 ROUTES" ip route
    capture_cmd "$OUTPUT_DIR/network/routes_v6.txt" "IPV6 ROUTES" ip -6 route
    capture_shell "$OUTPUT_DIR/network/nmcli.txt" "NETWORKMANAGER" 'nmcli connection show 2>&1; echo; nmcli device status 2>&1'
    capture_shell "$OUTPUT_DIR/network/listening_ports.txt" "LISTENING PORTS" 'ss -tulpen 2>&1'
    capture_function "$OUTPUT_DIR/network/redacted_connections.txt" "REDACTED NETWORKMANAGER CONNECTIONS" networkmanager_connections_redacted
}

collect_virtualization_info() {
    capture_shell "$OUTPUT_DIR/virtualization/libvirt.txt" "LIBVIRT" 'virsh version 2>&1; echo; virsh list --all 2>&1; echo; virsh net-list --all 2>&1; echo; virsh pool-list --all 2>&1'
    capture_shell "$OUTPUT_DIR/virtualization/libvirtd_status.txt" "LIBVIRTD STATUS" 'systemctl status libvirtd --no-pager 2>&1'
    capture_shell "$OUTPUT_DIR/virtualization/vfio_related_units.txt" "VFIO QEMU LIBVIRT UNITS" 'systemctl list-unit-files 2>&1 | grep -Ei "vfio|qemu|libvirt" || true'
    capture_function "$OUTPUT_DIR/virtualization/vm_xml_redacted.txt" "VM XML REDACTED" vm_xml_redacted
    capture_function "$OUTPUT_DIR/virtualization/vm_xml_raw_files.txt" "VM XML RAW FILES" vm_xml_raw_files
    capture_function "$OUTPUT_DIR/virtualization/vm_pci_devices.txt" "VM PCI DEVICES" vm_pci_devices
    capture_shell "$OUTPUT_DIR/virtualization/qemu.txt" "QEMU PACKAGES" 'qemu-system-x86_64 --version 2>&1; echo; rpm -qa | grep -Ei "qemu|libvirt|virt-install|edk2|ovmf" | sort'
    capture_shell "$OUTPUT_DIR/virtualization/disk_files.txt" "VM DISK FILES" "find /var/lib/libvirt/images /var/lib/libvirt -type f \( -name '*.qcow2' -o -name '*.qcow' -o -name '*.raw' -o -name '*.img' \) -printf '%p %s bytes\n' 2>/dev/null"
}

collect_security_info() {
    capture_shell "$OUTPUT_DIR/security/firewall.txt" "FIREWALL" 'firewall-cmd --list-all 2>&1; echo; firewall-cmd --list-all-zones 2>&1'
    capture_shell "$OUTPUT_DIR/security/selinux.txt" "SELINUX" 'getenforce 2>&1; echo; sestatus 2>&1'
    capture_shell "$OUTPUT_DIR/security/users_groups.txt" "USERS AND GROUPS" 'getent passwd; echo; getent group'
    capture_function "$OUTPUT_DIR/security/sudoers_redacted.txt" "SUDOERS" grep_files_redacted /etc/sudoers '.*' -maxdepth 1
}

collect_services_info() {
    capture_shell "$OUTPUT_DIR/services/enabled_services.txt" "ENABLED SERVICES" 'systemctl list-unit-files --state=enabled 2>&1'
    capture_shell "$OUTPUT_DIR/services/running_services.txt" "RUNNING SERVICES" 'systemctl --type=service --state=running --no-pager 2>&1'
    capture_function "$OUTPUT_DIR/services/custom_systemd.txt" "CUSTOM SYSTEMD UNITS" grep_files_redacted /etc/systemd/system '.*' -maxdepth 2
    capture_shell "$OUTPUT_DIR/services/cron.txt" "CRON" 'crontab -l 2>&1; echo; find /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly -maxdepth 1 -type f -print 2>/dev/null'
}

collect_packages_info() {
    capture_cmd "$OUTPUT_DIR/packages/repos.txt" "DNF REPOSITORIES" dnf repolist
    capture_function "$OUTPUT_DIR/packages/repo_files_redacted.txt" "DNF REPOSITORY FILES REDACTED" repo_files_redacted
    capture_shell "$OUTPUT_DIR/packages/modules.txt" "DNF MODULES" 'dnf module list 2>/dev/null'
    capture_shell "$OUTPUT_DIR/packages/rpm_packages.txt" "INSTALLED PACKAGES" 'rpm -qa | sort'
}

collect_containers_info() {
    capture_shell "$OUTPUT_DIR/containers/podman.txt" "PODMAN" 'podman info 2>&1; echo; podman ps -a 2>&1; echo; podman network ls 2>&1; echo; podman volume ls 2>&1'
    capture_shell "$OUTPUT_DIR/containers/docker.txt" "DOCKER" 'docker info 2>&1; echo; docker ps -a 2>&1; echo; docker network ls 2>&1; echo; docker volume ls 2>&1'
}

collect_logs_info() {
    capture_shell "$OUTPUT_DIR/logs/boot_errors.txt" "BOOT ERRORS" 'journalctl -b -p warning..alert --no-pager 2>&1'
    capture_shell "$OUTPUT_DIR/logs/kernel_recent.txt" "KERNEL LOG RECENT" 'journalctl -k -b --no-pager 2>&1 | tail -n 500'
}

main() {
    parse_args "$@"
    require_root
    prepare_output_dir
    write_manifest_start

    collect_system_info
    collect_kernel_info
    collect_cpu_info
    collect_gpu_info
    collect_custom_gpu_vfio_info
    collect_storage_info
    collect_network_info
    collect_virtualization_info
    collect_security_info
    collect_services_info
    collect_packages_info
    collect_containers_info
    collect_logs_info
    run_common_post_collection_copies

    write_manifest_finish
    echo "$OUTPUT_DIR"
}

main "$@"
