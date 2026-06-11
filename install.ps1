# aedifion AI-OS -- All-in-one installer (Windows PowerShell 5.1+, runs in pwsh too)
#
# Canonical location: aedifion-AI/aedifion-AI-OS/installer/install.ps1 (private)
# Public mirror:      aedifion-AI/ai-os-installer (sync target -- kept in lockstep)
# After editing this file, follow installer/MIRROR-SYNC.md to push to the mirror.
#
# Distribution paths:
#   1. Fresh laptop (recommended): one-liner against the public mirror --
#        iex "& { $(irm https://raw.githubusercontent.com/aedifion-AI/ai-os-installer/main/install.ps1) }"
#   2. Browser download from the Hauptrepo (org members only) --
#        https://github.com/aedifion-AI/aedifion-AI-OS/raw/main/installer/install.ps1
#        then locally:  powershell -ExecutionPolicy Bypass -File ~/Downloads/install.ps1
#
# Access control: the Hauptrepo is private. Step 8 (`gh repo clone`) is the
# auth gate -- non-members hit `permission denied` and the script stops.
#
# This installer:
#   1. Installs git via winget
#   2. Installs python3 via winget
#   3. Installs Node.js via winget
#   4. Installs GitHub CLI (gh) via winget
#   5. Installs VS Code via winget
#   6. Installs the Claude Code extension
#   7. Logs you into GitHub (browser opens)
#   8. Clones the private aedifion-AI-OS repo and opens VS Code
#   9. If a Cockpit-style workspace exists at $HOME/AI-OS (or $env:COCKPIT_PATH),
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

function Step([int]$n, [string]$msg) { Write-Host ""; Write-Host "▶ $n/9  $msg" }
function Ok([string]$msg) { Write-Host "  ✓ $msg" }
function Info([string]$msg) { Write-Host "  → $msg" }
function Warn([string]$msg) { Write-Host "  ⚠ $msg" }
function AbortMsg([string]$msg) { Write-Error $msg; exit 1 }
function Ask([string]$msg) {
    if ($Yes) { return $true }
    $ans = Read-Host "  → $msg [Y/n]"
    return ($ans -eq "" -or $ans -match "^[Yy]")
}

# Run a native command with $ErrorActionPreference relaxed to 'Continue' for
# the duration of the call. Windows PowerShell 5.1 otherwise promotes any
# stderr write from a native tool (git's "From https://...", gh's clone
# progress, etc.) to a terminating RemoteException -- even harmless status
# lines kill the script. $LASTEXITCODE is preserved so the caller can check
# success the normal way. See PowerShell issue #3996 and posh-git PR #370.
# Callers that want merged stdout+stderr should add `2>&1` inside the block,
# e.g. `$out = Invoke-Native { git pull 2>&1 }`.
function Invoke-Native {
    param([scriptblock]$Block)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Block }
    finally { $ErrorActionPreference = $prev }
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
Expected time: 5-10 minutes.

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
# Out-String, so the user saw no prompt -- looked like a hang at "1/9 git").
Write-Host ""
Info "warming up winget (accepting source agreements) ..."
Invoke-Native { winget source update --accept-source-agreements 2>&1 } | Out-Null

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
# Python from python.org, gh from a GitHub-Desktop bundle, etc. -- winget
# doesn't see those. Asking the wrong question makes winget try a second
# install that collides with the existing one (Inno Setup exit code 1).
#
# Flow:
#   1. If the tool's CLI is already on PATH → done, skip winget entirely.
#   2. Else: check whether winget has it registered → done if yes.
#   3. Else: try `winget install`.
#   4. After install (success OR failure): re-check the tool on PATH.
#      If it's there now, we're fine -- even if winget's exit code was odd.
#   5. Only if the tool is STILL missing → hard abort with manual-install
#      instructions for the specific package.
function Winget-Install {
    param(
        [Parameter(Mandatory=$true)][string]$pkg,
        [string]$tool = ""  # CLI command to probe for (git, python, gh, code)
    )

    # Step 1: tool-first check
    if ($tool -and (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Ok "$tool already available on PATH -- skipping winget install of $pkg"
        return
    }

    # Step 2: winget registry check (catches GUI-only apps without a CLI)
    winget list --id $pkg --exact --accept-source-agreements 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Ok "$pkg already installed (winget knows it)"
        Refresh-Path
        return
    }

    # Step 3: install. No --silent -- users need to see download progress,
    # otherwise the script looks frozen during large downloads.
    Info "installing $pkg ..."
    winget install --id $pkg --exact --accept-source-agreements --accept-package-agreements
    $installExit = $LASTEXITCODE
    Refresh-Path

    # Step 4: self-heal. Did the tool actually land on PATH? If yes, the
    # exit code doesn't matter -- winget sometimes reports oddly when an
    # installer chains sub-installers or when a reboot would be ideal.
    if ($tool -and (Get-Command $tool -ErrorAction SilentlyContinue)) {
        if ($installExit -ne 0) {
            Warn "winget reported exit $installExit, but $tool is now available -- continuing."
        } else {
            Ok "$pkg installed"
        }
        return
    }

    # Step 5: actually broken. Help the user help themselves.
    if ($installExit -eq 0) {
        # winget says success but tool is missing -- likely PATH not refreshed
        # by the installer until a new shell. Warn rather than abort.
        Warn "$pkg installed, but $tool is not yet on PATH."
        Warn "Close this PowerShell window and re-run the installer (one-liner) in a fresh shell."
        Warn "The next run will detect $tool and skip this step."
        return
    }

    $manualUrl = switch ($pkg) {
        "Git.Git"                    { "https://git-scm.com/download/win" }
        "Python.Python.3.12"         { "https://www.python.org/downloads/windows/" }
        "OpenJS.NodeJS.LTS"          { "https://nodejs.org/en/download" }
        "GitHub.cli"                 { "https://cli.github.com/" }
        "Microsoft.VisualStudioCode" { "https://code.visualstudio.com/Download" }
        default                      { $null }
    }
    $manualHint = if ($manualUrl) { @"


Workaround -- install $pkg manually, then re-run this installer:
   1. Download from: $manualUrl
   2. Run the installer with default settings.
   3. Close this PowerShell window, open a new one.
   4. Re-run the same one-liner. The installer is idempotent -- it will
      detect the manual install via '$tool' on PATH and continue from the
      next step.
"@ } else { "" }

    AbortMsg @"
winget install $pkg failed with exit code $installExit.

The detailed installer log path was printed by winget a few lines above.
Open it and read the last ~20 lines -- the actual cause is in there.

Common causes:
  • A conflicting pre-existing install of $pkg (most common). Uninstall
    the old version via Settings → Apps, or use the manual workaround.
  • UAC "No" was clicked -- re-run and allow the elevation prompt.
  • Antivirus / Defender blocking the installer.
  • No internet / corporate proxy blocking the MS Store CDN.$manualHint

The installer has stopped. Nothing else was changed. Re-run when ready.
"@
}

# ─── 1/9 git ──────────────────────────────────────────────
Step 1 "git"
Winget-Install -pkg "Git.Git" -tool "git"

# ─── 2/9 python3 ──────────────────────────────────────────
Step 2 "python3"
Winget-Install -pkg "Python.Python.3.12" -tool "python"

# ─── 3/9 Node.js ──────────────────────────────────────────
Step 3 "Node.js"
Winget-Install -pkg "OpenJS.NodeJS.LTS" -tool "node"

# ─── 4/9 gh (GitHub CLI) ──────────────────────────────────
Step 4 "GitHub CLI (gh)"
Winget-Install -pkg "GitHub.cli" -tool "gh"

# ─── 5/9 VS Code ──────────────────────────────────────────
Step 5 "VS Code"
Winget-Install -pkg "Microsoft.VisualStudioCode" -tool "code"

# ─── 6/9 Claude Code extension ────────────────────────────
Step 6 "Claude Code extension"
if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
    Warn "'code' CLI not on PATH yet -- VS Code may need a system restart to register."
    Warn "Skipping extension install. After restarting, run inside VS Code:"
    Warn "    code --install-extension anthropic.claude-code"
} else {
    $exts = Invoke-Native { code --list-extensions 2>&1 }
    if ($exts -match "anthropic.claude-code") {
        Ok "already installed"
    }
    else {
        Info "installing Claude Code extension ..."
        Invoke-Native { code --install-extension anthropic.claude-code }
        if ($LASTEXITCODE -ne 0) {
            Warn "Extension install returned $LASTEXITCODE -- install it from inside VS Code if needed."
        }
    }
}

# ─── 7/9 GitHub auth ──────────────────────────────────────
Step 7 "GitHub login"
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    AbortMsg "'gh' CLI not on PATH. Close this PowerShell window and re-run the installer (Windows needs a fresh shell after gh install)."
}
$ghStatus = Invoke-Native { gh auth status 2>&1 }
if ($LASTEXITCODE -eq 0) {
    Ok "already logged in to GitHub"
}
else {
    Write-Host ""
    Write-Host "  A browser window will open for GitHub login."
    Write-Host "  Use the GitHub account that has access to the aedifion-AI organisation."
    Write-Host ""
    Invoke-Native { gh auth login --hostname github.com --git-protocol https --web }
    if ($LASTEXITCODE -ne 0) {
        AbortMsg "GitHub login did not complete. Re-run the installer once logged in via 'gh auth login'."
    }
}

# ─── 8/9 Clone + open VS Code ─────────────────────────────
Step 8 "Workspace"

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
    # Workspace exists -- pull latest if it's a git repo. Without this, a user
    # who re-runs the installer to pick up a bug-fix gets the OLD files because
    # their clone is frozen at the moment of first install.
    if (Test-Path (Join-Path $Workspace ".git")) {
        Info "$Workspace already exists -- pulling latest from origin/main ..."
        Push-Location $Workspace
        try {
            $localChanges = Invoke-Native { git status --porcelain 2>&1 }
            if ($localChanges) {
                Warn "Local changes detected in $Workspace -- skipping pull to preserve your work."
                Warn "If you want the latest version, commit/stash your changes and run: git pull origin main"
            } else {
                $pullOutput = Invoke-Native { git pull --ff-only origin main 2>&1 }
                if ($LASTEXITCODE -eq 0) {
                    Ok "Workspace updated to origin/main"
                } else {
                    Warn "git pull failed (workspace may be on a non-main branch). Continuing with current state."
                    Warn "  $pullOutput"
                }
            }
        } finally {
            Pop-Location
        }
    } else {
        Warn "$Workspace exists but is not a git repository -- skipping clone."
        Info "If you want a clean install, remove or rename the existing folder, then re-run."
    }
}
else {
    Info "cloning $PrivateRepo into $Workspace ..."
    $cloneOutput = Invoke-Native { gh repo clone $PrivateRepo $Workspace 2>&1 }
    if ($LASTEXITCODE -ne 0) {
        Write-Host $cloneOutput
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
    Invoke-Native { code $Workspace }
    if ($LASTEXITCODE -ne 0) {
        Warn "'code' command failed. Open VS Code → File → Open Folder → $Workspace"
    }
} else {
    Warn "'code' CLI not on PATH yet -- VS Code may need a system restart to register."
    Warn "Open VS Code manually → File → Open Folder → $Workspace"
}

# ─── 9/9 Migration from any existing CC workspace ────────
Step 9 "Migration from any existing Claude Code workspace"

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

# A workspace is migratable if it has any of:
#   - Cockpit layout: 2+ of {CLAUDE.md, 01-memory/, 02-projects/, 03-skills/}
#   - Generic CC: .claude/skills or .claude/agents with non-empty contents
function Test-HasMigratableContent {
    param([string]$Path)
    if (-not (Test-Path $Path -PathType Container)) { return $false }
    $signals = 0
    if (Test-Path (Join-Path $Path "CLAUDE.md"))   { $signals++ }
    if (Test-Path (Join-Path $Path "01-memory"))   { $signals++ }
    if (Test-Path (Join-Path $Path "02-projects")) { $signals++ }
    if (Test-Path (Join-Path $Path "03-skills"))   { $signals++ }
    if ($signals -ge 2) { return $true }
    $skillsDir = Join-Path $Path ".claude\skills"
    $agentsDir = Join-Path $Path ".claude\agents"
    if ((Test-Path $skillsDir) -and (Get-ChildItem $skillsDir -ErrorAction SilentlyContinue)) {
        return $true
    }
    if ((Test-Path $agentsDir) -and (Get-ChildItem $agentsDir -ErrorAction SilentlyContinue)) {
        return $true
    }
    return $false
}

# Discover an existing CC-workspace in standard locations. Returns the first
# matching path, or $null. Covers:
#   - legacy aedifion-Cockpit at ~/AI-OS
#   - Documents/Dokumente, Desktop/Schreibtisch, Downloads (DE + EN locale)
#   - all of the above mirrored under OneDrive (env vars + "OneDrive*" patterns)
function Find-ExistingWorkspace {
    param([string]$Foundation, [string]$ExplicitCockpit)
    $candidates = New-Object System.Collections.Generic.List[string]
    if ($ExplicitCockpit) { $candidates.Add($ExplicitCockpit) | Out-Null }
    $candidates.Add((Join-Path $HOME "AI-OS")) | Out-Null
    $folders = @("Documents", "Dokumente", "Desktop", "Schreibtisch", "Downloads")
    foreach ($f in $folders) {
        $candidates.Add((Join-Path $HOME "$f\Claude Code")) | Out-Null
    }
    # OneDrive via env vars (per-machine + commercial + consumer)
    foreach ($oneDriveBase in @($env:OneDrive, $env:OneDriveCommercial, $env:OneDriveConsumer)) {
        if ($oneDriveBase -and (Test-Path $oneDriveBase)) {
            foreach ($f in $folders) {
                $candidates.Add((Join-Path $oneDriveBase "$f\Claude Code")) | Out-Null
            }
        }
    }
    # OneDrive folders directly under $HOME (e.g. "OneDrive - aedifion GmbH")
    Get-ChildItem -Path $HOME -Directory -Filter "OneDrive*" -ErrorAction SilentlyContinue | ForEach-Object {
        foreach ($f in $folders) {
            $candidates.Add((Join-Path $_.FullName "$f\Claude Code")) | Out-Null
        }
    }
    foreach ($path in $candidates) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if ($path -eq $Foundation) { continue }
        if (Test-HasMigratableContent $path) {
            return $path
        }
    }
    return $null
}

if (Test-FoundationHasPersonalContent $Workspace) {
    Ok "Foundation already has personal content -- skipping migration (idempotent)."
} else {
    $discovered = Find-ExistingWorkspace -Foundation $Workspace -ExplicitCockpit $Cockpit
    if ($discovered) {
        Info "Existing Claude Code workspace detected at: $discovered"
        Info "Migration will: 1) back up source  2) copy skills/agents/projects/memory/.env/MCP/settings"
        if (Ask "Run migration now?") {
            $MigrateScript = Join-Path $Workspace "installer\migrate-cockpit.ps1"
            if (Test-Path $MigrateScript) {
                $psExe = (Get-Process -Id $PID).Path
                Invoke-Native { & $psExe -NoProfile -ExecutionPolicy Bypass -File $MigrateScript -Yes -Cockpit $discovered -Foundation $Workspace }
                if ($LASTEXITCODE -ne 0) {
                    Warn "Migration script returned non-zero -- review output above. Source and backup are untouched."
                }
            } else {
                Warn "Migration script not found: $MigrateScript"
            }
        } else {
            Info "Skipped. Run later with: powershell -ExecutionPolicy Bypass -File $Workspace\installer\migrate-cockpit.ps1 -Cockpit `"$discovered`""
        }
    } else {
        Info "No existing Claude Code workspace found in standard locations."
        Info "Searched: `$HOME\AI-OS,"
        Info "          `$HOME\(Documents|Dokumente|Desktop|Schreibtisch|Downloads)\Claude Code,"
        Info "          `$HOME\OneDrive*\(same five folders)\Claude Code"
        if (-not $Yes) {
            $customPath = Read-Host "  → If you have one at a different path, enter it now (or press Enter to skip)"
            if ($customPath -and $customPath -ne $Workspace) {
                if (Test-HasMigratableContent $customPath) {
                    $MigrateScript = Join-Path $Workspace "installer\migrate-cockpit.ps1"
                    $psExe = (Get-Process -Id $PID).Path
                    Invoke-Native { & $psExe -NoProfile -ExecutionPolicy Bypass -File $MigrateScript -Yes -Cockpit $customPath -Foundation $Workspace }
                    if ($LASTEXITCODE -ne 0) {
                        Warn "Migration script returned non-zero."
                    }
                } else {
                    Warn "No migratable content found at: $customPath (skills/agents empty or missing)"
                }
            }
        }
    }
}

Write-Host @"

═══════════════════════════════════════════════════════════
  ✓ Installation complete.

  Next step -- inside VS Code:
    1. Open the Claude Code sidebar (Anthropic icon on the left)
    2. Type:  /onboard

═══════════════════════════════════════════════════════════
"@
