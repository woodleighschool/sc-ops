#!/bin/sh
# Probe for both Kea containers: probe.sh <dhcp4|ddns> <port>
# Kea's API has no GET endpoint, so this posts status-get to the loopback HTTP
# socket with the credentials start.sh wrote.
set -eu
auth="$(tr -d '\n' < "/run/kea-k8s/api-$1" | base64 | tr -d '\n')"
wget -q -T 5 -O - \
    --header 'Content-Type: application/json' \
    --header "Authorization: Basic $auth" \
    --post-data '{"command": "status-get"}' \
    "http://127.0.0.1:$2/" | grep -q '"result": 0'
