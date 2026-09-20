local testlib = require("testlib")

testlib.case("namespace defines schema version and travel categories", function()
    local globals = {
        suppliedGlobal = "available",
    }
    local addon, environment = testlib.loadAddon("AzerothTravelTracker\\Namespace.lua", globals)

    testlib.equal(addon.name, "AzerothTravelTracker")
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
    local emitted, reason, failures = addon.Emit("distanceChanged", 42)
    testlib.equal(emitted, true)
    testlib.equal(reason, nil)
    testlib.equal(failures, nil)
    testlib.truthy(received == 42)
end)

testlib.case("namespace isolates throwing subscribers and reports failures", function()
    local addon = testlib.loadAddon("AzerothTravelTracker\\Namespace.lua")
    local callbacks = {}

    addon.Subscribe("movementSegment", function()
        table.insert(callbacks, "first")
        error("subscriber failed")
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
    testlib.equal(failures, 1)
    testlib.equal(callbacks[1], "first")
    testlib.equal(callbacks[2], "later subscriber")
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
