-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"
local WindowCovering = clusters.WindowCovering

-- mock the actual device
local mock_device = test.mock_device.build_test_matter_device(
                      {
    profile = t_utils.get_profile_definition("window-covering-profile.yml"),
    manufacture_info = {vendor_id = 0x0000, product_id = 0x0000},
    endpoints = {
      {
        endpoint_id = 1,
        clusters = { -- list the clusters
          {
            cluster_id = clusters.WindowCovering.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 0,
            attributes = nil,
            server_commands = nil,
            client_commands = nil,
            event = nil,
          },
          {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER"}
        },
      },
    }, -- ]]
  }
                    )
-- add device for each mock device

local CLUSTER_SUBSCRIBE_LIST = {
  clusters.LevelControl.server.attributes.CurrentLevel,
  WindowCovering.server.attributes.CurrentPositionLiftPercent100ths,
  WindowCovering.server.attributes.OperationalStatus,
  clusters.PowerSource.server.attributes.BatPercentRemaining
}

local function test_init()
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Window Shade state closed", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 1, 10000
        ),
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 1, 0),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(0)
      )
    )
  end
)

test.register_coroutine_test(
  "Window Shade state open", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 1, 0
        ),
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 1, 0),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(100)
      )
    )
  end
)

test.register_coroutine_test(
  "Window Shade state partially open", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 1, ((100 - 25) *100)
        ),
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 1, 0),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(25)
      )
    )
  end
)

test.register_coroutine_test(
  "WindowShadeLevel cmd handler with difference more than 1 second", function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {
          capability = "windowShadeLevel",
          component = "main",
          command = "setShadeLevel",
          args = {33},
        },
      }
    )
    -- Command send after delay
    test.mock_time.advance_time(2)
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 1, (100-33), (100*(100-33)))}
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "WindowShade open cmd handler", function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShade", component = "main", command = "open", args = {}},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.UpOrOpen(mock_device, 1)}
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "WindowShade close cmd handler", function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShade", component = "main", command = "close", args = {}},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.DownOrClose(mock_device, 1)}
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "WindowShade pause cmd handler", function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShade", component = "main", command = "pause", args = {}},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.StopMotion(mock_device, 1)}
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Refresh necessary attributes", function()
    test.socket.device_lifecycle:__queue_receive({mock_device.id, "added"})
    test.socket.capability:__expect_send(
      {
        mock_device.id,
        {
          capability_id = "windowShade",
          component_id = "main",
          attribute_id = "supportedWindowShadeCommands",
          state = {value = {"open", "close", "pause"}},
        },
      }
    )
    test.wait_for_events()

    test.socket.capability:__queue_receive(
      {mock_device.id, {capability = "refresh", component = "main", command = "refresh", args = {}}}
    )
    local read_request = CLUSTER_SUBSCRIBE_LIST[1]:read(mock_device)
    for i, attr in ipairs(CLUSTER_SUBSCRIBE_LIST) do
      if i > 1 then read_request:merge(attr:read(mock_device)) end
    end
    test.socket.matter:__expect_send({mock_device.id, read_request})
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "WindowShade set level cmd handler", function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 1, (20 * 100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(100 -20)
      )
    )
    test.wait_for_events()
  end
)

--test battery
test.register_coroutine_test(
  "Battery percent reports should generate correct messages", function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(
          mock_device, 1, 150
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.battery.battery(math.floor(150/2.0+0.5))
      )
    )
    test.wait_for_events()
  end
)

test.run_registered_tests()
