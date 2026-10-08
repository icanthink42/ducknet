# DuckNet

DuckNet is an application network for CC:Tweaked and OpenComputers. It
deliberately keeps the layers separate so programs can use only the part they
need:

```text
Niobium application (sandboxed Lua)
        |
DLTP request/response + authenticated encryption
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
- `router`: packet forwarding, route configuration, and diagnostic tools
- `server`: the DLTP server runtime, network configuration, and website setup
- `developer`: every library, program, example, and bundled website
- `custom`: manual package selection

Client, router, and server profiles guide you through network configuration.
The server profile can activate the bundled Foo Bar test or Hello World site,
or download a DuckNet server application from a GitHub raw/blob URL. Start a
configured server with `duckserve /etc/ducknet/site.lua`, or a router with
`duck-router`.

Every push to `main` is tested and published automatically. The release pipeline
increments the latest semantic patch version, tags the tested commit, builds the
self-contained installer, and uploads it as the new latest GitHub Release. For
example, the push after `v0.1.0` becomes `v0.1.1`.

On OpenComputers, packages are installed into `/usr/lib` and programs into
`/usr/bin`. On CC:Tweaked, packages are installed into `/ducknet` and programs
at the filesystem root so CraftOS can resolve them. Both platforms use
`/etc/ducknet/config.lua`. Re-running the installer upgrades selected packages
and never replaces an existing config.

The optional `tools` package installs commands with a `duck-` prefix so it does
not replace OpenOS utilities:

```text
duck-ipconfig [config]                 adapter information
duck-route [destination] [config]      routing table or route lookup
duck-neighbors [config]                logical IP to modem mappings
duck-ping <ip> [count] [timeout]       ICMP reachability and latency
duck-traceroute <ip> [hops] [timeout]  per-router path discovery
dltp <method> <ip> <path> [body]       DLTP request client
```

## Minimal router

```lua
local modem = require("component").modem
local Link = require("ducknet.modem")
local IP = require("ducknet.ip")

local link = Link.new(modem, { port = 4660, peers = {
  ["10.0.0.2"] = "neighbor-modem-component-address"
}})
local ip = IP.new(link, { address = "10.0.0.1", forwarding = true })
local ICMP = require("ducknet.icmp")
ICMP.new(ip) -- answer pings and emit TTL-exceeded messages
ip:addRoute("10.0.0.2/32", "10.0.0.2")

while true do ip:pump(5) end
```

See [`examples/`](examples/) for a server and router. Protocol documentation is
in [`docs/protocol.md`](docs/protocol.md).

## Security model

Encrypted DLTP currently requires an OpenComputers data card (or a compatible
crypto provider) and a pre-shared key. It uses encrypt-then-MAC with independent
keys, random IVs, and HMAC-SHA-256. Niobium does not expose `component`, `computer`,
`filesystem`, `io`, `os`, `debug`, or the host `require`. Sites receive explicit
capabilities instead. This is intentional: unrestricted OpenComputers APIs and a
meaningful sandbox cannot coexist. On CC:Tweaked, Niobium also benefits from
CraftOS's built-in protection against programs which run too long without
yielding; platforms exposing `debug.sethook` receive the tighter configured
instruction quota.
