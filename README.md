# aedifion AI-OS Installer

Public bootstrap installer for the **aedifion AI Operations System**. This repository hosts only the entry-point installer script — the actual AI-OS is in the private repo `aedifion-AI/aedifion-AI-OS`.

## Quick start (macOS, ~10 min)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/aedifion-AI/ai-os-installer/main/install.sh)
```

The installer is idempotent — re-running is safe. Pass `--yes` to auto-accept all prompts.

## What it does

1. Installs Xcode Command Line Tools (if missing)
2. Installs Homebrew (if missing)
3. Installs CLI tools via brew: `git`, `python3`, `gh` (GitHub CLI)
4. Installs VS Code via brew cask
5. Installs the Claude Code extension
6. Logs you into GitHub via `gh auth login` (browser opens)
7. Clones `aedifion-AI/aedifion-AI-OS` to `~/aedifion-ai-os/` (or `$WORKSPACE_PATH`) and opens VS Code

## Requirements

- Member of the `aedifion-AI` GitHub organisation (you need read access to the private `aedifion-AI-OS` repo).
- macOS x64 / arm64. Linux currently prints manual instructions; Windows installer is on the roadmap.

## After install

Inside VS Code, open the Claude Code sidebar and type:

```
/onboard
```

This finishes the workspace setup (profile, plugin install, integration tokens, compliance hooks, smoke test).

## Source

`install.sh` is mirrored from the private repo at `aedifion-AI/aedifion-AI-OS/installer/install.sh`. The canonical source is the private repo; this public copy is what `curl | bash` pulls.
