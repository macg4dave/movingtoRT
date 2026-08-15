# movingtoRT

Rough host information collectors for Rocky Linux 9 / RHEL reinstall planning.

The main script is [scripts/collect_info.sh](scripts/collect_info.sh). It writes a timestamped folder under `collected-info/` with nested topic folders:

- `system/` - OS, date, hostname, release details
- `kernel/` - kernel version, command line, modules, IOMMU settings, dracut, initramfs, GRUB notes
- `cpu/` - CPU and topology
- `gpu/` - full PCI inventory, GPU PCI addresses, NVIDIA details, IOMMU groups, driver bindings, VFIO config
- `storage/` - disks, filesystems, mounts, LVM, SMART summary
- `network/` - addresses, routes, NetworkManager summary, listening ports
- `virtualization/` - libvirt, QEMU, VM XML, VM PCI passthrough snippets, VM disk files
- `security/` - firewall, SELinux, users/groups, sudoers summary
- `services/` - enabled/running services, custom units, cron
- `packages/` - DNF repos/modules and RPM package list
- `containers/` - Podman and Docker state
- `logs/` - recent boot/kernel warnings
- `custom/` - targeted searches for GPU/VFIO passthrough customisations

## Run

```bash
chmod +x scripts/collect_info.sh
sudo scripts/collect_info.sh
```

Use a custom output directory:

```bash
sudo scripts/collect_info.sh --output /root/reinstall-info
```

Include raw config copies that may contain secrets:

```bash
sudo scripts/collect_info.sh --include-sensitive
```

By default, the script tries to redact obvious passwords, PSKs, keys, tokens, and secrets from text output. Still review files before sharing them.

## GPU/VFIO Notes

For passthrough rebuild notes, start with:

- `custom/gpu_vfio_custom_summary.txt`
- `custom/gpu_vfio_config_files_redacted.txt`
- `custom/libvirt_hooks.txt`
- `custom/systemd_overrides.txt`
- `custom/initramfs_vfio_contents.txt`
- `gpu/gpu_drivers.txt`
- `gpu/gpu_iommu_groups.txt`
- `gpu/vfio_config.txt`
- `kernel/grub.txt`
- `kernel/dracut.txt`
- `virtualization/vm_pci_devices.txt`

## Verify

```bash
bash -n scripts/collect_info.sh
shellcheck scripts/collect_info.sh
```

There is intentionally no CI in this repository.
