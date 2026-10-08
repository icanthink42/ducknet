local Crypto = {}
Crypto.__index = Crypto

local function xorByteString(value, byte)
  local out = {}
  for index = 1, #value do out[index] = string.char(bit32.bxor(value:byte(index), byte)) end
  return table.concat(out)
end

local function constantTimeEqual(left, right)
  if type(left) ~= "string" or type(right) ~= "string" or #left ~= #right then return false end
  local difference = 0
  for index = 1, #left do
    difference = bit32.bor(difference, bit32.bxor(left:byte(index), right:byte(index)))
  end
  return difference == 0
end

function Crypto.new(provider)
  if not provider then
    local ok, component = pcall(require, "component")
    if ok and component.isAvailable("data") then provider = component.data end
  end
  assert(provider and provider.sha256 and provider.encrypt and provider.decrypt and provider.random,
    "secure DLTP requires a data-card-compatible crypto provider")
  return setmetatable({ provider = provider }, Crypto)
end

function Crypto:hash(value)
  return self.provider.sha256(value)
end

function Crypto:hmac(key, message)
  if #key > 64 then key = self:hash(key) end
  key = key .. string.rep("\0", 64 - #key)
  return self:hash(xorByteString(key, 0x5c) .. self:hash(xorByteString(key, 0x36) .. message))
end

function Crypto:seal(plaintext, sharedKey)
  assert(type(sharedKey) == "string" and #sharedKey >= 16, "shared key must be at least 16 bytes")
  local encryptionKey = self:hash("ducknet encryption\0" .. sharedKey):sub(1, 16)
  local macKey = self:hash("ducknet authentication\0" .. sharedKey)
  local iv = self.provider.random(16)
  local ciphertext = self.provider.encrypt(plaintext, encryptionKey, iv)
  return { iv = iv, ciphertext = ciphertext, tag = self:hmac(macKey, iv .. ciphertext) }
end

function Crypto:open(envelope, sharedKey)
  if type(envelope) ~= "table" or type(envelope.iv) ~= "string" or
      type(envelope.ciphertext) ~= "string" or type(envelope.tag) ~= "string" then
    return nil, "invalid secure envelope"
  end
  local encryptionKey = self:hash("ducknet encryption\0" .. sharedKey):sub(1, 16)
  local macKey = self:hash("ducknet authentication\0" .. sharedKey)
  local expected = self:hmac(macKey, envelope.iv .. envelope.ciphertext)
  if not constantTimeEqual(expected, envelope.tag) then return nil, "authentication failed" end
  return self.provider.decrypt(envelope.ciphertext, encryptionKey, envelope.iv)
end

return Crypto

