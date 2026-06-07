-- mDNS discovery for MiniDSP SHD / Volumio
-- Volumio broadcasts "_volumio._tcp.local" via mDNS (avahi).
-- Falls back to a manual placeholder when nothing responds.
local log       = require "log"
local mdns      = require "st.mdns"
local net_utils = require "st.net_utils"

local SERVICE_TYPE = "_volumio._tcp"
local DOMAIN       = "local"

local function dni_for_ip(ip)
  return "minidsp-shd-" .. ip:gsub("%.", "-")
end

local function device_exists(driver, dni)
  for _, dev in ipairs(driver:get_devices()) do
    if dev.device_network_id == dni then return true end
  end
  return false
end

local function create_device(driver, ip)
  local dni = dni_for_ip(ip)
  if device_exists(driver, dni) then
    log.info("Device already registered for " .. ip)
    return
  end

  local ok, err = pcall(driver.try_create_device, driver, {
    type              = "LAN",
    device_network_id = dni,
    label             = "MiniDSP SHD",
    profile           = "minidsp-shd",
    manufacturer      = "MiniDSP",
    model             = "SHD",
  })
  if ok then
    log.info("Device created for " .. ip .. " (dni=" .. dni .. ")")
  else
    log.error("Device creation failed for " .. ip .. ": " .. tostring(err))
  end
end

local discovery = {}

function discovery.start(driver, opts, cont)
  log.info("MiniDSP SHD mDNS discovery started (service=" .. SERVICE_TYPE .. ")")

  local responses, err = mdns.discover(SERVICE_TYPE, DOMAIN)
  if err then
    log.error("mDNS discover error: " .. tostring(err))
    return
  end

  local found_count = 0

  if responses and responses.found then
    for _, item in ipairs(responses.found) do
      local ip = item.host_info and item.host_info.address
      if ip and net_utils.validate_ipv4_string(ip) then
        log.info("Volumio/MiniDSP SHD found via mDNS at " .. ip)
        create_device(driver, ip)
        found_count = found_count + 1
      end
    end
  end

  -- Also check answers section (ARecord) as some drivers need this path
  if responses and responses.answers then
    for _, answer in ipairs(responses.answers) do
      local ip = answer.kind and answer.kind.ARecord and answer.kind.ARecord.ipv4
      if ip and net_utils.validate_ipv4_string(ip) then
        local dni = dni_for_ip(ip)
        if not device_exists(driver, dni) then
          log.info("Volumio/MiniDSP SHD found via mDNS (ARecord) at " .. ip)
          create_device(driver, ip)
          found_count = found_count + 1
        end
      end
    end
  end

  if found_count == 0 then
    log.info("No Volumio found via mDNS — creating manual placeholder")
    if #driver:get_devices() == 0 then
      local ok, create_err = pcall(driver.try_create_device, driver, {
        type              = "LAN",
        device_network_id = "minidsp-shd-manual",
        label             = "MiniDSP SHD",
        profile           = "minidsp-shd",
        manufacturer      = "MiniDSP",
        model             = "SHD",
      })
      if not ok then
        log.error("Placeholder creation failed: " .. tostring(create_err))
      else
        log.info("Placeholder created — configure IP in device preferences")
      end
    end
  end
end

-- Parses IP encoded in device_network_id by create_device()
-- Returns IP string or nil (nil = manual placeholder, use preferences)
function discovery.ip_from_dni(device)
  local a, b, c, d = (device.device_network_id or ""):match(
    "minidsp%-shd%-(%d+)%-(%d+)%-(%d+)%-(%d+)$"
  )
  if a then return a .. "." .. b .. "." .. c .. "." .. d end
  return nil
end

return discovery
