#!/usr/bin/env python3

# LibreNMS reboot-required SNMP extend script.
#
# Detects whether the host needs a reboot to apply a pending kernel or
# library update, across multiple distro families. Emits the standard
# LibreNMS JSON app-extend envelope, with "reboot" (1 or 0) in "data".
#
# On an unsupported distro, or when the expected detection tool is
# missing, "error" is set non-zero so LibreNMS surfaces a poll error
# instead of silently reporting "no reboot needed".

import json
import os
import shutil
import subprocess

VERSION = 1

DEBIAN_LIKE = {"debian", "ubuntu"}
RHEL_LIKE = {"rhel", "fedora", "centos", "rocky", "almalinux", "amzn"}
SUSE_LIKE = {"suse"}
ARCH_LIKE = {"arch"}


def parse_os_release():
    ids = set()
    try:
        with open("/etc/os-release") as f:
            for line in f:
                line = line.strip()
                if line.startswith("ID=") or line.startswith("ID_LIKE="):
                    _, value = line.split("=", 1)
                    ids.update(value.strip('"').split())
    except OSError:
        pass
    return ids


def check_reboot_required():
    """Returns (reboot, error, error_string). reboot is None on error."""
    ids = parse_os_release()

    if ids & DEBIAN_LIKE:
        # update-notifier-common/unattended-upgrades create this file.
        reboot = 1 if os.path.isfile("/var/run/reboot-required") else 0
        return reboot, 0, ""

    if ids & RHEL_LIKE:
        # yum-utils/dnf-utils. Exit 1 = reboot required, 0 = not required.
        if shutil.which("needs-restarting") is None:
            return None, 1, "needs-restarting not found"
        result = subprocess.run(
            ["needs-restarting", "-r"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return (1 if result.returncode == 1 else 0), 0, ""

    if ids & SUSE_LIKE:
        # zypper needs-rebooting. Exit 1 = reboot required, 0 = not required.
        if shutil.which("zypper") is None:
            return None, 1, "zypper not found"
        result = subprocess.run(
            ["zypper", "needs-rebooting"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return (1 if result.returncode == 1 else 0), 0, ""

    if ids & ARCH_LIKE:
        # No official tool: a reboot is needed once the running kernel's
        # module directory has been replaced by a newer package upgrade.
        current_kernel = os.uname().release
        reboot = 0 if os.path.isdir("/usr/lib/modules/" + current_kernel) else 1
        return reboot, 0, ""

    return None, 1, "unsupported distro"


def main():
    reboot, error, error_string = check_reboot_required()
    output = {
        "version": VERSION,
        "error": error,
        "errorString": error_string,
        # always a populated dict, even on error -- json_app_get() checks
        # required envelope keys with isset(), which treats a bare `null`
        # value as "not set" and would misroute this into the
        # legacy/malformed-output path instead of the error path.
        "data": {"reboot": reboot},
    }
    print(json.dumps(output))


if __name__ == "__main__":
    main()
