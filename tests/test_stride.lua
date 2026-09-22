local testlib = require("testlib")

local function loadStride()
    return testlib.loadAddon({
        "AzerothTravelMetrics\\Namespace.lua",
        "AzerothTravelMetrics\\Distance.lua",
        "AzerothTravelMetrics\\Stride.lua",
    })
end

testlib.case("stride uses race-specific estimates", function()
    local addon = loadStride()
    local expectedMeters = {
        Human = 0.80,
        Orc = 0.86,
        Dwarf = 0.66,
        NightElf = 0.90,
        Scourge = 0.78,
        Tauren = 1.05,
        Gnome = 0.52,
        Troll = 0.94,
        BloodElf = 0.82,
        Draenei = 0.92,
        Goblin = 0.56,
        Worgen = 0.92,
        Pandaren = 0.82,
        Nightborne = 0.86,
        HighmountainTauren = 1.05,
        VoidElf = 0.82,
        LightforgedDraenei = 0.92,
        ZandalariTroll = 0.98,
        KulTiran = 0.91,
        DarkIronDwarf = 0.66,
        Vulpera = 0.58,
        MagharOrc = 0.86,
        Mechagnome = 0.52,
        Dracthyr = 0.92,
        EarthenDwarf = 0.68,
    }

    for raceFile, meters in pairs(expectedMeters) do
        testlib.equal(addon.Stride.GetMeters(raceFile), meters, raceFile)
    end

    testlib.truthy(addon.Stride.GetMeters("Tauren") > addon.Stride.GetMeters("Gnome"))
end)

testlib.case("stride uses the neutral fallback for unknown races", function()
    local addon = loadStride()

    testlib.equal(addon.Stride.DEFAULT_METERS, 0.80)
    testlib.equal(addon.Stride.GetMeters("UnknownRace"), addon.Stride.DEFAULT_METERS)
end)

testlib.case("stride estimates human steps from yards", function()
    local addon = loadStride()
    local yardsForOneKilometer = 1000 / addon.Distance.YARDS_TO_METERS

    testlib.equal(addon.Stride.EstimateSteps(yardsForOneKilometer, "Human"), 1250)
end)

testlib.case("stride estimates zero steps for zero distance", function()
    local addon = loadStride()

    testlib.equal(addon.Stride.EstimateSteps(0, "Human"), 0)
end)

testlib.case("stride estimates steps using a non-human race stride", function()
    local addon = loadStride()
    local yardsForOneKilometer = 1000 / addon.Distance.YARDS_TO_METERS

    testlib.equal(addon.Stride.EstimateSteps(yardsForOneKilometer, "Tauren"), 952)
end)

testlib.case("stride rounds fractional step estimates upward", function()
    local addon = loadStride()
    local rawSteps = 1.6
    local yards = rawSteps * addon.Stride.GetMeters("Human") / addon.Distance.YARDS_TO_METERS

    testlib.equal(addon.Stride.EstimateSteps(yards, "Human"), 2)
end)
