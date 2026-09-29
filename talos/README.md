# Talos

Machine configuration is rendered from five layers, each a patch over the last:

- `machine.yaml.j2`: shared configuration.
- `<cluster>/cluster.yaml.j2`: cluster name, endpoint, secrets, network.
- `controlplane.yaml.j2`: control-plane role and Kubernetes components.
- `<cluster>/controlplane.yaml.j2`: the cluster's CA keys, etcd subnet and API SANs.
- `<cluster>/nodes/<role>/<node>.yaml.j2`: hostname, network interfaces and disk selectors.

`schematic.yaml.j2` defines the Image Factory image. A cluster can override it
with `<cluster>/schematic.yaml.j2`, a node with
`<cluster>/nodes/<role>/<node>.schematic.yaml.j2`.

Templates use `op inject` for secrets, from the cluster's own vault. Talos merges
CA certificates and keys as a pair, so role patches include both fields.

```sh
just talos render-config <cluster> <node>
just talos apply-node <cluster> <node> --dry-run
just talos apply-node <cluster> <node>
just talos upgrade-node <cluster> <node>
just talos upgrade-k8s <cluster> <version>
```

Upgrade Talos before applying configuration that requires the new release.
Tuppr manages OS and Kubernetes versions; machine configuration is applied manually.

OpenEBS uses `/var/openebs/local`. Its bind mount requires the legacy
`machine.kubelet` block because `KubeletConfig` has no `extraMounts` field.

The renderer preserves an empty DNS search list after Talos merges the documents.
Use the complete rendered config with `apply-config`; `patch mc` and `edit mc`
can omit the empty list. Existing pods receive DNS changes when recreated.

The sc Kubernetes API is `https://10.10.69.100:6443`. Direct node endpoints
`https://10.10.69.5:6443`, `.6` and `.7` are available if the VIP is unreachable.
sc's nodes take their addresses from DHCP on VLAN 69; that VLAN must never be
served by the Kea running in the cluster.
