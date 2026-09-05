# Cilium

The Aruba CX at `10.10.69.1` (AS 64513) peers with nodes `10.10.69.5–7`
(AS 64514). Cilium advertises Service addresses, including the API at
`10.10.69.100`.

## Switch configuration

```sh
router bgp 64513
  bgp router-id 10.10.69.1

  neighbor k8s peer-group
  neighbor k8s remote-as 64514
  neighbor k8s timers 3 9

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

The keepalive and hold timers are 3 and 9 seconds on both sides. Verify the
negotiated values after reconnecting the peers.

```sh
show running-config bgp
show bgp ipv4 unicast summary
show bgp ipv4 unicast 10.10.69.100/32
show ip route 10.10.69.100/32
```

All peers should be `Established`. With all three API endpoints ready, check for
three eligible next hops. AOS-CX normally allows four ECMP paths; changing
`maximum-paths` restarts BGP sessions in the VRF.

## Recovery

If sessions remain stuck after a node reboot, restarting BGP interrupts all
peers on the switch:

```sh
conf t
router bgp 64513
disable
enable
end
```

References: [neighbor timers](https://arubanetworking.hpe.com/techdocs/AOS-CX/10.16/HTML/ip_route_6300-6400-8100-83xx-93xx-100xx/Content/Chp_BGP/BGP_cmds/nei-tim-10.htm),
[maximum-paths](https://arubanetworking.hpe.com/techdocs/AOS-CX/10.16/HTML/ip_route_6300-6400-8100-83xx-93xx-100xx/Content/Chp_BGP/BGP_cmds/max-pat-10.htm).
