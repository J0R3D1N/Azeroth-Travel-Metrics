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
    addon.Emit("distanceChanged", 42)
    testlib.truthy(received == 42)
end)
