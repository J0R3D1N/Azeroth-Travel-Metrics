local testlib = require("testlib")

local function loadCompat(globals)
    return testlib.loadAddon({
        "AzerothTravelMetrics\\Namespace.lua",
        "AzerothTravelMetrics\\Compat.lua",
    }, globals)
end

local function completeGlobals(overrides)
    local globals = {
        UnitPosition = function()
            return 111, 222, 333, 444
        end,
        C_Map = {
            GetBestMapForUnit = function()
                return 50
            end,
        },
        GetTime = function()
            return 60
        end,
        UnitOnTaxi = function()
            return true
        end,
        IsSwimming = function()
            return false
        end,
        IsMounted = function()
            return false
        end,
        IsFalling = function()
            return false
        end,
        UnitName = function()
            return "Traveler", "DirectRealm"
        end,
        GetRealmName = function()
            return "FallbackRealm"
        end,
        UnitRace = function()
            return "Human", "Human"
        end,
        UnitLevel = function()
            return 42
        end,
        GetServerTime = function()
            return 1000
        end,
        time = function()
            return 2000
        end,
    }

    for key, value in pairs(overrides or {}) do
        globals[key] = value
    end

    return globals
end

testlib.case("compat reads a complete normalized sample", function()
    local addon = loadCompat(completeGlobals())

    local value, reason = addon.Compat.ReadSample()

    testlib.equal(reason, nil)
    testlib.equal(value.x, 222)
    testlib.equal(value.y, 111)
    testlib.equal(value.z, 333)
    testlib.equal(value.instanceID, 444)
    testlib.equal(value.mapID, 50)
    testlib.equal(value.time, 60)
    testlib.equal(value.onTaxi, true)
    testlib.equal(value.swimming, false)
    testlib.equal(value.mounted, false)
    testlib.equal(value.grounded, true)
end)

testlib.case("compat normalizes nil predicate results as false", function()
    local addon = loadCompat(completeGlobals({
        UnitOnTaxi = function()
            return nil
        end,
        IsSwimming = function()
            return nil
        end,
        IsMounted = function()
            return nil
        end,
        IsFalling = function()
            return nil
        end,
    }))

    local value, reason = addon.Compat.ReadSample()
    local capabilities = addon.Compat.GetCapabilities()

    testlib.equal(reason, nil)
    testlib.equal(value.onTaxi, false)
    testlib.equal(value.swimming, false)
    testlib.equal(value.mounted, false)
    testlib.equal(value.grounded, true)
    testlib.equal(capabilities.taxi, true)
    testlib.equal(capabilities.swimming, true)
    testlib.equal(capabilities.mounted, true)
    testlib.equal(capabilities.grounded, true)
    testlib.equal(capabilities.onFootReady, true)
end)

testlib.case("compat normalizes a falling player as explicitly not grounded", function()
    local addon = loadCompat(completeGlobals({
        IsFalling = function()
            return true
        end,
    }))

    local value = addon.Compat.ReadSample()

    testlib.equal(value.grounded, false)
end)

testlib.case("compat reports missing and throwing essential sample APIs without throwing", function()
    local cases = {
        {
            name = "missing position",
            globals = completeGlobals({ UnitPosition = false }),
            reason = "positionUnavailable",
        },
        {
            name = "throwing position",
            globals = completeGlobals({
                UnitPosition = function()
                    error("position failed")
                end,
            }),
            reason = "positionUnavailable",
        },
        {
            name = "missing map",
            globals = completeGlobals({ C_Map = false }),
            reason = "mapUnavailable",
        },
        {
            name = "throwing map",
            globals = completeGlobals({
                C_Map = {
                    GetBestMapForUnit = function()
                        error("map failed")
                    end,
                },
            }),
            reason = "mapUnavailable",
        },
        {
            name = "missing sample time",
            globals = completeGlobals({ GetTime = false }),
            reason = "timeUnavailable",
        },
        {
            name = "throwing sample time",
            globals = completeGlobals({
                GetTime = function()
                    error("time failed")
                end,
            }),
            reason = "timeUnavailable",
        },
    }

    for _, case in ipairs(cases) do
        local addon = loadCompat(case.globals)
        local succeeded, value, reason = pcall(addon.Compat.ReadSample)

        testlib.equal(succeeded, true, case.name .. " raised an error")
        testlib.equal(value, nil, case.name .. " returned a sample")
        testlib.equal(reason, case.reason, case.name .. " returned the wrong reason")
    end
end)

testlib.case("compat rejects nil and non-finite essential sample values", function()
    local invalidValues = {
        { name = "nil", value = nil },
        { name = "NaN", value = 0 / 0 },
        { name = "positive infinity", value = math.huge },
        { name = "negative infinity", value = -math.huge },
    }
    local cases = {
        {
            name = "position",
            reason = "positionUnavailable",
            apply = function(globals, invalid)
                globals.UnitPosition = function()
                    return invalid, 20, 30, 40
                end
            end,
        },
        {
            name = "map",
            reason = "mapUnavailable",
            apply = function(globals, invalid)
                globals.C_Map.GetBestMapForUnit = function()
                    return invalid
                end
            end,
        },
        {
            name = "sample time",
            reason = "timeUnavailable",
            apply = function(globals, invalid)
                globals.GetTime = function()
                    return invalid
                end
            end,
        },
    }

    for _, case in ipairs(cases) do
        for _, invalid in ipairs(invalidValues) do
            local globals = completeGlobals()
            case.apply(globals, invalid.value)
            local addon = loadCompat(globals)
            local value, reason = addon.Compat.ReadSample()

            local caseName = case.name .. " " .. invalid.name
            testlib.equal(value, nil, caseName .. " returned a sample")
            testlib.equal(reason, case.reason, caseName .. " returned the wrong reason")
        end
    end
end)

testlib.case("compat leaves unavailable state fields nil and capabilities false", function()
    local stateCases = {
        { name = "taxi", globalName = "UnitOnTaxi", field = "onTaxi", capability = "taxi" },
        { name = "swimming", globalName = "IsSwimming", field = "swimming", capability = "swimming" },
        { name = "mounted", globalName = "IsMounted", field = "mounted", capability = "mounted" },
        { name = "grounded", globalName = "IsFalling", field = "grounded", capability = "grounded" },
    }

    for _, case in ipairs(stateCases) do
        for _, mode in ipairs({ "missing", "throwing", "malformed" }) do
            local globals = completeGlobals()
            if mode == "missing" then
                globals[case.globalName] = false
            elseif mode == "throwing" then
                globals[case.globalName] = function()
                    error(case.name .. " failed")
                end
            else
                globals[case.globalName] = function()
                    return 1
                end
            end

            local addon = loadCompat(globals)
            local value = addon.Compat.ReadSample()
            local capabilities = addon.Compat.GetCapabilities()
            local caseName = case.name .. " " .. mode

            testlib.equal(value[case.field], nil, caseName .. " fabricated a state")
            testlib.equal(capabilities[case.capability], false, caseName .. " reported capability")
        end
    end
end)

testlib.case("compat exposes the exact category capability dependency matrix", function()
    local addon = loadCompat(completeGlobals())
    local capabilities = addon.Compat.GetCapabilities()

    for _, field in ipairs({
        "position",
        "map",
        "time",
        "taxi",
        "swimming",
        "mounted",
        "grounded",
        "taxiReady",
        "swimmingReady",
        "onFootReady",
    }) do
        testlib.equal(capabilities[field], true, field .. " was not ready")
    end

    local dependencies = {
        position = { taxiReady = false, swimmingReady = false, onFootReady = false },
        map = { taxiReady = false, swimmingReady = false, onFootReady = false },
        time = { taxiReady = false, swimmingReady = false, onFootReady = false },
        taxi = { taxiReady = false, swimmingReady = false, onFootReady = false },
        swimming = { taxiReady = true, swimmingReady = false, onFootReady = false },
        mounted = { taxiReady = true, swimmingReady = false, onFootReady = false },
        grounded = { taxiReady = true, swimmingReady = true, onFootReady = false },
    }
    local globalByCapability = {
        position = "UnitPosition",
        map = "C_Map",
        time = "GetTime",
        taxi = "UnitOnTaxi",
        swimming = "IsSwimming",
        mounted = "IsMounted",
        grounded = "IsFalling",
    }

    for capability, expected in pairs(dependencies) do
        local globals = completeGlobals()
        globals[globalByCapability[capability]] = false
        local partial = loadCompat(globals).Compat.GetCapabilities()

        testlib.equal(partial[capability], false, capability .. " stayed available")
        testlib.equal(partial.taxiReady, expected.taxiReady, capability .. " taxi dependency was wrong")
        testlib.equal(
            partial.swimmingReady,
            expected.swimmingReady,
            capability .. " swimming dependency was wrong"
        )
        testlib.equal(
            partial.onFootReady,
            expected.onFootReady,
            capability .. " on-foot dependency was wrong"
        )
    end
end)

testlib.case("compat returns stable identity and prefers the UnitName realm", function()
    local addon = loadCompat(completeGlobals())

    local identity, reason = addon.Compat.GetCharacterIdentity()

    testlib.equal(reason, nil)
    testlib.equal(identity.name, "Traveler")
    testlib.equal(identity.realm, "DirectRealm")
    testlib.equal(identity.raceFile, "Human")
    testlib.equal(identity.level, 42)
    testlib.equal(identity.now, 1000)
end)

testlib.case("compat falls back to GetRealmName for identity", function()
    local globals = completeGlobals()
    globals.UnitName = function()
        return "Traveler", ""
    end
    local addon = loadCompat(globals)

    local identity = addon.Compat.GetCharacterIdentity()

    testlib.equal(identity.realm, "FallbackRealm")
end)

testlib.case("compat rejects malformed identity level and wall-clock values", function()
    local identityCases = {
        {
            name = "missing name",
            globals = completeGlobals({
                UnitName = function()
                    return nil, "Realm"
                end,
            }),
            reason = "identityUnavailable",
        },
        {
            name = "missing realm",
            globals = completeGlobals({
                UnitName = function()
                    return "Traveler", ""
                end,
                GetRealmName = function()
                    return ""
                end,
            }),
            reason = "identityUnavailable",
        },
        {
            name = "missing race",
            globals = completeGlobals({
                UnitRace = function()
                    return "Human", nil
                end,
            }),
            reason = "identityUnavailable",
        },
        {
            name = "malformed level",
            globals = completeGlobals({
                UnitLevel = function()
                    return 42.5
                end,
            }),
            reason = "levelUnavailable",
        },
        {
            name = "malformed time",
            globals = completeGlobals({
                GetServerTime = function()
                    return math.huge
                end,
                time = function()
                    return 0 / 0
                end,
            }),
            reason = "timeUnavailable",
        },
    }

    for _, case in ipairs(identityCases) do
        local addon = loadCompat(case.globals)
        local identity, reason = addon.Compat.GetCharacterIdentity()

        testlib.equal(identity, nil, case.name .. " returned identity")
        testlib.equal(reason, case.reason, case.name .. " returned the wrong reason")
    end

    local addon = loadCompat(completeGlobals({
        UnitLevel = function()
            return 0
        end,
    }))
    local level, reason = addon.Compat.GetCurrentLevel()
    testlib.equal(level, nil)
    testlib.equal(reason, "levelUnavailable")
end)

testlib.case("compat wall-clock time accepts only positive integers and falls back", function()
    local invalidValues = {
        { name = "nil", value = nil },
        { name = "malformed", value = "2000" },
        { name = "zero", value = 0 },
        { name = "negative", value = -1 },
        { name = "fractional", value = 1000.5 },
        { name = "NaN", value = 0 / 0 },
        { name = "positive infinity", value = math.huge },
        { name = "negative infinity", value = -math.huge },
    }

    testlib.equal(loadCompat(completeGlobals()).Compat.GetNow(), 1000)

    for _, invalid in ipairs(invalidValues) do
        local fallbackAddon = loadCompat(completeGlobals({
            GetServerTime = function()
                return invalid.value
            end,
        }))
        testlib.equal(
            fallbackAddon.Compat.GetNow(),
            2000,
            "server " .. invalid.name .. " did not fall back to local time"
        )

        local unavailableAddon = loadCompat(completeGlobals({
            GetServerTime = false,
            time = function()
                return invalid.value
            end,
        }))
        local now, reason = unavailableAddon.Compat.GetNow()
        testlib.equal(now, nil, "local " .. invalid.name .. " returned a time")
        testlib.equal(
            reason,
            "timeUnavailable",
            "local " .. invalid.name .. " returned the wrong reason"
        )
    end

    local throwingAddon = loadCompat(completeGlobals({
        GetServerTime = function()
            error("not ready")
        end,
    }))
    testlib.equal(throwingAddon.Compat.GetNow(), 2000)

    local missingServerTimeGlobals = completeGlobals()
    missingServerTimeGlobals.GetServerTime = nil
    testlib.equal(loadCompat(missingServerTimeGlobals).Compat.GetNow(), 2000)

    local unavailableAddon = loadCompat(completeGlobals({
        GetServerTime = false,
        time = false,
    }))
    local now, reason = unavailableAddon.Compat.GetNow()
    testlib.equal(now, nil)
    testlib.equal(reason, "timeUnavailable")
end)

testlib.case("compat print prefers chat and falls back without recursion", function()
    local messages = {}
    local globals = completeGlobals({
        DEFAULT_CHAT_FRAME = {
            AddMessage = function(_, message)
                table.insert(messages, "chat:" .. message)
            end,
        },
        print = function(message)
            table.insert(messages, "print:" .. message)
        end,
    })
    local addon = loadCompat(globals)

    addon.Compat.Print("first")
    testlib.equal(messages[1], "chat:first")
    testlib.equal(#messages, 1)

    globals.DEFAULT_CHAT_FRAME.AddMessage = function()
        error("chat unavailable")
    end
    addon.Compat.Print("second")
    testlib.equal(messages[2], "print:second")

    globals.DEFAULT_CHAT_FRAME = nil
    globals.print = addon.Compat.Print
    local succeeded = pcall(addon.Compat.Print, "third")
    testlib.equal(succeeded, true)
    testlib.equal(#messages, 2)
end)
