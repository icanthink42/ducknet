# DuckNet

DuckNet is an application network for OpenComputers. It deliberately keeps the
layers separate so programs can use only the part they need:

```text
Niobium application (sandboxed Lua)
        |
DLTP request/response + authenticated encryption
        |
DuckNet TCP (connections, sequence numbers, ACKs, retransmission)
        |
DuckNet IP (addresses, longest-prefix routes, TTL, hops)
        |
OpenComputers modem
```

This repository is an initial, working protocol implementation. The APIs and
wire format are versioned, but should be considered `0.x` while real multiplayer
networks exercise them.

## Install

Download `install.lua`, run it, then choose a branch and one or more packages:

```sh
wget https://raw.githubusercontent.com/icanthink42/ducknet/main/install.lua /tmp/ducknet-install.lua
/tmp/ducknet-install.lua https://raw.githubusercontent.com/icanthink42/ducknet
```

The repository URL is supplied to the installer above. It will ask which branch
and packages to install.

Packages are installed into `/usr/lib`, programs into `/usr/bin`, examples into
`/usr/share/ducknet`, and configuration into `/etc/ducknet`. Re-running the
installer upgrades the selected packages. It never replaces an existing config.

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

Encrypted DLTP requires an OpenComputers data card (or a compatible crypto
provider) and a pre-shared key. It uses encrypt-then-MAC with independent keys,
random IVs, and HMAC-SHA-256. Niobium does not expose `component`, `computer`,
`filesystem`, `io`, `os`, `debug`, or the host `require`. Sites receive explicit
capabilities instead. This is intentional: unrestricted OpenComputers APIs and a
meaningful sandbox cannot coexist.
