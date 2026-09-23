local testlib = require("testlib")

local function loadUIModel()
    return testlib.loadAddon({
        "AzerothTravelMetrics\\Namespace.lua",
        "AzerothTravelMetrics\\Distance.lua",
        "AzerothTravelMetrics\\Stride.lua",
        "AzerothTravelMetrics\\UIModel.lua",
    })
end

local function newCharacter(raceFile)
    return {
        identity = {
            raceFile = raceFile or "Human",
        },
        lifetime = {
            onFoot = 100,
            swimming = 2000,
            taxi = 1760,
        },
        session = {
            onFoot = 50,
            swimming = 100,
            taxi = 880,
        },
        levels = {
            [2] = {
                reachedAt = 200,
                onFoot = 20,
                swimming = 21,
                taxi = 22,
            },
            [10] = {
                reachedAt = 1000,
                onFoot = 100,
                swimming = 101,
                taxi = 102,
            },
            [20] = {
                reachedAt = 2000,
                onFoot = 200,
                swimming = 201,
                taxi = 202,
            },
        },
        diagnostics = {
            zeta = 3,
            alpha = 1,
            omitted = 0,
        },
    }
end

local function tableKeyCount(value)
    local count = 0
    for _ in pairs(value) do
        count = count + 1
    end
    return count
end

local function assertInvalidStatistics(callback, message)
    local succeeded, result, modelError = pcall(callback)

    testlib.truthy(succeeded, message .. " raised an error")
    testlib.equal(result, nil, message .. " returned a model")
    testlib.equal(modelError, "invalidStatistics", message .. " returned the wrong error")
end

local function assertInvalidDiagnostics(callback, message)
    local succeeded, result, modelError = pcall(callback)

    testlib.truthy(succeeded, message .. " raised an error")
    testlib.equal(result, nil, message .. " returned diagnostics")
    testlib.equal(modelError, "invalidDiagnostics", message .. " returned the wrong error")
end

testlib.case("ui overview contains exactly the three compact summary groups", function()
    local addon = loadUIModel()
    local overview = addon.UIModel.BuildOverview(newCharacter(), 20, "metric")

    testlib.equal(tableKeyCount(overview), 3)
    testlib.truthy(type(overview.lifetime) == "table")
    testlib.truthy(type(overview.session) == "table")
    testlib.truthy(type(overview.currentLevel) == "table")
end)

testlib.case("ui overview derives only on-foot steps using the character race", function()
    local addon = loadUIModel()
    local humanOverview = addon.UIModel.BuildOverview(newCharacter("Human"), 20, "metric")
    local taurenOverview = addon.UIModel.BuildOverview(newCharacter("Tauren"), 20, "metric")

    testlib.equal(humanOverview.lifetime.rawSteps, 114)
    testlib.equal(humanOverview.lifetime.steps, "114")
    testlib.equal(taurenOverview.lifetime.rawSteps, 87)
    testlib.equal(taurenOverview.lifetime.steps, "87")
    testlib.equal(humanOverview.lifetime.swimmingSteps, nil)
    testlib.equal(humanOverview.lifetime.taxiSteps, nil)
    testlib.equal(humanOverview.session.swimmingSteps, nil)
    testlib.equal(humanOverview.session.taxiSteps, nil)
    testlib.equal(humanOverview.currentLevel.swimmingSteps, nil)
    testlib.equal(humanOverview.currentLevel.taxiSteps, nil)
end)

testlib.case("ui overview compacts large step totals and preserves raw steps", function()
    local addon = loadUIModel()
    local character = newCharacter()
    character.lifetime.onFoot = 12500 * addon.Stride.GetMeters("Human")
        / addon.Distance.YARDS_TO_METERS

    local overview = addon.UIModel.BuildOverview(character, 20, "metric")

    testlib.equal(overview.lifetime.rawSteps, 12500)
    testlib.equal(overview.lifetime.steps, "12.5K")
end)

testlib.case("ui overview includes raw and metric formatted category values", function()
    local addon = loadUIModel()
    local overview = addon.UIModel.BuildOverview(newCharacter(), 20, "metric")

    testlib.equal(overview.lifetime.onFootYards, 100)
    testlib.equal(overview.lifetime.swimmingYards, 2000)
    testlib.equal(overview.lifetime.taxiYards, 1760)
    testlib.equal(overview.lifetime.totalYards, 3860)
    testlib.equal(overview.lifetime.onFoot, "91.4 m")
    testlib.equal(overview.lifetime.swimming, "1.83 km")
    testlib.equal(overview.lifetime.taxi, "1.61 km")
    testlib.equal(overview.lifetime.total, "3.53 km")

    testlib.equal(overview.session.totalYards, 1030)
    testlib.equal(overview.session.total, "941.8 m")

    testlib.equal(overview.currentLevel.onFootYards, 200)
    testlib.equal(overview.currentLevel.swimmingYards, 201)
    testlib.equal(overview.currentLevel.taxiYards, 202)
    testlib.equal(overview.currentLevel.totalYards, 603)
    testlib.equal(overview.currentLevel.onFoot, "182.9 m")
    testlib.equal(overview.currentLevel.swimming, "183.8 m")
    testlib.equal(overview.currentLevel.taxi, "184.7 m")
    testlib.equal(overview.currentLevel.total, "551.4 m")
end)

testlib.case("ui overview uses imperial only when explicitly selected", function()
    local addon = loadUIModel()
    local imperial = addon.UIModel.BuildOverview(newCharacter(), 20, "imperial")
    local unknown = addon.UIModel.BuildOverview(newCharacter(), 20, "unknown")

    testlib.equal(imperial.lifetime.onFoot, "100 yd")
    testlib.equal(imperial.lifetime.swimming, "1.14 mi")
    testlib.equal(imperial.lifetime.taxi, "1.00 mi")
    testlib.equal(imperial.lifetime.total, "2.19 mi")
    testlib.equal(unknown.lifetime.onFoot, "91.4 m")
    testlib.equal(unknown.lifetime.total, "3.53 km")
end)

testlib.case("changing overview units changes strings only", function()
    local addon = loadUIModel()
    local metric = addon.UIModel.BuildOverview(newCharacter("Orc"), 20, "metric")
    local imperial = addon.UIModel.BuildOverview(newCharacter("Orc"), 20, "imperial")

    for _, groupName in ipairs({ "lifetime", "session", "currentLevel" }) do
        local metricGroup = metric[groupName]
        local imperialGroup = imperial[groupName]

        testlib.equal(metricGroup.rawSteps, imperialGroup.rawSteps)
        testlib.equal(metricGroup.steps, imperialGroup.steps)
        testlib.equal(metricGroup.onFootYards, imperialGroup.onFootYards)
        testlib.equal(metricGroup.swimmingYards, imperialGroup.swimmingYards)
        testlib.equal(metricGroup.taxiYards, imperialGroup.taxiYards)
        testlib.equal(metricGroup.totalYards, imperialGroup.totalYards)
        testlib.truthy(metricGroup.onFoot ~= imperialGroup.onFoot)
        testlib.truthy(metricGroup.swimming ~= imperialGroup.swimming)
        testlib.truthy(metricGroup.taxi ~= imperialGroup.taxi)
        testlib.truthy(metricGroup.total ~= imperialGroup.total)
    end
end)

testlib.case("ui overview selects the requested current level bucket", function()
    local addon = loadUIModel()
    local overview = addon.UIModel.BuildOverview(newCharacter(), 10, "metric")

    testlib.equal(overview.currentLevel.onFootYards, 100)
    testlib.equal(overview.currentLevel.swimmingYards, 101)
    testlib.equal(overview.currentLevel.taxiYards, 102)
end)

testlib.case("ui overview reports a missing current level bucket explicitly", function()
    local addon = loadUIModel()
    local overview, modelError = addon.UIModel.BuildOverview(newCharacter(), 30, "metric")

    testlib.equal(overview, nil)
    testlib.equal(modelError, "levelUnavailable")
end)

testlib.case("ui level rows sort numeric levels descending", function()
    local addon = loadUIModel()
    local rows = addon.UIModel.BuildLevelRows(newCharacter(), "metric")

    testlib.equal(#rows, 3)
    testlib.equal(rows[1].level, 20)
    testlib.equal(rows[2].level, 10)
    testlib.equal(rows[3].level, 2)
end)

testlib.case("ui level rows preserve timestamps and represent every category", function()
    local addon = loadUIModel()
    local rows = addon.UIModel.BuildLevelRows(newCharacter(), "imperial")
    local row = rows[1]

    testlib.equal(row.reachedAt, 2000)
    testlib.equal(row.rawSteps, 229)
    testlib.equal(row.steps, "229")
    testlib.equal(row.onFootYards, 200)
    testlib.equal(row.swimmingYards, 201)
    testlib.equal(row.taxiYards, 202)
    testlib.equal(row.totalYards, 603)
    testlib.equal(row.onFoot, "200 yd")
    testlib.equal(row.swimming, "201 yd")
    testlib.equal(row.taxi, "202 yd")
    testlib.equal(row.total, "603 yd")
    testlib.equal(row.swimmingSteps, nil)
    testlib.equal(row.taxiSteps, nil)
end)

testlib.case("ui diagnostics are empty when disabled", function()
    local addon = loadUIModel()
    local diagnostics = addon.UIModel.BuildDiagnostics({
        diagnostics = "not inspected while disabled",
    }, false)

    testlib.equal(#diagnostics, 0)
end)

testlib.case("ui diagnostics sort reasons and omit zero counts", function()
    local addon = loadUIModel()
    local diagnostics = addon.UIModel.BuildDiagnostics(newCharacter(), true)

    testlib.equal(#diagnostics, 2)
    testlib.equal(diagnostics[1].reason, "alpha")
    testlib.equal(diagnostics[1].count, 1)
    testlib.equal(diagnostics[2].reason, "zeta")
    testlib.equal(diagnostics[2].count, 3)
end)

testlib.case("ui model reports malformed character structures without throwing", function()
    local addon = loadUIModel()
    local malformed = {
        { name = "nil character", value = nil },
        { name = "non-table character", value = "character" },
        {
            name = "missing identity",
            value = {
                lifetime = { onFoot = 0, swimming = 0, taxi = 0 },
                session = { onFoot = 0, swimming = 0, taxi = 0 },
                levels = {},
            },
        },
        {
            name = "missing race",
            value = {
                identity = {},
                lifetime = { onFoot = 0, swimming = 0, taxi = 0 },
                session = { onFoot = 0, swimming = 0, taxi = 0 },
                levels = {},
            },
        },
    }

    for _, example in ipairs(malformed) do
        assertInvalidStatistics(function()
            return addon.UIModel.BuildOverview(example.value, 20, "metric")
        end, example.name .. " overview")
        assertInvalidStatistics(function()
            return addon.UIModel.BuildLevelRows(example.value, "metric")
        end, example.name .. " rows")
    end
end)

testlib.case("ui model reports malformed totals without throwing", function()
    local addon = loadUIModel()
    local invalidValues = {
        { name = "missing", value = nil },
        { name = "string", value = "1" },
        { name = "negative", value = -1 },
        { name = "NaN", value = 0 / 0 },
        { name = "positive infinity", value = math.huge },
    }

    for _, invalid in ipairs(invalidValues) do
        local character = newCharacter()
        character.lifetime.onFoot = invalid.value
        assertInvalidStatistics(function()
            return addon.UIModel.BuildOverview(character, 20, "metric")
        end, invalid.name .. " lifetime total")

        character = newCharacter()
        character.levels[20].taxi = invalid.value
        assertInvalidStatistics(function()
            return addon.UIModel.BuildLevelRows(character, "metric")
        end, invalid.name .. " level total")
    end
end)

testlib.case("ui overview rejects category totals whose sum overflows", function()
    local addon = loadUIModel()
    local character = newCharacter()
    character.lifetime.onFoot = 1e308
    character.lifetime.swimming = 1e308
    character.lifetime.taxi = 1e308

    assertInvalidStatistics(function()
        return addon.UIModel.BuildOverview(character, 20, "metric")
    end, "overflowing lifetime total")
end)

testlib.case("ui level rows reject category totals whose sum overflows", function()
    local addon = loadUIModel()
    local character = newCharacter()
    character.levels[20].onFoot = 1e308
    character.levels[20].swimming = 1e308
    character.levels[20].taxi = 1e308

    assertInvalidStatistics(function()
        return addon.UIModel.BuildLevelRows(character, "metric")
    end, "overflowing level total")
end)

testlib.case("ui model rejects finite totals whose derived steps overflow", function()
    local addon = loadUIModel()
    local character = newCharacter()
    character.lifetime.onFoot = 1.7e308
    character.lifetime.swimming = 0
    character.lifetime.taxi = 0

    assertInvalidStatistics(function()
        return addon.UIModel.BuildOverview(character, 20, "metric")
    end, "overflowing derived lifetime steps")

    character = newCharacter()
    character.levels[20].onFoot = 1.7e308
    character.levels[20].swimming = 0
    character.levels[20].taxi = 0

    assertInvalidStatistics(function()
        return addon.UIModel.BuildLevelRows(character, "metric")
    end, "overflowing derived level steps")
end)

testlib.case("ui model reports malformed levels and timestamps without throwing", function()
    local addon = loadUIModel()
    local malformedLevels = {
        { name = "missing levels", mutate = function(character) character.levels = nil end },
        { name = "non-table levels", mutate = function(character) character.levels = "levels" end },
        { name = "string level", mutate = function(character) character.levels["20"] = character.levels[20] end },
        { name = "fractional level", mutate = function(character) character.levels[1.5] = character.levels[20] end },
        { name = "zero level", mutate = function(character) character.levels[0] = character.levels[20] end },
        { name = "negative level", mutate = function(character) character.levels[-1] = character.levels[20] end },
        { name = "non-table bucket", mutate = function(character) character.levels[30] = "bucket" end },
        { name = "missing reachedAt", mutate = function(character) character.levels[20].reachedAt = nil end },
        { name = "fractional reachedAt", mutate = function(character) character.levels[20].reachedAt = 1.5 end },
        { name = "zero reachedAt", mutate = function(character) character.levels[20].reachedAt = 0 end },
        { name = "infinite reachedAt", mutate = function(character) character.levels[20].reachedAt = math.huge end },
    }

    for _, example in ipairs(malformedLevels) do
        local character = newCharacter()
        example.mutate(character)
        assertInvalidStatistics(function()
            return addon.UIModel.BuildLevelRows(character, "metric")
        end, example.name)
    end
end)

testlib.case("ui diagnostics report malformed values without throwing", function()
    local addon = loadUIModel()
    local malformedDiagnostics = {
        { name = "nil character", value = nil },
        { name = "non-table character", value = "character" },
        { name = "missing diagnostics", value = {} },
        { name = "non-table diagnostics", value = { diagnostics = "diagnostics" } },
        { name = "empty reason", value = { diagnostics = { [""] = 1 } } },
        { name = "nonnumeric reason", value = { diagnostics = { [5] = 1 } } },
        { name = "negative count", value = { diagnostics = { sample = -1 } } },
        { name = "fractional count", value = { diagnostics = { sample = 1.5 } } },
        { name = "NaN count", value = { diagnostics = { sample = 0 / 0 } } },
        { name = "infinite count", value = { diagnostics = { sample = math.huge } } },
    }

    for _, example in ipairs(malformedDiagnostics) do
        assertInvalidDiagnostics(function()
            return addon.UIModel.BuildDiagnostics(example.value, true)
        end, example.name)
    end
end)

testlib.case("ui model uses the stride fallback for unknown races", function()
    local addon = loadUIModel()
    local overview = addon.UIModel.BuildOverview(newCharacter("UnknownFutureRace"), 20, "metric")
    local rows = addon.UIModel.BuildLevelRows(newCharacter("UnknownFutureRace"), "metric")

    testlib.equal(overview.lifetime.rawSteps, 114)
    testlib.equal(overview.lifetime.steps, "114")
    testlib.equal(rows[1].rawSteps, 229)
    testlib.equal(rows[1].steps, "229")
end)
