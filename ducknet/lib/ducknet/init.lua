local ducknet = {}

ducknet.codec = require("ducknet.codec")
ducknet.Link = require("ducknet.modem")
ducknet.IP = require("ducknet.ip")
ducknet.ICMP = require("ducknet.icmp")
ducknet.TCP = require("ducknet.tcp")
ducknet.DLTP = require("ducknet.dltp")
ducknet.Crypto = require("ducknet.crypto")

-- Build a complete stack from a config table and an optional modem component.
function ducknet.stack(configuration, modem)
  local linkOptions = {}
  for key, value in pairs(configuration.link or {}) do linkOptions[key] = value end
  linkOptions.address = configuration.ip.address
  local link = ducknet.Link.new(modem, linkOptions)
  local ip = ducknet.IP.new(link, configuration.ip)
  for _, route in ipairs(configuration.routes or {}) do
    ip:addRoute(route.network, route.via, route.metric)
  end
  local tcp = ducknet.TCP.new(ip, configuration.tcp)
  local icmp = ducknet.ICMP.new(ip)
  local dltpOptions = configuration.dltp or {}
  if dltpOptions.key and not dltpOptions.crypto then
    dltpOptions.crypto = ducknet.Crypto.new()
  end
  local dltp = ducknet.DLTP.new(tcp, dltpOptions)
  return { link = link, ip = ip, icmp = icmp, tcp = tcp, dltp = dltp }
end

return ducknet
