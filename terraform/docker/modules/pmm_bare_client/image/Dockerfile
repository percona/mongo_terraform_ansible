# A plain OS with systemd as PID 1 and pmm-client installed from percona-release,
# so that tasks run against it the way they would on a VM.
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

ARG PMM_CLIENT_REPO=release
ARG PMM_CLIENT_VERSION=

ENV container=docker \
    PERCONA_TELEMETRY_DISABLE=1

COPY install.sh pmm-agent-register /usr/local/sbin/
COPY pmm-agent-register.service /etc/systemd/system/
RUN /usr/local/sbin/install.sh

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
