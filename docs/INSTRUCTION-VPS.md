# Setting up the dev environment on a VPS

Step-by-step guide to provision the AI-assisted development environment described in
the [README](../README.md) on a **headless Ubuntu 24.04 cloud VPS** (e.g. an ARM64
Oracle Cloud Ampere A1 instance).

The flow copies the provisioning script to the VPS over SSH, makes it executable, runs
it, and reboots once so every tweak takes effect. The script is idempotent — if
anything goes wrong you can simply re-run it (see [Troubleshooting](#troubleshooting)).

## Prerequisites

- A running **Ubuntu 24.04** VPS you can reach over SSH (this guide assumes the default
  cloud user is `ubuntu`).
- The SSH private key for the instance (e.g. `ssh-your-key.key`) on your local machine.
- The provisioning script from this repo: `setup_vps_ubuntu.sh`.

> [!NOTE]
> Replace `<vps-ip>` with your instance's public IP (or hostname) and
> `ssh-your-key.key` with the path to your private key in every command below.
> The `scp`/`ssh` commands run on your **local machine**; everything else runs
> **inside the VPS** over SSH.

## 1. Copy the script to the VPS

From the repository root on your local machine, copy the shell script into the
`ubuntu` user's home directory:

```bash
scp -i "ssh-your-key.key" "./setup_vps_ubuntu.sh" ubuntu@<vps-ip>:/home/ubuntu/
```

> On Windows PowerShell the same command works with backslash paths:
> `scp -i "ssh-your-key.key" ".\setup_vps_ubuntu.sh" ubuntu@<vps-ip>:/home/ubuntu/`

## 2. Connect to the VPS

```bash
ssh -i "ssh-your-key.key" ubuntu@<vps-ip>
```

## 3. Make the script executable

```bash
sudo chmod +x setup_vps_ubuntu.sh
```

## 4. Run the provisioning script

This installs and verifies the entire toolchain (languages, runtimes, Claude Code,
MCP/LSP servers, Docker, etc.). Run it with `sudo` **as the `ubuntu` user** — the
script reads `$SUDO_USER` to install user-scoped tools (NVM, Claude Code, MCP servers)
into `ubuntu`'s home rather than root's.

```bash
sudo ./setup_vps_ubuntu.sh
```

The run ends with a verification summary that flags any tool that failed to install.

> [!NOTE]
> This is the ARM64 / headless variant of the setup. Google Chrome and the Postman CLI
> are **not** installed (no ARM64 Linux build) — the script uses Playwright's Chromium
> and Newman instead.

### 4.1. Load the environment into your current shell

The script writes a `~/reload-env.sh` helper that loads NVM, `JAVA_HOME`,
`MAVEN_HOME`, and `uv` into the live session — no need to log out.

```bash
source ~/reload-env.sh
```

## 5. Restart the instance

Reboot the VPS so group membership (e.g. `docker`) and every `PATH`/environment tweak
apply to all future sessions.

```bash
sudo reboot
```

Your SSH connection will drop; wait a few seconds and reconnect:

```bash
ssh -i "ssh-your-key.key" ubuntu@<vps-ip>
```

## 6. Authenticate the tools

These require your accounts and are not automated. The script prints the same notes at
the end of its run.

| Tool | Command | Notes |
|---|---|---|
| **GitHub CLI** | `gh auth login` | GitHub.com → HTTPS → login via browser. Verify: `gh auth status` |
| **Claude Code** | `claude` | Opens a browser for Anthropic OAuth on first run. Or `export ANTHROPIC_API_KEY=sk-ant-...` |
| **Docker Hub** | `docker login` | Username + password, or an access token (recommended). Verify: `docker info \| grep Username` |
| **Context7 MCP** | *(optional)* | Works without a key (rate-limited). Add a key from <https://context7.com/dashboard> for higher limits. |

### 6.1. Install the Claude Code LSP servers

Inside a `claude` session, run once per user for semantic code intelligence:

```text
/plugin install vtsls@claude-code-lsps      (TypeScript/JS)
/plugin install jdtls@claude-code-lsps      (Java)
```

Inspect the registered MCP servers with `claude mcp list`.

## Troubleshooting

**Re-run the script.** It is idempotent — re-running `sudo ./setup_vps_ubuntu.sh`
fixes a partial install and re-verifies every tool.

**Tools "not found" in a new session.** Run `source ~/reload-env.sh`, or log out and
back in so the login shell picks up the full `PATH`.

**Docker permission denied.** The `ubuntu` user is added to the `docker` group, which
only takes effect after a re-login or reboot (step 5).

**Script installed tools into root's home.** You ran it as root directly. Re-run it as
the `ubuntu` user with `sudo ./setup_vps_ubuntu.sh` so `$SUDO_USER` is set correctly.
