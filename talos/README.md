# Talos

Machine configuration is rendered from three layers:

- `cluster.yaml.j2`: shared configuration.
- `controlplane.yaml.j2`: control-plane role and Kubernetes components.
- `nodes/<role>/<node>.yaml.j2`: hostname, network interfaces and disk selectors.

`schematic.yaml.j2` defines the Image Factory image. A node can override it with
`nodes/<role>/<node>.schematic.yaml.j2`.

Templates use `op inject` for secrets. Talos merges CA certificates and keys as a
pair, so role patches include both fields.

```sh
just talos render-config <node>
just talos apply-node <node> --dry-run
just talos apply-node <node>
just talos upgrade-node <node>
just talos upgrade-k8s <version>
```

Upgrade Talos before applying configuration that requires the new release.
Tuppr manages OS and Kubernetes versions; machine configuration is applied manually.

OpenEBS uses `/var/openebs/local`. Its bind mount requires the legacy
`machine.kubelet` block because `KubeletConfig` has no `extraMounts` field.

The renderer preserves an empty DNS search list after Talos merges the documents.
Use the complete rendered config with `apply-config`; `patch mc` and `edit mc`
can omit the empty list. Existing pods receive DNS changes when recreated.

The Kubernetes API is `https://10.10.69.100:6443`. Direct node endpoints
`https://10.10.69.5:6443`, `.6` and `.7` are available if the VIP is unreachable.
