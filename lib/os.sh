#!/usr/bin/env bash
# shellcheck shell=bash
# OS detection, hardware profiling, and package-manager / service abstraction.
# Supports Ubuntu, Debian, AlmaLinux, Rocky, CentOS Stream, RHEL, Oracle Linux, Amazon Linux 2023, and Fedora.

OS_ID=""; OS_VERSION=""; OS_CODENAME=""; OS_PRETTY=""
MEM_MB=0; CPU_COUNT=1; IS_CONTAINER=0
SSH_SERVICE=ssh
ADMIN_GROUP=sudo

is_rhel_family() {
  case "$OS_ID" in
    almalinux|rocky|rhel|centos|ol|amzn|fedora) return 0 ;;
    *) return 1 ;;
  esac
}

detect_os() {
  local os_rel=${NEO_OS_RELEASE:-/etc/os-release}
  if [[ -r $os_rel ]]; then
    OS_ID=$(. "$os_rel" && printf '%s' "${ID:-}")
    OS_VERSION=$(. "$os_rel" && printf '%s' "${VERSION_ID:-}")
    OS_CODENAME=$(. "$os_rel" && printf '%s' "${VERSION_CODENAME:-}")
    OS_PRETTY=$(. "$os_rel" && printf '%s' "${PRETTY_NAME:-$ID}")
  elif [[ -n ${OS_ID:-} ]]; then
    OS_VERSION=${OS_VERSION:-24.04}
    OS_PRETTY=${OS_PRETTY:-"$OS_ID $OS_VERSION"}
  elif (( DRY_RUN )); then
    OS_ID="ubuntu"
    OS_VERSION="24.04"
    OS_CODENAME="noble"
    OS_PRETTY="Ubuntu 24.04 LTS"
  else
    return 1
  fi
  case "$OS_ID" in
    almalinux|rocky|rhel|centos|ol|amzn|fedora)
      SSH_SERVICE=sshd
      ADMIN_GROUP=wheel
      ;;
    *)
      if [[ $OS_ID == ubuntu ]] && [[ $OS_VERSION == 24.04 ]] && command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet ssh.socket 2>/dev/null; then
        SSH_SERVICE=ssh.socket
      else
        SSH_SERVICE=ssh
      fi
      ADMIN_GROUP=sudo
      ;;
  esac
}

# 0 = supported, 1 = untested version, 2 = unsupported distro,
# 3 = end-of-life release.
os_check() {
  case "$OS_ID" in
    ubuntu)
      case "$OS_VERSION" in
        20.04|22.04|24.04) return 0 ;;
        14.04|16.04|18.04) return 3 ;;
        *)                 return 1 ;;
      esac ;;
    debian)
      case "$OS_VERSION" in
        11|12|13) return 0 ;;
        8|9|10)   return 3 ;;
        *)        return 1 ;;
      esac ;;
    almalinux|rocky|centos|rhel|ol)
      case "$OS_VERSION" in
        8|8.*|9|9.*) return 0 ;;
        7|7.*)       return 3 ;;
        *)           return 1 ;;
      esac ;;
    amzn)
      case "$OS_VERSION" in
        2023|2023.*) return 0 ;;
        2)           return 3 ;;
        *)           return 1 ;;
      esac ;;
    fedora)
      case "$OS_VERSION" in
        39|40|41|42) return 0 ;;
        [1-3][0-8])  return 3 ;;
        *)           return 1 ;;
      esac ;;
    *) return 2 ;;
  esac
}

detect_hw() {
  if [[ -r /proc/meminfo ]]; then
    MEM_MB=$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo)
  elif command -v sysctl >/dev/null 2>&1; then
    local bytes
    bytes=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    MEM_MB=$(( bytes / 1024 / 1024 ))
  else
    MEM_MB=1024
  fi
  CPU_COUNT=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
  if command -v systemd-detect-virt >/dev/null 2>&1 && systemd-detect-virt -cq 2>/dev/null; then
    IS_CONTAINER=1
  fi
}

ipv6_ok() {
  [[ -s /proc/net/if_inet6 ]] || return 1
  [[ $(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo 0) == 0 ]]
}

nginx_filter() {
  if ipv6_ok; then cat; else grep -vE '^[[:space:]]*listen[[:space:]]+\[::\]' || true; fi
}

has_systemd() { [[ -d /run/systemd/system ]]; }

is_wsl() { [[ -n ${WSL_DISTRO_NAME:-} ]] || grep -qi microsoft /proc/version 2>/dev/null; }

primary_ip() {
  local ip
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}') || true
  if [[ -z $ip ]]; then ip=$(hostname -I 2>/dev/null | awk '{print $1}') || true; fi
  printf '%s' "${ip:-YOUR_SERVER_IP}"
}

# ------------------------------------------------------------ packages
APT_OPTS=(-o DPkg::Lock::Timeout=120 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
DNF_OPTS=(--setopt=install_weak_deps=False --setopt=timeout=120)

pkg_update() {
  if is_rhel_family; then
    run dnf "${DNF_OPTS[@]}" -y makecache
  else
    run env DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" update
  fi
}

pkg_upgrade() {
  if is_rhel_family; then
    run dnf "${DNF_OPTS[@]}" -y upgrade
  else
    run env DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" -y upgrade
  fi
}

pkg_install() {
  if is_rhel_family; then
    run dnf "${DNF_OPTS[@]}" -y install "$@"
  else
    # Ensure apt package list cache exists before installing
    if (( ! DRY_RUN )) && [[ ! -d /var/lib/apt/lists || -z "$(ls -A /var/lib/apt/lists 2>/dev/null | grep -v 'lock\|partial' || true)" ]]; then
      pkg_update
    fi
    if ! run env DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" -y install "$@"; then
      (( DRY_RUN )) && return 0
      # Stale cache or missing package index: refresh lists and retry once
      pkg_update
      run env DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" -y install "$@"
    fi
  fi
}

pkg_installed() {
  if is_rhel_family; then
    rpm -q "$1" >/dev/null 2>&1
  else
    dpkg -s "$1" >/dev/null 2>&1
  fi
}

pkg_name() {
  if is_rhel_family; then
    case "$1" in
      apache2)                    echo httpd ;;
      mysql-server)               echo mysql-server ;;
      postgresql-contrib)         echo postgresql-contrib ;;
      python3-pip)                echo python3-pip ;;
      python3-venv)               echo python3 ;;
      python3-dev)                echo python3-devel ;;
      build-essential)            echo gcc gcc-c++ make ;;
      ufw)                        echo firewalld ;;
      unattended-upgrades)        echo dnf-automatic ;;
      lsb-release)                echo redhat-lsb-core ;;
      software-properties-common) echo dnf-plugins-core ;;
      sudo)                       echo sudo ;;
      openssl)                    echo openssl ;;
      ca-certificates)            echo ca-certificates ;;
      *)                          echo "$1" ;;
    esac
  else
    echo "$1"
  fi
}

pkg_install_mapped() {
  local p out=()
  # Word splitting intentional: pkg_name may map one name to multiple packages.
  # shellcheck disable=SC2207
  for p in "$@"; do out+=($(pkg_name "$p")); done
  pkg_install "${out[@]}"
}

# ------------------------------------------------------------ services
svc_enable_now() { run systemctl enable --now "$1"; }
svc_restart()    { run systemctl restart "$1"; }
svc_reload()     { run systemctl reload "$1"; }

detect_ssh_port() {
  local p
  p=$(sshd -T 2>/dev/null | awk '$1=="port"{print $2; exit}') || true
  printf '%s' "${p:-22}"
}
