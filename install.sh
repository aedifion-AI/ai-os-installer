#!/usr/bin/env bash
# aedifion AI-OS — All-in-one installer (macOS / Linux)
#
# Hosted publicly at: https://github.com/aedifion-AI/ai-os-installer
# Mirror in private:  aedifion-AI/aedifion-AI-OS/installer/install.sh
#
# Run on a fresh laptop:
#   bash <(curl -fsSL https://raw.githubusercontent.com/aedifion-AI/ai-os-installer/main/install.sh)
#
# This installer:
#   1. Installs Xcode Command Line Tools (macOS only)
#   2. Installs Homebrew (macOS only)
#   3. Installs git, python3, gh (GitHub CLI) via brew
#   4. Installs VS Code via brew cask
#   5. Installs the Claude Code extension
#   6. Logs you into GitHub (browser opens)
#   7. Clones the private aedifion-AI-OS repo and opens VS Code
#
# Idempotent: re-running is safe. Anything already installed is skipped.
# Pass --yes to auto-accept all prompts.

set -euo pipefail

WORKSPACE_DEFAULT="${HOME}/aedifion-ai-os"
WORKSPACE="${WORKSPACE_PATH:-}"
PRIVATE_REPO="aedifion-AI/aedifion-AI-OS"

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

═══════════════════════════════════════════════════════════
   aedifion AI-OS — Installer
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

🔐 You will be asked for your Mac login password during Homebrew install.
   macOS does NOT show characters or asterisks while you type — that is normal.
   Type your Mac password blindly and press Enter.

EOF

if [ "$YES" != "1" ]; then
  echo "Press Enter to continue, Ctrl+C to abort..."
  read -r _
fi

# ─── 1. Xcode CLT ────────────────────────────────────────
step "1/7  Xcode Command Line Tools"
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
step "2/7  Homebrew"
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
step "3/7  CLI tools (git, python3, gh)"
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
step "4/7  VS Code"
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
step "5/7  Claude Code extension"
if code --list-extensions 2>/dev/null | grep -q "anthropic.claude-code"; then
  ok "already installed"
else
  info "installing Claude Code extension ..."
  code --install-extension anthropic.claude-code
fi

# ─── 6. GitHub auth ──────────────────────────────────────
step "6/7  GitHub login"
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
step "7/7  Workspace"

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

cat <<EOF

═══════════════════════════════════════════════════════════
  ✓ Installation complete.

  Next step — inside VS Code:
    1. Open the Claude Code sidebar
    2. Type:  /onboard

═══════════════════════════════════════════════════════════
EOF
