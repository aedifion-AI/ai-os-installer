# aedifion AI-OS — All-in-one installer (Windows PowerShell 5.1+, runs in pwsh too)
#
# Canonical location: aedifion-AI/aedifion-AI-OS/installer/install.ps1 (private)
# Public mirror:      aedifion-AI/ai-os-installer (sync target — kept in lockstep)
# After editing this file, follow installer/MIRROR-SYNC.md to push to the mirror.
#
# Distribution paths:
#   1. Fresh laptop (recommended): one-liner against the public mirror —
#        iex "& { $(irm https://raw.githubusercontent.com/aedifion-AI/ai-os-installer/main/install.ps1) }"
#   2. Browser download from the Hauptrepo (org members only) —
#        https://github.com/aedifion-AI/aedifion-AI-OS/raw/main/installer/install.ps1
#        then locally:  powershell -ExecutionPolicy Bypass -File ~/Downloads/install.ps1
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
# $IsWindows is an automatic variable in PowerShell 7+ (Core). In Windows
# PowerShell 5.1 it does not exist (= $null), so we only treat the script as
# running on a non-Windows OS when the variable is explicitly defined and false.
$isWindowsCheck = Get-Variable -Name IsWindows -ErrorAction SilentlyContinue
if ($null -ne $isWindowsCheck -and -not $isWindowsCheck.Value) {
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

# Warm up winget: on a fresh Windows box the first winget call prompts
# interactively to accept the msstore/winget source terms. We pre-accept
# them once here, otherwise the first `winget list` inside Winget-Install
# stalls invisibly (stderr was redirected, stdout was buffered through
# Out-String, so the user saw no prompt — looked like a hang at "1/8 git").
Write-Host ""
Info "warming up winget (accepting source agreements) ..."
winget source update --accept-source-agreements 2>&1 | Out-Null

function Refresh-Path {
    # winget installs put new tools into the Machine/User PATH, but the running
    # PowerShell session still has the old PATH. Re-read both scopes after each
    # install so subsequent steps see freshly-installed CLIs (gh, code, ...).
    $machine = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:PATH = "$machine;$userPath"
}

# Brew_install equivalent for winget.
#
# Design: the question is "is this TOOL available?", not "is this winget
# PACKAGE installed?". Many devs already have Git from git-scm.com,
# Python from python.org, gh from a GitHub-Desktop bundle, etc. — winget
# doesn't see those. Asking the wrong question makes winget try a second
# install that collides with the existing one (Inno Setup exit code 1).
#
# Flow:
#   1. If the tool's CLI is already on PATH → done, skip winget entirely.
#   2. Else: check whether winget has it registered → done if yes.
#   3. Else: try `winget install`.
#   4. After install (success OR failure): re-check the tool on PATH.
#      If it's there now, we're fine — even if winget's exit code was odd.
#   5. Only if the tool is STILL missing → hard abort with manual-install
#      instructions for the specific package.
function Winget-Install {
    param(
        [Parameter(Mandatory=$true)][string]$pkg,
        [string]$tool = ""  # CLI command to probe for (git, python, gh, code)
    )

    # Step 1: tool-first check
    if ($tool -and (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Ok "$tool already available on PATH — skipping winget install of $pkg"
        return
    }

    # Step 2: winget registry check (catches GUI-only apps without a CLI)
    winget list --id $pkg --exact --accept-source-agreements 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Ok "$pkg already installed (winget knows it)"
        Refresh-Path
        return
    }

    # Step 3: install. No --silent — users need to see download progress,
    # otherwise the script looks frozen during large downloads.
    Info "installing $pkg ..."
    winget install --id $pkg --exact --accept-source-agreements --accept-package-agreements
    $installExit = $LASTEXITCODE
    Refresh-Path

    # Step 4: self-heal. Did the tool actually land on PATH? If yes, the
    # exit code doesn't matter — winget sometimes reports oddly when an
    # installer chains sub-installers or when a reboot would be ideal.
    if ($tool -and (Get-Command $tool -ErrorAction SilentlyContinue)) {
        if ($installExit -ne 0) {
            Warn "winget reported exit $installExit, but $tool is now available — continuing."
        } else {
            Ok "$pkg installed"
        }
        return
    }

    # Step 5: actually broken. Help the user help themselves.
    if ($installExit -eq 0) {
        # winget says success but tool is missing — likely PATH not refreshed
        # by the installer until a new shell. Warn rather than abort.
        Warn "$pkg installed, but $tool is not yet on PATH."
        Warn "Close this PowerShell window and re-run the installer (one-liner) in a fresh shell."
        Warn "The next run will detect $tool and skip this step."
        return
    }

    $manualUrl = switch ($pkg) {
        "Git.Git"                    { "https://git-scm.com/download/win" }
        "Python.Python.3.12"         { "https://www.python.org/downloads/windows/" }
        "GitHub.cli"                 { "https://cli.github.com/" }
        "Microsoft.VisualStudioCode" { "https://code.visualstudio.com/Download" }
        default                      { $null }
    }
    $manualHint = if ($manualUrl) { @"


Workaround — install $pkg manually, then re-run this installer:
   1. Download from: $manualUrl
   2. Run the installer with default settings.
   3. Close this PowerShell window, open a new one.
   4. Re-run the same one-liner. The installer is idempotent — it will
      detect the manual install via '$tool' on PATH and continue from the
      next step.
"@ } else { "" }

    AbortMsg @"
winget install $pkg failed with exit code $installExit.

The detailed installer log path was printed by winget a few lines above.
Open it and read the last ~20 lines — the actual cause is in there.

Common causes:
  • A conflicting pre-existing install of $pkg (most common). Uninstall
    the old version via Settings → Apps, or use the manual workaround.
  • UAC "No" was clicked — re-run and allow the elevation prompt.
  • Antivirus / Defender blocking the installer.
  • No internet / corporate proxy blocking the MS Store CDN.$manualHint

The installer has stopped. Nothing else was changed. Re-run when ready.
"@
}

# ─── 1/8 git ──────────────────────────────────────────────
Step 1 "git"
Winget-Install -pkg "Git.Git" -tool "git"

# ─── 2/8 python3 ──────────────────────────────────────────
Step 2 "python3"
Winget-Install -pkg "Python.Python.3.12" -tool "python"

# ─── 3/8 gh (GitHub CLI) ──────────────────────────────────
Step 3 "GitHub CLI (gh)"
Winget-Install -pkg "GitHub.cli" -tool "gh"

# ─── 4/8 VS Code ──────────────────────────────────────────
Step 4 "VS Code"
Winget-Install -pkg "Microsoft.VisualStudioCode" -tool "code"

# ─── 5/8 Claude Code extension ────────────────────────────
Step 5 "Claude Code extension"
if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Warn "'code' CLI not on PATH yet — VS Code may need a system restart to register."
    Warn "Skipping extension install. After restarting, run inside VS Code:"
    Warn "    code --install-extension anthropic.claude-code"
} else {
    $exts = & code --list-extensions 2>&1
    if ($exts -match "anthropic.claude-code") {
        Ok "already installed"
    }
    else {
        Info "installing Claude Code extension ..."
        & code --install-extension anthropic.claude-code
        if ($LASTEXITCODE -ne 0) {
            Warn "Extension install returned $LASTEXITCODE — install it from inside VS Code if needed."
        }
    }
}

# ─── 6/8 GitHub auth ──────────────────────────────────────
Step 6 "GitHub login"
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    AbortMsg "'gh' CLI not on PATH. Close this PowerShell window and re-run the installer (Windows needs a fresh shell after gh install)."
}
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
    if ($LASTEXITCODE -ne 0) {
        AbortMsg "GitHub login did not complete. Re-run the installer once logged in via 'gh auth login'."
    }
}

# ─── 7/8 Clone + open VS Code ─────────────────────────────
Step 7 "Workspace"

if ([string]::IsNullOrWhiteSpace($Workspace)) {
    $Workspace = $WorkspaceDefault
}

# Allow letters (incl. umlauts: \p{L}), digits, drive-letter colon, slashes,
# spaces, dots, tildes, underscores, dashes. Block shell-meta and quoting
# chars that would break git/gh and downstream scripts.
if ($Workspace -notmatch '^[\p{L}\p{N}:\\/ _.~-]+$') {
    AbortMsg "Path contains characters we can't safely pass to git/gh: $Workspace"
}

if (Test-Path $Workspace) {
    Warn "$Workspace already exists — skipping clone."
    Info "If you want a clean install, remove or rename the existing folder, then re-run."
}
else {
    Info "cloning $PrivateRepo into $Workspace ..."
    & gh repo clone $PrivateRepo $Workspace
    if ($LASTEXITCODE -ne 0) {
        AbortMsg @"
Clone of $PrivateRepo failed.

Most common cause: you're logged in to GitHub, but with an account that
isn't a member of the 'aedifion-AI' organisation. The Hauptrepo is private,
so non-members get 'permission denied' or 'Could not resolve to a Repository'.

To switch accounts:
    gh auth logout
    gh auth login --hostname github.com --git-protocol https --web

Use the GitHub account that aedifion-IT linked to the aedifion-AI org. Then
re-run this installer.
"@
    }
}

if (Get-Command code -ErrorAction SilentlyContinue) {
    Info "opening VS Code at $Workspace ..."
    & code $Workspace
    if ($LASTEXITCODE -ne 0) {
        Warn "'code' command failed. Open VS Code → File → Open Folder → $Workspace"
    }
} else {
    Warn "'code' CLI not on PATH yet — VS Code may need a system restart to register."
    Warn "Open VS Code manually → File → Open Folder → $Workspace"
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
            # Use the SAME PowerShell engine that's running this script. Avoids
            # the "pwsh not found" trap when the user is on Windows PowerShell
            # 5.1 (default Windows) and we don't ship PS 7 as a prerequisite.
            $psExe = (Get-Process -Id $PID).Path
            & $psExe -NoProfile -File $MigrateScript -Yes -Cockpit $Cockpit -Foundation $Workspace
            if ($LASTEXITCODE -ne 0) {
                Warn "Migration script returned non-zero — review output above. Cockpit and backup are untouched."
            }
        } else {
            Warn "Migration script not found: $MigrateScript"
        }
    } else {
        Info "Skipped. Run later with: powershell -File $Workspace\installer\migrate-cockpit.ps1"
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
