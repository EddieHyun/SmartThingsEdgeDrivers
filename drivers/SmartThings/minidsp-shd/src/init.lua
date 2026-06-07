local Driver       = require "st.driver"
local capabilities = require "st.capabilities"
local log          = require "log"

local discovery   = require "discovery"
local http_client = require "http_client"

-- ── address resolution ────────────────────────────────────────────────────────
-- Priority: persisted device field (set on init or infoChanged)
--           → IP encoded in device_network_id (SSDP-discovered devices)
--           → ipAddress preference (manual placeholder devices)

local function device_address(device)
  local ip   = device:get_field("ip")
               or discovery.ip_from_dni(device)
               or device.preferences.ipAddress
  local port = tonumber(device.preferences.port) or 80
  return ip, port
end

-- ── polling ───────────────────────────────────────────────────────────────────

local function schedule_poll(driver, device)
  local interval = tonumber(device.preferences.pollInterval) or 30
  driver:call_with_delay(interval, function(d)
    local ip, port = device_address(device)
    log.debug("polling " .. tostring(ip) .. ":" .. tostring(port))

    local state, err = http_client.get_state(ip, port)
    if err then
      log.warn("poll failed (" .. device.id .. "): " .. tostring(err))
      device:emit_event(capabilities.switch.switch.off())
    else
      device:emit_event(capabilities.switch.switch.on())
      if type(state.volume) == "number" then
        device:emit_event(capabilities.audioVolume.volume({ value = state.volume, unit = "%" }))
      end
    end

    schedule_poll(d, device)
  end)
end

-- ── capability handlers ───────────────────────────────────────────────────────

local function handle_volume_up(driver, device, command)
  local ip, port = device_address(device)
  local _, err = http_client.volume_up(ip, port)
  if err then log.error("volume_up: " .. tostring(err)) end
end

local function handle_volume_down(driver, device, command)
  local ip, port = device_address(device)
  local _, err = http_client.volume_down(ip, port)
  if err then log.error("volume_down: " .. tostring(err)) end
end

local function handle_set_volume(driver, device, command)
  local ip, port = device_address(device)
  local volume = command.args.volume
  local _, err = http_client.set_volume(ip, port, volume)
  if err then
    log.error("set_volume: " .. tostring(err))
    return
  end
  device:emit_event(capabilities.audioVolume.volume({ value = volume, unit = "%" }))
end

local function handle_switch_on(driver, device, command)
  local ip, port = device_address(device)
  local _, err = http_client.power_on(ip, port)
  if err then
    log.error("power_on: " .. tostring(err))
    return
  end
  device:emit_event(capabilities.switch.switch.on())
end

local function handle_switch_off(driver, device, command)
  local ip, port = device_address(device)
  local _, err = http_client.power_off(ip, port)
  if err then
    log.error("power_off: " .. tostring(err))
    return
  end
  device:emit_event(capabilities.switch.switch.off())
end

-- ── lifecycle handlers ────────────────────────────────────────────────────────

local function device_added(driver, device)
  log.info("device_added: " .. device.id)
end

local function device_init(driver, device)
  log.info("device_init: " .. device.id)

  -- Persist IP from device_network_id for mDNS-discovered devices so that
  -- device_address() always finds an ip field regardless of preferences state.
  local mdns_ip = discovery.ip_from_dni(device)
  if mdns_ip then
    device:set_field("ip", mdns_ip, { persist = true })
    log.info("Stored mDNS-discovered IP " .. mdns_ip .. " for " .. device.id)
  end

  schedule_poll(driver, device)
end

local function info_changed(driver, device, event, args)
  if args.preferences and args.preferences.ipAddress then
    local new_ip = args.preferences.ipAddress
    device:set_field("ip", new_ip, { persist = true })
    log.info("IP updated to " .. new_ip .. " for " .. device.id)
  end
end

local function device_removed(driver, device)
  log.info("device_removed: " .. device.id)
end

-- ── driver ────────────────────────────────────────────────────────────────────

local driver = Driver("minidsp-shd", {
  discovery = discovery.start,
  lifecycle_handlers = {
    added       = device_added,
    init        = device_init,
    removed     = device_removed,
    infoChanged = info_changed,
  },
  capability_handlers = {
    [capabilities.audioVolume.ID] = {
      [capabilities.audioVolume.commands.volumeUp.NAME]   = handle_volume_up,
      [capabilities.audioVolume.commands.volumeDown.NAME] = handle_volume_down,
      [capabilities.audioVolume.commands.setVolume.NAME]  = handle_set_volume,
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME]  = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
  },
})

driver:run()
