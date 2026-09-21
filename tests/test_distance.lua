local testlib = require("testlib")

local function loadDistance()
    return testlib.loadAddon({
        "AzerothTravelTracker\\Namespace.lua",
        "AzerothTravelTracker\\Distance.lua",
    })
end

testlib.case("distance converts yards to meters", function()
    local addon = loadDistance()

    testlib.equal(addon.Distance.YARDS_TO_METERS, 0.9144)
    testlib.equal(addon.Distance.YARDS_PER_MILE, 1760)
    testlib.near(addon.Distance.YardsToMeters(100), 91.44, 0.001)
end)

testlib.case("distance formats large numbers with compact WoW suffixes", function()
    local addon = loadDistance()

    testlib.equal(addon.Distance.FormatNumber(9999), "9999")
    testlib.equal(addon.Distance.FormatNumber(10000), "10.0K")
    testlib.equal(addon.Distance.FormatNumber(12500), "12.5K")
    testlib.equal(addon.Distance.FormatNumber(125000), "125K")
    testlib.equal(addon.Distance.FormatNumber(1250000), "1.25M")
    testlib.equal(addon.Distance.FormatNumber(1250000000), "1.25B")
end)

testlib.case("distance compact formatting carries across precision bands", function()
    local addon = loadDistance()

    testlib.equal(addon.Distance.FormatNumber(9999999), "10.0M")
    testlib.equal(addon.Distance.FormatNumber(99999999), "100M")
    testlib.equal(addon.Distance.FormatNumber(9999999999), "10.0B")
end)

testlib.case("distance compact formatting promotes rounded suffixes", function()
    local addon = loadDistance()

    testlib.equal(addon.Distance.FormatNumber(999999), "1.00M")
    testlib.equal(addon.Distance.FormatNumber(999999999), "1.00B")
end)

testlib.case("distance formats metric yards as meters", function()
    local addon = loadDistance()

    testlib.equal(addon.Distance.Format(100, "metric"), "91.4 m")
end)

testlib.case("distance formats metric yards as kilometers", function()
    local addon = loadDistance()

    testlib.equal(addon.Distance.Format(2000, "metric"), "1.83 km")
end)

testlib.case("distance switches metric units at 1000 meters", function()
    local addon = loadDistance()
    local metricThresholdYards = 1000 / addon.Distance.YARDS_TO_METERS

    testlib.equal(addon.Distance.Format(metricThresholdYards - 0.001, "metric"), "1000.0 m")
    testlib.equal(addon.Distance.Format(metricThresholdYards, "metric"), "1.00 km")
    testlib.equal(addon.Distance.Format(1093.6133, "metric"), "1.00 km")
end)

testlib.case("distance compacts large metric kilometer values", function()
    local addon = loadDistance()

    testlib.equal(addon.Distance.Format(10936133, "metric"), "10.0K km")
end)

testlib.case("distance formats imperial yards as yards", function()
    local addon = loadDistance()

    testlib.equal(addon.Distance.Format(100, "imperial"), "100 yd")
end)

testlib.case("distance switches imperial units at one mile", function()
    local addon = loadDistance()

    testlib.equal(addon.Distance.Format(1759.999, "imperial"), "1760 yd")
    testlib.equal(addon.Distance.Format(1760, "imperial"), "1.00 mi")
    testlib.equal(addon.Distance.Format(17600000, "imperial"), "10.0K mi")
end)

testlib.case("distance defaults unknown units to metric", function()
    local addon = loadDistance()

    testlib.equal(addon.Distance.Format(100), "91.4 m")
    testlib.equal(addon.Distance.Format(100, "unknown"), "91.4 m")
end)
