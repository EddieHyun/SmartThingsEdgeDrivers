-- HTTP client for Volumio REST API communication
local socket = require "cosock.socket"
local log = require "log"
local json = require "st.json"

local M = {}

local TIMEOUT = 5

local function http_get(host, port, path)
  local sock, err = socket.tcp()
  if err then
    return nil, "socket create failed: " .. tostring(err)
  end

  sock:settimeout(TIMEOUT)

  local ok, connect_err = sock:connect(host, port)
  if not ok then
    sock:close()
    return nil, "connect failed to " .. tostring(host) .. ":" .. tostring(port) .. " - " .. tostring(connect_err)
  end

  local req = string.format(
    "GET %s HTTP/1.1\r\nHost: %s:%d\r\nConnection: close\r\nAccept: application/json\r\n\r\n",
    path, host, port
  )
  local sent, send_err = sock:send(req)
  if not sent then
    sock:close()
    return nil, "send failed: " .. tostring(send_err)
  end

  -- cosock does not support receive("*a"); loop with receive(n) and collect
  -- partial data on "closed" (normal EOF for Connection: close responses).
  local chunks = {}
  while true do
    local chunk, recv_err, partial = sock:receive(4096)
    if chunk then
      table.insert(chunks, chunk)
    elseif recv_err == "closed" or recv_err == "timeout" then
      if partial and partial ~= "" then table.insert(chunks, partial) end
      break
    else
      sock:close()
      return nil, "receive error: " .. tostring(recv_err)
    end
  end
  sock:close()

  local full = table.concat(chunks)
  if full == "" then
    return nil, "empty response from " .. tostring(host) .. ":" .. tostring(port)
  end

  local _, _, status_code = full:find("HTTP/%d+%.%d+ (%d+)")
  -- handle both \r\n\r\n and \n\n as header separator
  local _, body_start = full:find("\r\n\r\n")
  if not body_start then
    _, body_start = full:find("\n\n")
  end

  if not body_start then
    log.warn("http_get: no header separator in response (first 200 bytes): "
      .. full:sub(1, 200))
    return nil, "malformed HTTP response from " .. tostring(host) .. ":" .. tostring(port)
  end

  local body = full:sub(body_start + 1)

  if status_code and tonumber(status_code) >= 400 then
    return nil, "HTTP error " .. status_code
  end

  return body, nil
end

-- GET /api/v1/commands/?cmd=volume&volume=plus
function M.volume_up(host, port)
  return http_get(host, port, "/api/v1/commands/?cmd=volume&volume=plus")
end

-- GET /api/v1/commands/?cmd=volume&volume=minus
function M.volume_down(host, port)
  return http_get(host, port, "/api/v1/commands/?cmd=volume&volume=minus")
end

-- GET /api/v1/commands/?cmd=volume&volume=<0-100>
function M.set_volume(host, port, volume)
  local pct = math.max(0, math.min(100, math.floor(volume)))
  local path = string.format("/api/v1/commands/?cmd=volume&volume=%d", pct)
  return http_get(host, port, path)
end

-- (power on)
function M.power_on(host, port)
  -- do nothing
end

-- (power off)
function M.power_off(host, port)
  -- do nothing
end

-- GET /api/v1/getState → { status, volume, mute, ... }
function M.get_state(host, port)
  local body, err = http_get(host, port, "/api/v1/getState")
  if err then return nil, err end
  local ok, data = pcall(json.decode, body)
  if not ok or type(data) ~= "table" then
    return nil, "JSON parse failed: " .. tostring(data)
  end
  return data, nil
end

return M
