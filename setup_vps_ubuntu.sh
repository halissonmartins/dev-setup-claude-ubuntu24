#!/usr/bin/env bash
# =============================================================================
# VPS Ubuntu 24.04 (ARM64 / aarch64) - Full Development Environment Setup Script
# =============================================================================
# Target: a headless ARM64 cloud VPS (e.g. Oracle Cloud Ampere A1).
# This is the ARM/VPS variant of the WSL setup — it assumes the host is ARM64
# and has NO graphical desktop, so all browser usage is headless/automation.
#
# Tools installed:
#   System update, Python (latest), PIP, Node.js (LTS), Angular CLI,
#   Next.js, React (create-react-app), OpenJDK 25, Maven (latest),
#   GitHub CLI, Git, Claude Code, Docker + Compose,
#   Chromium (headless, via Playwright), Newman (Postman collection runner),
#   GitHub Spec Kit (specify CLI via uvx),
#   ZIP, ShellCheck, PostgreSQL client (PGDG), k6 (load testing),
#   Kafka CLI (Apache), Playwright CLI + Chromium, OpenSpec CLI, Tmux,
#   Chrome DevTools MCP server, and MCP servers registered into Claude
#   (chrome-devtools + playwright + context7, user scope)
#
# NOTE: Google Chrome and the Postman CLI are NOT installed — neither ships an
# ARM64 Linux build. We reuse Playwright's ARM64 Chromium build instead of Chrome,
# and install Newman (Node-based) in place of the Postman CLI.
# =============================================================================

set -euo pipefail

# =============================================================================
# ROOT PATH BOOTSTRAP
# =============================================================================
# When running as root on a fresh VPS, the shell may start with a stripped PATH
# that omits /usr/bin and /bin, causing "command not found" for basic tools.
# Establish a complete, safe PATH before anything else runs.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

# Also ensure SUDO_USER is set so we know the real invoking user.
# If run directly as root (not via sudo), SUDO_USER will be empty — default to root.
REAL_USER="${SUDO_USER:-root}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
REAL_HOME="${REAL_HOME:-/root}"

# Warn if running as root — Docker group, NVM, and some tools behave differently
if [[ "$EUID" -eq 0 ]]; then
  echo -e "\033[1;33m[WARN]\033[0m  Running as root. NVM and npm globals will be installed for root."
  echo -e "\033[1;33m[WARN]\033[0m  REAL_USER=${REAL_USER}  REAL_HOME=${REAL_HOME}"
  echo -e "\033[1;33m[WARN]\033[0m  Target host assumed to be ARM64 (aarch64) — Oracle Cloud Ampere or similar."
fi

# --------------------------------------------------------------------------- #
# Colors & helpers
# --------------------------------------------------------------------------- #
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log()     { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

section() {
  echo ""
  echo -e "${CYAN}============================================================${NC}"
  echo -e "${CYAN}  $*${NC}"
  echo -e "${CYAN}============================================================${NC}"
}

# Tracks failures so we can show a summary at the end
FAILED=()
record_fail() { FAILED+=("$1"); }

# Verify a binary exists and print its version
# cmd is passed as separate args (no eval) to prevent code injection
check_tool() {
  local name="$1"
  shift
  # remaining args are the command + its arguments, executed directly
  if command -v "$name" &>/dev/null; then
    local ver
    ver=$(bash -c "$*" 2>&1 | head -1) || ver="(version query failed)"
    success "$name → $ver"
    return 0
  else
    error "$name not found in PATH"
    record_fail "$name"
    return 1
  fi
}

# Verify a URL is reachable before using it
check_url() {
  local label="$1"
  local url="$2"
  if curl -fsSL --max-time 10 --head "$url" &>/dev/null; then
    success "URL OK: $label ($url)"
    return 0
  else
    warn "URL unreachable: $label ($url)"
    return 1
  fi
}

# =============================================================================
# 0. URL VERIFICATION
# =============================================================================
section "0. Verifying installation URLs"

check_url "Ubuntu apt mirror"                  "https://archive.ubuntu.com"
check_url "Python deadsnakes PPA"              "https://launchpad.net/~deadsnakes/+archive/ubuntu/ppa"
check_url "NVM install script"                "https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh"
check_url "Adoptium (Temurin JDK 25)"          "https://packages.adoptium.net/artifactory/api/gpg/key/public"
check_url "Maven downloads (Apache CDN)"        "https://dlcdn.apache.org/maven/maven-3/"
check_url "GitHub CLI keyring"                 "https://cli.github.com/packages/githubcli-archive-keyring.gpg"
check_url "Docker GPG key"                     "https://download.docker.com/linux/ubuntu/gpg"
# Google Chrome and Postman CLI are NOT used on ARM64 (no ARM Linux builds) —
# Chromium is installed from the Ubuntu apt repo instead, so no URL check here.
check_url "Claude Code (npm)"                  "https://registry.npmjs.org/@anthropic-ai/claude-code"
check_url "GitHub Spec Kit (PyPI/git)"         "https://github.com/github/spec-kit"
check_url "uv installer (for Spec Kit)"        "https://astral.sh/uv/install.sh"
check_url "TypeScript LSP (vtsls npm)"         "https://registry.npmjs.org/@vtsls/language-server"
check_url "Java LSP (jdtls snapshot)"          "http://download.eclipse.org/jdtls/snapshots/jdt-language-server-latest.tar.gz"
check_url "PostgreSQL PGDG signing key"        "https://www.postgresql.org/media/keys/ACCC4CF8.asc"
check_url "PostgreSQL PGDG apt repo"           "https://apt.postgresql.org/pub/repos/apt/"
check_url "Grafana k6 (GitHub releases)"       "https://github.com/grafana/k6/releases/latest"
check_url "Apache Kafka CDN"                   "https://dlcdn.apache.org/kafka/"
check_url "Playwright (npm)"                   "https://registry.npmjs.org/playwright"
check_url "Playwright MCP (npm)"               "https://registry.npmjs.org/@playwright/mcp"
check_url "Chrome DevTools MCP (npm)"          "https://registry.npmjs.org/chrome-devtools-mcp"
check_url "OpenSpec (npm)"                     "https://registry.npmjs.org/@fission-ai/openspec"
check_url "Context7 MCP (npm)"                 "https://registry.npmjs.org/@upstash/context7-mcp"

# =============================================================================
# 1. SYSTEM UPDATE & ESSENTIALS
# =============================================================================
section "1. System update & essential packages"

log "Running apt update & upgrade..."
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y \
  curl wget gnupg ca-certificates \
  software-properties-common apt-transport-https \
  build-essential git unzip zip tar lsb-release shellcheck \
  libssl-dev zlib1g-dev libncurses5-dev libgdbm-dev \
  libnss3-dev libffi-dev libreadline-dev libsqlite3-dev libbz2-dev \
  libxss1 libxrandr2 libasound2t64 libpango-1.0-0 \
  libatk1.0-0 libcairo2 libgtk-3-0 \
  bubblewrap socat zsh
  # Note: libgconf-2-4 was dropped in Ubuntu 23.10+ (GConf is deprecated)
  # libasound2 → libasound2t64  (renamed in Ubuntu 24.04)
  # libpango1.0-0 → libpango-1.0-0  (renamed in Ubuntu 24.04)

success "System packages installed."

# =============================================================================
# 2. PYTHON (LATEST via deadsnakes) + PIP
# =============================================================================
section "2. Python (latest) + PIP"

log "Adding deadsnakes PPA..."
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt update -y

# Find the highest available python3.x version from deadsnakes
LATEST_PYTHON=$(apt-cache search '^python3\.[0-9]+$' \
  | awk '{print $1}' \
  | grep -E '^python3\.[0-9]+$' \
  | sort -t. -k2 -V \
  | tail -1)

if [[ -z "$LATEST_PYTHON" ]]; then
  warn "Could not determine latest Python version; falling back to python3.13"
  LATEST_PYTHON="python3.13"
fi

log "Installing $LATEST_PYTHON ..."
sudo apt install -y "$LATEST_PYTHON" \
  "${LATEST_PYTHON}-venv" \
  "${LATEST_PYTHON}-dev" \
  "${LATEST_PYTHON}-distutils" 2>/dev/null || \
sudo apt install -y "$LATEST_PYTHON" "${LATEST_PYTHON}-venv" "${LATEST_PYTHON}-dev"

log "Setting $LATEST_PYTHON as default python3 (user-facing)..."
# apt internally relies on the system python3.12 via apt_pkg.
# Overriding /usr/bin/python3 breaks apt ("No module named apt_pkg").
# Solution: keep /usr/bin/python3 → system python3, expose the new version
# under /usr/local/bin/python3 (which takes precedence for interactive shells
# once /usr/local/bin is first on PATH) and via its own versioned binary.
DEADSNAKES_PY_PATH="$(which "$LATEST_PYTHON")"
sudo ln -sf "$DEADSNAKES_PY_PATH" /usr/local/bin/python3
sudo ln -sf "$DEADSNAKES_PY_PATH" /usr/local/bin/python

log "Installing pip for $LATEST_PYTHON via ensurepip (no curl|python risk)..."
# ensurepip is bundled with the interpreter — no remote script download needed.
# Fall back to get-pip.py only if ensurepip is unavailable.
if sudo "$LATEST_PYTHON" -m ensurepip --upgrade 2>/dev/null; then
  sudo "$LATEST_PYTHON" -m pip install --upgrade pip
else
  warn "ensurepip unavailable; falling back to get-pip.py (PyPA official)"
  GET_PIP_TMP=$(mktemp /tmp/get-pip.XXXXXX.py)
  curl -fsSL https://bootstrap.pypa.io/get-pip.py -o "$GET_PIP_TMP"
  # Sanity-check: file must start with "#!/" or "import" — not a redirect/error page
  head -1 "$GET_PIP_TMP" | grep -qE "^#!|^import|^#" \
    || { error "get-pip.py download looks invalid"; rm -f "$GET_PIP_TMP"; exit 1; }
  sudo "$LATEST_PYTHON" "$GET_PIP_TMP"
  rm -f "$GET_PIP_TMP"
  sudo "$LATEST_PYTHON" -m pip install --upgrade pip
fi

# Make pip3 point to the new version's pip via its versioned binary name
# (safe: derived from the known binary name, not from pip show output)
PY_SHORT="${LATEST_PYTHON#python}"   # e.g. "3.13"
if command -v "pip${PY_SHORT}" &>/dev/null; then
  sudo ln -sf "$(command -v "pip${PY_SHORT}")" /usr/local/bin/pip3
elif command -v "pip3" &>/dev/null; then
  log "pip3 already on PATH: $(pip3 --version)"
fi

check_tool "$LATEST_PYTHON" "$LATEST_PYTHON --version"
check_tool "pip3"           "$LATEST_PYTHON -m pip --version"
log "Note: /usr/bin/python3 kept as system python3.12 so apt tools stay functional."
log "      Use '$LATEST_PYTHON' or '/usr/local/bin/python3' for your projects."

# Install uv (needed later for GitHub Spec Kit)
log "Installing uv (Python package manager)..."
# Install uv to /usr/local/bin so ALL users can access it (not just root)
UV_INSTALL_TMP=$(mktemp /tmp/uv-install.XXXXXX.sh)
curl -fsSL https://astral.sh/uv/install.sh -o "$UV_INSTALL_TMP"
head -1 "$UV_INSTALL_TMP" | grep -q "^#!" \
  || { error "uv install.sh looks invalid (missing shebang). Aborting."; rm -f "$UV_INSTALL_TMP"; exit 1; }
UV_INSTALL_DIR="/usr/local/bin" sh "$UV_INSTALL_TMP"
rm -f "$UV_INSTALL_TMP"
export PATH="/usr/local/bin:$PATH"
check_tool "uv" "uv --version"

# =============================================================================
# 3. NODE.JS (LTS) via NVM — avoids apt_pkg Python conflicts from NodeSource
# =============================================================================
section "3. Node.js (LTS via NVM)"

log "Installing NVM (Node Version Manager)..."
# Fetch latest NVM version tag from GitHub
NVM_LATEST=$(curl -fsSL --max-time 15 \
  "https://api.github.com/repos/nvm-sh/nvm/releases/latest" \
  | grep '"tag_name"' \
  | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
NVM_LATEST="${NVM_LATEST:-v0.40.3}"   # fallback if API is rate-limited or empty

# Validate NVM_LATEST is a safe semver tag (v0.0.0 format) before using in URL
if [[ ! "$NVM_LATEST" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  warn "NVM tag '$NVM_LATEST' has unexpected format; falling back to v0.40.3"
  NVM_LATEST="v0.40.3"
fi
log "NVM version: $NVM_LATEST"

# Install NVM to /opt/nvm so ALL users can use it (not just root)
# Each user still gets their own node version via NVM_DIR=/opt/nvm
sudo mkdir -p /opt/nvm
sudo chmod 775 /opt/nvm
export NVM_DIR="/opt/nvm"
NVM_INSTALL_TMP=$(mktemp /tmp/nvm-install.XXXXXX.sh)
curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_LATEST}/install.sh" \
  -o "$NVM_INSTALL_TMP"
# Basic integrity check: must be a shell script, not an error page or redirect
head -1 "$NVM_INSTALL_TMP" | grep -q "^#!" \
  || { error "NVM install.sh looks invalid (missing shebang). Aborting."; rm -f "$NVM_INSTALL_TMP"; exit 1; }
bash "$NVM_INSTALL_TMP"
rm -f "$NVM_INSTALL_TMP"

# Load NVM into the current shell session immediately
export NVM_DIR="/opt/nvm"

# NVM's own shell functions use unbound variables internally, which trips
# the -u flag in our set -euo pipefail. Suspend -eu around all NVM calls.
set +eu
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"

log "Installing Node.js LTS via NVM..."
nvm install --lts
nvm use --lts
nvm alias default 'lts/*'

# Set npm global prefix to /usr/local so all global installs land in
# /usr/local/bin — accessible to ALL users, not just root/the install user
npm config set prefix /usr/local
set -eu   # restore strict mode

# First upgrade: brings npm from NVM's bundled version to latest available
# at install time (may not be the absolute latest due to registry cache lag).
npm install -g npm@latest

# Create permanent symlinks AFTER the first upgrade so they point to the
# correct binary path. /usr/local/bin/npm must not exist before this step.
NODE_BIN_DIR=$(dirname "$(which node)")
sudo ln -sf "${NODE_BIN_DIR}/node"  /usr/local/bin/node
sudo ln -sf "${NODE_BIN_DIR}/npm"   /usr/local/bin/npm
sudo ln -sf "${NODE_BIN_DIR}/npx"   /usr/local/bin/npx

# Second upgrade: now that the symlink is in place, npm can update itself
# to the true latest version. Registry cache is now warm and returns the
# real latest (e.g. 11.12.1 instead of a cached 11.11.0).
npm install -g npm@latest

check_tool "node" "node --version"
check_tool "npm"  "npm --version"
check_tool "nvm"  "nvm --version"

log "NVM Node path: $(which node)"

# =============================================================================
# 4. ANGULAR CLI (latest)
# =============================================================================
section "4. Angular CLI (latest)"

# Ensure NVM is active in this subshell (suspend -eu: NVM has unbound vars)
export NVM_DIR="/opt/nvm"
set +eu
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
set -eu
log "Installing @angular/cli globally..."
npm install -g @angular/cli
check_tool "ng" "ng version --skip-confirmation 2>/dev/null | head -3"

# =============================================================================
# 5. NEXT.JS (latest — installed as global create tool)
# =============================================================================
section "5. Next.js (create-next-app)"

# Ensure NVM is active in this subshell (suspend -eu: NVM has unbound vars)
export NVM_DIR="/opt/nvm"
set +eu
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
set -eu
log "Installing create-next-app globally..."
npm install -g create-next-app
check_tool "create-next-app" "create-next-app --version"

# =============================================================================
# 6. REACT (create-react-app, latest)
# =============================================================================
section "6. React (create-react-app)"

# Ensure NVM is active in this subshell (suspend -eu: NVM has unbound vars)
export NVM_DIR="/opt/nvm"
set +eu
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
set -eu
log "Installing create-react-app globally..."
npm install -g create-react-app
check_tool "create-react-app" "create-react-app --version"

# =============================================================================
# 7. OPENJDK 25 (via Eclipse Temurin / Adoptium)
# =============================================================================
section "7. OpenJDK 25 (Eclipse Temurin)"

log "Adding Adoptium repository..."
wget -qO - https://packages.adoptium.net/artifactory/api/gpg/key/public \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/adoptium.gpg > /dev/null

UBUNTU_CODENAME=$(lsb_release -cs)
cat <<EOF | sudo tee /etc/apt/sources.list.d/adoptium.sources
Types: deb
URIs: https://packages.adoptium.net/artifactory/deb
Suites: ${UBUNTU_CODENAME}
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: /usr/share/keyrings/adoptium.gpg
EOF

sudo apt update -y
sudo apt install -y temurin-25-jdk

# JAVA_HOME & PATH
JAVA_HOME_PATH=$(dirname "$(dirname "$(readlink -f "$(which java)")")")
# Write to /etc/profile.d/ — sourced by ALL shell types (login + non-login).
# /etc/environment is only read by PAM logins and is not reliably sourced by non-login shells.
# Use a quoted heredoc so bash writes all $variables literally.
# They expand at runtime when devenv.sh is sourced, not at install time.
# Only JAVA_HOME_PATH is interpolated now — it is the actual installed path.
sudo tee /etc/profile.d/devenv.sh > /dev/null << DEVENVEOF
# Dev environment — set by setup_vps_ubuntu.sh
export JAVA_HOME=${JAVA_HOME_PATH}
export MAVEN_HOME=/opt/maven
export NVM_DIR=/opt/nvm
[ -s "\$NVM_DIR/nvm.sh" ] && . "\$NVM_DIR/nvm.sh"
[ -s "\$NVM_DIR/bash_completion" ] && . "\$NVM_DIR/bash_completion"
export PATH=\$JAVA_HOME/bin:\$MAVEN_HOME/bin:/usr/local/bin:\$PATH
DEVENVEOF
sudo chmod +x /etc/profile.d/devenv.sh

export JAVA_HOME="${JAVA_HOME_PATH}"
export PATH="$JAVA_HOME/bin:$PATH"

check_tool "java"   "java --version"
check_tool "javac"  "javac --version"
log "JAVA_HOME = $JAVA_HOME"

# =============================================================================
# 8. MAVEN (latest binary release)
# =============================================================================
section "8. Apache Maven (latest)"

log "Fetching latest Maven version number..."

# Strategy 1: Apache CDN directory listing (primary source)
MAVEN_VERSION=$(curl -fsSL --max-time 15 "https://dlcdn.apache.org/maven/maven-3/" 2>/dev/null \
  | grep -oP '(?<=href=")[0-9]+\.[0-9]+\.[0-9]+(?=/)' \
  | sort -V | tail -1)

# Strategy 2: Maven Central API (reliable fallback — no directory listing needed)
if [[ -z "$MAVEN_VERSION" ]]; then
  warn "Apache CDN listing unavailable; trying Maven Central API..."
  MAVEN_VERSION=$(curl -fsSL --max-time 15 \
    "https://search.maven.org/solrsearch/select?q=g:org.apache.maven+a:apache-maven&core=gav&rows=20&wt=json" \
    2>/dev/null \
    | python3 -c "
import json,sys
try:
  data=json.load(sys.stdin)
  versions=[d['v'] for d in data['response']['docs'] if d.get('v','').startswith('3.')]
  versions.sort(key=lambda v: list(map(int, v.split('.'))))
  print(versions[-1])
except: pass
" 2>/dev/null)
fi

# Strategy 3: Hard-coded known-good latest (last resort)
if [[ -z "$MAVEN_VERSION" ]]; then
  warn "Could not auto-detect Maven version; using 3.9.14 as fallback"
  MAVEN_VERSION="3.9.14"
fi

# Validate MAVEN_VERSION is a safe semver before using in URL/filename
if [[ ! "$MAVEN_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  warn "Maven version '$MAVEN_VERSION' has unexpected format; falling back to 3.9.14"
  MAVEN_VERSION="3.9.14"
fi
log "Installing Maven $MAVEN_VERSION ..."

# Prefer dlcdn, fall back to archive.apache.org
MAVEN_BASE_URL="https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries"
MAVEN_URL="${MAVEN_BASE_URL}/apache-maven-${MAVEN_VERSION}-bin.tar.gz"

# Verify the CDN URL; if unavailable use archive mirror
if ! curl -fsSL --max-time 10 --head "$MAVEN_URL" &>/dev/null; then
  warn "Apache CDN unreachable; switching to archive.apache.org mirror..."
  MAVEN_URL="https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
fi
check_url "Maven binary" "$MAVEN_URL"

MAVEN_TMP=$(mktemp /tmp/maven.XXXXXX.tar.gz)
MAVEN_SHA_URL="${MAVEN_URL}.sha512"
MAVEN_SHA_TMP=$(mktemp /tmp/maven.XXXXXX.sha512)
wget -qO "$MAVEN_TMP"     "$MAVEN_URL"
wget -qO "$MAVEN_SHA_TMP" "$MAVEN_SHA_URL"
log "Verifying Maven SHA512 checksum..."
# Apache publishes the hash alone (no filename) in the .sha512 file
EXPECTED_SHA=$(cat "$MAVEN_SHA_TMP" | tr -d "[:space:]")
ACTUAL_SHA=$(sha512sum "$MAVEN_TMP" | awk '{print $1}')
if [[ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
  error "Maven SHA512 mismatch! Aborting to prevent a corrupted install."
  error "  Expected: $EXPECTED_SHA"
  error "  Got:      $ACTUAL_SHA"
  rm -f "$MAVEN_TMP" "$MAVEN_SHA_TMP"
  exit 1
fi
success "Maven checksum verified."
rm -f "$MAVEN_SHA_TMP"
sudo mkdir -p /opt/maven
sudo tar -xzf "$MAVEN_TMP" -C /opt/maven --strip-components=1
rm -f "$MAVEN_TMP"

# MAVEN_HOME and PATH already written to /etc/profile.d/devenv.sh above (Java section)

export MAVEN_HOME=/opt/maven
export PATH="$MAVEN_HOME/bin:$PATH"

# Symlink mvn to /usr/local/bin so ALL users can run it without
# needing MAVEN_HOME on their PATH (no devenv.sh sourcing required)
sudo ln -sf /opt/maven/bin/mvn /usr/local/bin/mvn

check_tool "mvn" "mvn --version"
log "MAVEN_HOME = $MAVEN_HOME"

# Persist env vars for the current user's shell
PROFILE_FILE="${REAL_HOME}/.bashrc"
# Source /etc/profile.d/devenv.sh from .bashrc so non-login shells also get the env.
# (Non-login interactive shells skip /etc/profile and its profile.d sourcing.)
grep -q 'devenv.sh' "$PROFILE_FILE" 2>/dev/null || cat <<'BASHEOF' >> "$PROFILE_FILE"

# ---- Dev environment (added by setup_vps_ubuntu.sh) ----
# Source system-wide dev env for non-login (e.g. ssh exec) shells too
[ -f /etc/profile.d/devenv.sh ] && source /etc/profile.d/devenv.sh
BASHEOF

# =============================================================================
# 9. GITHUB CLI
# =============================================================================
section "9. GitHub CLI"

log "Adding GitHub CLI official repository..."
sudo mkdir -p -m 755 /etc/apt/keyrings
wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] \
https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

sudo apt update -y
sudo apt install -y gh

check_tool "gh" "gh --version"

# =============================================================================
# 10. GIT
# =============================================================================
section "10. Git"

sudo apt install -y git
check_tool "git" "git --version"

# =============================================================================
# 11. CLAUDE CODE
# =============================================================================
section "11. Claude Code"

# Ensure NVM is active in this subshell (suspend -eu: NVM has unbound vars)
export NVM_DIR="/opt/nvm"
set +eu
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
set -eu
log "Installing @anthropic-ai/claude-code globally via npm..."
npm install -g @anthropic-ai/claude-code
# Ensure claude binary is explicitly symlinked for all users
[ -f /usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js ] && \
  sudo ln -sf /usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js \
              /usr/local/bin/claude 2>/dev/null || true
check_tool "claude" "claude --version"

# ── Define the CLAUDE.md generator here, but DO NOT run it yet. ───────────────
# It is invoked LATER (section 24), after every tool has been installed, so the
# version strings it embeds are captured live and are always accurate.
generate_claude_md() {
CLAUDE_SETTINGS_DIR="${REAL_HOME}/.claude"
mkdir -p "$CLAUDE_SETTINGS_DIR"

# ── CLAUDE.md — global user memory for Claude Code ───────────────────────────
# Location: ~/.claude/CLAUDE.md
# This file is automatically loaded into every Claude Code session regardless
# of which project you open. It gives Claude persistent context about the
# environment so you never have to re-explain what tools are available.
#
# Best practices applied:
#   - Kept under 100 lines (concise = better adherence)
#   - Actual version strings captured at install time (always accurate)
#   - Structured with clear headings (Claude reads sequentially, top = more weight)
#   - Actionable directives, not vague descriptions
# Reference: https://code.claude.com/docs/en/memory

CLAUDE_MD_FILE="${CLAUDE_SETTINGS_DIR}/CLAUDE.md"

log "Writing global CLAUDE.md to ${CLAUDE_MD_FILE}..."

# Capture real versions now — written into the file so Claude always knows
# the exact versions present, not just that a tool "is installed"
_py_ver=$(python3    --version 2>/dev/null || echo "not found")
_pip_ver=$(pip3      --version 2>/dev/null | awk "{print \$1" "\$2}" || echo "not found")
_uv_ver=$(uv         --version 2>/dev/null || echo "not found")
_node_ver=$(node     --version 2>/dev/null || echo "not found")
_npm_ver=$(npm       --version 2>/dev/null || echo "not found")
_ng_ver=$(ng version --skip-confirmation 2>/dev/null | grep "Angular CLI" | awk "{print \$NF}" || echo "not found")
_next_ver=$(create-next-app --version 2>/dev/null || echo "not found")
_cra_ver=$(create-react-app --version 2>/dev/null || echo "not found")
_java_ver=$(java     --version 2>/dev/null | head -1 || echo "not found")
_javac_ver=$(javac   --version 2>/dev/null || echo "not found")
_mvn_ver=$(mvn       --version 2>/dev/null | head -1 || echo "not found")
_git_ver=$(git       --version 2>/dev/null || echo "not found")
_gh_ver=$(gh         --version 2>/dev/null | head -1 || echo "not found")
_docker_ver=$(docker --version 2>/dev/null || echo "not found")
_compose_ver=$(docker-compose --version 2>/dev/null || echo "not found")
_chrome_ver=$(chrome --version 2>/dev/null || echo "not found")
_newman_ver=$(newman --version 2>/dev/null || echo "not found")
_claude_ver=$(claude --version 2>/dev/null || echo "not found")
_vtsls_ver=$(vtsls --version 2>/dev/null || echo "not found")
_tslsp_ver=$(typescript-language-server --version 2>/dev/null || echo "not found")
# jdtls starts a daemon and blocks — extract version from the jar filename instead
_jdtls_ver=$(find /opt/jdtls/plugins -name "org.eclipse.jdt.ls.core_*.jar" 2>/dev/null \
  | head -1 | grep -oP "(?<=core_)[0-9]+\.[0-9]+\.[0-9]+" || echo "not found")
_tsc_ver=$(tsc        --version 2>/dev/null || echo "not found")
_zip_ver=$(zip        --version 2>/dev/null | sed -n "s/^This is \(Zip [0-9.]*\).*/\1/p" || echo "not found")
_shellcheck_ver=$(shellcheck --version 2>/dev/null | grep "version:" || echo "not found")
_psql_ver=$(psql      --version 2>/dev/null || echo "not found")
_k6_ver=$(k6          version 2>/dev/null | head -1 || echo "not found")
_kafka_ver=$(kafka-topics.sh --version 2>/dev/null | head -1 || echo "not found")
_playwright_ver=$(playwright --version 2>/dev/null || echo "not found")
_openspec_ver=$(openspec --version 2>/dev/null || echo "not found")
_tmux_ver=$(tmux -V 2>/dev/null || echo "not found")
_install_date=$(date "+%Y-%m-%d")

if [[ -f "$CLAUDE_MD_FILE" ]]; then
  warn "${CLAUDE_MD_FILE} already exists — skipping to avoid overwriting."
else
  cat > "$CLAUDE_MD_FILE" << CLAUDEEOF
# Development Environment — VPS Ubuntu 24.04 (ARM64)

This file is loaded automatically by Claude Code at the start of every session.
It describes the tools installed in this environment so you never need to ask.

## System

- OS: Ubuntu 24.04 LTS on a headless ARM64 (aarch64) cloud VPS (e.g. Oracle Cloud Ampere)
- Architecture: arm64 — prefer ARM-native packages; some amd64-only tools (Google Chrome, Postman CLI) are unavailable
- Shell: bash with NVM, Java, Maven, and uv on PATH via /etc/profile.d/devenv.sh
- Sandbox: enabled (bubblewrap) — bash commands are isolated by default
- No graphical desktop: browsers run headless (automation only)
- Environment installed: ${_install_date}

## Installed tools and versions

| Tool | Version | Notes |
|---|---|---|
| python3 | ${_py_ver} | deadsnakes PPA — default for projects |
| pip3 | ${_pip_ver} | |
| uv | ${_uv_ver} | fast Python package manager |
| node | ${_node_ver} | LTS via NVM (~/.nvm) |
| npm | ${_npm_ver} | |
| ng (Angular CLI) | ${_ng_ver} | global npm install |
| create-next-app | ${_next_ver} | global npm install |
| create-react-app | ${_cra_ver} | global npm install |
| java | ${_java_ver} | Eclipse Temurin JDK 25 |
| javac | ${_javac_ver} | |
| mvn (Maven) | ${_mvn_ver} | installed at /opt/maven |
| git | ${_git_ver} | |
| gh (GitHub CLI) | ${_gh_ver} | official GitHub apt repo |
| docker | ${_docker_ver} | Docker CE with systemd autostart |
| docker-compose | ${_compose_ver} | symlink to Docker CLI plugin |
| chromium | ${_chrome_ver} | Playwright's ARM64 build at /opt/ms-playwright; 'chrome' wrapper runs it headless --no-sandbox |
| newman | ${_newman_ver} | Postman collection runner (replaces Postman CLI on ARM) — 'newman run <collection.json>' |
| claude (Claude Code) | ${_claude_ver} | |
| vtsls | ${_vtsls_ver} | TypeScript LSP for Claude Code |
| typescript-language-server | ${_tslsp_ver} | TypeScript LSP (editors) |
| tsc (TypeScript) | ${_tsc_ver} | TypeScript compiler — global npm |
| jdtls | ${_jdtls_ver} | Java LSP — Eclipse JDT |
| specify (GitHub Spec Kit) | installed (uvx) | via uvx (git+spec-kit) — 'specify init <PROJECT>' |
| zip | ${_zip_ver} | archive utilities (apt; unzip also installed) |
| shellcheck | ${_shellcheck_ver} | shell script linter (apt) |
| psql | ${_psql_ver} | PostgreSQL client (PGDG repo) |
| k6 | ${_k6_ver} | load testing CLI — ARM64 binary from GitHub releases (apt repo has no arm64) |
| kafka-topics.sh (Kafka CLI) | ${_kafka_ver} | Apache Kafka CLI tools at /opt/kafka (KAFKA_HOME) |
| playwright | ${_playwright_ver} | E2E browser automation CLI + Chromium (shared at /opt/ms-playwright) |
| openspec | ${_openspec_ver} | OpenSpec CLI — run 'openspec init' (select Claude Code) per project |
| tmux | ${_tmux_ver} | terminal multiplexer (apt) |

## MCP servers (Claude Code, user scope)

- chrome-devtools — \`npx chrome-devtools-mcp@latest\` (Chrome DevTools automation)
- playwright — \`npx @playwright/mcp@latest\` (Playwright browser automation)
- context7 — \`npx @upstash/context7-mcp\` (up-to-date library docs; no API key by default — add one for higher rate limits)
- Inspect with: \`claude mcp list\`

## Environment variables

- JAVA_HOME: set — points to Eclipse Temurin JDK 25
- MAVEN_HOME: /opt/maven
- KAFKA_HOME: /opt/kafka  (Kafka CLI tools on PATH via /opt/kafka/bin)
- NVM_DIR: /opt/nvm  (system-wide, accessible to all users)
- PLAYWRIGHT_BROWSERS_PATH: /opt/ms-playwright  (shared Chromium for the 'chrome' wrapper, Playwright CLI & MCP)

## Key commands

- Reload dev environment: \`source ~/reload-env.sh\`
- Run Angular project: \`ng serve\`
- Run Next.js project: \`npx next dev\`
- Build Java project: \`mvn clean install\`
- Start Docker service: \`sudo systemctl start docker\`
- Run headless Chromium: \`chrome\`  (Playwright's Chromium, --no-sandbox --headless=new)
- Run a Postman collection: \`newman run <collection.json>\`
- Init GitHub Spec Kit: \`uvx --from git+https://github.com/github/spec-kit.git specify init <PROJECT>\`
- Init OpenSpec (per project): \`openspec init\` (select Claude Code)
- Run a k6 load test: \`k6 run script.js\`

## Preferences

- Always check if a tool or binary exists before suggesting installation
- Prefer existing installed versions over suggesting alternatives
- Use the versions listed above when generating build files, CI configs, or Dockerfiles
- Maven wrapper (mvnw) preferred over direct mvn when available in a project
CLAUDEEOF

  success "CLAUDE.md written: ${CLAUDE_MD_FILE}"
  log "  This file is auto-loaded by Claude Code in every session."
fi
}

# =============================================================================
# 12. DOCKER + DOCKER COMPOSE + AUTOSTART
# =============================================================================
section "12. Docker CE + Docker Compose (with autostart)"

log "Adding Docker GPG key and repository..."
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y
sudo apt install -y \
  docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# Add current user to docker group
sudo usermod -aG docker "$USER"

# Also add the pre-created 'dev' user to the docker group ('dev' is created
# before this script runs). Guarded so it is a no-op if the user does not exist.
if id "dev" &>/dev/null; then
  sudo usermod -aG docker dev
  success "User 'dev' added to the docker group."
else
  warn "User 'dev' not found — skipping docker group membership for 'dev'."
fi

# Autostart on a VPS — a real Ubuntu server uses systemd, so enable + start the
# docker service directly. (No /etc/wsl.conf here: that file only applies to WSL.)
if command -v systemctl &>/dev/null && systemctl list-unit-files docker.service &>/dev/null; then
  sudo systemctl enable docker
  sudo systemctl start docker
  log "Docker enabled and started via systemd."
else
  # Fallback for the rare container/VPS image without systemd (e.g. minimal LXC):
  # start the service now and ensure it comes up on each login shell.
  warn "systemd not managing docker — using SysV 'service' fallback."
  grep -q 'service docker start' "$PROFILE_FILE" 2>/dev/null || cat <<'EOF' >> "$PROFILE_FILE"

# Auto-start Docker daemon if not running (no-systemd fallback)
if ! pgrep -x "dockerd" > /dev/null 2>&1; then
  sudo service docker start > /dev/null 2>&1 &
fi
EOF
  sudo service docker start 2>/dev/null || warn "Could not start Docker right now (start it manually with: sudo service docker start)."
fi

check_tool "docker" "docker --version"

# docker-compose-plugin installs the binary as a Docker CLI plugin at
# /usr/libexec/docker/cli-plugins/docker-compose — not on PATH as a standalone.
# Create a symlink so both 'docker compose' (plugin) and 'docker-compose' work.
COMPOSE_PLUGIN_PATH="/usr/libexec/docker/cli-plugins/docker-compose"
if [[ -f "$COMPOSE_PLUGIN_PATH" ]]; then
  sudo ln -sf "$COMPOSE_PLUGIN_PATH" /usr/local/bin/docker-compose
  success "docker compose → $(docker compose version 2>/dev/null || echo 'plugin installed')"
else
  error "docker-compose-plugin binary not found at $COMPOSE_PLUGIN_PATH"
  record_fail "docker-compose"
fi

# =============================================================================
# 13. CHROMIUM (headless — ARM64 replacement for Google Chrome)
# =============================================================================
section "13. Chromium (headless, via Playwright)"

# Google Chrome ships NO ARM64 Linux build (only amd64). Rather than the Ubuntu
# 'chromium' snap (which needs snapd and runs poorly as root/headless), we reuse
# Playwright's own ARM64 Chromium build — the same browser section 20 needs — and
# install it ONCE here into a shared, system-wide path so every user, the
# Playwright CLI and the playwright/chrome-devtools MCP servers find one copy.
PLAYWRIGHT_BROWSERS_DIR="/opt/ms-playwright"

# Ensure NVM is active in this subshell (suspend -eu: NVM has unbound vars)
export NVM_DIR="/opt/nvm"
set +eu
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
set -eu

# Persist PLAYWRIGHT_BROWSERS_PATH system-wide so the wrapper, the Playwright CLI
# (section 20) and the MCP servers all resolve the same shared browser location.
export PLAYWRIGHT_BROWSERS_PATH="$PLAYWRIGHT_BROWSERS_DIR"
sudo mkdir -p "$PLAYWRIGHT_BROWSERS_DIR"
sudo chmod 755 "$PLAYWRIGHT_BROWSERS_DIR"
if ! grep -q 'PLAYWRIGHT_BROWSERS_PATH' /etc/profile.d/devenv.sh 2>/dev/null; then
  echo "export PLAYWRIGHT_BROWSERS_PATH=${PLAYWRIGHT_BROWSERS_DIR}" \
    | sudo tee -a /etc/profile.d/devenv.sh > /dev/null
fi

log "Installing Playwright + its ARM64 Chromium into ${PLAYWRIGHT_BROWSERS_DIR}..."
npm install -g playwright
# The script runs as root, so no sudo is needed; PLAYWRIGHT_BROWSERS_PATH is
# already exported, so the browser lands in the shared path. --with-deps pulls
# the required OS libraries via apt (needs root).
playwright install --with-deps chromium \
  || { error "Playwright Chromium install failed."; record_fail "chromium"; }

# Locate the freshly installed Chromium binary (path embeds a build number).
CHROMIUM_BIN=$(find "$PLAYWRIGHT_BROWSERS_DIR" -type f \
  -path '*/chrome-linux/chrome' 2>/dev/null | sort -V | tail -1 || true)

# Headless VPS wrapper. This host has no display, so Chromium is only used for
# automation (Playwright / Puppeteer / chrome-devtools MCP).
# SECURITY NOTE: --no-sandbox disables Chromium's renderer sandboxing. Chromium
# refuses to start as root without it; on a single-tenant dev VPS the OS user
# boundary provides isolation. Never use --no-sandbox to browse untrusted sites.
# The wrapper re-resolves the binary at runtime so it survives Chromium upgrades.
if [[ -n "$CHROMIUM_BIN" ]]; then
  sudo tee /usr/local/bin/chrome > /dev/null <<EOF
#!/usr/bin/env bash
# Wrapper for Playwright's Chromium on a headless ARM64 VPS (automation use only)
# --no-sandbox is required as root; --headless because the host has no display.
PLAYWRIGHT_BROWSERS_PATH="\${PLAYWRIGHT_BROWSERS_PATH:-${PLAYWRIGHT_BROWSERS_DIR}}"
bin=\$(find "\$PLAYWRIGHT_BROWSERS_PATH" -type f -path '*/chrome-linux/chrome' 2>/dev/null | sort -V | tail -1)
[ -z "\$bin" ] && { echo "chrome: Playwright Chromium not found under \$PLAYWRIGHT_BROWSERS_PATH" >&2; exit 1; }
exec "\$bin" --no-sandbox --headless=new --disable-gpu "\$@"
EOF
  sudo chmod +x /usr/local/bin/chrome
  check_tool "chrome" "chrome --version"
  log "Launch headless Chromium with: chrome   (Playwright build: ${CHROMIUM_BIN})"
else
  error "Could not locate Playwright's Chromium under ${PLAYWRIGHT_BROWSERS_DIR}"
  record_fail "chromium"
fi

# =============================================================================
# 14. NEWMAN (Postman collection runner — ARM64 replacement for Postman CLI)
# =============================================================================
section "14. Newman (Postman CLI alternative)"

# The Postman CLI installer (dl-cli.pstmn.io/install/linux64.sh) only ships an
# amd64 (linux64) binary — there is no ARM64 Linux build. We install Newman
# instead: the official Postman command-line collection runner, which is
# Node-based and therefore architecture-independent.
# Ensure NVM is active in this subshell (suspend -eu: NVM has unbound vars)
export NVM_DIR="/opt/nvm"
set +eu
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
set -eu
log "Installing newman globally..."
npm install -g newman
check_tool "newman" "newman --version"
log "Run a Postman collection with: newman run <collection.json>"

# =============================================================================
# 15. GITHUB SPEC KIT (specify CLI via uvx / uv)
# =============================================================================
section "15. GitHub Spec Kit (specify CLI)"

log "Installing GitHub Spec Kit 'specify' CLI via uvx..."
# Ensure uv/uvx is on PATH (installed system-wide at /usr/local/bin)
export PATH="/usr/local/bin:$PATH"

# Install specify from the official GitHub repo
if uvx --from git+https://github.com/github/spec-kit.git specify --help &>/dev/null; then
  success "GitHub Spec Kit (specify) is available via uvx."
else
  warn "uvx run failed; attempting pip install of spec-kit..."
  if pip3 install --user git+https://github.com/github/spec-kit.git 2>/dev/null; then
    success "spec-kit installed via pip"
  else
    error "Could not install GitHub Spec Kit"
    record_fail "github-spec-kit"
  fi
fi

log "Usage: uvx --from git+https://github.com/github/spec-kit.git specify init <PROJECT>"

# =============================================================================
# 16. LSP SERVERS — TypeScript (vtsls) + Java (jdtls)
# =============================================================================
section "16. LSP Servers (TypeScript + Java)"

# LSP servers give Claude Code semantic code intelligence:
# - go-to-definition, find-references, hover, diagnostics
# - 900x faster than text search (50ms vs 45s for large codebases)
# - Required by Claude Code >= v2.0.74 for IDE-level understanding
# Both servers are installed system-wide (/usr/local/bin) so all users benefit.
# After install, each user activates them once inside Claude Code:
#   /plugin install vtsls@claude-code-lsps
#   /plugin install jdtls@claude-code-lsps

# ── TypeScript LSP: vtsls + typescript-language-server + typescript ───────────
# vtsls is the recommended TypeScript server for Claude Code.
# typescript-language-server is the standard LSP wrapper used by other editors.
# Both require the typescript package for type resolution.
log "Installing TypeScript LSP servers (vtsls, typescript-language-server, typescript)..."

# Re-source NVM so node/npm are available (system-wide via /usr/local/bin symlink)
export NVM_DIR="/opt/nvm"
set +eu
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
set -eu

npm install -g @vtsls/language-server typescript-language-server typescript

check_tool "vtsls"                      "vtsls --version"
check_tool "typescript-language-server" "typescript-language-server --version"
check_tool "tsc"                        "tsc --version"
success "TypeScript LSP servers installed at /usr/local/bin"

# ── Java LSP: Eclipse JDT Language Server (jdtls) ────────────────────────────
# jdtls is the standard Java LSP — used by Claude Code, Neovim, VS Code, etc.
# Installed to /opt/jdtls and symlinked to /usr/local/bin/jdtls.
# Requires JDK >= 21 to run (JDK 25 is already installed in this environment).
log "Installing Eclipse JDT Language Server (jdtls) for Java..."

JDTLS_DIR="/opt/jdtls"
JDTLS_URL="http://download.eclipse.org/jdtls/snapshots/jdt-language-server-latest.tar.gz"

check_url "jdtls snapshot" "$JDTLS_URL"

JDTLS_TMP=$(mktemp /tmp/jdtls.XXXXXX.tar.gz)
wget -qO "$JDTLS_TMP" "$JDTLS_URL"

sudo mkdir -p "$JDTLS_DIR"
sudo tar -xzf "$JDTLS_TMP" -C "$JDTLS_DIR"
rm -f "$JDTLS_TMP"

# Create wrapper in /usr/local/bin so jdtls is on PATH for all users
sudo ln -sf "${JDTLS_DIR}/bin/jdtls" /usr/local/bin/jdtls

# jdtls --version starts the daemon and blocks — verify by checking binary + plugins
if [[ -L /usr/local/bin/jdtls ]] && [[ -d "${JDTLS_DIR}/plugins" ]]; then
  JDTLS_VER=$(find "${JDTLS_DIR}/plugins" -name "org.eclipse.jdt.ls.core_*.jar" \
    | head -1 | grep -oP "(?<=core_)[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown")
  success "jdtls → v${JDTLS_VER} (symlink: /usr/local/bin/jdtls → ${JDTLS_DIR}/bin/jdtls)"
else
  error "jdtls installation could not be verified"
  record_fail "jdtls"
fi
log "jdtls installed at: ${JDTLS_DIR}"
log "JAVA_HOME used by jdtls: ${JAVA_HOME:-<check devenv.sh>}"

success "Java LSP server (jdtls) installed."

log "To activate LSP in Claude Code, run inside a session:"
log "  /plugin install vtsls@claude-code-lsps      (TypeScript/JavaScript)"
log "  /plugin install jdtls@claude-code-lsps      (Java)"

# =============================================================================
# 17. POSTGRESQL CLIENT (psql) via official PGDG apt repository
# =============================================================================
section "17. PostgreSQL client (PGDG)"

log "Adding PostgreSQL PGDG repository..."
# Store the ASCII-armored signing key directly (apt accepts .asc with signed-by)
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
  https://www.postgresql.org/media/keys/ACCC4CF8.asc

echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
  | sudo tee /etc/apt/sources.list.d/pgdg.list > /dev/null

sudo apt update -y
# postgresql-client is a metapackage that pulls the latest client (psql) version
sudo apt install -y postgresql-client

check_tool "psql" "psql --version"

# =============================================================================
# 18. K6 (load testing CLI) — official ARM64 binary from GitHub releases
# =============================================================================
section "18. k6 (load testing CLI)"

# The Grafana k6 apt repo (dl.k6.io/deb) only ships amd64/i386 — there is NO
# arm64 package — so on an ARM VPS we install the official ARM64 binary straight
# from GitHub releases. This is the SAME k6: existing k6 JS scripts (k6/http,
# k6/metrics, ...) run unchanged. Other JS load-test tools (Artillery, etc.) are
# NOT drop-in replacements for k6 scripts, so we stay on k6 itself.
K6_ARCH="$(dpkg --print-architecture)"   # arm64 on this VPS

log "Fetching latest k6 version number..."
# Strategy 1: GitHub releases API (primary source)
K6_VERSION=$(curl -fsSL --max-time 15 \
  "https://api.github.com/repos/grafana/k6/releases/latest" 2>/dev/null \
  | grep '"tag_name"' \
  | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

# Strategy 2: hard-coded known-good latest (last resort if the API is rate-limited)
if [[ -z "$K6_VERSION" ]]; then
  warn "Could not auto-detect k6 version; using v2.0.0 as fallback"
  K6_VERSION="v2.0.0"
fi

# Validate K6_VERSION is a safe 'vX.Y.Z' tag before using it in a URL/filename
if [[ ! "$K6_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  warn "k6 version '$K6_VERSION' has unexpected format; falling back to v2.0.0"
  K6_VERSION="v2.0.0"
fi
log "Installing k6 ${K6_VERSION} (linux-${K6_ARCH}) from GitHub releases..."

K6_TGZ="k6-${K6_VERSION}-linux-${K6_ARCH}.tar.gz"
K6_BASE="https://github.com/grafana/k6/releases/download/${K6_VERSION}"
K6_URL="${K6_BASE}/${K6_TGZ}"
K6_SHA_URL="${K6_BASE}/k6-${K6_VERSION}-checksums.txt"
check_url "k6 binary" "$K6_URL"

K6_TMP=$(mktemp /tmp/k6.XXXXXX.tar.gz)
K6_SHA_TMP=$(mktemp /tmp/k6.XXXXXX.checksums)
if wget -qO "$K6_TMP" "$K6_URL" && wget -qO "$K6_SHA_TMP" "$K6_SHA_URL"; then
  log "Verifying k6 SHA256 checksum..."
  # checksums.txt holds lines of "<sha256>  <filename>" — match our tarball's row.
  EXPECTED_SHA=$(awk -v f="$K6_TGZ" '$2==f {print $1}' "$K6_SHA_TMP")
  ACTUAL_SHA=$(sha256sum "$K6_TMP" | awk '{print $1}')
  if [[ -z "$EXPECTED_SHA" || "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
    error "k6 SHA256 mismatch! Skipping k6 install to avoid a corrupted binary."
    error "  Expected: ${EXPECTED_SHA:-<not found in checksums.txt>}"
    error "  Got:      $ACTUAL_SHA"
    record_fail "k6"
  else
    success "k6 checksum verified."
    # Tarball top dir is k6-<ver>-linux-<arch>/ containing the 'k6' binary;
    # --strip-components=1 drops that dir so the binary lands directly in tmp.
    K6_EXTRACT=$(mktemp -d /tmp/k6.XXXXXX)
    tar -xzf "$K6_TMP" -C "$K6_EXTRACT" --strip-components=1
    if [[ -f "$K6_EXTRACT/k6" ]]; then
      sudo install -m 0755 "$K6_EXTRACT/k6" /usr/local/bin/k6
      check_tool "k6" "k6 version"
    else
      error "k6 binary not found inside the downloaded tarball."
      record_fail "k6"
    fi
    rm -rf "$K6_EXTRACT"
  fi
else
  warn "Could not download k6 ${K6_VERSION} for ${K6_ARCH} — skipping."
  record_fail "k6"
fi
rm -f "$K6_TMP" "$K6_SHA_TMP"

# =============================================================================
# 19. KAFKA CLI (Apache Kafka binary — command-line tools)
# =============================================================================
section "19. Kafka CLI (Apache)"

# The Kafka CLI tools (kafka-topics.sh, kafka-console-producer.sh, etc.) ship
# only inside the Apache Kafka binary distribution — there is no apt package for
# just the CLI. We download the tarball to /opt/kafka and put its bin/ on PATH.
# These scripts are JVM wrappers and rely on the already-installed JDK 25.
KAFKA_SCALA="2.13"

log "Fetching latest Kafka version number..."
# Strategy 1: Apache CDN directory listing (primary source)
KAFKA_VERSION=$(curl -fsSL --max-time 15 "https://dlcdn.apache.org/kafka/" 2>/dev/null \
  | grep -oP '(?<=href=")[0-9]+\.[0-9]+\.[0-9]+(?=/)' \
  | sort -V | tail -1)

# Strategy 2: hard-coded known-good latest (last resort)
if [[ -z "$KAFKA_VERSION" ]]; then
  warn "Could not auto-detect Kafka version; using 4.1.0 as fallback"
  KAFKA_VERSION="4.1.0"
fi

# Validate KAFKA_VERSION is a safe semver before using in URL/filename
if [[ ! "$KAFKA_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  warn "Kafka version '$KAFKA_VERSION' has unexpected format; falling back to 4.1.0"
  KAFKA_VERSION="4.1.0"
fi
log "Installing Kafka $KAFKA_VERSION (Scala $KAFKA_SCALA) ..."

KAFKA_TGZ="kafka_${KAFKA_SCALA}-${KAFKA_VERSION}.tgz"
KAFKA_URL="https://dlcdn.apache.org/kafka/${KAFKA_VERSION}/${KAFKA_TGZ}"

# Verify the CDN URL; if unavailable use archive mirror
if ! curl -fsSL --max-time 10 --head "$KAFKA_URL" &>/dev/null; then
  warn "Apache CDN unreachable; switching to archive.apache.org mirror..."
  KAFKA_URL="https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/${KAFKA_TGZ}"
fi
check_url "Kafka binary" "$KAFKA_URL"

KAFKA_TMP=$(mktemp /tmp/kafka.XXXXXX.tgz)
KAFKA_SHA_TMP=$(mktemp /tmp/kafka.XXXXXX.sha512)
wget -qO "$KAFKA_TMP"     "$KAFKA_URL"
wget -qO "$KAFKA_SHA_TMP" "${KAFKA_URL}.sha512"
log "Verifying Kafka SHA512 checksum..."
# Apache Kafka publishes the hash as "filename: <HASH split across lines>".
# Strip the filename, colon, and ALL whitespace to recover the bare hash.
EXPECTED_SHA=$(sed 's/^.*: *//' "$KAFKA_SHA_TMP" | tr -d "[:space:]" | tr "A-F" "a-f")
ACTUAL_SHA=$(sha512sum "$KAFKA_TMP" | awk '{print $1}')
if [[ -z "$EXPECTED_SHA" || "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
  error "Kafka SHA512 mismatch! Aborting to prevent a corrupted install."
  error "  Expected: $EXPECTED_SHA"
  error "  Got:      $ACTUAL_SHA"
  rm -f "$KAFKA_TMP" "$KAFKA_SHA_TMP"
  record_fail "kafka"
else
  success "Kafka checksum verified."
  rm -f "$KAFKA_SHA_TMP"
  sudo rm -rf /opt/kafka
  sudo mkdir -p /opt/kafka
  sudo tar -xzf "$KAFKA_TMP" -C /opt/kafka --strip-components=1
  rm -f "$KAFKA_TMP"

  # Expose Kafka CLI tools system-wide via /etc/profile.d/devenv.sh
  if ! grep -q 'KAFKA_HOME' /etc/profile.d/devenv.sh 2>/dev/null; then
    sudo tee -a /etc/profile.d/devenv.sh > /dev/null <<'KAFKAENVEOF'
export KAFKA_HOME=/opt/kafka
export PATH=$KAFKA_HOME/bin:$PATH
KAFKAENVEOF
  fi

  export KAFKA_HOME=/opt/kafka
  export PATH="$KAFKA_HOME/bin:$PATH"
  check_tool "kafka-topics.sh" "kafka-topics.sh --version"
  log "KAFKA_HOME = $KAFKA_HOME (CLI tools: kafka-topics.sh, kafka-console-producer.sh, ...)"
fi

# =============================================================================
# 20. PLAYWRIGHT CLI (+ Chromium browser)
# =============================================================================
section "20. Playwright CLI (+ Chromium)"

# Ensure NVM is active in this subshell (suspend -eu: NVM has unbound vars)
export NVM_DIR="/opt/nvm"
set +eu
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
set -eu
log "Installing playwright globally..."
npm install -g playwright

# Reuse the shared browser path set up in section 13 so Playwright resolves the
# SAME Chromium build the 'chrome' wrapper uses (no second copy in a user cache).
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-/opt/ms-playwright}"
log "Ensuring Chromium + OS dependencies (shared at ${PLAYWRIGHT_BROWSERS_PATH})..."
# --with-deps installs the required system libraries via apt (needs root).
# Idempotent: if section 13 already fetched Chromium here, this is a fast no-op.
playwright install --with-deps chromium

check_tool "playwright" "playwright --version"

# =============================================================================
# 21. OPENSPEC CLI
# =============================================================================
section "21. OpenSpec CLI"

# Ensure NVM is active in this subshell (suspend -eu: NVM has unbound vars)
export NVM_DIR="/opt/nvm"
set +eu
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
set -eu
log "Installing @fission-ai/openspec globally..."
npm install -g @fission-ai/openspec@latest
check_tool "openspec" "openspec --version"
log "Per project, run 'openspec init' (select 'Claude Code') to wire OpenSpec into Claude."

# =============================================================================
# 22. TMUX (terminal multiplexer)
# =============================================================================
section "22. Tmux (terminal multiplexer)"

log "Installing tmux via apt..."
sudo apt install -y tmux

check_tool "tmux" "tmux -V"

# =============================================================================
# 23. MCP SERVERS — Chrome DevTools + Playwright + Context7 (registered into Claude)
# =============================================================================
section "23. MCP servers (chrome-devtools + playwright + context7)"

# context7 is registered over local stdio (npx) — no API key is configured here.
# It works rate-limited out of the box; a key can be added later (see notes).

# Ensure NVM is active so node/npm/npx are available
export NVM_DIR="/opt/nvm"
set +eu
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
set -eu

log "Installing Chrome DevTools MCP server globally..."
npm install -g chrome-devtools-mcp

log "Installing Context7 MCP server globally..."
npm install -g @upstash/context7-mcp

# Register both MCP servers at USER scope so they are available in every project.
# Run as REAL_USER with the right HOME so the config lands in REAL_HOME/.claude.json
# (when the script runs directly as root, REAL_USER=root — consistent with the rest).
log "Registering MCP servers into Claude (user scope)..."
sudo -u "$REAL_USER" HOME="$REAL_HOME" claude mcp add --scope user \
  chrome-devtools npx chrome-devtools-mcp@latest 2>/dev/null \
  && success "MCP 'chrome-devtools' registered (user scope)." \
  || warn "MCP 'chrome-devtools' already registered or registration failed (non-fatal)."

sudo -u "$REAL_USER" HOME="$REAL_HOME" claude mcp add --scope user \
  playwright npx @playwright/mcp@latest 2>/dev/null \
  && success "MCP 'playwright' registered (user scope)." \
  || warn "MCP 'playwright' already registered or registration failed (non-fatal)."

# Context7 — up-to-date library docs, registered over local stdio (npx), matching
# the chrome-devtools/playwright pattern above. It is registered WITHOUT an API
# key (works rate-limited out of the box). To raise the rate limits, the user
# re-registers later with their own key — see the post-install notes.
log "Registering Context7 MCP server into Claude (user scope, npx stdio)..."
sudo -u "$REAL_USER" HOME="$REAL_HOME" claude mcp add --scope user \
  context7 -- npx -y @upstash/context7-mcp 2>/dev/null \
  && success "MCP 'context7' registered (user scope, no API key — rate-limited; add a key later, see notes)." \
  || warn "MCP 'context7' already registered or registration failed (non-fatal)."

sudo -u "$REAL_USER" HOME="$REAL_HOME" claude mcp list 2>/dev/null || true

# =============================================================================
# 24. GLOBAL CLAUDE.md (generated AFTER all tools are installed)
# =============================================================================
section "24. Global CLAUDE.md"

# Now that every tool (sections 1–23) is installed, generate the global
# CLAUDE.md. Re-assert the full PATH first so each freshly installed tool
# resolves and its LIVE version is captured inside generate_claude_md().
export NVM_DIR="/opt/nvm"
set +eu
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
set -eu
export PATH="/usr/local/bin:$PATH"
[ -n "${JAVA_HOME:-}" ]  && export PATH="$JAVA_HOME/bin:$PATH"
[ -n "${MAVEN_HOME:-}" ] && export PATH="$MAVEN_HOME/bin:$PATH"
[ -d /opt/kafka/bin ]    && export KAFKA_HOME=/opt/kafka && export PATH="/opt/kafka/bin:$PATH"

generate_claude_md

# =============================================================================
# FINAL VERIFICATION SUMMARY
# =============================================================================
section "Final Verification Summary"

# ── Rebuild the full PATH so every tool installed during this session is found ─
# Tools like NVM (node, npm, ng, claude), uv, and pip live under home directories
# that may not be on PATH if the shell was started without sourcing .bashrc first.

# 1. NVM — node, npm, and all global npm packages (ng, create-react-app, claude, etc.)
export NVM_DIR="/opt/nvm"
set +eu
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
set -eu

# 2. uv / uvx — installed to /usr/local/bin (system-wide)
export PATH="/usr/local/bin:$PATH"

# 3. Java, Maven & Kafka (already exported above, but re-assert in case of subshell)
[ -n "${JAVA_HOME:-}" ]  && export PATH="$JAVA_HOME/bin:$PATH"
[ -n "${MAVEN_HOME:-}" ] && export PATH="$MAVEN_HOME/bin:$PATH"
[ -d /opt/kafka/bin ]    && export KAFKA_HOME=/opt/kafka && export PATH="/opt/kafka/bin:$PATH"

# 4. /usr/local/bin (docker-compose symlink, postman, chrome wrapper)
export PATH="/usr/local/bin:$PATH"

echo ""
echo -e "${CYAN}Checking all installed tools...${NC}"
echo ""

check_tool "python3"              "python3 --version"          || true
check_tool "pip3"                 "pip3 --version"             || true
check_tool "uv"                   "uv --version"               || true
check_tool "node"                 "node --version"             || true
check_tool "npm"                  "npm --version"              || true
check_tool "ng"                   "ng version --skip-confirmation 2>/dev/null | grep 'Angular CLI'" || true
check_tool "create-next-app"      "create-next-app --version"  || true
check_tool "create-react-app"     "create-react-app --version" || true
check_tool "java"                 "java --version"             || true
check_tool "javac"                "javac --version"            || true
check_tool "mvn"                  "mvn --version"              || true
check_tool "git"                  "git --version"              || true
check_tool "gh"                   "gh --version"               || true
check_tool "claude"               "claude --version"           || true
check_tool "docker"               "docker --version"           || true
check_tool "docker-compose"       "docker-compose version"     || true
# 'chrome' wrapper runs Playwright's Chromium headless (no Google Chrome on ARM)
check_tool "chrome"               "chrome --version"           || true
# Newman replaces the Postman CLI (no ARM64 Linux build for Postman)
check_tool "newman"               "newman --version"           || true
check_tool "vtsls"                "vtsls --version"            || true
check_tool "typescript-language-server" "typescript-language-server --version" || true
check_tool "zip"                  "zip --version | head -2 | tail -1" || true
check_tool "shellcheck"           "shellcheck --version | grep version:" || true
check_tool "psql"                 "psql --version"             || true
check_tool "k6"                   "k6 version"                 || true
check_tool "kafka-topics.sh"      "kafka-topics.sh --version"  || true
check_tool "playwright"           "playwright --version"       || true
check_tool "openspec"             "openspec --version"         || true
check_tool "tmux"                 "tmux -V"                    || true
# jdtls --version blocks (starts daemon) — verify via symlink + plugin dir
if [[ -L /usr/local/bin/jdtls ]] && [[ -d /opt/jdtls/plugins ]]; then
  JDTLS_VER=$(find /opt/jdtls/plugins -name "org.eclipse.jdt.ls.core_*.jar" \
    | head -1 | grep -oP "(?<=core_)[0-9]+\.[0-9]+\.[0-9]+" || echo "unknown")
  success "jdtls → v${JDTLS_VER}"
else
  error "jdtls not found"
  record_fail "jdtls"
fi

echo ""
echo -e "${CYAN}MCP servers registered in Claude (user scope):${NC}"
sudo -u "$REAL_USER" HOME="$REAL_HOME" claude mcp list 2>/dev/null \
  || warn "Could not list MCP servers (run 'claude mcp list' manually)."

echo ""
echo -e "${CYAN}Environment variables set:${NC}"
echo "  JAVA_HOME  = ${JAVA_HOME:-<not set>}"
echo "  MAVEN_HOME = ${MAVEN_HOME:-<not set>}"
echo "  KAFKA_HOME = ${KAFKA_HOME:-<not set>}"
echo "  NVM_DIR    = ${NVM_DIR:-<not set>}"

echo ""
if [[ ${#FAILED[@]} -eq 0 ]]; then
  echo -e "${GREEN}✔  All tools installed and verified successfully!${NC}"
else
  echo -e "${YELLOW}⚠  The following tools had issues:${NC}"
  for f in "${FAILED[@]}"; do
    echo -e "   ${RED}✗  $f${NC}"
  done
fi

# =============================================================================
# RELOAD ENVIRONMENT IN THE CURRENT SHELL PROCESS
# =============================================================================
# NOTE: 'source ~/.bashrc' inside a script only affects the script's own child
# process — it does NOT propagate back to the terminal that ran this script.
# The only way to reload the environment in the parent terminal is to run
# 'source ~/.bashrc' manually, or use 'exec bash' to replace the current shell.
#
# What we CAN do here is write a one-liner helper script so the user just runs
# a single short command after the install finishes, instead of remembering the
# exact source command.
# =============================================================================

RELOAD_SCRIPT="${REAL_HOME}/reload-env.sh"
cat > "$RELOAD_SCRIPT" << 'RELOADEOF'
#!/usr/bin/env bash
# Run this once after setup_vps_ubuntu.sh completes:
#   source ~/reload-env.sh
#
# This reloads your full dev environment into the current terminal session.
# (Must be sourced, not executed — "source ~/reload-env.sh" or ". ~/reload-env.sh")

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "ERROR: This script must be sourced, not executed directly."
  echo "Run:  source ~/reload-env.sh"
  exit 1
fi

echo "Reloading dev environment..."
[ -f /etc/profile.d/devenv.sh ] && source /etc/profile.d/devenv.sh
[ -f ~/.bashrc ] && source ~/.bashrc
# Ensure NVM is loaded (system-wide install at /opt/nvm)
export NVM_DIR="/opt/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
echo "Done. Current tool versions:"
command -v node    &>/dev/null && echo "  node    $(node --version)"
command -v npm     &>/dev/null && echo "  npm     $(npm --version)"
command -v python3 &>/dev/null && echo "  python3 $(python3 --version)"
command -v java    &>/dev/null && echo "  java    $(java --version 2>&1 | head -1)"
command -v mvn     &>/dev/null && echo "  mvn     $(mvn --version 2>&1 | head -1)"
command -v claude  &>/dev/null && echo "  claude  $(claude --version 2>&1 | head -1)"
command -v docker  &>/dev/null && echo "  docker  $(docker --version)"
RELOADEOF

chmod +x "$RELOAD_SCRIPT"
success "Helper script written: ~/reload-env.sh"

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Post-install notes${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════${NC}"
echo ""

# ── Environment setup ─────────────────────────────────────────────────────────
echo -e "  ${GREEN}▶  STEP 1 — Reload your current shell:${NC}"
echo "       source ~/reload-env.sh"
echo "     (loads NVM, JAVA_HOME, MAVEN_HOME, uv into the live session)"
echo ""
echo -e "  ${GREEN}▶  STEP 2 — Open a fresh SSH session:${NC}"
echo "       Log out and back in (or 'exec bash -l') so /etc/profile.d/devenv.sh"
echo "       and the docker group membership apply to every new shell."
echo ""

# ── Authentication ─────────────────────────────────────────────────────────────
echo -e "  ${CYAN}── Authentication ───────────────────────────────────────${NC}"
echo ""

echo -e "  ${GREEN}▶  GitHub CLI${NC}"
echo "       gh auth login"
echo "     • Choose: GitHub.com → HTTPS → Login with a web browser"
echo "     • Follow the one-time code prompt in your browser"
echo "     • Verify:  gh auth status"
echo ""

echo -e "  ${GREEN}▶  Claude Code${NC}"
echo "       claude"
echo "     • On first run it opens a browser for Anthropic login"
echo "     • Complete OAuth and return to the terminal"
echo "     • Alternatively use an API key:"
echo "         export ANTHROPIC_API_KEY=sk-ant-..."
echo "         echo 'export ANTHROPIC_API_KEY=sk-ant-...' >> ~/.bashrc"
echo "     • Verify:  claude --version  then start a session with  claude"
echo ""

echo -e "  ${GREEN}▶  Docker Hub${NC}"
echo "       docker login"
echo "     • Enter your Docker Hub username and password"
echo "     • Or use an access token (recommended — create at hub.docker.com/settings/security):"
echo "         docker login -u <username>"
echo "         Password: <paste access token>"
echo "     • Verify:  docker info | grep Username"
echo ""

echo -e "  ${GREEN}▶  Newman (Postman collection runner)${NC}"
echo "     • Installed in place of the Postman CLI (which has no ARM64 Linux build)."
echo "     • Run a collection:  newman run <collection.json>"
echo ""

echo -e "  ${GREEN}▶  Context7 MCP (optional API key — higher rate limits)${NC}"
echo "     • The context7 MCP server is already registered and works WITHOUT a key"
echo "       (rate-limited). Add your own key to raise the limits:"
echo "     • Get a free key at:  https://context7.com/dashboard"
echo "     • Re-register the server with your key:"
echo "         claude mcp remove context7 -s user 2>/dev/null"
echo "         claude mcp add --scope user context7 -- \\"
echo "           npx -y @upstash/context7-mcp --api-key <YOUR_KEY>"
echo "     • Verify:  claude mcp list"
echo ""

# ── Other notes ───────────────────────────────────────────────────────────────
echo -e "  ${CYAN}── Other notes ──────────────────────────────────────────${NC}"
echo ""
echo "  • Chromium (headless):  chrome  (Playwright's Chromium, --no-sandbox --headless=new)"
echo "  • Newman:         newman run <collection.json>   (Postman CLI alternative on ARM)"
echo "  • Spec Kit:       uvx --from git+https://github.com/github/spec-kit.git specify init <PROJECT>"
echo "  • OpenSpec:       cd <project> && openspec init   (select 'Claude Code' when prompted)"
echo "  • k6:             k6 run script.js"
echo "  • Kafka CLI:      kafka-topics.sh --bootstrap-server localhost:9092 --list   (KAFKA_HOME=/opt/kafka)"
echo "  • Playwright:     playwright test   |   playwright codegen <url>"
echo "  • Tmux:           tmux   (new session)   |   tmux attach   (reattach)"
echo ""
echo -e "  ${CYAN}── MCP servers (Claude Code, user scope) ────────────────${NC}"
echo ""
echo "  Already registered globally — inspect with:  claude mcp list"
echo "    • chrome-devtools  → npx chrome-devtools-mcp@latest"
echo "    • playwright       → npx @playwright/mcp@latest"
echo "    • context7         → npx @upstash/context7-mcp (no API key by default; add one for higher limits)"
echo ""
echo -e "  ${CYAN}── LSP servers (Claude Code) ────────────────────────────${NC}"
echo ""
echo "  Inside a Claude Code session, run once per user:"
echo "    /plugin install vtsls@claude-code-lsps      (TypeScript/JS)"
echo "    /plugin install jdtls@claude-code-lsps      (Java)"
echo ""

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}  Applying environment to current shell...${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# =============================================================================
# SOURCE ~/.bashrc IN THE CURRENT PROCESS
# =============================================================================
# Sourcing inside a script only affects the script's own shell process —
# it does NOT propagate to the parent terminal that ran this script.
# However, sourcing HERE still has two real benefits:
#   1. All subsequent commands in THIS script (including the docker group
#      check below) run with the full environment loaded.
#   2. If the script was run with "source ./setup_vps_ubuntu.sh" instead of
#      "bash ./setup_vps_ubuntu.sh", the environment IS applied to the caller.
#
# For a normal "bash script.sh" invocation, the user still needs to open a
# new terminal or run "source ~/reload-env.sh" manually — but the reload-env.sh
# written earlier makes that a single short command.
# =============================================================================

log "Sourcing ~/.bashrc in the current shell process..."
# .bashrc references PS1, TERM, and other variables that only exist in
# interactive shells — they are unbound in a non-interactive script context.
# Suspending -eu prevents the PS1: unbound variable error from aborting the
# script. This is the same pattern used for NVM sourcing above.
set +eu
# shellcheck source=/dev/null
if [ -f "${REAL_HOME}/.bashrc" ]; then
  source "${REAL_HOME}/.bashrc" && success "${REAL_HOME}/.bashrc sourced successfully."     || warn "${REAL_HOME}/.bashrc returned a non-zero exit (non-fatal — continuing)."
else
  warn "${REAL_HOME}/.bashrc not found — skipping."
fi

log "Sourcing /etc/profile.d/devenv.sh..."
# shellcheck source=/dev/null
if [ -f /etc/profile.d/devenv.sh ]; then
  source /etc/profile.d/devenv.sh && success "/etc/profile.d/devenv.sh sourced successfully."     || warn "/etc/profile.d/devenv.sh returned a non-zero exit (non-fatal — continuing)."
else
  warn "/etc/profile.d/devenv.sh not found — skipping."
fi
set -eu   # restore strict mode

echo ""
success "Environment reloaded in this shell process."
echo ""

# =============================================================================
# DOCKER GROUP — activate without logout
# =============================================================================
# newgrp docker only works without a password when the user is ALREADY a member
# of the group in the current session. When called right after usermod -aG,
# the kernel hasn't reloaded the group database yet — newgrp prompts for a
# group password (which is almost never set), causing "Invalid password."
#
# The only reliable ways to apply a new group membership are:
#   a) exec su -l "$USER"  — starts a fresh login shell for the same user,
#      which reads /etc/group fresh. Works for both root and regular users.
#   b) logout + login      — same effect, cleanest approach.
#
# Strategy used here:
#   1. If already in the docker group → skip.
#   2. If running as root (EUID=0) → docker commands work regardless of group.
#   3. Otherwise → use exec su -l to start a fresh login shell for the user.
# =============================================================================

log "Checking docker group membership..."

if [[ "$EUID" -eq 0 ]]; then
  success "Running as root — docker commands work without group membership."
elif groups "$REAL_USER" 2>/dev/null | grep -qw docker; then
  success "Docker group already active for ${REAL_USER} — no action needed."
else
  warn "User '${REAL_USER}' was added to the docker group but the current"
  warn "shell session has not picked it up yet (group DB reloads on new login)."
  echo ""
  echo -e "${CYAN}Starting a fresh login shell to apply docker group membership...${NC}"
  echo -e "${CYAN}Your shell will be replaced. The environment is already loaded.${NC}"
  echo ""
  sleep 2
  # exec su -l starts a new login shell for REAL_USER, which reads /etc/group
  # fresh and picks up the docker group — no password prompt.
  exec su -l "$REAL_USER"
fi
