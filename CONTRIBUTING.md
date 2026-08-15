# Contributing

This repository contains small Bash shell scripts used to collect system information from Rocky Linux 9 servers before a Red Hat reinstall.

Please follow these lightweight rules:

- Linting: use ShellCheck for all scripts. Fix warnings before committing.

  Commands:

```bash
# check a single script
shellcheck script.sh

# run shellcheck across repository (bash / WSL / Git Bash)
find . -type f -name "*.sh" -print0 | xargs -0 shellcheck
```

- Naming: prefer snake_case for filenames and script-level identifiers. Examples: `collect_info.sh`, `gather_network_info.sh`.

- Shebang: use a portable bash shebang at the top of executable scripts:

```bash
#!/usr/bin/env bash
```

- No CI: do not add GitHub Actions, CI workflows, or other automated testing to this repository without explicit approval from the repo owner.

- Editing policy: do NOT delete files automatically. If you propose removals, explain why and request confirmation.

If you'd like, I can add a `.shellcheckrc` template to document any allowed exceptions.
