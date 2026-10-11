# DuckNet

DuckNet is an application network for CC:Tweaked and OpenComputers. It
deliberately keeps the layers separate so programs can use only the part they
need:

```text
Niobium application                    DHCP address assignment
        |                                      |
DLTP request/response                  DuckNet UDP (datagrams)
        |                                      |
DuckNet TCP (ACKs and retransmission)          |
        |                                      |
DuckNet IP (addresses, longest-prefix routes, TTL, hops)
        |
CC:Tweaked or OpenComputers modem
```

This repository is an initial, working protocol implementation. The APIs and
wire format are versioned, but should be considered `0.x` while real multiplayer
networks exercise them.

## Install

For stable installs, download the self-contained asset from the latest GitHub
Release, then choose the bundled release and one or more packages:

```sh
wget https://github.com/icanthink42/ducknet/releases/latest/download/ducknet-installer.lua /tmp/ducknet-install.lua
/tmp/ducknet-install.lua
```

Release installers contain every DuckNet file, so installation does not depend
on raw-file cache updates. The branch prompt defaults to the bundled version;
entering a branch name such as `main` deliberately switches to raw development
files. Developers can optionally pass a different raw repository base URL as
the first argument when testing a fork.

The installer provides these profiles:

- `client`: automatic DHCP, Niobium, DLTP, TCP/IP, and diagnostic tools
- `router`: multi-interface packet forwarding, route configuration, and diagnostic tools
- `server`: the DLTP server runtime, network configuration, and website setup
- `developer`: every library, program, example, and bundled website
- `custom`: manual package selection

Client, router, and server profiles guide you through network configuration.
The client profile only asks for its modem side and channel, enables DHCP, and
acquires its address, subnet, and gateway automatically when the computer starts.
Every router runs the same forwarding software and gives each interface a role:
`lan` for client/server networks or `transit` for links to other routers. The
`home` preset creates one LAN and one or more transit links; the `transit` preset
creates a router for the backbone web and can optionally attach LANs too. LAN
interfaces can run DHCP automatically. Transit links derive both endpoint
addresses from their link subnet, so exact router addresses do not need to be
entered during normal setup. The presets describe topology rather than different
kinds of router.
Interface roles are persisted for the upcoming dynamic-routing service. In this
release, connected routes are automatic but routes through neighboring routers
are still static; the transit preset can create those neighbor routes during
setup. Automatic route advertisement and failover are the next routing-layer
step.
The server profile can activate the bundled Foo Bar test, Hello World site, or
interactive Player Tracker, or download a DuckNet server application from a
GitHub raw/blob URL. Start a
configured server with `serve /etc/ducknet/site.lua`, or a router with
`router`. On CC:Tweaked, client, router, and server profiles install their
long-running work as `systemdck` services. Rebooting starts enabled services on
basic and advanced computers, and failed services are restarted automatically.

The Player Tracker site requires an Advanced Peripherals Player Detector
attached to the server computer. Open it in Niobium, enter an online Minecraft
username, and it requests the player's coordinates and available detector
metadata from the server. The site supports both `player_detector`/`getPlayer`
and legacy `playerDetector`/`getPlayerPos` APIs. It exposes player locations to
every client that can reach the site, so deploy it only on a network where that
is intended.

Every push to `main` is tested and published automatically. The release pipeline
increments the latest semantic patch version, tags the tested commit, builds the
self-contained installer, and uploads it as the new latest GitHub Release. For
The current release series is `v0.2.x`; for example, the push after `v0.2.0`
becomes `v0.2.1`.

On OpenComputers, packages use the normal `/usr/lib`, `/usr/bin`, and
`/usr/share/ducknet` directories. CC:Tweaked keeps everything organized under
`/ducknet/lib`, `/ducknet/bin`, and `/ducknet/share`; an early startup entry adds
`/ducknet/bin` to CraftOS's command path. Both platforms use
`/etc/ducknet/config.lua`. Re-running the installer upgrades selected packages
and never replaces an existing config.

The optional `tools` package installs familiar networking commands:

```text
ip address set <address/prefix>          set a host's IP address and subnet
ip gateway set <ip|none>                 set or remove a host's default gateway
ip channel set <channel>                 set a host's modem channel
ip ttl set <ttl>                         set the default packet TTL
ip forwarding set <on|off>               enable or disable packet forwarding
ip dltp-port set <port>                  set the DLTP service port
ip interface list [config]              list configured network interfaces
ip interface add <name> <modem> <cidr> [channel]
                                        persist a new router interface
ip interface set <name> <modem> <cidr> [channel]
                                        replace an interface's configuration
ip interface role <name> <lan|transit>  set an interface's topology role
ip interface remove <name>              remove a router interface
ip route list                           list persistent routes
ip route add <cidr> <interface> <via|direct> [metric]
                                        add a persistent static route
ip route remove <cidr> [interface]      remove persistent static routes
dhcpd pool list                        list router DHCP pools
dhcpd pool add <interface> <first> <last> [lease-seconds]
                                        serve addresses on an interface
dhcpd pool remove <interface>          remove an interface's DHCP pool
dhcpd lease list                       list persistent leases
dhclient enable <modem> [channel]      acquire an address and enable renewal
dhclient configure <modem> [channel]   enable DHCP for acquisition at startup
dhclient renew                         renew the current DHCP lease
dhclient status                        show the current lease
dhclient release                       return and disable the current lease
systemdck list                         list installed background services
systemdck status <service>             show service state and restart count
systemdck logs <service>               show captured service output
systemdck start|stop|restart <service> control a service immediately
systemdck enable|disable <service>     control whether a service starts at boot
systemdck create <name> <program> [args...]
                                        create and enable a custom service
systemdck remove <service>             stop and remove a custom service
ipconfig [config]                      adapter information
route [destination] [config]           routing table or route lookup
arp [config]                           logical IP to modem mappings
ping <ip> [count] [timeout]            ICMP reachability and latency
traceroute <ip> [hops] [timeout]       per-router path discovery
dltp <method> <ip> <path> [body]       DLTP request client
router                                 run the configured router
serve <site.lua>                       run a configured DLTP website
uninstall-ducknet                      remove DuckNet
```

The uninstaller removes libraries, programs, and startup services, then asks
separately before deleting `/etc/ducknet` configuration and website data.

## Background services

`systemdck` is DuckNet's small service supervisor for CC:Tweaked. It uses the
standard `parallel` API to cooperatively run an interactive shell, its control
loop, and up to 16 service workers in one top-level process. This works on both
basic and advanced computers and does not depend on multishell. It records state
under `/var/run/systemdck`, captures service output under
`/var/log/systemdck`, restarts failed programs, and starts enabled unit files
from `/etc/systemdck` during boot. Installed profiles create these units
automatically:

- `ducknet-network` acquires and renews a client's DHCP lease
- `ducknet-router` runs packet forwarding and the DHCP server
- `ducknet-server` runs the configured website

For example:

```text
systemdck list
systemdck status ducknet-network
systemdck logs ducknet-network
systemdck restart ducknet-router
systemdck disable ducknet-server
```

On boot, `systemdck` becomes the parent process and opens a normal interactive
CraftOS shell as one of its parallel tasks. Service output is logged instead of
being written over the shell prompt. The hosted shell keeps up to 1,000 lines of
scrollback: use the mouse wheel or Page Up/Page Down to move through it, Home to
jump to the oldest retained output, and End or any normal typing key to return
to the live prompt. As with all ComputerCraft cooperative
multitasking, a service must eventually yield by waiting for an event, sleeping,
or calling another yielding API; a program that spins forever without yielding
would stall the whole computer.

## DHCP

DuckNet DHCP uses UDP ports 67 and 68 and the standard four-step
DISCOVER/OFFER/REQUEST/ACK exchange. On a router, create a pool for a directly
connected client interface and reboot:

```text
dhcpd pool add lan 11.0.0.100 11.0.0.200 3600
reboot
```

The home-router installer creates this LAN pool automatically by default.

On a client attached through its left modem, acquire a lease:

```text
dhclient enable left 4660
reboot
```

The lease supplies the address, prefix, and default gateway. It is stored in the
normal DuckNet configuration, renewed automatically halfway through its lifetime
on systems with background-task support, and displayed by `ipconfig` and
`dhclient status`. DHCP broadcasts remain on their local cable/interface;
centralized DHCP across routers will require the future relay service. DHCP is
currently unauthenticated, so clients trust DHCP servers on their physical modem
network.

## Minimal router

```lua
return {
  link = { broadcastUnknown = false, peers = {} },
  interfaces = {
    { name = "net10", role = "lan", modem = "left", address = "10.0.0.1",
      network = "10.0.0.0/24", port = 4660 },
    { name = "net11", role = "lan", modem = "right", address = "11.0.0.1",
      network = "11.0.0.0/24", port = 4660 },
  },
  ip = { forwarding = true, ttl = 16 },
  routes = {},
  tcp = { mtu = 4096, timeout = 2, retries = 4 },
  dltp = { port = 80 },
}
```

A host on `10.0.0.0/24` uses `10.0.0.1` as its gateway; a host on
`11.0.0.0/24` uses `11.0.0.1`. The router automatically adds a direct route for
each interface subnet. Static routes use `interface = "net10"` (or another
interface name) and may also specify `via` for the next-hop router.

See [`examples/`](examples/) for a server and router. Protocol documentation is
in [`docs/protocol.md`](docs/protocol.md).

## Security model

DLTP is currently plaintext-only. Encryption will return with the future naming
and identity system, where it can authenticate the site being contacted rather
than merely encrypting traffic with a manually shared key. Niobium does not
expose `component`, `computer`,
`filesystem`, `io`, `os`, `debug`, or the host `require`. Sites receive explicit
capabilities instead. This is intentional: unrestricted OpenComputers APIs and a
meaningful sandbox cannot coexist. On CC:Tweaked, Niobium also benefits from
CraftOS's built-in protection against programs which run too long without
yielding; platforms exposing `debug.sethook` receive the tighter configured
instruction quota.
