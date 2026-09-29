# wood-ops

Each cluster runs its own Flux, pointed at `kubernetes/clusters/<cluster>`.

- `kubernetes/clusters/<cluster>`: `cluster-settings` (storage classes, backup
  bucket, cluster name) and `cluster-apps`, which substitutes them everywhere.
- `kubernetes/apps/<cluster>`: what the cluster runs, one Flux Kustomization per
  app. Cluster-specific config is a component next to it.
- `kubernetes/apps/base`: the apps.
- `talos`: shared machine config, and each cluster's own under `talos/<cluster>`.

Recipes take the cluster first (`just talos apply-node sc k8s-1`,
`just kube sync sc ks`); kubeconfig and talosconfig contexts are named after the
cluster. A new cluster copies `kubernetes/clusters/sc`, a trimmed
`kubernetes/apps/sc` and `talos/sc`, with its own 1Password vault, age key and
backup bucket.

---

### 🙌 Credits

Everything in this repo is based on the awesome work at [onedr0p/home-ops](https://github.com/onedr0p/home-ops)
