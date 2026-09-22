local testlib = require("testlib")

testlib.case("namespace defines schema version and travel categories", function()
    local globals = {
        suppliedGlobal = "available",
    }
    local addon, environment = testlib.loadAddon(
        "AzerothTravelMetrics\\Namespace.lua",
        globals,
        "AzerothTravelMetrics"
    )

    testlib.equal(addon.name, "AzerothTravelMetrics")
    testlib.equal(addon.SCHEMA_VERSION, 1)
    testlib.near(addon.SAMPLE_INTERVAL_SECONDS, 0.5, 0.0001)
    testlib.equal(addon.MAX_SAMPLE_GAP_SECONDS, 3)
    testlib.equal(addon.Categories.ON_FOOT, "onFoot")
    testlib.equal(addon.Categories.SWIMMING, "swimming")
    testlib.equal(addon.Categories.TAXI, "taxi")
    testlib.equal(environment, globals)
    testlib.equal(environment.suppliedGlobal, "available")

    local received
    addon.Subscribe("distanceChanged", function(payload)
        received = payload
    end)
    local emitted = addon.Emit("distanceChanged", 42)
    testlib.equal(emitted, nil)
    testlib.truthy(received == 42)
end)

testlib.case("namespace isolates throwing subscribers and reports failures", function()
    local addon = testlib.loadAddon("AzerothTravelMetrics\\Namespace.lua")
    local callbacks = {}

    addon.Subscribe("movementSegment", function()
        table.insert(callbacks, "first")
        error("first subscriber failed")
    end)
    addon.Subscribe("movementSegment", function()
        table.insert(callbacks, "second")
        error("second subscriber failed")
    end)
    addon.Subscribe("movementSegment", function(payload)
        table.insert(callbacks, payload)
    end)

    local succeeded, emitted, reason, failures = pcall(
        addon.Emit,
        "movementSegment",
        "later subscriber"
    )

    testlib.equal(succeeded, true)
    testlib.equal(emitted, false)
    testlib.equal(reason, "subscriberFailed")
    testlib.equal(type(failures), "table")
    testlib.equal(#failures, 2)
    testlib.equal(failures[1].subscriber, 1)
    testlib.truthy(
        failures[1].error:find("first subscriber failed", 1, true) ~= nil
    )
    testlib.equal(failures[2].subscriber, 2)
    testlib.truthy(
        failures[2].error:find("second subscriber failed", 1, true) ~= nil
    )
    testlib.equal(callbacks[1], "first")
    testlib.equal(callbacks[2], "second")
    testlib.equal(callbacks[3], "later subscriber")
end)

testlib.case("namespace preserves unprintable subscriber errors without aborting", function()
    local addon = testlib.loadAddon("AzerothTravelMetrics\\Namespace.lua")
    local hostileError = setmetatable({}, {
        __tostring = function()
            error("error formatting failed")
        end,
    })
    local laterSubscriberRan = false

    addon.Subscribe("movementSegment", function()
        error(hostileError)
    end)
    addon.Subscribe("movementSegment", function()
        laterSubscriberRan = true
    end)

    local succeeded, emitted, reason, failures = pcall(
        addon.Emit,
        "movementSegment",
        {}
    )

    testlib.equal(succeeded, true)
    testlib.equal(emitted, false)
    testlib.equal(reason, "subscriberFailed")
    testlib.equal(failures[1].error, hostileError)
    testlib.equal(laterSubscriberRan, true)
end)

testlib.case("near rejects NaN values", function()
    local nan = 0 / 0

    local actualAccepted = pcall(testlib.near, nan, 1, 0.1)
    local expectedAccepted = pcall(testlib.near, 1, nan, 0.1)
    local toleranceAccepted = pcall(testlib.near, 1, 1, nan)

    testlib.equal(actualAccepted, false)
    testlib.equal(expectedAccepted, false)
    testlib.equal(toleranceAccepted, false)
end)
