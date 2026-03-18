#!/usr/bin/env bash
#---------------------------------------------------------------------------------------------------------------
#
# Script name : install.sh
# Description : Install script for LibreNMS SNMP extension "proxmox"
# Repository  : <https://github.com/librenms/librenms-agent>
# Version     : 2.0.0
# Author      : LibreNMS Team
# License     : MIT
#
# Usage:
#   Local:    ./install.sh
#   Remote:    curl -s https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/proxmox/install.sh | bash
#---------------------------------------------------------------------------------------------------------------

set -euo pipefail

EXT_NAME="proxmox"
EXT_BIN="/usr/local/lib/snmpd/${EXT_NAME}"
EXT_CONF_DIR="/etc/snmp/extension"
EXT_CONF="${EXT_CONF_DIR}/${EXT_NAME}.yaml"
EXT_CACHE_DIR="/run/snmp/extension"
EXT_CACHE="${EXT_CACHE_DIR}/${EXT_NAME}.json"
SNMP_SNIPPET="/etc/snmp/snmpd.conf.d/librnms.conf"
SYSTEMD_UNIT_DIR="/etc/systemd/system"
SYSTEMD_UNIT_TIMER="${SYSTEMD_UNIT_DIR}/librenms-snmp-extension@.timer"
SYSTEMD_UNIT_SERVICE="${SYSTEMD_UNIT_DIR}/librenms-snmp-extension@.service"
GITHUB_USER=${GITHUB_USER:-librenms}
GITHUB_BRANCH=${GITHUB_BRANCH:-master}
GITHUB_BASE="https://raw.githubusercontent.com/${GITHUB_USER}/librenms-agent/${GITHUB_BRANCH}"

SNMPD_MAIN_CONF="/etc/snmp/snmpd.conf"
SNMPD_INCLUDE_DIR_LINE="includeDir /etc/snmp/snmpd.conf.d"

REFRESH_METHOD=""
VERBOSE_LOG=${VERBOSE_LOG:-0}

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
    echo "Usage: $0 [--cron|--systemd]"
    echo "  --cron     Force cron-based cache refresh"
    echo "  --systemd  Force systemd-based cache refresh (default)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cron)
            REFRESH_METHOD="cron"
            shift
            ;;
        --systemd)
            REFRESH_METHOD="systemd"
            shift
            ;;
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

is_systemd_available() {
    if command -v systemctl >/dev/null 2>&1 && \
       systemctl is-system-running >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

detect_refresh_method() {
    if [[ -n "${REFRESH_METHOD}" ]]; then
        return
    fi
    if is_systemd_available; then
        REFRESH_METHOD="systemd"
        log_notice "Detected systemd, using timer-based cache refresh."
    else
        REFRESH_METHOD="cron"
        log_notice "No systemd detected, using cron-based cache refresh."
    fi
}

detect_snmp_user() {
    SNMP_USER=$(ps aux | grep -E '[s]nmpd' | awk '{print $1}' | grep -v root | head -1)
    if [[ -z "${SNMP_USER}" ]]; then
        SNMP_USER="snmp"
        log_warn "Could not detect snmpd user, defaulting to '${SNMP_USER}'"
    else
        log_info "Detected snmpd user: ${SNMP_USER}"
    fi
}

install_deps() {
    if ! is_installed curl || ! is_installed snmpd; then
        if ask_yes_no "Install dependencies?"; then
            run_cmd apt update
            run_cmd apt install -y curl snmpd ca-certificates
        else
            log_warn "Skipping dependencies."
        fi
    fi
}

is_remote_install() {
    [[ ! -f "./${EXT_NAME}" && ! -d "../common" ]]
}

download_file() {
    local url="$1"
    local dest="$2"
    log_info "Downloading ${dest}..."
    curl -fsSL "${url}" -o "${dest}" || error "Failed to download ${url}"
}

install_agent() {
    if is_remote_install; then
        download_file "${GITHUB_BASE}/snmp/proxmox/${EXT_NAME}" "${EXT_BIN}"
    else
        install -v -m 0755 "./${EXT_NAME}" "${EXT_BIN}"
    fi
}

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
install -v -d -m 0755 "${EXT_CACHE_DIR}"
install -v -d -m 0755 /etc/snmp/snmpd.conf.d

log_info "Installing ${EXT_NAME} agent..."
install_agent

SUDOERS_FILE="/etc/sudoers.d/librenms-proxmox"
if [ ! -f "${SUDOERS_FILE}" ]; then
    detect_snmp_user
    cat >"${SUDOERS_FILE}" <<'EOF'
# Cmnd alias for Proxmox VE read-only API access
Cmnd_Alias C_PROXMOX = \
  /usr/bin/pvesh get version, \
  /usr/bin/pvesh get /nodes/*/lxc, \
  /usr/bin/pvesh get /nodes/*/qemu, \
  /usr/bin/pvesh get /nodes/*/status, \
  /usr/bin/pvesh get /nodes/*/storage, \
  /usr/bin/pvesh get /nodes/*/netstat, \
  /usr/bin/pvesh get /nodes/*/ceph/status, \
  /usr/bin/pvesh get /nodes/*/subscription, \
  /usr/bin/pvesh get /nodes/*/replication, \
  /usr/bin/pvesh get /cluster/resources, \
  /usr/bin/pvesh get /cluster/status, \
  /usr/bin/pvesh get /cluster/ceph/status, \
  /usr/bin/pvesh get /cluster/ha/status, \
  /usr/bin/pvesh get /cluster/ha/resources, \
  /usr/bin/pvesh get /cluster/ha/groups, \
  /usr/bin/pvesh get /cluster/ha/rules, \
  /usr/bin/pvesh get /cluster/options, \
  /usr/bin/pvesh get /cluster/config/nodes, \
  /usr/bin/pvesh get /cluster/replication, \
  /usr/bin/pvesh get /pools

%SNMP_USER% ALL=NOPASSWD: C_PROXMOX
EOF
    sed -i "s/%SNMP_USER%/${SNMP_USER}/g" "${SUDOERS_FILE}"
    chmod 0440 "${SUDOERS_FILE}"
    log_notice "Created sudoers file for ${SNMP_USER} to run pvesh without password."
fi

if [ ! -f "${EXT_CONF}" ]; then
    log_info "Installing default configuration..."
    cat >"${EXT_CONF}" <<'EOF'
pvesh_path: pvesh
EOF
fi

EXTEND_LINE="extend ${EXT_NAME} /bin/cat ${EXT_CACHE}"
if [ ! -f "${SNMP_SNIPPET}" ] || ! grep -Fqs "${EXTEND_LINE}" "${SNMP_SNIPPET}"; then
    printf '%s\n' "${EXTEND_LINE}" >>"${SNMP_SNIPPET}"
    log_notice "Added extend line to ${SNMP_SNIPPET}."
fi

detect_refresh_method
detect_snmp_user

install_cron() {
    log_info "Installing cron job..."
    CRON_FILE="/etc/cron.d/librenms-snmp-extension-${EXT_NAME}"
    cat >"${CRON_FILE}" <<EOF
PATH=/usr/local/bin:/usr/bin:/bin
*/5 * * * * ${SNMP_USER} /usr/local/lib/snmpd/${EXT_NAME} --config /etc/snmp/extension/${EXT_NAME}.json --output /run/snmp/extension/${EXT_NAME}.json
EOF
    chmod 644 "${CRON_FILE}"
    log_notice "Cron job installed to ${CRON_FILE}."
}

install_systemd() {
    log_info "Installing systemd timer..."

    install -v -d -m 0755 "${SYSTEMD_UNIT_DIR}"

    if [ ! -f "${SYSTEMD_UNIT_SERVICE}" ]; then
        download_file "${GITHUB_BASE}/snmp/common/librenms-snmp-extension@.service" "${SYSTEMD_UNIT_SERVICE}"
    else
        log_info "Systemd service already exists at ${SYSTEMD_UNIT_SERVICE}."
    fi

    if [ ! -f "${SYSTEMD_UNIT_TIMER}" ]; then
        download_file "${GITHUB_BASE}/snmp/common/librenms-snmp-extension@.timer" "${SYSTEMD_UNIT_TIMER}"
    else
        log_info "Systemd timer already exists at ${SYSTEMD_UNIT_TIMER}."
    fi

    OVERRIDE_DIR="${SYSTEMD_UNIT_DIR}/librenms-snmp-extension@.service.d"
    OVERRIDE_FILE="${OVERRIDE_DIR}/override.conf"
    install -v -d -m 0755 "${OVERRIDE_DIR}"

    if [ ! -f "${OVERRIDE_FILE}" ]; then
        cat >"${OVERRIDE_FILE}" <<EOF
[Service]
User=${SNMP_USER}
Group=${SNMP_USER}
EOF
        log_notice "Created override with user ${SNMP_USER} at ${OVERRIDE_FILE}."
    else
        log_info "Override already exists at ${OVERRIDE_FILE}."
    fi

    run_cmd systemctl daemon-reload
    run_cmd systemctl enable --now "librenms-snmp-extension@${EXT_NAME}.timer"
    log_notice "Systemd timer enabled for ${EXT_NAME}."
}

case "${REFRESH_METHOD}" in
    cron)
        install_cron
        ;;
    systemd)
        install_systemd
        ;;
esac

log_notice "Installed ${EXT_NAME} with ${REFRESH_METHOD} cache refresh."
log_notice "Run '${EXT_BIN} --help' for more options."
