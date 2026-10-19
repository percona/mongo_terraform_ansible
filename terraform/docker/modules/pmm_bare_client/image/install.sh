#!/bin/sh
set -eu

if command -v apt-get >/dev/null; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg2 lsb-release iproute2 procps python3 python3-venv systemd systemd-sysv
    curl -fsSL -o /tmp/percona-release.deb https://repo.percona.com/apt/percona-release_latest.generic_all.deb
    apt-get install -y /tmp/percona-release.deb
    percona-release enable pmm3-client "$PMM_CLIENT_REPO"
    apt-get update
    apt-get install -y "pmm-client${PMM_CLIENT_VERSION:+=$PMM_CLIENT_VERSION*}"
    rm -rf /tmp/percona-release.deb /var/lib/apt/lists/*
else
    dnf install -y ca-certificates iproute procps-ng python3 systemd
    command -v curl >/dev/null || dnf install -y curl-minimal
    dnf install -y https://repo.percona.com/yum/percona-release-latest.noarch.rpm
    percona-release enable pmm3-client "$PMM_CLIENT_REPO"
    dnf install -y "pmm-client${PMM_CLIENT_VERSION:+-$PMM_CLIENT_VERSION}"
    dnf clean all
fi

systemctl enable pmm-agent.service pmm-agent-register.service
