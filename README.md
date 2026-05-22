# aedifion AI-OS Installer

Public bootstrap installer for the **aedifion AI Operations System**. This repository hosts only the entry-point installer script — the actual AI-OS lives in the private repo `aedifion-AI/aedifion-AI-OS`. Access is gated at runtime by GitHub: if your account is not a member of the `aedifion-AI` organisation, the script stops at the clone step.

## Quick start

**macOS — one line in Terminal:**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/aedifion-AI/ai-os-installer/main/install.sh)
```

**Windows — one line in PowerShell** (works in the default Windows PowerShell 5.1 and in PowerShell 7+):

```powershell
iex "& { $(irm https://raw.githubusercontent.com/aedifion-AI/ai-os-installer/main/install.ps1) }"
```

> Paste as a **single line**. If you copied it from a message that ended with a comma, drop the trailing `,` — PowerShell treats `,` as the array operator and will wait for another expression.

The installer is idempotent — re-running is safe. Pass `--yes` (or `-Yes` on Windows) to auto-accept all prompts.

## What it does

1. Installs Xcode Command Line Tools (if missing)
2. Installs Homebrew (if missing)
3. Installs CLI tools via brew: `git`, `python3`, `gh` (GitHub CLI)
4. Installs VS Code via brew cask
5. Installs the Claude Code extension
6. Logs you into GitHub via `gh auth login` (browser opens)
7. Clones `aedifion-AI/aedifion-AI-OS` to `~/aedifion-ai-os/` (or `$WORKSPACE_PATH`) and opens VS Code
8. If a Cockpit-style workspace exists at `$HOME/AI-OS` (or `$COCKPIT_PATH`), backs it up to `~/cockpit-backup-YYYY-MM-DD-HHMMSS.tar.gz` and migrates personal skills, agents, projects, memory, `.env`, MCP, and settings into the new Foundation workspace. Idempotent: skipped if no Cockpit is found or if the Foundation already has personal content.

## Requirements

- Member of the `aedifion-AI` GitHub organisation (you need read access to the private `aedifion-AI-OS` repo). Without that access, step 7 will fail with `permission denied` and the install stops there.
- macOS x64 / arm64 — uses `install.sh`.
- Windows 10/11 with PowerShell 5.1+ — uses `install.ps1`. The default `powershell.exe` is fine; PowerShell 7 (`pwsh`) is not required.
- Linux — currently prints manual instructions.

## After install

Inside VS Code, open the Claude Code sidebar and type:

```
/onboard
```

This finishes the workspace setup (profile, plugin install, integration tokens, compliance hooks, smoke test).

## Source

`install.sh` and `install.ps1` mirror `aedifion-AI/aedifion-AI-OS/installer/`. The canonical source is the Hauptrepo; this public copy is what `curl | bash` and `iex | irm` pull. Updates to the Hauptrepo's installers must be synced here.
