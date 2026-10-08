# DuckNet protocol 1

All values use DuckNet's length-delimited codec. Unknown map fields must be
ignored, allowing compatible additions.

## IP

An IP packet contains `v`, `id`, `src`, `dst`, `ttl`, `protocol`, `payload`, and
`hops`. Routers decrement TTL before forwarding and append their logical address
to `hops`. Routes use longest-prefix match and then the lowest metric. IP protocol
`6` carries DuckNet TCP.

## ICMP

IP protocol `1` carries diagnostic control messages. Version 1 defines echo
request, echo reply, and TTL-exceeded messages. Attaching `ducknet.icmp` to an IP
instance makes a host answer echo requests and makes routers report packets whose
TTL reaches zero. These messages power `duck-ping` and `duck-traceroute`.

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
and `body`. Port 80 is conventional for plaintext and 443 for encrypted DLTP.

Secure envelopes contain a random IV, ciphertext, and HMAC-SHA-256 tag. Keys are
derived independently from the configured pre-shared key. The MAC is checked in
constant time before decryption. Encryption is provided by an OpenComputers data
card; secure mode fails closed when it is unavailable.

## Platform links

The protocol above the link layer is identical on CC:Tweaked and OpenComputers.
CC:Tweaked carries a targeted DuckNet envelope over modem channel 4660 by
default. OpenComputers sends the same encoded IP frame to the configured modem
component address. Logical addressing, routing, TCP, and DLTP do not depend on
the platform adapter.
