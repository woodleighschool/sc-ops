#!/bin/sh
# Entrypoint for both Kea containers, running as the kea user:
#   start.sh <dhcp4|ddns> <command...>
# Prepares what Kea's path checks require, a per-pod password for the probes,
# and removes the PID files a crashed Kea leaves behind (Kea refuses to start
# while its PID file names a live process, and in a restarted container that
# process is PID 1 again).
set -eu
umask 077
mkdir -p /run/kea-k8s/sockets
chmod 0750 /run/kea-k8s/sockets
if [ ! -s "/run/kea-k8s/api-$1" ]; then
    printf 'probe:%s\n' "$(head -c 24 /dev/urandom | base64 | tr -d '/+=\n')" > "/run/kea-k8s/api-$1"
fi
rm -f /run/kea-k8s/sockets/*"$1"*.pid
[ "$1" = dhcp4 ] && rm -f /var/lib/kea/*.pid
shift
exec "$@"
