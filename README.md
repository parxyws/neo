# 🐱 Neo

**Neo** is a production-grade, zero-dependency Linux server setup and management CLI tool written in pure Bash. Named after a British Shorthair cat, Neo provisions fresh VPS instances into hardened, production-ready servers with interactive inline terminal pickers or scriptable automated pipelines.

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
  - **Anti-Lockout Guard**: Never disables password/root login unless a sudo user with a valid SSH key is confirmed.
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
  - **MySQL / MariaDB**: RAM-tuned InnoDB buffer pool, secure defaults, root credentials saved in `/root/.my.cnf` (`600`).
  - **Redis**: In-memory cache capped at 30% RAM with `allkeys-lru` eviction.
  - Guided interactive database and dedicated user creation.

- **📦 Containers & PaaS**:
  - **Docker + Docker Compose**: Official engine via `get.docker.com`. Forces container ports to bind to `127.0.0.1` by default to prevent Docker from bypassing the host firewall.
  - **Podman + podman-compose**: Daemonless, rootless container engine with `loginctl enable-linger` for persistent background containers.
  - **Dokploy PaaS**: One-command deployment of Dokploy (Docker Swarm + Traefik) accessible on port `3000`.

- **⚙️ Runtimes**:
  - PHP-FPM (8.1–8.4) + Composer, Node.js (NodeSource 18/20/22/24), Bun, Go, Python 3 + pip + venv, FrankenPHP.

- **📊 Ops, Backups & Reliability**:
  - Automated nightly database dumps to `/var/backups/neo/db/` via `/usr/local/bin/neo-backup` with retention rotation.
  - Real-time health monitoring via `neo status` / `neo doctor` and nightly health snapshots.
  - Extra Fail2ban jails for Nginx (`http-auth`, `botsearch`, and `bad-request`).

- **🔒 Safe Rollback & Data Preservation**:
  - Backups before changes saved to `/var/backups/neo/`.
  - Web server syntax is strictly tested before reload; automatically reverts on failure.
  - Database drop creates a compressed pre-drop dump and requires typing the database name to confirm.
  - Site deletion moves files to `/var/backups/neo/removed-sites/`, never runs `rm -rf`.

---

## 💻 CLI Commands

### Core Subcommands

```bash
sudo neo                         # Launch interactive inline terminal picker
sudo neo setup [options]         # Server configuration workflow
neo doctor                       # Read-only health and security audit (no root needed)
neo status                       # Real-time server health dashboard (neo-health)
neo site list                    # Inventory of configured websites
sudo neo site add [options]      # Guided domain and SSL creation wizard
sudo neo site remove <domain>    # Safely remove website and back up configs
neo db list                      # Enumerate active PostgreSQL and MySQL databases
sudo neo db create [options]     # Guided database and user creation wizard
sudo neo db drop <name>          # Drop database (auto-dumps backup first)
sudo neo dokploy [setup|status|update] # Install or manage Dokploy PaaS
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
- **`domain`**: Guided website creation and Let's Encrypt certificate acquisition.
- **`database`**: Dedicated database and user creation.
- **`cloudflare`**: Visitor real-IP restoration behind Cloudflare proxy.

---

## 🧪 Testing

Neo includes a complete test harness:

```bash
bash tests/unit.sh        # Validators, hardware profiling, and distro checks
bash tests/cli.sh         # CLI subcommand routing and exit code compliance
bash tests/dry-run.sh     # Syntax, message keys, and full end-to-end dry runs
bash tests/manage.sh      # Hermetic mock tests for site removal & DB drop safeguards
bash tests/templates.sh   # Template linting and placeholder verification
bash tests/secrets.sh     # Secret masking and leak prevention checks
bash tests/features.sh    # Feature registration, WSL detection, and port-80 mappings
```

---

## 📄 License

MIT License.
