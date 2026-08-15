# Roadmap

Ideas to improve `scripts/collect-info.sh` after the initial root-level collection cleanup.

## Safety and Permissions

- Keep `umask 077` so collected files are private by default.
- Add collision protection for run directories. The current run ID uses hostname plus a timestamp; add a PID/random suffix or fail if the target output directory already exists.
- Add an explicit warning in the manifest that `raw_config/` may contain secrets and should not be shared without review.
- Consider creating a compressed archive with restrictive permissions once collection finishes.

## Completeness

- Add a command availability report for tools such as `lspci`, `virsh`, `smartctl`, `lsinitrd`, `nmcli`, `podman`, `docker`, `numactl`, and `lstopo-no-graphics`.
- Add a manifest section listing each output file and the command exit status that produced it.
- Add collection for relevant bootloader paths beyond `/etc/default/grub` where applicable.
- Capture package repository configuration files in addition to `dnf repolist`.

## Redaction and Review

- Broaden redaction patterns to handle `key: value`, quoted values, JSON/YAML-style secrets, private keys, certificates, tokens, and identity fields.
- Produce redacted VM XML by default, with raw VM XML clearly separated in `raw_config/`.
- Review broad searches under `/root`, `/usr/local/bin`, and `/usr/local/sbin` so useful VFIO/GPU hints are captured without dumping unrelated secrets.
- Add a final "review before sharing" checklist in the manifest.

## Maintainability

- Prefer small collection functions plus `capture_function` over large string snippets passed to `capture_shell`.
- Reduce duplicated GPU/VFIO grep patterns by centralizing search paths and patterns.
- Add short comments only where collection behavior is non-obvious.
- Keep ShellCheck clean after every script change.

## Verification

- Continue checking with `shellcheck scripts/collect-info.sh`.
- Also run `bash -n scripts/collect-info.sh` after edits.
- Test on a Rocky/RHEL host as root and confirm the expected topic directories and `raw_config/` are created.

### edits by agent - 2026-08-15

Implemented in `scripts/collect-info.sh`:

- Collision-resistant run IDs and output-directory collision failure.
- Manifest warning for `raw_config/`, command status table, and review-before-sharing checklist.
- Command availability report for key collection tools.
- Broader redaction helper covering `key: value`, quoted values, JSON/YAML-style secret fields, private keys, certificates, tokens, credentials, and identity fields.
- Redacted VM XML output by default, with raw per-VM XML written under `raw_config/libvirt/vms`.
- Additional bootloader and package repository configuration capture.
