# DuckNet protocol 1

All values use DuckNet's length-delimited codec. Unknown map fields must be
ignored, allowing compatible additions.

## IP

An IP packet contains `v`, `id`, `src`, `dst`, `ttl`, `protocol`, `payload`, and
`hops`. Routers decrement TTL before forwarding and append the outgoing
interface's logical address to `hops`. Routes use longest-prefix match and then
the lowest metric. A router can have multiple interfaces, each with its own
modem, IP address, and directly connected subnet; routes select an outgoing
interface. IP protocol `6` carries DuckNet TCP.

The limited broadcast address `255.255.255.255` is delivered to every DuckNet
host listening on the local modem network and is never forwarded by a router.

## UDP

IP protocol `17` carries DuckNet UDP. A datagram contains `v`, `srcPort`,
`dstPort`, and `payload`. UDP provides message boundaries but no connection,
ordering, acknowledgement, or retransmission. Applications which require those
properties use TCP instead.

## DHCP

DuckNet DHCP uses UDP server port 67 and client port 68. A client without an
address sends broadcast DISCOVER and REQUEST messages from `0.0.0.0`; the server
returns broadcast OFFER and ACK messages. Messages include a transaction ID and
persistent client ID. An ACK assigns an address, prefix, default gateway, server
identifier, lease duration, and optional DNS resolver/search-domain lists.
Servers persist leases and clients renew them halfway through their lifetime.
Routers do not forward DHCP broadcasts.

## DNS

DuckNet DNS uses UDP port `53`. A query contains `kind = "query"`, a transaction
`id`, `name`, record `type`, and the recursion-desired flag `rd`. A response uses
the same ID and contains an `rcode`, authoritative/recursion flags, and `answers`,
`authority`, and `additional` record lists. Records contain `name`, `type`,
`value`, and `ttl`. Version 1 supports `A`, `NS`, `CNAME`, `SOA`, and `TXT`
records plus `ANY` queries.

Stub resolvers query servers learned from DHCP or configured locally. Recursive
servers begin with configured root hints, follow `NS` referrals and glue `A`
records, and cache positive and negative results according to TTL. Authoritative
servers select the longest matching configured zone and return referrals at
delegation points. DNS names are case-insensitive and are normalized to lower
case without a trailing dot. DNS version 1 uses UDP only; TCP fallback and
DNSSEC are reserved for later protocol versions.

## ICMP

IP protocol `1` carries diagnostic control messages. Version 1 defines echo
request, echo reply, and TTL-exceeded messages. Attaching `ducknet.icmp` to an IP
instance makes a host answer echo requests and makes routers report packets whose
TTL reaches zero. These messages power `ping` and `traceroute`.

## TCP

DuckNet TCP is intentionally small, not wire-compatible with Internet TCP. A
segment contains connection ID, source/destination ports, sequence and ACK
numbers, flags, and data. Connection setup is `SYN`, `SYN|ACK`, `ACK`. Data is
stop-and-wait, split into bounded segments, acknowledged by sequence number, and
retransmitted on timeout. This favors clarity and reliability over throughput on
the low-bandwidth OpenComputers modem bus.

## DLTP

DLTP carries one codec-encoded request and response per TCP connection. Requests
have `method`, `path`, `headers`, and `body`; responses have `status`, `headers`,
and `body`. DLTP currently uses port 80 and provides no encryption. DNS names may
be sent in the `host` header, but they do not authenticate the responding server.
A future secure-transport version will add certificates and authenticated site
identity.

## Platform links

The protocol above the link layer is identical on CC:Tweaked and OpenComputers.
CC:Tweaked carries a targeted DuckNet envelope over modem channel 4660 by
default. OpenComputers sends the same encoded IP frame to the configured modem
component address. Logical addressing, routing, TCP, and DLTP do not depend on
the platform adapter.
