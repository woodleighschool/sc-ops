set default-list
set default-script
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[doc('Apply local Flux Kustomization')]
apply-ks cluster ns ks:
    just kube render-local-ks "{{ cluster }}" "{{ ns }}" "{{ ks }}" | kubectl --context "{{ cluster }}" apply --server-side --force-conflicts --field-manager=kustomize-controller -f -

[doc('Browse a PVC')]
browse-pvc cluster ns claim:
    kubectl --context "{{ cluster }}" run -n {{ ns }} browse-pvc-{{ claim }} -it --rm --restart=Never \
        --image=mirror.gcr.io/alpine:latest \
        --overrides='{"spec":{"containers":[{"name":"browse-pvc-{{ claim }}","image":"mirror.gcr.io/alpine:latest","stdin":true,"tty":true,"command":["/bin/sh"],"workingDir":"/mnt","volumeMounts":[{"mountPath":"/mnt","name":"data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"{{ claim }}"}}]}}'

[doc('Debug a node')]
debug-node cluster node:
    trap 'kubectl --context "{{ cluster }}" delete pod -n default -l app.kubernetes.io/managed-by=kubectl-debug --field-selector spec.nodeName={{ node }} --ignore-not-found --wait=false' EXIT
    kubectl --context "{{ cluster }}" debug node/{{ node }} -n default -it --image=mirror.gcr.io/alpine:latest --profile=sysadmin

[doc('Delete local Flux Kustomization')]
delete-ks cluster ns ks:
    just kube render-local-ks "{{ cluster }}" "{{ ns }}" "{{ ks }}" | kubectl --context "{{ cluster }}" delete -f -

[doc('Prune pods in Failed, Pending, or Succeeded state')]
prune-pods cluster:
    for phase in Failed Pending Succeeded; do
        kubectl --context "{{ cluster }}" delete pods -A --field-selector status.phase="$phase" --ignore-not-found=true
    done

[doc('Restore a PVC from Kopiur')]
restore cluster ns app previous='0':
    ctx=(--context "{{ cluster }}" -n "{{ ns }}")
    flux "${ctx[@]}" suspend kustomization {{ app }}
    flux "${ctx[@]}" suspend helmrelease {{ app }}
    kubectl "${ctx[@]}" get deploy,sts -l app.kubernetes.io/name={{ app }} -o name \
        | xargs -r -I{} kubectl "${ctx[@]}" scale {} --replicas=0
    kubectl "${ctx[@]}" wait pod --for=delete --selector="app.kubernetes.io/name={{ app }}" --timeout=5m
    kopiur restore --from-policy {{ app }} --offset {{ previous }} --to-pvc {{ app }} \
        --enable-file-deletion --on-missing-snapshot fail --wait --timeout 2h "${ctx[@]}"
    flux "${ctx[@]}" resume kustomization {{ app }}
    flux "${ctx[@]}" resume helmrelease {{ app }}
    flux "${ctx[@]}" reconcile helmrelease {{ app }} --force
    kubectl "${ctx[@]}" wait pod --for=condition=ready --selector="app.kubernetes.io/name={{ app }}" --timeout=5m

[doc('Snapshot every Kopiur policy now')]
snapshot cluster:
    kubectl --context "{{ cluster }}" get snapshotpolicies --no-headers -A | while read -r ns name _; do
        kopiur snapshot now --policy "$name" --context "{{ cluster }}" -n "$ns"
    done

[arg('resource', pattern='hr|ks|gitrepo|ocirepo|es')]
[doc('Sync a resource')]
sync cluster resource:
    kubectl --context "{{ cluster }}" get {{ resource }} --no-headers -A | while read -r ns name _; do
        kubectl --context "{{ cluster }}" -n "$ns" annotate --field-manager flux-client-side-apply --overwrite {{ resource }} "$name" \
            "force-sync=$(date +%s)" \
            "reconcile.fluxcd.io/requestedAt=$(date +%s)" \
            "reconcile.fluxcd.io/forceAt=$(date +%s)"
    done

[doc('View a secret')]
view-secret cluster ns secret:
    kubectl --context "{{ cluster }}" view-secret -n {{ ns }} {{ secret }}

[private]
render-local-ks cluster ns ks:
    flate build ks --path "{{ source_directory() }}/clusters/{{ cluster }}" --namespace "{{ ns }}" --output yaml "{{ ks }}"
