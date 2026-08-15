# AI agent instructions for this repository

Purpose: help AI coding agents understand what's in this workspace and how to act safely and effectively.

Summary

- This repository holds small Bash scripts used to collect system information from Rocky Linux 9 servers before a Red Hat reinstall. All scripts are in the `scripts/` folder.
- Main language: Bash. Agents should treat files as shell scripts by default.
- Preferred workflow: make small, incremental Bash changes that keep the script working, then validate them before making broader changes. I prefer smaller fixes over large, untested rewrites.
- Naming convention: prefer snake_case for filenames and script-level identifiers to remain human-readable (e.g., `collect_info.sh`, `gather_network_info.sh`).
- `roadmap.md` is a living planning document. Agents should use it as the guide for future improvements, update it when priorities or ideas change, and keep it aligned with completed work.
- There is intentionally no CI or automated GitHub testing in this repo — do not create CI workflows, GitHub Actions, or other remote testing automation unless explicitly requested by the repo owner.

Linting and checks

- Standard: run ShellCheck only when Bash/shell scripts are edited. Prefer fixing ShellCheck warnings (SCxxxx) before committing script changes.
- Example local check command for an edited Bash script:

```bash
# single script
shellcheck script.sh
```

- If broader Bash changes touch multiple scripts, ShellCheck each edited script. Do not run ShellCheck for documentation-only changes.
- If you want, I can add a suggested `.shellcheckrc` file with preferred disables/level settings — ask before adding.

Key files

- `scripts/collect-info.sh` — the active information-gathering script in this repo.
- `roadmap.md` — living guide for planned improvements and follow-up work.
- Any additional helper scripts or notes should live under `scripts/` and be kept small and focused.

Agent behavior guidelines (concise & actionable)

- Do NOT delete or remove files automatically. The repository owner prefers manual deletions; ask before removing anything.
- Prefer smaller, validated Bash edits over large, sweeping changes. If a fix works and is scoped, keep it small and confirm it before broadening scope.
- Preserve original file content when updating: prefer appending a clearly labeled section such as "### edits by agent — YYYY-MM-DD" rather than rewriting files in-place.
- Follow the ShellCheck standard only for edited Bash scripts: run ShellCheck locally and include the exact command you used in the commit message or PR description.
- Do NOT add CI/automation for testing on GitHub or elsewhere unless the owner explicitly requests it.
- If you need to run scripts or destructive commands, ask the user for approval first. Avoid running remote or privileged commands.
- When proposing changes, include a short rationale and a one-line verification step the user can run locally (e.g., `shellcheck myscript.sh` or `bash -n myscript.sh`).

When to create additional customization files

- If the workspace later includes more scripts or a tooling matrix, consider adding a small `CONTRIBUTING.md` or `.shellcheckrc` that documents how to run ShellCheck and any repo-specific exceptions.

Files added/modified by agents in this session

- `AGENTS.md` — this file: concise guidance for AI agents and repo-specific Bash workflow preferences.

Questions for the repo owner

- None at the moment; keep changes small, focused, and validated before broadening scope.

Next steps I can take (pick one):

- Create an optional `.shellcheckrc` with suggested rules.
- Add a short `CONTRIBUTING.md` describing how to run ShellCheck locally and the repo's no-CI policy.
- Leave as-is (no further files).

