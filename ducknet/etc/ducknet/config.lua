-- Edit this file for this computer. It works on CC:Tweaked and OpenComputers.
return {
  link = {
    port = 4660,
    broadcastUnknown = false,
    peers = {
      -- ["10.0.0.1"] = "modem-component-address-of-neighbor"
    }
  },
  ip = {
    address = "10.0.0.2",
    forwarding = false,
    ttl = 16
  },
  routes = {
    -- Direct logical neighbors use via = nil.
    { network = "10.0.0.0/24", via = nil, metric = 10 }
    -- { network = "0.0.0.0/0", via = "10.0.0.1", metric = 100 }
  },
  tcp = { mtu = 4096, timeout = 2, retries = 4 },
  dltp = {
    port = 80
  }
}
