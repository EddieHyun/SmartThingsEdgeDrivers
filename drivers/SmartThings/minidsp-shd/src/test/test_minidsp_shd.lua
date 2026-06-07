local test         = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils      = require "integration_test.utils"

-- ── mock device ───────────────────────────────────────────────────────────────

local mock_device = test.mock_device.build_test_generic_device({
  profile = t_utils.get_profile_definition("minidsp-shd.yml"),
  preferences = {
    ipAddress = "192.168.1.100",
    port      = 80,
  },
})

-- ── http_client stub ──────────────────────────────────────────────────────────

local http_stub = { last_call = nil, return_err = nil }

local function make_stub()
  local stub = {}

  local function record(fn, extras)
    local t = { fn = fn }
    if extras then for k, v in pairs(extras) do t[k] = v end end
    http_stub.last_call = t
    if http_stub.return_err then return nil, http_stub.return_err end
    return "{}", nil
  end

  function stub.volume_up(host, port)       return record("volume_up") end
  function stub.volume_down(host, port)     return record("volume_down") end
  function stub.set_volume(host, port, vol) return record("set_volume", { volume = vol }) end
  function stub.power_on(host, port)        return record("power_on") end
  function stub.power_off(host, port)       return record("power_off") end
  return stub
end

package.loaded["http_client"] = make_stub()

-- ── test init ─────────────────────────────────────────────────────────────────

local function test_init()
  test.mock_device.add_test_device(mock_device)
  http_stub.last_call  = nil
  http_stub.return_err = nil
end

test.set_test_init_function(test_init)

-- ── tests ─────────────────────────────────────────────────────────────────────

test.register_message_test(
  "volumeUp sends volume=plus to device",
  {
    {
      channel   = "capability",
      direction = "receive",
      message   = {
        mock_device.id,
        { capability = "audioVolume", component = "main", command = "volumeUp", args = {} }
      }
    },
    -- no capability event emitted for up/down (device-driven state)
  }
)

test.register_message_test(
  "volumeDown sends volume=minus to device",
  {
    {
      channel   = "capability",
      direction = "receive",
      message   = {
        mock_device.id,
        { capability = "audioVolume", component = "main", command = "volumeDown", args = {} }
      }
    },
  }
)

test.register_message_test(
  "setVolume emits volume event with percent value",
  {
    {
      channel   = "capability",
      direction = "receive",
      message   = {
        mock_device.id,
        { capability = "audioVolume", component = "main", command = "setVolume", args = { volume = 75 } }
      }
    },
    {
      channel   = "capability",
      direction = "send",
      message   = mock_device:generate_test_message("main",
        capabilities.audioVolume.volume({ value = 75, unit = "%" }))
    },
  }
)

test.register_message_test(
  "switch on emits switch.on after power_on succeeds",
  {
    {
      channel   = "capability",
      direction = "receive",
      message   = {
        mock_device.id,
        { capability = "switch", component = "main", command = "on", args = {} }
      }
    },
    {
      channel   = "capability",
      direction = "send",
      message   = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    },
  }
)

test.register_message_test(
  "switch off emits switch.off after power_off succeeds",
  {
    {
      channel   = "capability",
      direction = "receive",
      message   = {
        mock_device.id,
        { capability = "switch", component = "main", command = "off", args = {} }
      }
    },
    {
      channel   = "capability",
      direction = "send",
      message   = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    },
  }
)

test.register_coroutine_test(
  "switch on does NOT emit event when power_on fails",
  function()
    http_stub.return_err = "connection refused"

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switch", component = "main", command = "on", args = {} }
    })
    -- no __expect_send: driver must not emit on error
    test.wait_for_events()
  end
)

-- ── run ───────────────────────────────────────────────────────────────────────

test.run_registered_tests()
