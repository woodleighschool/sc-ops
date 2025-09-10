# Cilium

### Switch Configuration

```bash
router bgp 64513
  bgp router-id 10.10.69.1

  neighbor k8s peer-group
  neighbor k8s remote-as 64514

  neighbor 10.10.69.5 peer-group k8s
  neighbor 10.10.69.6 peer-group k8s
  neighbor 10.10.69.7 peer-group k8s

  address-family ipv4 unicast
    neighbor k8s next-hop-self
    neighbor k8s soft-reconfiguration inbound

    neighbor 10.10.69.5 activate
    neighbor 10.10.69.6 activate
    neighbor 10.10.69.7 activate
  exit-address-family
```