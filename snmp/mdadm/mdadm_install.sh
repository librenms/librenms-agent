#!/usr/bin/env bash
#---------------------------------------------------------------------------------------------------------------
#
# Script name : mdadm_install.sh
# Description : Install script for LibreNMS SNMP extension "mdadm"
# Repository  : <https://github.com/librenms/librenms-agent/tree/master/snmp/mdadm>
# Version     : 2.0.0
# Author      : LibreNMS contributors
# License     : MIT
#
# The mdadm agent is a net-snmp pass_persist agent. snmpd launches it, keeps it
# resident, and queries it on demand. There is no cache file, cron job, or
# systemd timer to install.
#---------------------------------------------------------------------------------------------------------------

set -euo pipefail

ID="unknown"
ID_LIKE="unknown"
PKG_FAMILY="unknown"

EXT_NAME="mdadm"
EXT_URL="https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/mdadm/mdadm"
SUDOERS_URL="https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/mdadm/sudoers.d-mdadm"
EXT_BIN="/usr/local/lib/snmpd/${EXT_NAME}"
EXT_CONF_DIR="/etc/snmp/extension"
EXT_CONF="${EXT_CONF_DIR}/${EXT_NAME}.yaml"
SUDOERS_FILE="/etc/sudoers.d/${EXT_NAME}"
SNMP_SNIPPET="/etc/snmp/snmpd.conf.d/librenms.conf"

# pass_persist root OID - MDADM-MIB, enterprise 1.3.6.1.4.1.60652.101
BASE_OID=".1.3.6.1.4.1.60652.101"

SNMPD_MAIN_CONF="/etc/snmp/snmpd.conf"
SNMPD_INCLUDE_DIR_LINE="includeDir /etc/snmp/snmpd.conf.d"

# Optional: disable interactivity for automation
# export AUTO_YES=1
VERBOSE_LOG=${VERBOSE_LOG:-0}

# Logging functions
_date() {
  date +%Y-%m-%d_%H:%M:%S
}

log_verbose() {
  [[ "${VERBOSE_LOG}" -eq 1 ]] || return 0
  echo -e "\033[94m VERBOSE: $*\033[0m"
}

log_info() {
  echo "$( _date ): INFO: $*"
}

log_notice() {
  echo -e "\033[92m$( _date ): NOTICE: $* \033[0m"
}

log_warn() {
  echo -e "\033[93m$( _date ): WARN: $* \033[0m"
}

log_error() {
  echo -e "\033[91m$( _date ): ERROR: $* \033[0m" >&2
}

run_cmd() {
  local -a cmd=("$@")
  log_verbose "Running command: ${cmd[*]}"
  "${cmd[@]}"
}

error() {
  log_error "$*"
  exit 1
}

usage() {
  echo "Usage: $0"
  echo "  Installs the mdadm pass_persist SNMP agent."
  echo "  Set AUTO_YES=1 for non-interactive installs."
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  log_error "This script must be run with sudo or as root"
  exit 1
fi

log_notice "Installing ${EXT_NAME} SNMP extension."

ask_yes_no() {
  if [[ "${AUTO_YES:-}" == "1" ]]; then
    return 0
  fi
  local prompt="$1"
  local answer

  while true; do
    read -rp "$prompt [y/n]: " answer < /dev/tty
    case "${answer,,}" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

is_installed() {
  command -v "$1" >/dev/null 2>&1
}

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  error "Cannot detect OS (missing /etc/os-release)"
fi

case "$ID_LIKE $ID" in

  *debian*|*ubuntu*)
    PKG_FAMILY="deb"
    SNMP_USER="Debian-snmp"
    ;;
  *rhel*|*fedora*|*centos*)
    PKG_FAMILY="rpm"
    SNMP_USER="snmp"
    ;;
  *)
    error "Unsupported distro: ID=$ID ID_LIKE=$ID_LIKE"
    ;;
esac

debian_install() {

  if ! is_installed curl || ! is_installed snmpd || ! is_installed python3 || ! is_installed mdadm; then
    if ask_yes_no "Install dependencies?"; then
      run_cmd apt update
      run_cmd apt install -y curl snmpd ca-certificates python3 mdadm
    else
      log_warn "Skipping dependencies."
    fi
  fi
}

rpm_install() {

  if ! is_installed curl || ! is_installed snmpd || ! is_installed python3 || ! is_installed mdadm; then
    if ask_yes_no "Install dependencies?"; then
      run_cmd dnf install -y curl net-snmp net-snmp-utils ca-certificates python3 mdadm
      run_cmd systemctl enable --now snmpd || true
    else
      log_warn "Skipping dependencies."
    fi
  fi
}

install_deps() {
  case "$PKG_FAMILY" in
    deb)
      debian_install
      ;;
    rpm)
      rpm_install
      ;;
  esac
}

install_deps

if [[ -f "${SNMPD_MAIN_CONF}" ]]; then
  if ! grep -Fqs "${SNMPD_INCLUDE_DIR_LINE}" "${SNMPD_MAIN_CONF}"; then
    log_warn "Missing '${SNMPD_INCLUDE_DIR_LINE}' in ${SNMPD_MAIN_CONF}."
    log_warn "Without it, snmpd may not load ${SNMP_SNIPPET}."

    if ask_yes_no "Append includeDir to ${SNMPD_MAIN_CONF}?"; then
      install -d -m 0755 /etc/snmp/snmpd.conf.d
      cp -a "${SNMPD_MAIN_CONF}" "${SNMPD_MAIN_CONF}.bak.$(date +%Y%m%d%H%M%S)"
      printf '\n%s\n' "${SNMPD_INCLUDE_DIR_LINE}" >> "${SNMPD_MAIN_CONF}"
      log_notice "Appended '${SNMPD_INCLUDE_DIR_LINE}' to ${SNMPD_MAIN_CONF}."
      log_notice "Restart snmpd to apply changes."
    else
      log_warn "Skipping includeDir update."
    fi
  fi
else
  log_warn "${SNMPD_MAIN_CONF} not found; cannot verify includeDir configuration."
fi

install -v -d -m 0755 /usr/local/lib/snmpd
install -v -d -m 0755 "${EXT_CONF_DIR}"
install -v -d -m 0755 /etc/snmp/snmpd.conf.d

log_info "Downloading ${EXT_NAME} agent from ${EXT_URL}..."
curl -fsSL "${EXT_URL}" -o "${EXT_BIN}" || error "Failed to download ${EXT_NAME}"
chmod 0755 "${EXT_BIN}"

if [ ! -f "${EXT_CONF}" ]; then
  log_info "Installing default configuration for ${EXT_NAME}..."
  cat >"${EXT_CONF}" <<EOF
---
# mdadm pass_persist agent configuration
log_level: WARNING

# In-process data refresh interval in seconds.
ttl: 60

# Devices to poll. Empty list discovers all md arrays.
devices: []
EOF
fi

# Sudoers rule lets the unprivileged snmpd user run the two read-only mdadm
# commands the agent needs for full detail.
log_info "Installing sudoers rule to ${SUDOERS_FILE}..."
if curl -fsSL "${SUDOERS_URL}" -o "${SUDOERS_FILE}.tmp"; then
  # Substitute the SNMP user for this distro (template ships with Debian-snmp).
  sed -i "s/^Debian-snmp\b/${SNMP_USER}/" "${SUDOERS_FILE}.tmp"
  if visudo -cf "${SUDOERS_FILE}.tmp" >/dev/null 2>&1; then
    install -m 0440 "${SUDOERS_FILE}.tmp" "${SUDOERS_FILE}"
    rm -f "${SUDOERS_FILE}.tmp"
    log_notice "Installed sudoers rule for ${SNMP_USER}."
  else
    rm -f "${SUDOERS_FILE}.tmp"
    log_warn "Sudoers rule failed validation; skipping. Agent will run with reduced detail."
  fi
else
  log_warn "Failed to download sudoers rule; skipping. Agent will run with reduced detail."
fi

PASS_PERSIST_LINE="pass_persist ${BASE_OID} ${EXT_BIN}"
if [ ! -f "${SNMP_SNIPPET}" ] || ! grep -Fqs "${PASS_PERSIST_LINE}" "${SNMP_SNIPPET}"; then
  printf '%s\n' "${PASS_PERSIST_LINE}" >>"${SNMP_SNIPPET}"
  log_notice "Added pass_persist line to ${SNMP_SNIPPET}."
fi

# Restart snmpd so the pass_persist agent is picked up.
if is_installed systemctl && systemctl is-active --quiet snmpd; then
  if ask_yes_no "Restart snmpd now?"; then
    run_cmd systemctl restart snmpd
    log_notice "snmpd restarted."
  else
    log_warn "Restart snmpd manually to load the agent."
  fi
else
  log_warn "Could not restart snmpd automatically; restart it manually to load the agent."
fi

log_notice "Installed ${EXT_NAME} pass_persist agent."
