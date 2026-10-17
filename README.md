# 🐱 Neo

**Neo** is a production-grade, zero-dependency Linux server setup and management CLI tool written in pure Bash. Neo provisions fresh VPS instances into hardened, production-ready servers with an interactive inline terminal picker or scriptable automated pipelines.

```text
  /\_/\  
 ( o.o )  Neo — Linux Server Manager
  > ^ <   Calm, sturdy, and keeping your VPS purr-fect.
```

---

## ⚡ Quick Start

On a fresh Linux VPS running as root (or with `sudo`):

```bash
curl -fsSL https://raw.githubusercontent.com/parxyws/neo/main/install.sh | sudo bash
```

This installs Neo to `/opt/neo` and symlinks the binary to `/usr/local/bin/neo`.

To run from a cloned repository:

```bash
git clone https://github.com/parxyws/neo.git
cd neo
sudo ./neo.sh
```

---

## 🐾 The Neo Control Center (Hub)

Running `sudo neo` on any interactive terminal launches the **Neo Hub**—a modern, inline control center with zero full-screen takeover or flashing buffers:

```text
? 🐱 Neo Hub — Server management and control center
  (Use arrow keys, Enter to select, q to quit)
  ▸ 🩺 Server Doctor       (Health & security audit)
    📊 Server Status       (Live CPU, RAM, disk & services)
    🌐 Websites            (List, add, or remove sites)
    🗄️  Databases           (PostgreSQL, MySQL / MariaDB)
    🚀 Dokploy PaaS        (Deploy, inspect, or update Dokploy)
    🛠️  Server Setup        (Fresh VPS provisioning wizard)
    ☁️  Cloudflare          (Restore real visitor IPs)
    🔄 Update Neo          (Check for latest release)
    🗑️  Uninstall           (Safely roll back Neo configs)
    🚪 Quit
```

- **Inline Terminal Picker**: Native ANSI arrow-key navigation (`k`/`j`), Spacebar checklist toggles, and Enter confirmation. No `whiptail` or external dependencies required.
- **Categorized Reference**: The "About the options" guide categorizes all 29 features into clean, scannable topics with terminal pager (`less -FRX`) support.

---

## 🐧 Supported Distributions

Neo natively supports both `apt` (Debian family) and `dnf` (Enterprise Linux & Fedora):

| Distribution | Supported Versions | Notes |
|---|---|---|
| **Ubuntu** | `20.04 LTS`, `22.04 LTS`, `24.04 LTS` | Auto-detects `ssh.socket` activation on 24.04 |
| **Debian** | `11` (Bullseye), `12` (Bookworm), `13` (Trixie) | Native package streams & MariaDB defaults |
| **AlmaLinux / Rocky Linux** | `8`, `9` | Full Enterprise Linux hardening & firewalld |
| **CentOS Stream / RHEL / Oracle Linux** | `8`, `9` | `dnf` package mapping & SELinux-aware |
| **Amazon Linux** | `2023` | AWS EC2 cloud-ready defaults |
| **Fedora Server** | `39`, `40`, `41` | Modern stream support |

---

## ✨ Features

- **🛡️ Access & Hardening**:
  - Creates a dedicated non-root admin user (`deploy`) with password or passwordless `sudo`/`wheel` privileges.
  - SSH hardening (`00-neo.conf`): disables password login and root login; supports custom ports.
  - **Anti-Lockout Guard**: Never disables password/root login unless a sudo user with an authorized SSH key is confirmed.
  - Host firewall: UFW (Ubuntu/Debian) or firewalld (Enterprise Linux/Fedora).
  - Fail2ban: SSH brute-force jail with client IP auto-whitelisting.
  - Automatic background security updates (`unattended-upgrades` / `dnf-automatic`) with optional 04:00 AM reboot.

- **🌐 Web Servers & Domains**:
  - **Nginx, Caddy, or Apache**: Standard security headers, 64MB upload limit, gzip/zstd, and friendly catch-all virtual hosts.
  - **Let's Encrypt SSL/TLS**: Automated certificate provisioning with auto-renewal timers (`certbot` or native Caddy).
  - **Site Profiles**: Guided creation for `static`, `spa`, `proxy`, `laravel` (with scheduler timer & queue worker), `php`, `wordpress`, and `redirect`.
  - **Cloudflare**: Real visitor IP restoration (`CF-Connecting-IP`) with automated weekly IP range updates.

- **🗄️ Databases**:
  - **PostgreSQL**: Local socket authentication, SCRAM-SHA-256 encryption, RAM-tuned `shared_buffers` and cache sizes.
  - **MySQL / MariaDB**: RAM-tuned InnoDB buffer pool, secure defaults, root credentials saved in `/root/.my.cnf` (`600`). Automatic MariaDB fallback on Debian.
  - **Redis**: In-memory cache capped at 30% RAM with `allkeys-lru` eviction on localhost.
  - Guided interactive database and dedicated user creation.

- **📦 Containers & PaaS**:
  - **Dokploy PaaS**: One-command deployment of Dokploy on Docker Swarm with Traefik ingress and dashboard on port `3000`.
  - **Docker + Docker Compose**: Official engine via `get.docker.com`. Forces container ports to bind to `127.0.0.1` by default to prevent Docker from bypassing host firewalls.
  - **Podman + podman-compose**: Daemonless, rootless container engine with `loginctl enable-linger` for persistent background containers.

- **⚙️ Runtimes**:
  - PHP-FPM (8.1–8.4) + Composer, Node.js (NodeSource 18/20/22/24), Bun, Go, Python 3 + pip + venv, FrankenPHP.

- **📊 Ops, Backups & Reliability**:
  - Automated nightly database dumps to `/var/backups/neo/db/` via `/usr/local/bin/neo-backup` with retention rotation.
  - Real-time health monitoring via `neo status` and `neo doctor` (`Result: purr-fect!`).
  - Extra Fail2ban jails for Nginx (`http-auth`, `botsearch`, and `bad-request`).

- **🔒 Safe Rollback & Data Preservation**:
  - Backups before changes saved to `/var/backups/neo/`.
  - Web server syntax is strictly tested before reload; automatically reverts on failure.
  - Database drop creates a compressed pre-drop dump and requires typing the database name to confirm.
  - Site deletion moves files to `/var/backups/neo/removed-sites/`, never runs `rm -rf`.
  - Auto-healing package cache: automatically refreshes empty or stale `/var/lib/apt/lists/` on container/minimal hosts.

---

## 💻 CLI Commands

### Core Subcommands

```bash
sudo neo                         # Launch interactive Neo Hub (Control Center)
sudo neo setup [options]         # Server configuration workflow
neo doctor                       # Read-only health & security audit (runs without root)
neo status                       # Real-time server health dashboard (neo-health)
neo site list                    # Inventory of configured websites
sudo neo site add [options]      # Guided domain and SSL creation wizard
sudo neo site remove <domain>    # Safely remove website and back up configs
neo db list                      # Enumerate active PostgreSQL and MySQL databases
sudo neo db create [options]     # Guided database and user creation wizard
sudo neo db drop <name>          # Drop database (auto-dumps backup first)
sudo neo dokploy [setup|status|update] # Install, check, or update Dokploy PaaS
sudo neo cloudflare              # Configure Cloudflare real visitor IP restoration
sudo neo update                  # Update Neo itself to the latest release
sudo neo uninstall [--yes]       # Clean rollback of configurations (preserves packages)
```

### Setup Options

| Option | Description |
|---|---|
| `--preset <name>` | `recommended`, `minimal`, `dokploy`, `domain`, `database`, `cloudflare`, or `custom` |
| `--dry-run` | Preview all actions without modifying the filesystem or system services |
| `-y, --yes` | Non-interactive mode (requires `--preset`) |
| `--ssh-key "KEY"` | Public SSH key for the admin user |
| `--webserver <name>` | `nginx`, `caddy`, or `apache` (default: `nginx`) |

### Site Add Options

| Option | Description |
|---|---|
| `--domain <domain>` | Website domain name (e.g. `app.example.com`) |
| `--site-type <type>` | `static`, `spa`, `proxy`, `laravel`, `php`, `wordpress`, or `redirect` |
| `--port <port>` | Backend app listening port for `--site-type proxy` (default: `3000`) |
| `--redirect-to <url>` | Destination URL for `--site-type redirect` |
| `--app-cmd "CMD"` | Systemd service startup command for proxy apps (e.g. `npm start`) |
| `--hsts` | Enable HTTP Strict Transport Security |
| `--no-workers` | Skip Laravel queue worker and scheduler timer |

### Database Options

| Option | Description |
|---|---|
| `--engine <name>` | Database engine: `postgresql` or `mysql` (default: `postgresql`) |
| `--db <name>` | Database name to create or drop |
| `--db-user <user>` | Database user (defaults to `--db` value) |

---

## 🎯 Presets

- **`recommended`**: Production web server (Base tools, Swap, Admin user, SSH hardening, UFW, Fail2ban, Auto updates, Nginx, Certbot, DB backup, Health monitoring, Nginx jails).
- **`minimal`**: Essential server hardening only (Base tools, Swap, Admin user, SSH hardening, Firewall, Fail2ban).
- **`dokploy`**: Production Docker Swarm PaaS stack with Traefik and dashboard on port 3000.
- **`domain`**: Guided website creation and Let's Encrypt certificate acquisition (`neo site add`).
- **`database`**: Dedicated database and user creation (`neo db create`).
- **`cloudflare`**: Visitor real-IP restoration behind Cloudflare proxy (`neo cloudflare`).

---

## 🐳 Testing with Podman

You can test Neo locally in a real Ubuntu 24.04 container with live `systemd` (PID 1):

```bash
# Start or attach to the Ubuntu 24.04 container with current repository mounted at /neo
./tests/podman-test.sh

# Reset to a fresh, clean Ubuntu container anytime
./tests/podman-test.sh --reset
```

Inside the container:
```bash
cd /neo
./neo.sh doctor                  # Run health checks
./neo.sh setup --preset minimal  # Run provisioning
```

---

## 🧪 Test Harness

Run automated regression and unit tests:

```bash
bash tests/unit.sh        # Validators, hardware profiling, and distro checks
bash tests/cli.sh         # CLI subcommand routing and exit code compliance
bash tests/dry-run.sh     # Syntax, message keys, and full end-to-end dry runs
bash tests/manage.sh      # Hermetic mock tests for site removal & DB drop safeguards
bash tests/templates.sh   # Template linting and placeholder verification
bash tests/secrets.sh     # Secret masking and leak prevention checks
bash tests/features.sh    # Feature registration, WSL detection, and port-80 mappings
```
