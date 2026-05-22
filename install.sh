#!/usr/bin/env bash
# aedifion AI-OS — All-in-one installer (macOS / Linux)
#
# Canonical location: aedifion-AI/aedifion-AI-OS/installer/install.sh (private)
# Public mirror:      aedifion-AI/ai-os-installer (sync target — kept in lockstep)
#
# Distribution paths:
#   1. Fresh laptop (recommended): one-liner against the public mirror —
#        bash <(curl -fsSL https://raw.githubusercontent.com/aedifion-AI/ai-os-installer/main/install.sh)
#   2. Browser download from the Hauptrepo (org members only) —
#        https://github.com/aedifion-AI/aedifion-AI-OS/raw/main/installer/install.sh
#        then locally:  bash ~/Downloads/install.sh
#
# Access control: the Hauptrepo is private. Step 7 (`gh repo clone`) is the
# auth gate — non-members hit `permission denied` and the script stops.
#
# This installer:
#   1. Installs Xcode Command Line Tools (macOS only)
#   2. Installs Homebrew (macOS only)
#   3. Installs git, python3, gh (GitHub CLI) via brew
#   4. Installs VS Code via brew cask
#   5. Installs the Claude Code extension
#   6. Logs you into GitHub (browser opens)
#   7. Clones the private aedifion-AI-OS repo and opens VS Code
#   8. If a Cockpit-style workspace exists at $HOME/AI-OS (or $COCKPIT_PATH),
#      backs it up and migrates personal skills, agents, projects, memory,
#      .env, MCP, settings into the new Foundation workspace.
#
# Idempotent: re-running is safe. Anything already installed is skipped.
# Step 8 is also idempotent: if the Foundation already has personal content
# (.claude/skills/*-priv/ or personal-*/) the migration is skipped.
#
# Pass --yes to auto-accept all prompts.

set -euo pipefail

WORKSPACE_DEFAULT="${HOME}/aedifion-ai-os"
WORKSPACE="${WORKSPACE_PATH:-}"
PRIVATE_REPO="aedifion-AI/aedifion-AI-OS"
COCKPIT_DEFAULT="${HOME}/AI-OS"
COCKPIT="${COCKPIT_PATH:-$COCKPIT_DEFAULT}"

YES=0
[ "${1:-}" = "--yes" ] && YES=1

step()  { echo ""; echo "▶ $1"; }
ok()    { echo "  ✓ $1"; }
info()  { echo "  → $1"; }
warn()  { echo "  ⚠ $1"; }
abort() { echo "✗ $1" >&2; exit 1; }
ask()   {
  if [ "$YES" = "1" ]; then return 0; fi
  echo "  → $1 [Y/n]"
  read -r ans
  case "${ans:-y}" in y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac
}

# ─── 0. OS check ─────────────────────────────────────────
case "$(uname -s)" in
  Darwin) OS="macos" ;;
  Linux)  OS="linux" ;;
  *) abort "Unsupported platform. Use install.ps1 on Windows." ;;
esac

if [ "$OS" = "linux" ]; then
  cat <<'EOF'
Linux is not yet auto-supported. Install manually:
  - git ≥ 2.30, python3 ≥ 3.11, VS Code, Claude Code extension, gh CLI
  - gh auth login
  - gh repo clone aedifion-AI/aedifion-AI-OS ~/aedifion-ai-os
  - code ~/aedifion-ai-os, then /onboard
EOF
  exit 0
fi

cat <<'EOF'

 █████╗ ███████╗██████╗ ██╗███████╗██╗ ██████╗ ███╗   ██╗     █████╗ ██╗       ██████╗ ███████╗
██╔══██╗██╔════╝██╔══██╗██║██╔════╝██║██╔═══██╗████╗  ██║    ██╔══██╗██║      ██╔═══██╗██╔════╝
███████║█████╗  ██║  ██║██║█████╗  ██║██║   ██║██╔██╗ ██║    ███████║██║█████╗██║   ██║███████╗
██╔══██║██╔══╝  ██║  ██║██║██╔══╝  ██║██║   ██║██║╚██╗██║    ██╔══██║██║╚════╝██║   ██║╚════██║
██║  ██║███████╗██████╔╝██║██║     ██║╚██████╔╝██║ ╚████║    ██║  ██║██║      ╚██████╔╝███████║
╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝    ╚═╝  ╚═╝╚═╝       ╚═════╝ ╚══════╝

═══════════════════════════════════════════════════════════
   Installer
═══════════════════════════════════════════════════════════

This will set up the aedifion AI Operations System on your Mac.
Expected time: 5–10 minutes.

Steps:
  1. Xcode Command Line Tools (if missing)
  2. Homebrew (if missing)
  3. CLI tools: git, python3, GitHub CLI (gh)
  4. VS Code
  5. Claude Code extension
  6. GitHub login (browser opens)
  7. Clone the AI-OS repo and open VS Code
  8. Migrate from Cockpit (only if a Cockpit-style workspace is found)

🔐 You will be asked for your Mac login password during Homebrew install.
   macOS does NOT show characters or asterisks while you type — that is normal.
   Type your Mac password blindly and press Enter.

EOF

if [ "$YES" != "1" ]; then
  echo "Press Enter to continue, Ctrl+C to abort..."
  read -r _
fi

# ─── 1. Xcode CLT ────────────────────────────────────────
step "1/8  Xcode Command Line Tools"
if xcode-select -p >/dev/null 2>&1; then
  ok "already installed"
else
  if ask "Install Xcode Command Line Tools? (opens a system dialog)"; then
    xcode-select --install
    info "Wait for the system dialog to finish, then re-run this installer."
    exit 0
  fi
fi

# ─── 2. Homebrew ─────────────────────────────────────────
step "2/8  Homebrew"
if command -v brew >/dev/null 2>&1; then
  ok "already installed"
else
  cat <<'PWHINT'

  🔐 The Homebrew installer will ask for your Mac password.
     No characters will appear while you type — type it blindly and press Enter.

PWHINT
  if ask "Install Homebrew?"; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    abort "Homebrew is required."
  fi
fi

# Make brew available in this shell (Apple Silicon vs Intel)
if [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"
fi

# ─── 3. CLI tools ─────────────────────────────────────────
step "3/8  CLI tools (git, python3, gh)"
brew_install() {
  local pkg="$1"
  if brew list "$pkg" >/dev/null 2>&1; then
    ok "$pkg already installed"
  else
    info "installing $pkg ..."
    brew install "$pkg"
  fi
}
brew_install git
brew_install python@3.12
brew_install gh

# ─── 4. VS Code ──────────────────────────────────────────
step "4/8  VS Code"
if command -v code >/dev/null 2>&1; then
  ok "'code' CLI already in PATH"
elif [ -d "/Applications/Visual Studio Code.app" ]; then
  warn "VS Code is installed but 'code' CLI is not in PATH"
  cat <<'EOF'

  Manual step needed:
    1. Switch to VS Code
    2. Open Command Palette: ⇧⌘P
    3. Type and run: 'Shell Command: Install code command in PATH'
    4. Re-run this installer.

EOF
  exit 0
else
  if brew list --cask visual-studio-code >/dev/null 2>&1; then
    ok "already installed"
  else
    info "installing VS Code ..."
    brew install --cask visual-studio-code
  fi
  info "opening VS Code once so it can register the 'code' CLI ..."
  open -a "Visual Studio Code"
  sleep 3
  if ! command -v code >/dev/null 2>&1; then
    cat <<'EOF'

  ⚠ 'code' CLI is not yet in PATH. Manual step:
    1. Switch to VS Code (just opened)
    2. Open Command Palette: ⇧⌘P
    3. Type and run: 'Shell Command: Install code command in PATH'
    4. Re-run this installer.

EOF
    exit 0
  fi
fi

# ─── 5. Claude Code extension ────────────────────────────
step "5/8  Claude Code extension"
if code --list-extensions 2>/dev/null | grep -q "anthropic.claude-code"; then
  ok "already installed"
else
  info "installing Claude Code extension ..."
  code --install-extension anthropic.claude-code
fi

# ─── 6. GitHub auth ──────────────────────────────────────
step "6/8  GitHub login"
if gh auth status >/dev/null 2>&1; then
  ok "already logged in to GitHub"
else
  cat <<'EOF'

  A browser window will open for GitHub login.
  Use the GitHub account that has access to the aedifion-AI organisation.
  After authorising, return to this terminal.

EOF
  gh auth login --hostname github.com --git-protocol https --web
fi

# ─── 7. Clone + open VS Code ─────────────────────────────
step "7/8  Workspace"

if [ -z "$WORKSPACE" ]; then
  WORKSPACE="$WORKSPACE_DEFAULT"
fi

# Validate path: no spaces, no special characters
echo "$WORKSPACE" | grep -qE '^[A-Za-z0-9/_.~-]+$' \
  || abort "Path contains spaces or special characters: $WORKSPACE"

if [ -d "$WORKSPACE" ]; then
  warn "$WORKSPACE already exists — skipping clone."
  info "If you want a clean install, remove or rename the existing folder, then re-run."
else
  info "cloning $PRIVATE_REPO into $WORKSPACE ..."
  gh repo clone "$PRIVATE_REPO" "$WORKSPACE" || abort "Clone failed."
fi

info "opening VS Code at $WORKSPACE ..."
code "$WORKSPACE" 2>/dev/null \
  || warn "'code' command failed. Open VS Code → File → Open Folder → $WORKSPACE"

# ─── 8. Cockpit auto-migration ───────────────────────────
step "8/8  Cockpit auto-migration"

# Idempotency: if Foundation already has any personal skills/agents migrated,
# skip — don't re-run migration over existing personal content.
foundation_has_personal_content() {
  local p="$1"
  shopt -s nullglob 2>/dev/null || true
  local matches=( "$p"/.claude/skills/*-priv "$p"/.claude/skills/personal-* \
                  "$p"/.claude/agents/*-priv.md "$p"/.claude/agents/personal-*.md )
  [ "${#matches[@]}" -gt 0 ]
}

# Cockpit detection: directory exists AND at least 2 of 4 Cockpit-style markers.
is_cockpit_workspace() {
  local p="$1"
  [ -d "$p" ] || return 1
  local signals=0
  [ -f "$p/CLAUDE.md" ]   && signals=$((signals+1))
  [ -d "$p/01-memory" ]   && signals=$((signals+1))
  [ -d "$p/02-projects" ] && signals=$((signals+1))
  [ -d "$p/03-skills" ]   && signals=$((signals+1))
  [ "$signals" -ge 2 ]
}

if foundation_has_personal_content "$WORKSPACE"; then
  ok "Foundation already has personal content — skipping migration (idempotent)."
elif [ "$COCKPIT" = "$WORKSPACE" ]; then
  info "Cockpit path equals Foundation path — skipping."
elif is_cockpit_workspace "$COCKPIT"; then
  info "Cockpit-style workspace detected at $COCKPIT"
  info "Migration will: 1) back up Cockpit  2) copy skills/agents/projects/memory/.env/MCP/settings"
  if ask "Run migration now?"; then
    MIGRATE_SCRIPT="$WORKSPACE/installer/migrate-cockpit.sh"
    if [ -x "$MIGRATE_SCRIPT" ]; then
      bash "$MIGRATE_SCRIPT" --yes --cockpit "$COCKPIT" --foundation "$WORKSPACE" \
        || warn "Migration script returned non-zero — review output above. Cockpit and backup are untouched."
    else
      warn "Migration script not found or not executable: $MIGRATE_SCRIPT"
    fi
  else
    info "Skipped. Run later with: bash $WORKSPACE/installer/migrate-cockpit.sh"
  fi
else
  info "No Cockpit-style workspace at $COCKPIT — nothing to migrate."
fi

cat <<EOF

═══════════════════════════════════════════════════════════
  ✓ Installation complete.

  Next step — inside VS Code:
    1. Open the Claude Code sidebar
    2. Type:  /onboard

═══════════════════════════════════════════════════════════
EOF
