local testlib = require("testlib")

local function loadMovement()
    return testlib.loadAddon({
        "AzerothTravelTracker\\Namespace.lua",
        "AzerothTravelTracker\\Movement.lua",
    })
end

local function sample(overrides)
    local value = {
        x = 0,
        y = 0,
        z = 0,
        mapID = 1,
        instanceID = 1,
        time = 10,
        onTaxi = false,
        swimming = false,
        mounted = false,
        grounded = true,
    }

    for key, override in pairs(overrides or {}) do
        value[key] = override
    end

    return value
end

local function assertRejected(from, to, expectedReason)
    local addon = loadMovement()
    local segment, reason = addon.Movement.BuildSegment(from, to)

    testlib.equal(segment, nil)
    testlib.equal(reason, expectedReason)
end

testlib.case("movement calculates 3D world-coordinate distance", function()
    local addon = loadMovement()
    local from = sample({ x = 1, y = 2, z = 3 })
    local to = sample({ x = 4, y = 6, z = 3 })

    testlib.equal(addon.Movement.Distance(from, to), 5)
end)

testlib.case("movement builds an on-foot segment and preserves sample references", function()
    local addon = loadMovement()
    local from = sample({ x = 1, y = 2, z = 3, time = 10 })
    local to = sample({ x = 4, y = 6, z = 3, time = 11 })

    local segment, reason = addon.Movement.BuildSegment(from, to)

    testlib.equal(reason, nil)
    testlib.equal(segment.category, addon.Categories.ON_FOOT)
    testlib.equal(segment.yards, 5)
    testlib.equal(segment.elapsed, 1)
    testlib.equal(segment.from, from)
    testlib.equal(segment.to, to)
end)

testlib.case("movement independently classifies taxi and swimming samples", function()
    local addon = loadMovement()
    local cases = {
        {
            name = "taxi",
            overrides = {
                onTaxi = true,
                swimming = false,
                mounted = false,
                grounded = false,
            },
            expected = addon.Categories.TAXI,
        },
        {
            name = "swimming",
            overrides = {
                onTaxi = false,
                swimming = true,
                mounted = false,
                grounded = false,
            },
            expected = addon.Categories.SWIMMING,
        },
    }

    for _, case in ipairs(cases) do
        local from = sample(case.overrides)
        local toOverrides = {}
        for key, value in pairs(case.overrides) do
            toOverrides[key] = value
        end
        toOverrides.x = 5
        toOverrides.time = 11
        local to = sample(toOverrides)

        testlib.equal(addon.Movement.Classify(from), case.expected, case.name .. " classification failed")

        local segment, reason = addon.Movement.BuildSegment(from, to)
        testlib.equal(reason, nil, case.name .. " segment was rejected")
        testlib.equal(segment.category, case.expected, case.name .. " segment category was wrong")
    end
end)

testlib.case("movement rejects contradictory taxi and swimming state", function()
    local addon = loadMovement()
    local contradictory = sample({
        onTaxi = true,
        swimming = true,
        mounted = false,
        grounded = false,
    })

    local category, reason = addon.Movement.Classify(contradictory)
    testlib.equal(category, nil)
    testlib.equal(reason, "unsupportedState")

    assertRejected(
        contradictory,
        sample({
            x = 1,
            time = 11,
            onTaxi = true,
            swimming = true,
            mounted = false,
            grounded = false,
        }),
        "unsupportedState"
    )
end)

testlib.case("movement rejects mounted travel outside taxi", function()
    local addon = loadMovement()
    local mounted = sample({
        onTaxi = false,
        swimming = false,
        mounted = true,
        grounded = true,
    })

    local category, reason = addon.Movement.Classify(mounted)
    testlib.equal(category, nil)
    testlib.equal(reason, "unsupportedState")

    assertRejected(
        mounted,
        sample({
            x = 1,
            time = 11,
            onTaxi = false,
            swimming = false,
            mounted = true,
            grounded = true,
        }),
        "unsupportedState"
    )
end)

testlib.case("movement rejects missing and non-boolean state flags", function()
    local addon = loadMovement()
    local cases = {
        { name = "missing onTaxi", key = "onTaxi", value = nil },
        { name = "missing swimming", key = "swimming", value = nil },
        { name = "missing mounted", key = "mounted", value = nil },
        { name = "missing grounded", key = "grounded", value = nil },
        { name = "unknown grounded state", key = "grounded", value = false },
        { name = "nonnumeric truthy state", key = "onTaxi", value = 1 },
    }

    for _, case in ipairs(cases) do
        local unknown = sample()
        unknown[case.key] = case.value

        local category, reason = addon.Movement.Classify(unknown)
        testlib.equal(category, nil, case.name .. " was classified")
        testlib.equal(reason, "unsupportedState", case.name .. " returned the wrong reason")
    end
end)

testlib.case("movement rejects missing invalid and non-finite coordinates without throwing", function()
    local invalidValues = {
        { name = "missing", value = nil },
        { name = "nonnumeric", value = "1" },
        { name = "NaN", value = 0 / 0 },
        { name = "positive infinity", value = math.huge },
        { name = "negative infinity", value = -math.huge },
    }
    local fields = {
        "x",
        "y",
        "z",
        "mapID",
        "instanceID",
        "time",
    }

    for _, endpoint in ipairs({ "from", "to" }) do
        for _, field in ipairs(fields) do
            for _, invalid in ipairs(invalidValues) do
                local from = sample()
                local to = sample({ x = 1, time = 11 })
                local target = endpoint == "from" and from or to
                target[field] = invalid.value

                local succeeded, segment, reason = pcall(function()
                    local addon = loadMovement()
                    return addon.Movement.BuildSegment(from, to)
                end)

                local caseName = endpoint .. " " .. field .. " " .. invalid.name
                testlib.equal(succeeded, true, caseName .. " raised an error")
                testlib.equal(segment, nil, caseName .. " was accepted")
                testlib.equal(reason, "missingPosition", caseName .. " returned the wrong reason")
            end
        end
    end
end)

testlib.case("movement distance rejects invalid coordinates without throwing", function()
    local addon = loadMovement()
    local invalid = sample({ x = math.huge })
    local valid = sample({ x = 1 })

    local succeeded, yards, reason = pcall(addon.Movement.Distance, invalid, valid)

    testlib.equal(succeeded, true)
    testlib.equal(yards, nil)
    testlib.equal(reason, "missingPosition")
end)

testlib.case("movement rejects map and instance discontinuities", function()
    assertRejected(sample(), sample({ x = 1, time = 11, mapID = 2 }), "mapChanged")
    assertRejected(sample(), sample({ x = 1, time = 11, instanceID = 2 }), "instanceChanged")
end)

testlib.case("movement rejects invalid elapsed time and sample gaps", function()
    local cases = {
        { name = "zero elapsed", time = 10, reason = "invalidElapsed" },
        { name = "negative elapsed", time = 9, reason = "invalidElapsed" },
        { name = "sample gap", time = 13.001, reason = "sampleGap" },
    }

    for _, case in ipairs(cases) do
        assertRejected(sample(), sample({ x = 1, time = case.time }), case.reason)
    end
end)

testlib.case("movement allows exactly the maximum sample gap", function()
    local addon = loadMovement()
    local from = sample()
    local to = sample({ x = 1, time = 10 + addon.MAX_SAMPLE_GAP_SECONDS })

    local segment, reason = addon.Movement.BuildSegment(from, to)

    testlib.equal(reason, nil)
    testlib.equal(segment.elapsed, addon.MAX_SAMPLE_GAP_SECONDS)
end)

testlib.case("movement rejects stationary samples after state and time validation", function()
    assertRejected(sample(), sample({ time = 11 }), "stationary")
end)

testlib.case("movement rejects unsupported endpoints and category transitions", function()
    assertRejected(
        sample({
            onTaxi = false,
            swimming = false,
            mounted = true,
            grounded = true,
        }),
        sample({ x = 1, time = 11 }),
        "unsupportedState"
    )
    assertRejected(
        sample(),
        sample({
            x = 1,
            time = 11,
            onTaxi = false,
            swimming = true,
            mounted = false,
            grounded = false,
        }),
        "unsupportedState"
    )
end)

testlib.case("movement enforces conservative category speed limits", function()
    local addon = loadMovement()
    local cases = {
        {
            name = "on foot",
            category = addon.Categories.ON_FOOT,
            limit = 20,
            state = {
                onTaxi = false,
                swimming = false,
                mounted = false,
                grounded = true,
            },
        },
        {
            name = "swimming",
            category = addon.Categories.SWIMMING,
            limit = 15,
            state = {
                onTaxi = false,
                swimming = true,
                mounted = false,
                grounded = false,
            },
        },
        {
            name = "taxi",
            category = addon.Categories.TAXI,
            limit = 200,
            state = {
                onTaxi = true,
                swimming = false,
                mounted = false,
                grounded = false,
            },
        },
    }

    for _, case in ipairs(cases) do
        local from = sample(case.state)

        for _, distance in ipairs({ case.limit - 0.001, case.limit }) do
            local toOverrides = {
                x = distance,
                time = 11,
            }
            for key, value in pairs(case.state) do
                toOverrides[key] = value
            end

            local segment, reason = addon.Movement.BuildSegment(from, sample(toOverrides))
            testlib.equal(reason, nil, case.name .. " rejected distance " .. tostring(distance))
            testlib.equal(segment.category, case.category)
        end

        local aboveLimit = {
            x = case.limit + 0.001,
            time = 11,
        }
        for key, value in pairs(case.state) do
            aboveLimit[key] = value
        end

        local segment, reason = addon.Movement.BuildSegment(from, sample(aboveLimit))
        testlib.equal(segment, nil, case.name .. " accepted an implausible speed")
        testlib.equal(reason, "implausibleSpeed")
    end
end)

testlib.case("movement rejects non-finite calculated speed", function()
    assertRejected(
        sample({ time = 0 }),
        sample({ x = 1e308, time = 1e-308 }),
        "implausibleSpeed"
    )
end)
