# AI-Ready Dev Environment for Ubuntu 24.04

One script to provision a complete, **AI-assisted development environment** on Ubuntu 24.04 — ready to run on a **VPS**, inside **WSL2**, or in a **Docker** container.

The goal is simple: go from a bare Ubuntu 24.04 system to a fully equipped workstation for building **Java, TypeScript/JavaScript, Python, and PostgreSQL** applications with [Claude Code](https://www.anthropic.com/claude-code) — including the LSP and MCP servers that give the AI real, semantic understanding of your code — in a single, repeatable run.

> [!NOTE]
> This README describes **what the project is and what it installs**. For step-by-step
> setup instructions, see **[docs/INSTRUCTION-WSL.md](docs/INSTRUCTION-WSL.md)** (WSL2).

## Why this exists

Setting up a modern, AI-ready dev box by hand is tedious and easy to get wrong: language runtimes, package managers, repository keys, browser dependencies, MCP and LSP servers all have to line up. This project captures that whole process in one idempotent, self-verifying script so you can stand up an identical environment anywhere Ubuntu 24.04 runs.

## Work from anywhere: tmux + remote control

Once the environment is up, you don't have to sit at the same machine where Claude Code runs. Two complementary patterns let you start a session on your VPS and keep driving it from your phone, a browser, or your desktop.

**tmux (persistent sessions you can reattach to)**

The setup installs `tmux`, so any Claude Code session can run inside a long-lived terminal that survives disconnects:

```bash
tmux new -s claude     # start (or: tmux attach -t claude to reattach)
claude                 # run Claude Code inside the tmux session
# detach with Ctrl-b d — the session keeps running on the VPS
```

Because the session lives on the server, you can close your laptop, reconnect later from another device, and `tmux attach -t claude` right back into the same running session.

**Claude remote control (phone or claude.ai/code)**

Pair that persistent session with [Claude Code's remote control](https://www.anthropic.com/claude-code): the session running on your VPS can be handed off to your **phone** or to **[claude.ai/code](https://claude.ai/code)**, so you can monitor progress, answer prompts, and steer the agent from a browser or mobile device while the work executes on the VPS.

**Desktop app over SSH (your PC controlling the remote)**

The **Claude Code desktop app** (on your PC) can connect over **SSH**: point it at `ubuntu@your-vps` and the session runs *there*, using the VPS's environment — the exact toolchain this script installs. Your local app is just the front end "controlling" the remote box.

> [!NOTE]
> **Prerequisite:** `ssh ubuntu@your-vps` must already work from your terminal (key-based login configured) before the desktop app can connect over SSH.

## Target environments

| Target | Notes |
|---|---|
| **VPS** | Any cloud or bare-metal Ubuntu 24.04 server. |
| **WSL2** | Ubuntu 24.04 on Windows. The script tunes `/etc/wsl.conf` (systemd, `appendWindowsPath=false`, drive metadata) and supports Chrome via WSLg. |
| **Docker** | Ubuntu 24.04 base image, for a disposable or reproducible container. |

## What gets installed

Everything is pinned to the **latest available version** at install time and verified afterward, with a final summary reporting any failures.

**Languages & runtimes**
- Python (latest, via the deadsnakes PPA) + `pip` + [`uv`](https://github.com/astral-sh/uv)
- Node.js (LTS, via NVM installed system-wide at `/opt/nvm`) + `npm`
- OpenJDK 25 (Eclipse Temurin) + Apache Maven (latest, checksum-verified)

**Web frameworks & tooling (global)**
- Angular CLI, `create-next-app`, `create-react-app`
- TypeScript compiler (`tsc`)

**AI development**
- **Claude Code** (`@anthropic-ai/claude-code`)
- A generated global `~/.claude/CLAUDE.md` documenting the live, installed tool versions so Claude always knows what's available
- **MCP servers** (registered at user scope): `chrome-devtools`, `playwright`, `context7`
- **LSP servers** for semantic code intelligence: `vtsls` / `typescript-language-server` (TS/JS) and `jdtls` (Java)

**Databases & messaging**
- PostgreSQL client (`psql`, via the official PGDG repo)
- Apache Kafka CLI tools (`/opt/kafka`)

**Testing & automation**
- Playwright CLI + Chromium
- k6 (load testing)
- Postman CLI

**Spec-driven development**
- GitHub Spec Kit (`specify`, via `uvx`)
- OpenSpec CLI

**Containers & browser**
- Docker CE + Compose plugin (with WSL autostart)
- Google Chrome (stable, WSLg-aware)

**Shell & utilities**
- Git, GitHub CLI (`gh`), tmux, zip/unzip, ShellCheck

## Scripts

| Script | Purpose |
|---|---|
| `setup_wsl_ubuntu.sh` | Main provisioning script — installs and verifies every tool above. |
| `create_user.sh` | Creates a `dev` user with sudo privileges (run before the setup script). |

## Getting started

| Target | Guide |
|---|---|
| **WSL2** | [docs/INSTRUCTION-WSL.md](docs/INSTRUCTION-WSL.md) — import Ubuntu 24.04, create the `dev` user, run the setup script, authenticate. |
| **VPS / Docker** | Copy `create_user.sh` and `setup_wsl_ubuntu.sh` to the host, then run `./create_user.sh` (as root) followed by `sudo ./setup_wsl_ubuntu.sh` (as `dev`). |

## Design principles

- **Idempotent & safe** — re-runnable; existing files (like `CLAUDE.md`) are preserved rather than clobbered.
- **Verified downloads** — SHA-512 checksums for Maven and Kafka, shebang sanity checks on installer scripts, and reachability checks on every source URL before use.
- **System-wide installs** — NVM, `uv`, Maven, and global npm binaries land in shared locations (`/opt`, `/usr/local/bin`) so every user gets the same toolchain.
- **Self-documenting** — finishes with a verification summary, post-install authentication steps, and a `~/reload-env.sh` helper to load the environment into your current shell.

## License

See [LICENSE](LICENSE).
