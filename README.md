# DuckNet

DuckNet is an application network for CC:Tweaked and OpenComputers. It
deliberately keeps the layers separate so programs can use only the part they
need:

```text
Niobium application (sandboxed Lua)
        |
DLTP request/response
        |
DuckNet TCP (connections, sequence numbers, ACKs, retransmission)
        |
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

- `client`: Niobium, DLTP, TCP/IP, and diagnostic tools
- `router`: multi-interface packet forwarding, route configuration, and diagnostic tools
- `server`: the DLTP server runtime, network configuration, and website setup
- `developer`: every library, program, example, and bundled website
- `custom`: manual package selection

Client, router, and server profiles guide you through network configuration.
The router profile configures two interfaces by default. Each interface has its
own modem, IP address, subnet, and channel, so one router can join two subnets.
The server profile can activate the bundled Foo Bar test or Hello World site,
or download a DuckNet server application from a GitHub raw/blob URL. Start a
configured server with `serve /etc/ducknet/site.lua`, or a router with
`router`. Router and server profiles also install and enable the matching
startup service automatically. Rebooting the computer resumes its configured
role without another command.

Every push to `main` is tested and published automatically. The release pipeline
increments the latest semantic patch version, tags the tested commit, builds the
self-contained installer, and uploads it as the new latest GitHub Release. For
example, the push after `v0.1.0` becomes `v0.1.1`.

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
ip interface remove <name>              remove a router interface
ip route list                           list persistent routes
ip route add <cidr> <interface> <via|direct> [metric]
                                        add a persistent static route
ip route remove <cidr> [interface]      remove persistent static routes
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

## Minimal router

```lua
return {
  link = { broadcastUnknown = false, peers = {} },
  interfaces = {
    { name = "net10", modem = "left", address = "10.0.0.1",
      network = "10.0.0.0/24", port = 4660 },
    { name = "net11", modem = "right", address = "11.0.0.1",
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
