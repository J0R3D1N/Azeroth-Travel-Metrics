local testlib = require("testlib")

local function loadTracker()
    return testlib.loadAddon({
        "AzerothTravelMetrics\\Namespace.lua",
        "AzerothTravelMetrics\\Tracker.lua",
    })
end

local function validDependencies()
    return {
        compat = {
            ReadSample = function()
                return nil, "unused"
            end,
        },
        storage = {
            AddDistance = function()
                return true
            end,
            EnsureLevel = function()
                return {}
            end,
        },
        movement = {
            BuildSegment = function()
                return nil, "stationary"
            end,
        },
        character = {
            diagnostics = {},
        },
        level = 10,
        emit = function() end,
    }
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

local function sequenceReader(entries)
    local index = 0

    return function()
        index = index + 1
        local entry = entries[index]
        return entry.value, entry.reason
    end
end

local function assertSampleSnapshot(actual, expected)
    testlib.truthy(actual ~= expected)
    testlib.equal(actual.x, expected.x)
    testlib.equal(actual.y, expected.y)
    testlib.equal(actual.z, expected.z)
    testlib.equal(actual.mapID, expected.mapID)
    testlib.equal(actual.instanceID, expected.instanceID)
    testlib.equal(actual.time, expected.time)
    testlib.equal(actual.onTaxi, expected.onTaxi)
    testlib.equal(actual.swimming, expected.swimming)
    testlib.equal(actual.mounted, expected.mounted)
    testlib.equal(actual.grounded, expected.grounded)
    testlib.equal(actual.capabilities, nil)
end

testlib.case("tracker validates constructor dependencies", function()
    local addon = loadTracker()
    local valid = validDependencies()
    local dependencyCases = {
        {
            name = "deps",
            build = function()
                return nil
            end,
        },
        {
            name = "compat.ReadSample",
            build = function()
                local deps = validDependencies()
                deps.compat = {}
                return deps
            end,
        },
        {
            name = "storage.AddDistance",
            build = function()
                local deps = validDependencies()
                deps.storage.AddDistance = nil
                return deps
            end,
        },
        {
            name = "storage.EnsureLevel",
            build = function()
                local deps = validDependencies()
                deps.storage.EnsureLevel = nil
                return deps
            end,
        },
        {
            name = "movement.BuildSegment",
            build = function()
                local deps = validDependencies()
                deps.movement = {}
                return deps
            end,
        },
        {
            name = "character.diagnostics",
            build = function()
                local deps = validDependencies()
                deps.character = {}
                return deps
            end,
        },
        {
            name = "level",
            build = function()
                local deps = validDependencies()
                deps.level = 0
                return deps
            end,
        },
        {
            name = "emit",
            build = function()
                local deps = validDependencies()
                deps.emit = nil
                return deps
            end,
        },
    }

    for _, case in ipairs(dependencyCases) do
        local succeeded, constructionError = pcall(addon.Tracker.New, case.build())

        testlib.equal(succeeded, false, case.name .. " was accepted")
        testlib.truthy(
            tostring(constructionError):find(case.name, 1, true) ~= nil,
            case.name .. " returned an unclear construction error"
        )
    end

    local tracker = addon.Tracker.New(valid)
    testlib.equal(tracker.compat, valid.compat)
    testlib.equal(tracker.storage, valid.storage)
    testlib.equal(tracker.movement, valid.movement)
    testlib.equal(tracker.character, valid.character)
    testlib.equal(tracker.level, valid.level)
    testlib.equal(tracker.emit, valid.emit)
    testlib.equal(tracker.previous, nil)
end)

testlib.case("tracker stores a private scalar snapshot as its first baseline", function()
    local addon = loadTracker()
    local first = sample()
    local storageCalls = 0
    local movementCalls = 0
    local emitCalls = 0
    local deps = validDependencies()
    deps.compat.ReadSample = sequenceReader({
        { value = first },
    })
    deps.storage.AddDistance = function()
        storageCalls = storageCalls + 1
        return true
    end
    deps.movement.BuildSegment = function()
        movementCalls = movementCalls + 1
        return nil, "stationary"
    end
    deps.emit = function()
        emitCalls = emitCalls + 1
    end
    local tracker = addon.Tracker.New(deps)

    local segment, reason = tracker:Sample()

    testlib.equal(segment, nil)
    testlib.equal(reason, "baseline")
    assertSampleSnapshot(tracker.previous, first)
    testlib.equal(storageCalls, 0)
    testlib.equal(movementCalls, 0)
    testlib.equal(emitCalls, 0)
end)

testlib.case("tracker treats a nil emitter result as successful", function()
    local addon = loadTracker()
    local first = sample()
    local second = sample({ x = 5, time = 11 })
    local expectedSegment = {
        category = "onFoot",
        yards = 5,
        from = first,
        to = second,
    }
    local storageArguments
    local emittedEvent
    local emittedSegment
    local deps = validDependencies()
    deps.compat.ReadSample = sequenceReader({
        { value = first },
        { value = second },
    })
    deps.movement.BuildSegment = function(from, to)
        assertSampleSnapshot(from, first)
        testlib.equal(to, second)
        return expectedSegment
    end
    deps.storage.AddDistance = function(...)
        storageArguments = {
            count = select("#", ...),
            ...,
        }
        return true
    end
    deps.emit = function(eventName, segment)
        emittedEvent = eventName
        emittedSegment = segment
    end
    local tracker = addon.Tracker.New(deps)

    tracker:Sample()
    local segment, reason = tracker:Sample()

    testlib.equal(reason, nil)
    testlib.equal(segment, expectedSegment)
    assertSampleSnapshot(tracker.previous, second)
    testlib.equal(storageArguments.count, 4)
    testlib.equal(storageArguments[1], deps.character)
    testlib.equal(storageArguments[2], 10)
    testlib.equal(storageArguments[3], "onFoot")
    testlib.equal(storageArguments[4], 5)
    testlib.equal(emittedEvent, "movementSegment")
    testlib.equal(emittedSegment, expectedSegment)
    testlib.equal(deps.character.diagnostics.emitFailed, nil)
end)

testlib.case("tracker updates its baseline for stationary samples without side effects", function()
    local addon = loadTracker()
    local first = sample()
    local second = sample({ time = 11 })
    local storageCalls = 0
    local emitCalls = 0
    local deps = validDependencies()
    deps.compat.ReadSample = sequenceReader({
        { value = first },
        { value = second },
    })
    deps.storage.AddDistance = function()
        storageCalls = storageCalls + 1
        return true
    end
    deps.emit = function()
        emitCalls = emitCalls + 1
    end
    local tracker = addon.Tracker.New(deps)

    tracker:Sample()
    local segment, reason = tracker:Sample()

    testlib.equal(segment, nil)
    testlib.equal(reason, "stationary")
    assertSampleSnapshot(tracker.previous, second)
    testlib.equal(deps.character.diagnostics.stationary, nil)
    testlib.equal(storageCalls, 0)
    testlib.equal(emitCalls, 0)
end)

testlib.case("tracker records rejected segments and advances the baseline", function()
    local rejectionReasons = {
        "mapChanged",
        "instanceChanged",
        "implausibleSpeed",
        "unsupportedState",
    }

    for _, rejectionReason in ipairs(rejectionReasons) do
        local addon = loadTracker()
        local first = sample()
        local second = sample({ x = 1, time = 11 })
        local storageCalls = 0
        local emitCalls = 0
        local deps = validDependencies()
        deps.compat.ReadSample = sequenceReader({
            { value = first },
            { value = second },
        })
        deps.movement.BuildSegment = function()
            return nil, rejectionReason
        end
        deps.storage.AddDistance = function()
            storageCalls = storageCalls + 1
            return true
        end
        deps.emit = function()
            emitCalls = emitCalls + 1
        end
        local tracker = addon.Tracker.New(deps)

        tracker:Sample()
        local segment, reason = tracker:Sample()

        testlib.equal(segment, nil, rejectionReason .. " returned a segment")
        testlib.equal(reason, rejectionReason)
        assertSampleSnapshot(tracker.previous, second)
        testlib.equal(deps.character.diagnostics[rejectionReason], 1)
        testlib.equal(storageCalls, 0)
        testlib.equal(emitCalls, 0)
    end
end)

testlib.case("tracker records read failures and clears its baseline", function()
    local addon = loadTracker()
    local first = sample()
    local deps = validDependencies()
    deps.compat.ReadSample = sequenceReader({
        { value = first },
        { value = nil, reason = "positionUnavailable" },
    })
    local tracker = addon.Tracker.New(deps)

    tracker:Sample()
    local segment, reason = tracker:Sample()

    testlib.equal(segment, nil)
    testlib.equal(reason, "positionUnavailable")
    testlib.equal(deps.character.diagnostics.positionUnavailable, 1)
    testlib.equal(tracker.previous, nil)
end)

testlib.case("tracker does not aggregate mounted movement rejected by Movement", function()
    local addon = testlib.loadAddon({
        "AzerothTravelMetrics\\Namespace.lua",
        "AzerothTravelMetrics\\Movement.lua",
        "AzerothTravelMetrics\\Tracker.lua",
    })
    local first = sample({ mounted = true })
    local second = sample({ x = 5, time = 11, mounted = true })
    local storageCalls = 0
    local deps = validDependencies()
    deps.compat.ReadSample = sequenceReader({
        { value = first },
        { value = second },
    })
    deps.movement = addon.Movement
    deps.storage.AddDistance = function()
        storageCalls = storageCalls + 1
        return true
    end
    local tracker = addon.Tracker.New(deps)

    tracker:Sample()
    local segment, reason = tracker:Sample()

    testlib.equal(segment, nil)
    testlib.equal(reason, "unsupportedState")
    testlib.equal(deps.character.diagnostics.unsupportedState, 1)
    testlib.equal(storageCalls, 0)
    assertSampleSnapshot(tracker.previous, second)
end)

testlib.case("tracker sends taxi and swimming distance only to their category", function()
    local categories = {
        "taxi",
        "swimming",
    }

    for _, category in ipairs(categories) do
        local addon = loadTracker()
        local first = sample()
        local second = sample({ x = 7, time = 11 })
        local receivedCategory
        local receivedYards
        local deps = validDependencies()
        deps.compat.ReadSample = sequenceReader({
            { value = first },
            { value = second },
        })
        deps.movement.BuildSegment = function()
            return {
                category = category,
                yards = 7,
                from = first,
                to = second,
            }
        end
        deps.storage.AddDistance = function(_, _, actualCategory, yards)
            receivedCategory = actualCategory
            receivedYards = yards
            return true
        end
        local tracker = addon.Tracker.New(deps)

        tracker:Sample()
        tracker:Sample()

        testlib.equal(receivedCategory, category)
        testlib.equal(receivedYards, 7)
    end
end)

testlib.case("tracker ResetBaseline prevents a bridge segment", function()
    local addon = loadTracker()
    local first = sample()
    local second = sample({ x = 10, time = 11 })
    local movementCalls = 0
    local deps = validDependencies()
    deps.compat.ReadSample = sequenceReader({
        { value = first },
        { value = second },
    })
    deps.movement.BuildSegment = function()
        movementCalls = movementCalls + 1
        return {
            category = "onFoot",
            yards = 10,
        }
    end
    local tracker = addon.Tracker.New(deps)

    tracker:Sample()
    tracker:ResetBaseline()
    local segment, reason = tracker:Sample()

    testlib.equal(segment, nil)
    testlib.equal(reason, "baseline")
    testlib.equal(movementCalls, 0)
    assertSampleSnapshot(tracker.previous, second)
end)

testlib.case("tracker SetLevel ensures storage before updating and uses the new level", function()
    local addon = loadTracker()
    local beforeLevelChange = sample()
    local newBaseline = sample({ x = 10, time = 20 })
    local afterLevelChange = sample({ x = 15, time = 21 })
    local ensuredCharacter
    local ensuredLevel
    local ensuredNow
    local aggregatedLevel
    local deps = validDependencies()
    deps.compat.ReadSample = sequenceReader({
        { value = beforeLevelChange },
        { value = newBaseline },
        { value = afterLevelChange },
    })
    deps.movement.BuildSegment = function(from, to)
        return {
            category = "onFoot",
            yards = to.x - from.x,
            from = from,
            to = to,
        }
    end
    deps.storage.AddDistance = function(_, level)
        aggregatedLevel = level
        return true
    end
    local tracker
    deps.storage.EnsureLevel = function(character, level, now)
        testlib.equal(tracker.level, 10)
        assertSampleSnapshot(tracker.previous, beforeLevelChange)
        ensuredCharacter = character
        ensuredLevel = level
        ensuredNow = now
        return {}
    end
    tracker = addon.Tracker.New(deps)
    tracker:Sample()

    local updated, updateError = tracker:SetLevel(11, 1000)

    testlib.equal(updated, true)
    testlib.equal(updateError, nil)
    testlib.equal(ensuredCharacter, deps.character)
    testlib.equal(ensuredLevel, 11)
    testlib.equal(ensuredNow, 1000)
    testlib.equal(tracker.level, 11)
    testlib.equal(tracker.previous, nil)

    local segment, reason = tracker:Sample()
    testlib.equal(segment, nil)
    testlib.equal(reason, "baseline")
    tracker:Sample()
    testlib.equal(aggregatedLevel, 11)
end)

testlib.case("tracker SetLevel rejects invalid input atomically", function()
    local invalidCases = {
        { level = 0, now = 1000, reason = "invalidLevel" },
        { level = 10.5, now = 1000, reason = "invalidLevel" },
        { level = math.huge, now = 1000, reason = "invalidLevel" },
        { level = 11, now = 0, reason = "invalidTime" },
        { level = 11, now = 1000.5, reason = "invalidTime" },
        { level = 11, now = 0 / 0, reason = "invalidTime" },
    }

    for _, invalid in ipairs(invalidCases) do
        local addon = loadTracker()
        local baseline = sample()
        local ensureCalls = 0
        local deps = validDependencies()
        deps.storage.EnsureLevel = function()
            ensureCalls = ensureCalls + 1
            return {}
        end
        local tracker = addon.Tracker.New(deps)
        tracker.previous = baseline

        local updated, reason = tracker:SetLevel(invalid.level, invalid.now)

        testlib.equal(updated, nil)
        testlib.equal(reason, invalid.reason)
        testlib.equal(ensureCalls, 0)
        testlib.equal(tracker.level, 10)
        testlib.equal(tracker.previous, baseline)
    end
end)

testlib.case("tracker SetLevel preserves state when storage rejects the level", function()
    local addon = loadTracker()
    local baseline = sample()
    local deps = validDependencies()
    deps.storage.EnsureLevel = function()
        return nil, "invalidStoredLevel"
    end
    local tracker = addon.Tracker.New(deps)
    tracker.previous = baseline

    local updated, reason = tracker:SetLevel(11, 1000)

    testlib.equal(updated, nil)
    testlib.equal(reason, "invalidStoredLevel")
    testlib.equal(tracker.level, 10)
    testlib.equal(tracker.previous, baseline)
end)

testlib.case("tracker records storage failures and does not emit", function()
    local addon = loadTracker()
    local first = sample()
    local second = sample({ x = 5, time = 11 })
    local emitCalls = 0
    local deps = validDependencies()
    deps.compat.ReadSample = sequenceReader({
        { value = first },
        { value = second },
    })
    deps.movement.BuildSegment = function()
        return {
            category = "onFoot",
            yards = 5,
            from = first,
            to = second,
        }
    end
    deps.storage.AddDistance = function()
        return nil, "invalidStoredTotal"
    end
    deps.emit = function()
        emitCalls = emitCalls + 1
    end
    local tracker = addon.Tracker.New(deps)

    tracker:Sample()
    local segment, reason = tracker:Sample()

    testlib.equal(segment, nil)
    testlib.equal(reason, "invalidStoredTotal")
    testlib.equal(deps.character.diagnostics.invalidStoredTotal, 1)
    testlib.equal(emitCalls, 0)
    assertSampleSnapshot(tracker.previous, second)
end)

testlib.case("tracker subscribers receive full segment coordinates and references", function()
    local addon = loadTracker()
    local first = sample({ x = 1, y = 2, z = 3 })
    local second = sample({ x = 4, y = 6, z = 3, time = 11 })
    local reference = {
        source = "futureBreadcrumb",
    }
    local expectedSegment = {
        category = "onFoot",
        yards = 5,
        elapsed = 1,
        from = first,
        to = second,
        reference = reference,
    }
    local emittedSegment
    local deps = validDependencies()
    deps.compat.ReadSample = sequenceReader({
        { value = first },
        { value = second },
    })
    deps.movement.BuildSegment = function()
        return expectedSegment
    end
    deps.emit = function(_, segment)
        emittedSegment = segment
    end
    local tracker = addon.Tracker.New(deps)

    tracker:Sample()
    tracker:Sample()

    testlib.equal(emittedSegment, expectedSegment)
    testlib.equal(emittedSegment.from, first)
    testlib.equal(emittedSegment.to, second)
    testlib.equal(emittedSegment.from.x, 1)
    testlib.equal(emittedSegment.to.y, 6)
    testlib.equal(emittedSegment.reference, reference)
end)

testlib.case("tracker keeps its baseline isolated from subscriber mutation", function()
    local addon = testlib.loadAddon({
        "AzerothTravelMetrics\\Namespace.lua",
        "AzerothTravelMetrics\\Movement.lua",
        "AzerothTravelMetrics\\Tracker.lua",
    })
    local first = sample()
    local second = sample({ x = 5, time = 11 })
    local third = sample({ x = 8, time = 12 })
    local storedYards = {}
    local deps = validDependencies()
    deps.compat.ReadSample = sequenceReader({
        { value = first },
        { value = second },
        { value = third },
    })
    deps.movement = addon.Movement
    deps.storage.AddDistance = function(_, _, _, yards)
        table.insert(storedYards, yards)
        return true
    end
    deps.emit = function(_, segment)
        segment.to.x = 1000
    end
    local tracker = addon.Tracker.New(deps)

    tracker:Sample()
    local firstSegment = tracker:Sample()
    local secondSegment = tracker:Sample()

    testlib.equal(firstSegment.to, second)
    testlib.equal(firstSegment.to.x, 1000)
    testlib.equal(secondSegment.from.x, 5)
    testlib.equal(secondSegment.to, third)
    testlib.equal(storedYards[1], 5)
    testlib.equal(storedYards[2], 3)
end)

testlib.case("tracker returns committed segments when a throwing emitter fails", function()
    local addon = loadTracker()
    local first = sample()
    local second = sample({ x = 5, time = 11 })
    local acceptedSegment = {
        category = "onFoot",
        yards = 5,
        from = first,
        to = second,
    }
    local storageCalls = 0
    local deps = validDependencies()
    deps.compat.ReadSample = sequenceReader({
        { value = first },
        { value = second },
    })
    deps.movement.BuildSegment = function()
        return acceptedSegment
    end
    deps.storage.AddDistance = function()
        storageCalls = storageCalls + 1
        return true
    end
    deps.emit = function()
        error("emitter failed")
    end
    local tracker = addon.Tracker.New(deps)

    tracker:Sample()
    local succeeded, segment, reason = pcall(tracker.Sample, tracker)

    testlib.equal(succeeded, true)
    testlib.equal(segment, acceptedSegment)
    testlib.equal(reason, "emitFailed")
    testlib.equal(storageCalls, 1)
    testlib.equal(deps.character.diagnostics.emitFailed, 1)
end)

testlib.case("tracker recognizes isolated subscriber failure results", function()
    local addon = loadTracker()
    local first = sample()
    local second = sample({ x = 5, time = 11 })
    local acceptedSegment = {
        category = "onFoot",
        yards = 5,
        from = first,
        to = second,
    }
    local deps = validDependencies()
    deps.compat.ReadSample = sequenceReader({
        { value = first },
        { value = second },
    })
    deps.movement.BuildSegment = function()
        return acceptedSegment
    end
    deps.emit = function()
        return false, "subscriberFailed", {
            {
                subscriber = 1,
                error = "subscriber failed",
            },
        }
    end
    local tracker = addon.Tracker.New(deps)

    tracker:Sample()
    local segment, reason = tracker:Sample()

    testlib.equal(segment, acceptedSegment)
    testlib.equal(reason, "emitFailed")
    testlib.equal(deps.character.diagnostics.emitFailed, 1)
end)

testlib.case("tracker repairs invalid diagnostic counters on every failure path", function()
    local invalidCounters = {
        { name = "missing" },
        { name = "nonnumeric", value = "corrupt" },
        { name = "negative", value = -1 },
        { name = "NaN", value = 0 / 0 },
        { name = "infinite", value = math.huge },
    }
    local failurePaths = {
        {
            reason = "readFailed",
            configure = function(deps)
                deps.compat.ReadSample = function()
                    return nil, "readFailed"
                end
            end,
            exercise = function(tracker)
                tracker:Sample()
            end,
        },
        {
            reason = "buildFailed",
            configure = function(deps)
                deps.compat.ReadSample = sequenceReader({
                    { value = sample() },
                    { value = sample({ x = 1, time = 11 }) },
                })
                deps.movement.BuildSegment = function()
                    return nil, "buildFailed"
                end
            end,
            exercise = function(tracker)
                tracker:Sample()
                tracker:Sample()
            end,
        },
        {
            reason = "storageFailed",
            configure = function(deps)
                deps.compat.ReadSample = sequenceReader({
                    { value = sample() },
                    { value = sample({ x = 1, time = 11 }) },
                })
                deps.movement.BuildSegment = function(from, to)
                    return {
                        category = "onFoot",
                        yards = 1,
                        from = from,
                        to = to,
                    }
                end
                deps.storage.AddDistance = function()
                    return nil, "storageFailed"
                end
            end,
            exercise = function(tracker)
                tracker:Sample()
                tracker:Sample()
            end,
        },
        {
            reason = "emitFailed",
            configure = function(deps)
                deps.compat.ReadSample = sequenceReader({
                    { value = sample() },
                    { value = sample({ x = 1, time = 11 }) },
                })
                deps.movement.BuildSegment = function(from, to)
                    return {
                        category = "onFoot",
                        yards = 1,
                        from = from,
                        to = to,
                    }
                end
                deps.emit = function()
                    error("emit failed")
                end
            end,
            exercise = function(tracker)
                tracker:Sample()
                tracker:Sample()
            end,
        },
    }

    for _, failurePath in ipairs(failurePaths) do
        for _, invalidCounter in ipairs(invalidCounters) do
            local addon = loadTracker()
            local deps = validDependencies()
            deps.character.diagnostics[failurePath.reason] = invalidCounter.value
            failurePath.configure(deps)
            local tracker = addon.Tracker.New(deps)

            local succeeded = pcall(failurePath.exercise, tracker)

            testlib.equal(
                succeeded,
                true,
                failurePath.reason .. " crashed for " .. invalidCounter.name
            )
            testlib.equal(deps.character.diagnostics[failurePath.reason], 1)
        end
    end
end)
