set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

render_root := justfile_dir() / ".private/bootstrap"

[confirm('Bootstrap cluster? [y|N]')]
[doc('Bootstrap a Talos & Kubernetes cluster end-to-end')]
cluster cluster: (render cluster) (nodes cluster) (k8s cluster) (kubeconfig cluster "node") (base cluster) (apps cluster) (kubeconfig cluster)

# Render the cluster's Flux tree once. Every HelmRelease gets a directory with
# its chart (release.yaml), its values (values.yaml) and the other objects of
# the Flux Kustomization that renders it (manifests.yaml).
[doc('Render what Flux will reconcile, for helmfile to install')]
render cluster:
    just log info "Running stage..." "stage" "{{ recipe_name() }}" "cluster" "{{ cluster }}"
    dir="{{ render_root }}/{{ cluster }}"
    rm -rf "${dir}" && mkdir -p "${dir}"
    flate build ks --path "{{ justfile_dir() }}/kubernetes/clusters/{{ cluster }}" --no-progress > "${dir}/rendered.yaml"
    yq -N 'select(.kind == "HelmRelease") | .metadata.namespace + "/" + .metadata.name' "${dir}/rendered.yaml" | while read -r id; do
        export NS="${id%/*}" NAME="${id#*/}"
        mkdir -p "${dir}/${id}"
        hr='select(.kind == "HelmRelease" and .metadata.namespace == env(NS) and .metadata.name == env(NAME))'
        export CHART="$(yq -N "${hr} | .spec.chartRef.name" "${dir}/rendered.yaml")"
        export KS="$(yq -N "${hr} | .metadata.labels.\"kustomize.toolkit.fluxcd.io/name\"" "${dir}/rendered.yaml")"
        yq -N "${hr} | .spec.values // {}" "${dir}/rendered.yaml" > "${dir}/${id}/values.yaml"
        yq -N 'select(.kind == "OCIRepository" and .metadata.namespace == env(NS) and .metadata.name == env(CHART)) | {"chart": .spec.url, "version": .spec.ref.tag}' \
            "${dir}/rendered.yaml" > "${dir}/${id}/release.yaml"
        yq 'select(.metadata.labels."kustomize.toolkit.fluxcd.io/name" == env(KS) and .metadata.labels."kustomize.toolkit.fluxcd.io/namespace" == env(NS))' \
            "${dir}/rendered.yaml" > "${dir}/${id}/manifests.yaml"
    done

[private]
nodes cluster:
    just log info "Running stage..." "stage" "{{ recipe_name() }}" "cluster" "{{ cluster }}"
    for n in $(talosctl --context "{{ cluster }}" config info -o yaml | yq -r -e '.nodes | join(" ")'); do
        if ! op=$(just --yes talos apply-node "{{ cluster }}" "$n" --insecure 2>&1); then
            if [[ "$op" == *"certificate required"* ]]; then
                just log info "Talos already configured, skipping apply of config" "stage" "{{ recipe_name() }}" "node" "$n"
                continue
            fi
            just log fatal "Failed to apply Talos configuration" "stage" "{{ recipe_name() }}" "node" "$n" "output" "$op"
        fi
    done

[private]
k8s cluster:
    just log info "Running stage..." "stage" "{{ recipe_name() }}" "cluster" "{{ cluster }}"
    controller="$(just bootstrap controller "{{ cluster }}")"
    until op=$(talosctl --context "{{ cluster }}" -n "${controller}" bootstrap 2>&1 || true) && [[ "$op" == *"AlreadyExists"* ]]; do
        just log info "Kubernetes bootstrap in progress. Retrying in 5 seconds..." "stage" "{{ recipe_name() }}"
        sleep 5
    done

# The kubeconfig context is named after the cluster. Until Cilium serves the API
# LoadBalancer address, talk to the first controller directly.
[private]
kubeconfig cluster lb="cilium":
    just log info "Running stage..." "stage" "{{ recipe_name() }}" "cluster" "{{ cluster }}"
    controller="$(just bootstrap controller "{{ cluster }}")"
    if ! talosctl --context "{{ cluster }}" kubeconfig -n "${controller}" -f --force-context-name "{{ cluster }}" "{{ justfile_dir() }}"; then
        just log fatal "Failed to fetch kubeconfig" "stage" "{{ recipe_name() }}"
    fi
    if [[ "{{ lb }}" != "cilium" ]]; then
        if ! kubectl config set-cluster "{{ cluster }}" --server "https://${controller}:6443"; then
            just log fatal "Failed to set kubectl cluster server address" "stage" "{{ recipe_name() }}"
        fi
    fi

# Secrets and admission policy that must exist before Flux runs. The 1Password
# vault is the first one in the cluster's ClusterSecretStore.
[private]
base cluster: (api-ready cluster) (nodes-ready cluster)
    just log info "Running stage..." "stage" "{{ recipe_name() }}" "cluster" "{{ cluster }}"
    apps="{{ justfile_dir() }}/kubernetes/apps/{{ cluster }}"
    vault="$(yq -r -e '.spec.provider.onepassword.vaults | to_entries | sort_by(.value) | .[0].key' "${apps}/external-secrets/onepassword-connect/clustersecretstore.yaml")"
    dirs=(apps)
    [[ -f "${apps}/network/cloudflare-tunnel.yaml" ]] && dirs+=(cloudflare-tunnel)
    for d in "${dirs[@]}"; do kustomize build "{{ source_directory() }}/kustomize/${d}"; done \
        | just template - -D "vault=${vault}" \
        | kubectl --context "{{ cluster }}" apply --server-side --force-conflicts -f - \
        || just log fatal "Failed to apply base manifests" "stage" "{{ recipe_name() }}"
    just bootstrap crds "{{ cluster }}"

# Also useful on a running cluster, before Flux applies objects of a new CRD.
[doc("Apply the CRDs of the cluster's CRD-providing charts")]
crds cluster:
    just log info "Running stage..." "stage" "{{ recipe_name() }}" "cluster" "{{ cluster }}"
    [[ -d "{{ render_root }}/{{ cluster }}" ]] || just bootstrap render "{{ cluster }}"
    if ! CLUSTER="{{ cluster }}" BOOTSTRAP_RENDER_DIR="{{ render_root }}/{{ cluster }}" helmfile -f "{{ source_directory() }}/helmfile/crds.yaml.gotmpl" template -q | yq ea -r -e 'select(.kind == "CustomResourceDefinition")' | kubectl --context "{{ cluster }}" apply --server-side --force-conflicts -f -; then
        just log fatal "Failed to apply base crds" "stage" "{{ recipe_name() }}"
    fi

[private]
apps cluster:
    just log info "Running stage..." "stage" "{{ recipe_name() }}" "cluster" "{{ cluster }}"
    if ! CLUSTER="{{ cluster }}" BOOTSTRAP_RENDER_DIR="{{ render_root }}/{{ cluster }}" helmfile -f "{{ source_directory() }}/helmfile/apps.yaml.gotmpl" sync --hide-notes; then
        just log fatal "Failed to sync helmfile" "stage" "{{ recipe_name() }}"
    fi

# Wait until every apiserver answers /readyz. Helm and kubectl calls after this stage are not retried.
[private]
api-ready cluster:
    just log info "Running stage..." "stage" "{{ recipe_name() }}" "cluster" "{{ cluster }}"
    for n in $(talosctl --context "{{ cluster }}" config info -o yaml | yq -r -e '.nodes | join(" ")'); do
        until [[ "$(curl -ks -o /dev/null -w '%{http_code}' --connect-timeout 2 "https://${n}:6443/readyz")" == "200" ]]; do
            just log info "Waiting for kube-apiserver. Retrying in 5 seconds..." "stage" "{{ recipe_name() }}" "node" "$n"
            sleep 5
        done
    done

# Wait until every node registers as Ready=False. They only become Ready=True once the CNI is healthy.
[private]
nodes-ready cluster:
    just log info "Running stage..." "stage" "{{ recipe_name() }}" "cluster" "{{ cluster }}"
    if ! kubectl --context "{{ cluster }}" wait nodes --for=condition=Ready=True --all --timeout=10s &>/dev/null; then
        until kubectl --context "{{ cluster }}" wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do
            just log info "Nodes not available, waiting for nodes to be available. Retrying in 5 seconds..." "stage" "{{ recipe_name() }}"
            sleep 5
        done
    fi

[private]
controller cluster:
    talosctl --context "{{ cluster }}" config info -o yaml | yq -r -e '.endpoints[0]'
