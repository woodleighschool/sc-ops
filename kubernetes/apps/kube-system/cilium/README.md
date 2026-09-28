# Cilium

The Aruba CX (AS 64513) peers with nodes `10.10.69.5–7` (AS 64514) on
`10.10.69.1`. Cilium advertises Service addresses, including the API at
`10.10.69.100`.

## Switch configuration

Cilium dials out to the switch but does not listen on TCP 179, so the switch
must wait for the nodes to connect. It accepts them as dynamic neighbors, which
AOS-CX keeps passive and creates for each incoming session. Static neighbors
stayed `Idle` after a hold-timer expiry, such as a node reboot, even when set to
`passive`.

```sh
router bgp 64513
  bgp router-id 10.10.69.110

  neighbor k8s peer-group
  neighbor k8s remote-as 64514
  neighbor k8s timers 3 9
  neighbor k8s listen ip-range 10.10.69.4/30 as-range 64514

  address-family ipv4 unicast
    neighbor k8s next-hop-self
    neighbor k8s soft-reconfiguration inbound
  exit-address-family
```

Dynamic eBGP peers need `as-range`; without it AOS-CX only brings up iBGP
sessions. Dynamic peers negotiate every address family, so they need no
`activate`. The range covers `10.10.69.4–7`; widen it before adding a node.

The keepalive and hold timers are 3 and 9 seconds on both sides. Cilium retries
the connection every 5 seconds, so a session returns shortly after its node.
Verify the negotiated values after reconnecting the peers.

```sh
show running-config bgp
show bgp ipv4 unicast summary
show bgp ipv4 unicast 10.10.69.100/32
show ip route 10.10.69.100/32
```

All peers should be `Established`. With all three API endpoints ready, check for
three eligible next hops. AOS-CX normally allows four ECMP paths; changing
`maximum-paths` restarts BGP sessions in the VRF.

References: [neighbor listen ip-range](https://arubanetworking.hpe.com/techdocs/AOS-CX/10.16/HTML/ip_route_6300-6400-8100-83xx-93xx-100xx/Content/Chp_BGP/BGP_cmds/nei-lis-ip-rng.htm),
[neighbor timers](https://arubanetworking.hpe.com/techdocs/AOS-CX/10.16/HTML/ip_route_6300-6400-8100-83xx-93xx-100xx/Content/Chp_BGP/BGP_cmds/nei-tim-10.htm),
[maximum-paths](https://arubanetworking.hpe.com/techdocs/AOS-CX/10.16/HTML/ip_route_6300-6400-8100-83xx-93xx-100xx/Content/Chp_BGP/BGP_cmds/max-pat-10.htm).
