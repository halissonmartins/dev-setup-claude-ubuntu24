# Setting up the dev environment on WSL2

Step-by-step guide to provision the AI-assisted development environment described in
the [README](../README.md) on **Ubuntu 24.04 running under WSL2**.

The flow imports a clean Ubuntu 24.04 image into its own WSL distro, creates a `dev`
user, and runs the provisioning script. Everything is repeatable — if anything goes
wrong you can unregister the distro and start over (see [Troubleshooting](#troubleshooting)).

## Prerequisites

- Windows 10/11 with **WSL2** enabled (`wsl --install` if you have never used it).
- A drive with a few GB free for the distro rootfs (this guide uses `D:`).
- The two scripts from this repo: `create_user.sh` and `setup_wsl_ubuntu.sh`.

> [!NOTE]
> All **PowerShell** commands below are run from the repository root on Windows
> (e.g. `D:\dev-setup-claude-ubuntu24`). All **bash** commands run *inside* the
> WSL distro.

## 1. List existing WSL distros

Check which distros are already registered so you don't clobber one.

```powershell
wsl --list --verbose
```

## 2. Download the Ubuntu 24.04 LTS image

Create a `downloads` folder and pull the official WSL rootfs into it.

```powershell
New-Item -ItemType Directory -Force downloads | Out-Null
Invoke-WebRequest `
  -Uri "https://cloud-images.ubuntu.com/wsl/releases/24.04/current/ubuntu-noble-wsl-amd64-24.04lts.rootfs.tar.gz" `
  -OutFile ".\downloads\ubuntu-24.04.tar.gz"
```

## 3. Import the image as a new distro

This creates a distro named `Ubuntu-24` whose virtual disk lives in `.\ubuntu24`.

```powershell
wsl --import Ubuntu-24 ".\ubuntu24" ".\downloads\ubuntu-24.04.tar.gz"
```

## 4. Start the distro

The freshly imported distro logs in as **root** by default — that's expected; we fix
it in step 5.

```powershell
wsl -d Ubuntu-24
```

## 5. Make the repo scripts available inside WSL

The scripts live on your Windows drive, reachable from WSL under `/mnt/`. Copy them
into the Linux home directory so they run from the native filesystem (faster, and free
of Windows line-ending/permission quirks).

```bash
cp /mnt/d/dev-setup-claude-ubuntu24/create_user.sh \
   /mnt/d/dev-setup-claude-ubuntu24/setup_wsl_ubuntu.sh ~/
cd ~
```

> Adjust the source path if your repository lives somewhere other than `D:\dev-setup-claude-ubuntu24`.

## 6. Create the `dev` user

`create_user.sh` creates a `dev` user (password `changeit`) and grants it sudo. Run it
as root (you already are after step 4).

```bash
chmod +x create_user.sh && ./create_user.sh
```

> [!IMPORTANT]
> Change the default password after first login: `passwd dev`.

### 6.1. Set `dev` as the default WSL user

So every new session starts as `dev` instead of root:

```bash
printf '\n[user]\ndefault=dev\n' | sudo tee -a /etc/wsl.conf
```

### 6.2. Restart the distro to apply the default user

Changes to `/etc/wsl.conf` only take effect after a full shutdown.

```powershell
wsl --shutdown
wsl -d Ubuntu-24
```

You should now be logged in as `dev`. Confirm with `whoami`.

## 7. Run the provisioning script

This installs and verifies the entire toolchain (languages, runtimes, Claude Code,
MCP/LSP servers, Docker, etc.). Run it with `sudo` **as the `dev` user** — the script
reads `$SUDO_USER` to install user-scoped tools (NVM, Claude Code, MCP servers) into
`dev`'s home rather than root's.

```bash
chmod +x setup_wsl_ubuntu.sh && sudo ./setup_wsl_ubuntu.sh
```

The run ends with a verification summary that flags any tool that failed to install.

### 7.1. Load the environment into your current shell

The script writes a `~/reload-env.sh` helper that loads NVM, `JAVA_HOME`,
`MAVEN_HOME`, and `uv` into the live session — no need to log out.

```bash
source ~/reload-env.sh
```

### 7.2. Restart WSL once more

A final shutdown ensures the `/etc/wsl.conf` tweaks the script made (systemd,
`appendWindowsPath=false`, drive metadata) and the full `PATH` apply to all future
terminals.

```powershell
wsl --shutdown
wsl -d Ubuntu-24
```

## 8. Authenticate the tools

These require your accounts and are not automated. The script prints the same notes at
the end of its run.

| Tool | Command | Notes |
|---|---|---|
| **GitHub CLI** | `gh auth login` | GitHub.com → HTTPS → login via browser. Verify: `gh auth status` |
| **Claude Code** | `claude` | Opens a browser for Anthropic OAuth on first run. Or `export ANTHROPIC_API_KEY=sk-ant-...` |
| **Docker Hub** | `docker login` | Username + password, or an access token (recommended). Verify: `docker info \| grep Username` |
| **Postman CLI** | `postman login` | Paste your Postman API key. Verify: `postman whoami` |
| **Context7 MCP** | *(optional)* | Works without a key (rate-limited). Add a key from <https://context7.com/dashboard> for higher limits. |

### 8.1. Install the Claude Code LSP servers

Inside a `claude` session, run once per user for semantic code intelligence:

```text
/plugin install vtsls@claude-code-lsps      (TypeScript/JS)
/plugin install jdtls@claude-code-lsps      (Java)
```

Inspect the registered MCP servers with `claude mcp list`.

## Troubleshooting

**Start over from scratch.** Unregister the distro (this deletes its disk and all data)
and repeat from step 3:

```powershell
wsl --unregister Ubuntu-24
```

**Tools "not found" in a new terminal.** Run `source ~/reload-env.sh`, or do a full
`wsl --shutdown` and reopen Ubuntu.

**Script installed tools into root's home.** You ran it as root directly. Re-run it as
the `dev` user with `sudo ./setup_wsl_ubuntu.sh` so `$SUDO_USER` is set correctly.
