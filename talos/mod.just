set default-list
set default-script
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[confirm('Apply Talos config to ' + node + ' in ' + cluster + ' [y|N] ?')]
[doc('Apply Talos config to a node')]
apply-node cluster node *args:
    just talos render-config "{{ cluster }}" "{{ node }}" | talosctl --context "{{ cluster }}" -n "{{ node }}" apply-config -f /dev/stdin {{ args }}

[doc('Download Talos machine image')]
download-image cluster version node="":
    export SCHEMATIC="$(just talos schematic-id "{{ cluster }}" "{{ node }}")"
    curl -fL --remove-on-error --retry 5 --retry-delay 5 --retry-all-errors --progress-bar \
        -o "{{ source_directory() }}/talos-{{ version }}-${SCHEMATIC:0:8}.iso" \
        "https://factory.talos.dev/image/${SCHEMATIC}/{{ version }}/metal-amd64.iso"
    just log info "Downloaded Talos" version "{{ version }}" schematic "${SCHEMATIC}"

[confirm('Reboot node ' + node + ' in ' + cluster + ' [y|N] ?')]
[doc('Reboot a node')]
reboot-node cluster node:
    talosctl --context "{{ cluster }}" -n {{ node }} reboot -m powercycle

# Shared machine config, then the cluster's, the role's, the cluster's role
# additions and the node's, each patched over the last.
[doc('Render Talos config for a node')]
render-config cluster node:
    dir="{{ source_directory() }}"
    schematic="$(just talos schematic-id "{{ cluster }}" "{{ node }}")"
    role="controlplane"
    if [[ -f "${dir}/{{ cluster }}/nodes/workers/{{ node }}.yaml.j2" ]]; then
        role="workers"
    fi
    talosctl machineconfig patch <(just template "${dir}/machine.yaml.j2" -D "schematic=${schematic}") \
        -p @<(just template "${dir}/{{ cluster }}/cluster.yaml.j2") \
        -p @<(just template "${dir}/${role}.yaml.j2") \
        -p @<(just template "${dir}/{{ cluster }}/${role}.yaml.j2") \
        -p @<(just template "${dir}/{{ cluster }}/nodes/${role}/{{ node }}.yaml.j2") | \
        yq 'with(select(.kind == "ResolverConfig"); .searchDomains.domains = [])'

[confirm('Reset node ' + node + ' in ' + cluster + ' [y|N] ?')]
[doc('Reset a node')]
reset-node cluster node *args:
    talosctl --context "{{ cluster }}" -n "{{ node }}" reset --system-labels-to-wipe STATE --system-labels-to-wipe EPHEMERAL --system-labels-to-wipe u-local-hostpath --graceful=false {{ args }}

[confirm('Shutdown node ' + node + ' in ' + cluster + ' [y|N] ?')]
[doc('Shutdown a node')]
shutdown-node cluster node *args:
    talosctl --context "{{ cluster }}" -n "{{ node }}" shutdown {{ args }}

[confirm('Upgrade Kubernetes on ' + cluster + ' to ' + version + ' [y|N] ?')]
[doc('Upgrade Kubernetes version on a cluster')]
upgrade-k8s cluster version:
    talosctl --context "{{ cluster }}" -n "$(talosctl --context "{{ cluster }}" config info -o yaml | yq -r -e '.endpoints[0]')" upgrade-k8s --to {{ version }}

[confirm('Upgrade node ' + node + ' in ' + cluster + ' [y|N] ?')]
[doc('Upgrade Talos version on a node')]
upgrade-node cluster node *args:
    talosctl --context "{{ cluster }}" -n "{{ node }}" upgrade -i "$(just talos machine-image "{{ cluster }}" "{{ node }}")" -m powercycle --timeout=10m {{ args }}

# Most specific wins: node, then cluster, then the shared default.
[private]
schematic-file cluster node="":
    dir="{{ source_directory() }}"
    file="${dir}/schematic.yaml.j2"
    [[ -f "${dir}/{{ cluster }}/schematic.yaml.j2" ]] && file="${dir}/{{ cluster }}/schematic.yaml.j2"
    if [[ -n "{{ node }}" ]]; then
        for f in "${dir}/{{ cluster }}"/nodes/*/"{{ node }}".schematic.yaml.j2; do
            [[ -f "$f" ]] && file="$f"
        done
    fi
    echo "$file"

[private]
schematic-id cluster node="":
    curl -sX POST --data-binary @<(just template "$(just talos schematic-file "{{ cluster }}" "{{ node }}")") "https://factory.talos.dev/schematics" | jq -r '.id'

[private]
machine-image cluster node="":
    just template "{{ source_directory() }}/machine.yaml.j2" -D "schematic=$(just talos schematic-id "{{ cluster }}" "{{ node }}")" | yq -r -e 'select(.kind == "UnattendedInstallConfig") | .installer.image'
