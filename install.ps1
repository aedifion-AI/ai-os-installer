# aedifion AI-OS — All-in-one installer (Windows PowerShell 7+)
#
# Canonical location: aedifion-AI/aedifion-AI-OS/installer/install.ps1 (private)
# Public mirror:      aedifion-AI/ai-os-installer (sync target — kept in lockstep)
#
# Distribution paths:
#   1. Fresh laptop (recommended): one-liner against the public mirror —
#        iex "& { $(irm https://raw.githubusercontent.com/aedifion-AI/ai-os-installer/main/install.ps1) }"
#   2. Browser download from the Hauptrepo (org members only) —
#        https://github.com/aedifion-AI/aedifion-AI-OS/raw/main/installer/install.ps1
#        then locally:  pwsh ~/Downloads/install.ps1
#
# Access control: the Hauptrepo is private. Step 7 (`gh repo clone`) is the
# auth gate — non-members hit `permission denied` and the script stops.
#
# This installer:
#   1. Installs git via winget
#   2. Installs python3 via winget
#   3. Installs GitHub CLI (gh) via winget
#   4. Installs VS Code via winget
#   5. Installs the Claude Code extension
#   6. Logs you into GitHub (browser opens)
#   7. Clones the private aedifion-AI-OS repo and opens VS Code
#   8. If a Cockpit-style workspace exists at $HOME/AI-OS (or $env:COCKPIT_PATH),
#      backs it up and migrates personal skills, agents, projects, memory,
#      .env, MCP, settings into the new Foundation workspace.
#
# Idempotent: re-running is safe. Anything already installed is skipped.
# Step 8 is also idempotent: if the Foundation already has personal content
# (.claude/skills/*-priv/ or personal-*/) the migration is skipped.
#
# Pass -Yes to auto-accept all prompts.

param([switch]$Yes)

$ErrorActionPreference = "Stop"

$WorkspaceDefault = Join-Path $HOME "aedifion-ai-os"
$Workspace = $env:WORKSPACE_PATH
$PrivateRepo = "aedifion-AI/aedifion-AI-OS"
$CockpitDefault = Join-Path $HOME "AI-OS"
$Cockpit = if ($env:COCKPIT_PATH) { $env:COCKPIT_PATH } else { $CockpitDefault }

function Step([int]$n, [string]$msg) { Write-Host ""; Write-Host "▶ $n/8  $msg" }
function Ok([string]$msg) { Write-Host "  ✓ $msg" }
function Info([string]$msg) { Write-Host "  → $msg" }
function Warn([string]$msg) { Write-Host "  ⚠ $msg" }
function AbortMsg([string]$msg) { Write-Error $msg; exit 1 }
function Ask([string]$msg) {
    if ($Yes) { return $true }
    $ans = Read-Host "  → $msg [Y/n]"
    return ($ans -eq "" -or $ans -match "^[Yy]")
}

# ─── 0. OS check ─────────────────────────────────────────
if (-not $IsWindows) {
    AbortMsg "Use install.sh on macOS/Linux."
}

Write-Host @'

 █████╗ ███████╗██████╗ ██╗███████╗██╗ ██████╗ ███╗   ██╗     █████╗ ██╗       ██████╗ ███████╗
██╔══██╗██╔════╝██╔══██╗██║██╔════╝██║██╔═══██╗████╗  ██║    ██╔══██╗██║      ██╔═══██╗██╔════╝
███████║█████╗  ██║  ██║██║█████╗  ██║██║   ██║██╔██╗ ██║    ███████║██║█████╗██║   ██║███████╗
██╔══██║██╔══╝  ██║  ██║██║██╔══╝  ██║██║   ██║██║╚██╗██║    ██╔══██║██║╚════╝██║   ██║╚════██║
██║  ██║███████╗██████╔╝██║██║     ██║╚██████╔╝██║ ╚████║    ██║  ██║██║      ╚██████╔╝███████║
╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝    ╚═╝  ╚═╝╚═╝       ╚═════╝ ╚══════╝

═══════════════════════════════════════════════════════════
   Installer (Windows)
═══════════════════════════════════════════════════════════

This will set up the aedifion AI Operations System on your Windows PC.
Expected time: 5–10 minutes.

🔐 Windows will show UAC (User Account Control) elevated-permission prompts
   during winget installs. Click "Yes" to allow each install.

'@

if (-not $Yes) {
    Read-Host "Press Enter to continue, Ctrl+C to abort"
}

# Ensure winget is available
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    AbortMsg "winget not available. Update to Windows 10 1809+ / 11, then install App Installer from Microsoft Store."
}

# Brew_install equivalent for winget
function Winget-Install {
    param([string]$pkg)
    $installed = winget list --id $pkg --exact 2>$null | Out-String
    if ($installed -match $pkg) {
        Ok "$pkg already installed"
    }
    else {
        Info "installing $pkg ..."
        winget install --id $pkg --exact --silent --accept-source-agreements --accept-package-agreements
    }
}

# ─── 1/7 git ──────────────────────────────────────────────
Step 1 "git"
Winget-Install "Git.Git"

# ─── 2/7 python3 ──────────────────────────────────────────
Step 2 "python3"
Winget-Install "Python.Python.3.12"

# ─── 3/7 gh (GitHub CLI) ──────────────────────────────────
Step 3 "GitHub CLI (gh)"
Winget-Install "GitHub.cli"

# ─── 4/7 VS Code ──────────────────────────────────────────
Step 4 "VS Code"
Winget-Install "Microsoft.VisualStudioCode"

# Refresh PATH for the rest of this session
$env:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + `
            [System.Environment]::GetEnvironmentVariable("Path", "User")

# ─── 5/7 Claude Code extension ────────────────────────────
Step 5 "Claude Code extension"
$exts = & code --list-extensions
if ($exts -match "anthropic.claude-code") {
    Ok "already installed"
}
else {
    Info "installing Claude Code extension ..."
    & code --install-extension anthropic.claude-code
}

# ─── 6/7 GitHub auth ──────────────────────────────────────
Step 6 "GitHub login"
$ghStatus = & gh auth status 2>&1
if ($LASTEXITCODE -eq 0) {
    Ok "already logged in to GitHub"
}
else {
    Write-Host ""
    Write-Host "  A browser window will open for GitHub login."
    Write-Host "  Use the GitHub account that has access to the aedifion-AI organisation."
    Write-Host ""
    & gh auth login --hostname github.com --git-protocol https --web
}

# ─── 7/7 Clone + open VS Code ─────────────────────────────
Step 7 "Workspace"

if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = $WorkspaceDefault
}

if ($Workspace -notmatch '^[A-Za-z0-9:\\/_.~-]+$') {
    AbortMsg "Path contains spaces or special characters: $Workspace"
}

if (Test-Path $Workspace) {
    Warn "$Workspace already exists — skipping clone."
    Info "If you want a clean install, remove or rename the existing folder, then re-run."
}
else {
    Info "cloning $PrivateRepo into $Workspace ..."
    & gh repo clone $PrivateRepo $Workspace
    if ($LASTEXITCODE -ne 0) { AbortMsg "Clone failed." }
}

Info "opening VS Code at $Workspace ..."
& code $Workspace
if ($LASTEXITCODE -ne 0) {
    Warn "'code' command failed. Open VS Code → File → Open Folder → $Workspace"
}

# ─── 8/8 Cockpit auto-migration ──────────────────────────
Step 8 "Cockpit auto-migration"

function Test-FoundationHasPersonalContent {
    param([string]$Path)
    $patterns = @(
        (Join-Path $Path ".claude\skills\*-priv"),
        (Join-Path $Path ".claude\skills\personal-*"),
        (Join-Path $Path ".claude\agents\*-priv.md"),
        (Join-Path $Path ".claude\agents\personal-*.md")
    )
    foreach ($p in $patterns) {
        if (Get-ChildItem -Path $p -ErrorAction SilentlyContinue) { return $true }
    }
    return $false
}

function Test-IsCockpitWorkspace {
    param([string]$Path)
    if (-not (Test-Path $Path -PathType Container)) { return $false }
    $signals = 0
    if (Test-Path (Join-Path $Path "CLAUDE.md"))   { $signals++ }
    if (Test-Path (Join-Path $Path "01-memory"))   { $signals++ }
    if (Test-Path (Join-Path $Path "02-projects")) { $signals++ }
    if (Test-Path (Join-Path $Path "03-skills"))   { $signals++ }
    return ($signals -ge 2)
}

if (Test-FoundationHasPersonalContent $Workspace) {
    Ok "Foundation already has personal content — skipping migration (idempotent)."
} elseif ($Cockpit -eq $Workspace) {
    Info "Cockpit path equals Foundation path — skipping."
} elseif (Test-IsCockpitWorkspace $Cockpit) {
    Info "Cockpit-style workspace detected at $Cockpit"
    Info "Migration will: 1) back up Cockpit  2) copy skills/agents/projects/memory/.env/MCP/settings"
    if (Ask "Run migration now?") {
        $MigrateScript = Join-Path $Workspace "installer\migrate-cockpit.ps1"
        if (Test-Path $MigrateScript) {
            & pwsh -NoProfile -File $MigrateScript -Yes -Cockpit $Cockpit -Foundation $Workspace
            if ($LASTEXITCODE -ne 0) {
                Warn "Migration script returned non-zero — review output above. Cockpit and backup are untouched."
            }
        } else {
            Warn "Migration script not found: $MigrateScript"
        }
    } else {
        Info "Skipped. Run later with: pwsh $Workspace\installer\migrate-cockpit.ps1"
    }
} else {
    Info "No Cockpit-style workspace at $Cockpit — nothing to migrate."
}

Write-Host @"

═══════════════════════════════════════════════════════════
  ✓ Installation complete.

  Next step — inside VS Code:
    1. Open the Claude Code sidebar (Anthropic icon on the left)
    2. Type:  /onboard

═══════════════════════════════════════════════════════════
"@
