local testlib = require("testlib")

local CORE_FILES = {
    "AzerothTravelMetrics\\Namespace.lua",
    "AzerothTravelMetrics\\Core.lua",
}

local RELOG_INTEGRATION_FILES = {
    "AzerothTravelMetrics\\Namespace.lua",
    "AzerothTravelMetrics\\Storage.lua",
    "AzerothTravelMetrics\\Core.lua",
}

local UI_FILES = {
    "AzerothTravelMetrics\\Namespace.lua",
    "AzerothTravelMetrics\\UITheme.lua",
    "AzerothTravelMetrics\\UI.lua",
}

local function countKeys(value)
    local count = 0
    for _ in pairs(value or {}) do
        count = count + 1
    end
    return count
end

local function contains(text, fragment)
    return type(text) == "string"
        and text:find(fragment, 1, true) ~= nil
end

local function newEventGlobals()
    local eventFrame = {
        events = {},
        scripts = {},
    }

    function eventFrame:RegisterEvent(eventName)
        self.events[eventName] = true
    end

    function eventFrame:SetScript(scriptName, callback)
        self.scripts[scriptName] = callback
    end

    local globals = {
        SlashCmdList = {},
        CreateFrame = function()
            return eventFrame
        end,
    }

    return globals, eventFrame
end

local function newCoreHarness(options)
    options = options or {}

    local globals, eventFrame = newEventGlobals()
    globals.AzerothTravelMetricsDB = options.savedDB

    local addon, environment = testlib.loadAddon(CORE_FILES, globals)
    local calls = {
        initialize = 0,
        identity = 0,
        getCharacter = 0,
        startSession = 0,
        trackerNew = 0,
        capabilities = 0,
        uiInitialize = 0,
        minimapInitialize = 0,
        uiRefresh = 0,
        uiToggle = 0,
        uiConfirmReset = 0,
        uiErrors = {},
        prints = {},
        tickers = {},
        tickerAttempts = 0,
        samples = 0,
        resets = 0,
        levelCalls = {},
        order = {},
        initializationOrder = {},
        characterKeys = {},
    }
    local initializedDB = options.initializedDB or {
        settings = {
            units = "metric",
            showDiagnostics = false,
        },
        characters = {},
    }
    local identity = options.identity or {
        name = "Traveler",
        realm = "TestRealm",
        raceFile = "Human",
        level = 42,
        now = 1000,
    }
    local character = options.character or {
        diagnostics = {
            zeta = 3,
            alpha = 1,
        },
    }
    local tracker = options.tracker or {}

    function tracker:ResetBaseline()
        calls.resets = calls.resets + 1
    end

    function tracker:Sample()
        calls.samples = calls.samples + 1
        if options.sampleResults then
            local result = options.sampleResults[calls.samples] or {}
            return result.segment, result.reason, result.capabilities
        end
        return nil, "baseline"
    end

    function tracker:SetLevel(level, now)
        table.insert(calls.order, "setLevel")
        table.insert(calls.levelCalls, {
            level = level,
            now = now,
        })
        if options.setLevelResult then
            return options.setLevelResult[1], options.setLevelResult[2]
        end
        return true
    end

    addon.Storage = {
        Initialize = function(existing)
            calls.initialize = calls.initialize + 1
            calls.initializeArgument = existing
            if options.initializeThrows then
                error("storage exploded")
            end
            if options.initializeError then
                return existing, options.initializeError
            end
            return initializedDB
        end,
        GetCharacter = function(db, key, receivedIdentity)
            calls.getCharacter = calls.getCharacter + 1
            table.insert(calls.initializationOrder, "getCharacter")
            table.insert(calls.characterKeys, key)
            calls.characterArguments = {
                db = db,
                key = key,
                identity = receivedIdentity,
            }
            if options.getCharacterThrows then
                error("character exploded")
            end
            if options.realisticCharacterLookup then
                local existingCharacter = db.characters[key]
                if existingCharacter then
                    return existingCharacter
                end

                local createdCharacter = {
                    identity = {
                        name = receivedIdentity.name,
                        realm = receivedIdentity.realm,
                        raceFile = receivedIdentity.raceFile,
                        firstSeenAt = receivedIdentity.now,
                    },
                    lifetime = {
                        onFoot = 0,
                        swimming = 0,
                        taxi = 0,
                    },
                    levels = {},
                    diagnostics = {},
                }
                db.characters[key] = createdCharacter
                return createdCharacter
            end
            return character
        end,
        StartSession = function(receivedCharacter, now)
            calls.startSession = calls.startSession + 1
            table.insert(calls.initializationOrder, "startSession")
            calls.sessionArguments = {
                character = receivedCharacter,
                now = now,
            }
            if options.startSessionThrows then
                error("session exploded")
            end
            if options.startSessionResult ~= nil then
                return options.startSessionResult
            end
            receivedCharacter.session = {
                startedAt = now,
                onFoot = 0,
                swimming = 0,
                taxi = 0,
            }
            return receivedCharacter.session
        end,
        IsValidSession = function(session)
            return type(session) == "table"
                and type(session.startedAt) == "number"
                and type(session.onFoot) == "number"
                and session.onFoot >= 0
                and type(session.swimming) == "number"
                and session.swimming >= 0
                and type(session.taxi) == "number"
                and session.taxi >= 0
        end,
    }

    addon.Compat = {
        GetCharacterIdentity = function()
            calls.identity = calls.identity + 1
            table.insert(calls.initializationOrder, "identity")
            if options.identityThrows then
                error("identity exploded")
            end
            if options.identityError then
                return nil, options.identityError
            end
            return identity
        end,
        GetCapabilities = function()
            calls.capabilities = calls.capabilities + 1
            table.insert(calls.initializationOrder, "capabilities")
            if options.capabilitiesThrows then
                error("capabilities exploded")
            end
            return options.capabilities or {
                position = true,
                map = true,
                time = true,
                taxi = true,
                swimming = true,
                mounted = true,
                flying = true,
                vehicle = true,
                grounded = true,
                taxiReady = true,
                swimmingReady = true,
                onFootReady = true,
            }
        end,
        GetNow = function()
            table.insert(calls.order, "getNow")
            if options.nowThrows then
                error("time exploded")
            end
            if options.nowError then
                return nil, options.nowError
            end
            return options.now or 2000
        end,
        Print = function(message)
            table.insert(calls.prints, message)
        end,
    }

    addon.Movement = {}
    addon.Tracker = {
        New = function(deps)
            calls.trackerNew = calls.trackerNew + 1
            table.insert(calls.initializationOrder, "trackerNew")
            calls.trackerDependencies = deps
            if options.trackerThrows then
                error("tracker exploded")
            end
            return tracker
        end,
    }

    local shown = options.shown == true
    addon.UI = {
        Initialize = function(context)
            calls.uiInitialize = calls.uiInitialize + 1
            calls.uiContext = context
            table.insert(calls.initializationOrder, "uiInitialize")
        end,
        Refresh = function()
            calls.uiRefresh = calls.uiRefresh + 1
        end,
        Toggle = function()
            calls.uiToggle = calls.uiToggle + 1
            shown = not shown
        end,
        IsShown = function()
            return shown
        end,
        ShowError = function(message)
            table.insert(calls.uiErrors, message)
        end,
        ConfirmResetSession = function()
            calls.uiConfirmReset = calls.uiConfirmReset + 1
        end,
    }
    if not options.missingMinimap then
        addon.Minimap = {
            Initialize = function(context)
                calls.minimapInitialize = calls.minimapInitialize + 1
                calls.minimapContext = context
                table.insert(calls.initializationOrder, "minimapInitialize")
                if options.minimapThrows then
                    error("minimap exploded")
                end
            end,
        }
    end

    environment.C_Timer = {
        NewTicker = function(interval, callback)
            table.insert(calls.initializationOrder, "ticker")
            calls.tickerAttempts = calls.tickerAttempts + 1
            if calls.tickerAttempts <= (options.invalidTickerAttempts or 0) then
                return {}
            end
            if options.nativeTickerHandles then
                local ticker = {
                    interval = interval,
                    callback = callback,
                    cancelled = false,
                }
                local handle = coroutine.create(function()
                end)
                debug.setmetatable(handle, {
                    __index = function(_, key)
                        if key == "Cancel" then
                            return function(receivedHandle)
                                testlib.equal(receivedHandle, handle)
                                ticker.cancelled = true
                            end
                        end
                    end,
                })
                ticker.handle = handle
                table.insert(calls.tickers, ticker)
                return handle
            end

            local ticker = {
                interval = interval,
                callback = callback,
                cancelled = false,
            }
            function ticker:Cancel()
                self.cancelled = true
            end
            table.insert(calls.tickers, ticker)
            return ticker
        end,
    }

    local function fire(eventName, ...)
        eventFrame.scripts.OnEvent(eventFrame, eventName, ...)
    end

    return {
        addon = addon,
        environment = environment,
        eventFrame = eventFrame,
        calls = calls,
        db = initializedDB,
        character = character,
        tracker = tracker,
        options = options,
        fire = fire,
    }
end

local function newRelogIntegrationHarness(options)
    options = options or {}
    local globals, eventFrame = newEventGlobals()
    local identity = {
        name = "Traveler",
        realm = "TestRealm",
        raceFile = "Human",
        level = 42,
        now = 9000,
    }
    local character = {
        identity = {
            name = "Traveler",
            realm = "TestRealm",
            raceFile = "Human",
            firstSeenAt = 1000,
        },
        lifetime = {
            onFoot = 111,
            swimming = 222,
            taxi = 333,
        },
        session = {
            startedAt = 7000,
            onFoot = 11,
            swimming = 22,
            taxi = 33,
        },
        levels = {
            [42] = {
                onFoot = 44,
                swimming = 55,
                taxi = 66,
                reachedAt = 8000,
            },
        },
        diagnostics = {
            samples = 77,
            rejected = 8,
        },
    }
    local db = {
        schemaVersion = 1,
        settings = {
            units = "imperial",
            showMinimap = true,
            minimapAngle = 225,
            showDiagnostics = true,
            hudPoint = "CENTER",
            hudX = 0,
            hudY = 0,
        },
        characters = {
            ["Traveler-TestRealm"] = character,
        },
    }
    if not options.deferSavedDB then
        globals.AzerothTravelMetricsDB = db
    end

    local addon, environment = testlib.loadAddon(
        RELOG_INTEGRATION_FILES,
        globals
    )
    local calls = {
        identity = 0,
        capabilities = 0,
        trackerNew = 0,
        trackerDependencies = {},
        resets = 0,
        uiInitialize = 0,
        uiContexts = {},
        uiErrors = {},
        minimapInitialize = 0,
        minimapContexts = {},
        tickers = {},
    }
    local tracker = {}

    function tracker:ResetBaseline()
        calls.resets = calls.resets + 1
        calls.resetReceiver = self
    end

    function tracker:Sample()
        return nil, "baseline"
    end

    addon.Compat = {
        GetCharacterIdentity = function()
            calls.identity = calls.identity + 1
            return identity
        end,
        GetCapabilities = function()
            calls.capabilities = calls.capabilities + 1
            return {
                position = true,
                map = true,
                time = true,
                taxi = true,
                swimming = true,
                mounted = true,
                grounded = true,
                taxiReady = true,
                swimmingReady = true,
                onFootReady = true,
            }
        end,
        Print = function()
        end,
    }
    addon.Movement = {}
    addon.Tracker = {
        New = function(dependencies)
            calls.trackerNew = calls.trackerNew + 1
            table.insert(calls.trackerDependencies, dependencies)
            return tracker
        end,
    }
    addon.UI = {
        Initialize = function(context)
            calls.uiInitialize = calls.uiInitialize + 1
            table.insert(calls.uiContexts, context)
        end,
        Refresh = function()
        end,
        Toggle = function()
        end,
        IsShown = function()
            return false
        end,
        ShowError = function(message)
            table.insert(calls.uiErrors, message)
        end,
        ConfirmResetSession = function()
        end,
    }
    addon.Minimap = {
        Initialize = function(context)
            calls.minimapInitialize = calls.minimapInitialize + 1
            table.insert(calls.minimapContexts, context)
        end,
    }
    environment.C_Timer = {
        NewTicker = function(interval, callback)
            local ticker = {
                interval = interval,
                callback = callback,
                cancelled = false,
            }
            function ticker:Cancel()
                self.cancelled = true
            end
            table.insert(calls.tickers, ticker)
            return ticker
        end,
    }

    return {
        addon = addon,
        environment = environment,
        eventFrame = eventFrame,
        calls = calls,
        db = db,
        character = character,
        identity = identity,
        tracker = tracker,
        loadSavedDB = function()
            environment.AzerothTravelMetricsDB = db
        end,
        fire = function(eventName, ...)
            eventFrame.scripts.OnEvent(eventFrame, eventName, ...)
        end,
    }
end

local function initialize(harness)
    harness.fire("ADDON_LOADED", "AzerothTravelMetrics")
end

local function enterWorld(harness, isInitialLogin, isReloadingUi)
    harness.fire(
        "PLAYER_ENTERING_WORLD",
        isInitialLogin,
        isReloadingUi
    )
end

local function makeReady(harness)
    initialize(harness)
    enterWorld(harness)
end

testlib.case("core registers one frame for all lifecycle events and slash commands", function()
    local harness = newCoreHarness()

    testlib.equal(countKeys(harness.eventFrame.events), 4)
    testlib.equal(harness.eventFrame.events.ADDON_LOADED, true)
    testlib.equal(harness.eventFrame.events.PLAYER_ENTERING_WORLD, true)
    testlib.equal(harness.eventFrame.events.PLAYER_LEVEL_UP, true)
    testlib.equal(harness.eventFrame.events.PLAYER_LOGOUT, true)
    testlib.equal(harness.environment.SLASH_AZEROTHTRAVELMETRICS1, "/atm")
    testlib.equal(
        harness.environment.SLASH_AZEROTHTRAVELMETRICS2,
        nil
    )
    testlib.equal(
        type(harness.environment.SlashCmdList.AZEROTHTRAVELMETRICS),
        "function"
    )
    testlib.equal(
        harness.environment.SlashCmdList["AZEROTH" .. "TRAVELTRACKER"],
        nil
    )
end)

testlib.case("core does not replace a missing Blizzard slash command table", function()
    local eventFrame = {
        RegisterEvent = function() end,
        SetScript = function() end,
    }
    local globals = {
        CreateFrame = function()
            return eventFrame
        end,
    }

    local succeeded, _, environment = pcall(testlib.loadAddon, CORE_FILES, globals)

    testlib.equal(succeeded, true)
    testlib.equal(environment.SlashCmdList, nil)
end)

testlib.case("ADDON_LOADED initializes only the database once", function()
    local harness = newCoreHarness({
        savedDB = {
            sentinel = true,
        },
    })

    harness.fire("ADDON_LOADED", "OtherAddon")
    testlib.equal(harness.calls.initialize, 0)

    initialize(harness)
    testlib.equal(harness.calls.initialize, 1)
    testlib.equal(harness.calls.identity, 0)
    testlib.equal(harness.calls.getCharacter, 0)
    testlib.equal(harness.calls.startSession, 0)
    testlib.equal(harness.calls.trackerNew, 0)
    testlib.equal(harness.calls.capabilities, 0)
    testlib.equal(harness.calls.uiInitialize, 0)
    testlib.equal(harness.calls.minimapInitialize, 0)
    testlib.equal(#harness.calls.tickers, 0)
    testlib.equal(harness.environment.AzerothTravelMetricsDB, harness.db)
    local state = harness.addon.Core.GetState()
    testlib.equal(state.initialized, true)
    testlib.equal(state.databaseReady, true)
    testlib.equal(state.ready, false)
    testlib.equal(state.db, harness.db)

    initialize(harness)
    testlib.equal(harness.calls.initialize, 1)
    testlib.equal(harness.calls.identity, 0)
end)

testlib.case("first entering world binds runtime and starts one fresh session", function()
    local harness = newCoreHarness()
    initialize(harness)

    enterWorld(harness, true, false)

    testlib.equal(harness.calls.identity, 1)
    testlib.equal(harness.calls.getCharacter, 1)
    testlib.equal(harness.calls.startSession, 1)
    testlib.equal(harness.calls.trackerNew, 1)
    testlib.equal(harness.calls.capabilities, 1)
    testlib.equal(harness.calls.uiInitialize, 1)
    testlib.equal(harness.calls.minimapInitialize, 1)
    testlib.equal(#harness.calls.tickers, 1)
    testlib.near(harness.calls.tickers[1].interval, 0.5, 0.0001)
    testlib.equal(harness.calls.initializationOrder[1], "identity")
    testlib.equal(harness.calls.initializationOrder[2], "getCharacter")
    testlib.equal(harness.calls.initializationOrder[3], "startSession")
    testlib.equal(harness.calls.initializationOrder[4], "trackerNew")
    testlib.equal(harness.calls.initializationOrder[5], "capabilities")
    testlib.equal(harness.calls.initializationOrder[6], "uiInitialize")
    testlib.equal(harness.calls.initializationOrder[7], "minimapInitialize")
    testlib.equal(harness.calls.initializationOrder[8], "ticker")
    testlib.equal(harness.calls.minimapContext.db, harness.db)
    testlib.equal(harness.calls.characterArguments.db, harness.db)
    testlib.equal(
        harness.calls.characterArguments.key,
        "Traveler-TestRealm"
    )
    testlib.equal(
        harness.calls.characterArguments.identity.name,
        "Traveler"
    )
    testlib.equal(harness.calls.sessionArguments.character, harness.character)
    testlib.equal(harness.calls.sessionArguments.now, 1000)
    testlib.equal(harness.calls.trackerDependencies.compat, harness.addon.Compat)
    testlib.equal(harness.calls.trackerDependencies.storage, harness.addon.Storage)
    testlib.equal(harness.calls.trackerDependencies.movement, harness.addon.Movement)
    testlib.equal(harness.calls.trackerDependencies.character, harness.character)
    testlib.equal(harness.calls.trackerDependencies.level, 42)
    testlib.equal(type(harness.calls.trackerDependencies.emit), "function")
    testlib.equal(harness.calls.uiContext.db, harness.db)
    testlib.equal(harness.calls.uiContext.character, harness.character)
    testlib.equal(harness.calls.uiContext.tracker, harness.tracker)
    testlib.equal(harness.calls.uiContext.getCurrentLevel(), 42)
    testlib.equal(harness.calls.uiContext.capabilities.position, true)
    testlib.equal(harness.addon.Core.GetState().ready, true)
end)

testlib.case("reload preserves an existing session", function()
    local session = {
        startedAt = 7000,
        onFoot = 11,
        swimming = 22,
        taxi = 33,
    }
    local character = {
        identity = {
            name = "Traveler",
            realm = "TestRealm",
            raceFile = "Human",
            firstSeenAt = 1000,
        },
        lifetime = {
            onFoot = 111,
            swimming = 222,
            taxi = 333,
        },
        session = session,
        levels = {
            [42] = {
                onFoot = 44,
                swimming = 55,
                taxi = 66,
                reachedAt = 8000,
            },
        },
        diagnostics = {},
    }
    local harness = newCoreHarness({
        character = character,
    })
    initialize(harness)

    enterWorld(harness, false, true)

    testlib.equal(harness.calls.startSession, 0)
    testlib.equal(character.session, session)
    testlib.equal(character.session.onFoot, 11)
    testlib.equal(harness.calls.trackerDependencies.character, character)
    testlib.equal(harness.addon.Core.GetState().ready, true)
end)

testlib.case("reload replaces a malformed persisted session", function()
    local character = {
        identity = {
            name = "Traveler",
            realm = "TestRealm",
            raceFile = "Human",
            firstSeenAt = 1000,
        },
        lifetime = {
            onFoot = 111,
            swimming = 222,
            taxi = 333,
        },
        session = {},
        levels = {
            [42] = {
                onFoot = 44,
                swimming = 55,
                taxi = 66,
                reachedAt = 8000,
            },
        },
        diagnostics = {},
    }
    local harness = newCoreHarness({
        character = character,
    })
    initialize(harness)

    enterWorld(harness, false, true)

    testlib.equal(harness.calls.startSession, 1)
    testlib.equal(character.session.startedAt, 1000)
    testlib.equal(character.session.onFoot, 0)
    testlib.equal(character.session.swimming, 0)
    testlib.equal(character.session.taxi, 0)
end)

testlib.case("reload intent survives a transient identity failure", function()
    local session = {
        startedAt = 7000,
        onFoot = 11,
        swimming = 22,
        taxi = 33,
    }
    local character = {
        identity = {
            name = "Traveler",
            realm = "TestRealm",
            raceFile = "Human",
            firstSeenAt = 1000,
        },
        lifetime = {
            onFoot = 111,
            swimming = 222,
            taxi = 333,
        },
        session = session,
        levels = {
            [42] = {
                onFoot = 44,
                swimming = 55,
                taxi = 66,
                reachedAt = 8000,
            },
        },
        diagnostics = {},
    }
    local harness = newCoreHarness({
        character = character,
        identityError = "identityUnavailable",
    })
    initialize(harness)

    enterWorld(harness, false, true)
    testlib.equal(harness.calls.startSession, 0)
    testlib.equal(harness.addon.Core.GetState().ready, false)

    harness.options.identityError = nil
    enterWorld(harness, false, false)

    testlib.equal(harness.calls.startSession, 0)
    testlib.equal(character.session, session)
    testlib.equal(character.session.onFoot, 11)
    testlib.equal(harness.addon.Core.GetState().ready, true)
end)

testlib.case("reload waits for late SavedVariables before binding runtime", function()
    local harness = newRelogIntegrationHarness({
        deferSavedDB = true,
    })
    local character = harness.character
    local session = character.session
    local lifetime = character.lifetime
    local levels = character.levels

    initialize(harness)

    local state = harness.addon.Core.GetState()
    testlib.equal(state.databaseReady, false)
    testlib.equal(state.db, nil)
    testlib.equal(harness.environment.AzerothTravelMetricsDB, nil)

    harness.loadSavedDB()
    enterWorld(harness, false, true)

    testlib.equal(state.databaseReady, true)
    testlib.equal(state.db, harness.db)
    testlib.equal(state.character, character)
    testlib.equal(character.session, session)
    testlib.equal(character.lifetime, lifetime)
    testlib.equal(character.levels, levels)
    testlib.equal(character.session.onFoot, 11)
    testlib.equal(character.lifetime.onFoot, 111)
    testlib.equal(character.levels[42].onFoot, 44)
    testlib.equal(countKeys(harness.db.characters), 1)
    testlib.equal(harness.calls.trackerNew, 1)
    testlib.equal(harness.calls.uiInitialize, 1)
    testlib.equal(#harness.calls.tickers, 1)
end)

testlib.case("production storage lifecycle recovers canonical relog character", function()
    local harness = newRelogIntegrationHarness()
    local character = harness.character
    local storedIdentity = character.identity
    local lifetime = character.lifetime
    local priorSession = character.session
    local levels = character.levels
    local currentLevel = levels[42]
    local diagnostics = character.diagnostics

    initialize(harness)
    enterWorld(harness)

    local state = harness.addon.Core.GetState()
    local freshSession = character.session
    testlib.equal(harness.environment.AzerothTravelMetricsDB, harness.db)
    testlib.equal(state.db, harness.db)
    testlib.equal(
        harness.db.characters["Traveler-TestRealm"],
        character
    )
    testlib.equal(countKeys(harness.db.characters), 1)
    testlib.equal(harness.db.characters[""], nil)
    for key, storedCharacter in pairs(harness.db.characters) do
        testlib.equal(key, "Traveler-TestRealm")
        testlib.equal(storedCharacter, character)
    end
    testlib.equal(state.character, character)
    testlib.equal(character.identity, storedIdentity)
    testlib.equal(character.identity.name, "Traveler")
    testlib.equal(character.identity.realm, "TestRealm")
    testlib.equal(character.identity.raceFile, "Human")
    testlib.equal(character.identity.firstSeenAt, 1000)
    testlib.equal(character.lifetime, lifetime)
    testlib.equal(character.lifetime.onFoot, 111)
    testlib.equal(character.lifetime.swimming, 222)
    testlib.equal(character.lifetime.taxi, 333)
    testlib.equal(character.levels, levels)
    testlib.equal(character.levels[42], currentLevel)
    testlib.equal(currentLevel.onFoot, 44)
    testlib.equal(currentLevel.swimming, 55)
    testlib.equal(currentLevel.taxi, 66)
    testlib.equal(currentLevel.reachedAt, 8000)
    testlib.equal(character.diagnostics, diagnostics)
    testlib.equal(character.diagnostics.samples, 77)
    testlib.equal(character.diagnostics.rejected, 8)
    testlib.truthy(freshSession ~= priorSession)
    testlib.equal(freshSession.startedAt, harness.identity.now)
    testlib.equal(freshSession.onFoot, 0)
    testlib.equal(freshSession.swimming, 0)
    testlib.equal(freshSession.taxi, 0)
    testlib.equal(harness.calls.trackerNew, 1)
    testlib.equal(
        harness.calls.trackerDependencies[1].character,
        character
    )
    testlib.equal(harness.calls.uiInitialize, 1)
    testlib.equal(harness.calls.uiContexts[1].character, character)
    testlib.equal(harness.calls.minimapInitialize, 1)
    testlib.equal(harness.calls.minimapContexts[1].character, character)
    testlib.equal(#harness.calls.tickers, 1)

    enterWorld(harness)

    testlib.equal(character.session, freshSession)
    testlib.equal(character.session.startedAt, harness.identity.now)
    testlib.equal(harness.calls.identity, 1)
    testlib.equal(harness.calls.trackerNew, 1)
    testlib.equal(harness.calls.uiInitialize, 1)
    testlib.equal(harness.calls.minimapInitialize, 1)
    testlib.equal(#harness.calls.tickers, 1)
    testlib.equal(harness.calls.resets, 2)
    testlib.equal(harness.calls.resetReceiver, harness.tracker)
end)

testlib.case("relog initialization recovers existing character and resets only one session", function()
    local identity = {
        name = "Traveler",
        realm = "TestRealm",
        raceFile = "Human",
        level = 42,
        now = 9000,
    }
    local character = {
        identity = {
            name = "Traveler",
            realm = "TestRealm",
            raceFile = "Human",
            firstSeenAt = 1000,
        },
        lifetime = {
            onFoot = 111,
            swimming = 222,
            taxi = 333,
        },
        session = {
            startedAt = 7000,
            onFoot = 11,
            swimming = 22,
            taxi = 33,
        },
        levels = {
            [42] = {
                onFoot = 44,
                swimming = 55,
                taxi = 66,
                reachedAt = 8000,
            },
        },
        diagnostics = {
            samples = 77,
            rejected = 8,
        },
    }
    local db = {
        settings = {
            units = "imperial",
            showDiagnostics = true,
        },
        characters = {
            ["Traveler-TestRealm"] = character,
        },
    }
    local lifetime = character.lifetime
    local oldSession = character.session
    local levels = character.levels
    local currentLevel = levels[42]
    local diagnostics = character.diagnostics
    local storedIdentity = character.identity
    local storedName = storedIdentity.name
    local storedRealm = storedIdentity.realm
    local storedRaceFile = storedIdentity.raceFile
    local storedFirstSeenAt = storedIdentity.firstSeenAt
    local harness = newCoreHarness({
        initializedDB = db,
        identity = identity,
        realisticCharacterLookup = true,
    })

    initialize(harness)
    enterWorld(harness)

    local state = harness.addon.Core.GetState()
    local freshSession = character.session
    testlib.equal(harness.calls.getCharacter, 1)
    testlib.equal(harness.calls.startSession, 1)
    testlib.equal(harness.calls.characterArguments.db, db)
    testlib.equal(harness.calls.characterArguments.key, "Traveler-TestRealm")
    testlib.equal(#harness.calls.characterKeys, 1)
    testlib.equal(harness.calls.characterKeys[1], "Traveler-TestRealm")
    testlib.equal(db.characters["Traveler-TestRealm"], character)
    testlib.equal(countKeys(db.characters), 1)
    testlib.equal(db.characters[""], nil)
    testlib.equal(db.characters["Traveler-"], nil)
    for key, storedCharacter in pairs(db.characters) do
        testlib.equal(key, "Traveler-TestRealm")
        testlib.equal(storedCharacter, character)
    end
    testlib.equal(state.character, character)
    testlib.equal(harness.calls.sessionArguments.character, character)
    testlib.equal(character.lifetime, lifetime)
    testlib.equal(character.levels, levels)
    testlib.equal(character.levels[42], currentLevel)
    testlib.equal(character.diagnostics, diagnostics)
    testlib.equal(character.identity, storedIdentity)
    testlib.equal(character.identity.name, storedName)
    testlib.equal(character.identity.realm, storedRealm)
    testlib.equal(character.identity.raceFile, storedRaceFile)
    testlib.equal(character.identity.firstSeenAt, storedFirstSeenAt)
    testlib.equal(character.lifetime.onFoot, 111)
    testlib.equal(character.lifetime.swimming, 222)
    testlib.equal(character.lifetime.taxi, 333)
    testlib.equal(currentLevel.onFoot, 44)
    testlib.equal(currentLevel.swimming, 55)
    testlib.equal(currentLevel.taxi, 66)
    testlib.equal(currentLevel.reachedAt, 8000)
    testlib.equal(character.diagnostics.samples, 77)
    testlib.equal(character.diagnostics.rejected, 8)
    testlib.truthy(freshSession ~= oldSession)
    testlib.equal(freshSession.startedAt, identity.now)
    testlib.equal(freshSession.onFoot, 0)
    testlib.equal(freshSession.swimming, 0)
    testlib.equal(freshSession.taxi, 0)

    enterWorld(harness)

    testlib.equal(harness.calls.getCharacter, 1)
    testlib.equal(harness.calls.startSession, 1)
    testlib.equal(#harness.calls.characterKeys, 1)
    testlib.equal(countKeys(db.characters), 1)
    testlib.equal(db.characters["Traveler-TestRealm"], character)
    testlib.equal(character.session, freshSession)
    testlib.equal(character.session.startedAt, identity.now)
end)

testlib.case("core tolerates missing minimap for load-order safety", function()
    local harness = newCoreHarness({
        missingMinimap = true,
    })

    makeReady(harness)

    testlib.equal(harness.addon.Core.GetState().ready, true)
    testlib.equal(harness.calls.uiInitialize, 1)
    testlib.equal(#harness.calls.uiErrors, 0)
end)

testlib.case("core reports minimap initialization failure without disabling tracking", function()
    local harness = newCoreHarness({
        minimapThrows = true,
    })

    makeReady(harness)
    initialize(harness)

    testlib.equal(harness.addon.Core.GetState().ready, true)
    testlib.equal(harness.calls.minimapInitialize, 1)
    testlib.equal(#harness.calls.prints, 1)
    testlib.equal(#harness.calls.uiErrors, 1)
    testlib.truthy(contains(harness.calls.prints[1], "minimap"))
    testlib.truthy(contains(harness.calls.uiErrors[1], "minimap"))

    testlib.equal(#harness.calls.tickers, 1)
end)

testlib.case("unsupported storage preserves the saved DB and reports once", function()
    local savedDB = {
        schemaVersion = 999,
        sentinel = true,
    }
    local harness = newCoreHarness({
        savedDB = savedDB,
        initializeError = "unsupportedSchema",
    })

    initialize(harness)
    initialize(harness)
    enterWorld(harness)

    testlib.equal(harness.environment.AzerothTravelMetricsDB, savedDB)
    testlib.equal(harness.calls.identity, 0)
    testlib.equal(harness.calls.getCharacter, 0)
    testlib.equal(#harness.calls.tickers, 0)
    testlib.equal(#harness.calls.uiErrors, 1)
    testlib.equal(#harness.calls.prints, 1)
    testlib.truthy(contains(harness.calls.prints[1], "unsupportedSchema"))
end)

testlib.case("identity failure retains the database and retries without an empty record", function()
    local savedDB = {
        sentinel = true,
    }
    local harness = newCoreHarness({
        savedDB = savedDB,
        identityError = "identityUnavailable",
    })

    initialize(harness)
    enterWorld(harness)

    testlib.equal(harness.environment.AzerothTravelMetricsDB, harness.db)
    testlib.equal(harness.addon.Core.GetState().databaseReady, true)
    testlib.equal(harness.addon.Core.GetState().ready, false)
    testlib.equal(harness.calls.identity, 1)
    testlib.equal(harness.calls.getCharacter, 0)
    testlib.equal(harness.calls.startSession, 0)
    testlib.equal(harness.calls.trackerNew, 0)
    testlib.equal(#harness.calls.tickers, 0)
    testlib.equal(#harness.calls.uiErrors, 1)
    testlib.equal(#harness.calls.prints, 1)

    harness.options.identityError = nil
    enterWorld(harness)

    testlib.equal(harness.calls.identity, 2)
    testlib.equal(harness.calls.getCharacter, 1)
    testlib.equal(harness.calls.startSession, 1)
    testlib.equal(harness.calls.trackerNew, 1)
    testlib.equal(harness.calls.uiInitialize, 1)
    testlib.equal(#harness.calls.tickers, 1)
    testlib.equal(countKeys(harness.db.characters), 0)
end)

testlib.case("identity exceptions are throttled and retried on entering world", function()
    local harness = newCoreHarness({
        identityThrows = true,
    })
    initialize(harness)

    enterWorld(harness)
    enterWorld(harness)

    testlib.equal(harness.calls.identity, 2)
    testlib.equal(harness.calls.getCharacter, 0)
    testlib.equal(harness.calls.startSession, 0)
    testlib.equal(#harness.calls.tickers, 0)
    testlib.equal(#harness.calls.prints, 1)
    testlib.equal(#harness.calls.uiErrors, 1)
end)

testlib.case("session initialization failure prevents partial runtime startup", function()
    local throwing = newCoreHarness({
        startSessionThrows = true,
    })
    initialize(throwing)
    enterWorld(throwing)
    enterWorld(throwing)

    testlib.equal(throwing.calls.identity, 2)
    testlib.equal(throwing.calls.getCharacter, 2)
    testlib.equal(throwing.calls.startSession, 2)
    testlib.equal(throwing.calls.trackerNew, 0)
    testlib.equal(#throwing.calls.tickers, 0)
    testlib.equal(throwing.addon.Core.GetState().ready, false)
    testlib.equal(throwing.addon.Core.GetState().db, throwing.db)
    testlib.equal(#throwing.calls.prints, 1)
    testlib.truthy(contains(
        throwing.calls.prints[1],
        "sessionInitializeFailed"
    ))

    local invalid = newCoreHarness({
        startSessionResult = false,
    })
    initialize(invalid)
    enterWorld(invalid)

    testlib.equal(invalid.calls.startSession, 1)
    testlib.equal(invalid.calls.trackerNew, 0)
    testlib.equal(#invalid.calls.tickers, 0)
    testlib.equal(invalid.addon.Core.GetState().databaseReady, true)
    testlib.equal(#invalid.calls.prints, 1)
    testlib.truthy(contains(
        invalid.calls.prints[1],
        "sessionInitializeFailed"
    ))
end)

testlib.case("runtime retries preserve a session that already started", function()
    local harness = newCoreHarness({
        trackerThrows = true,
    })
    initialize(harness)

    enterWorld(harness)
    harness.options.trackerThrows = false
    enterWorld(harness)

    testlib.equal(harness.calls.identity, 1)
    testlib.equal(harness.calls.getCharacter, 1)
    testlib.equal(harness.calls.startSession, 1)
    testlib.equal(harness.calls.trackerNew, 2)
    testlib.equal(harness.calls.uiInitialize, 1)
    testlib.equal(#harness.calls.tickers, 1)
    testlib.equal(harness.addon.Core.GetState().ready, true)
end)

testlib.case("subsequent entering world preserves runtime and refreshes capabilities", function()
    local initialCapabilities = {
        position = false,
        onFootReady = false,
    }
    local harness = newCoreHarness({
        capabilities = initialCapabilities,
    })
    makeReady(harness)
    local exposedCapabilities = harness.calls.uiContext.capabilities
    local selectedCharacter = harness.addon.Core.GetState().character
    local selectedTracker = harness.addon.Core.GetState().tracker
    local activeTicker = harness.addon.Core.GetState().ticker

    harness.options.capabilities = {
        position = true,
        onFootReady = true,
    }
    harness.options.identityThrows = true
    enterWorld(harness)

    testlib.equal(harness.calls.uiContext.capabilities, exposedCapabilities)
    testlib.equal(exposedCapabilities.position, true)
    testlib.equal(exposedCapabilities.onFootReady, true)
    testlib.equal(harness.calls.identity, 1)
    testlib.equal(harness.calls.getCharacter, 1)
    testlib.equal(harness.calls.startSession, 1)
    testlib.equal(harness.calls.trackerNew, 1)
    testlib.equal(harness.calls.capabilities, 2)
    testlib.equal(harness.calls.uiInitialize, 1)
    testlib.equal(harness.calls.minimapInitialize, 1)
    testlib.equal(harness.calls.resets, 2)
    testlib.equal(#harness.calls.tickers, 1)
    testlib.equal(harness.calls.tickers[1].cancelled, false)
    testlib.equal(harness.addon.Core.GetState().character, selectedCharacter)
    testlib.equal(harness.addon.Core.GetState().tracker, selectedTracker)
    testlib.equal(harness.addon.Core.GetState().ticker, activeTicker)
end)

testlib.case("ticker refreshes shared capabilities after failure and recovery", function()
    local harness = newCoreHarness({
        capabilities = {
            position = true,
            map = true,
            onFootReady = true,
            stale = true,
        },
        sampleResults = {
            {
                reason = "positionUnavailable",
                capabilities = {
                    position = false,
                    map = true,
                    onFootReady = false,
                },
            },
            {
                reason = "baseline",
                capabilities = {
                    position = true,
                    map = true,
                    onFootReady = true,
                },
            },
        },
    })
    makeReady(harness)
    local capabilities = harness.calls.uiContext.capabilities
    local ticker = harness.calls.tickers[1]

    ticker.callback()
    testlib.equal(capabilities.position, false)
    testlib.equal(capabilities.onFootReady, false)
    testlib.equal(capabilities.stale, nil)

    ticker.callback()
    testlib.equal(capabilities.position, true)
    testlib.equal(capabilities.onFootReady, true)
    testlib.equal(harness.calls.capabilities, 1)
end)

testlib.case("entering world retries an unavailable ticker without rebuilding runtime", function()
    local harness = newCoreHarness({
        invalidTickerAttempts = 1,
    })
    initialize(harness)

    enterWorld(harness)

    local state = harness.addon.Core.GetState()
    local selectedCharacter = state.character
    local selectedTracker = state.tracker
    testlib.equal(state.ready, true)
    testlib.equal(state.ticker, nil)
    testlib.equal(harness.calls.tickerAttempts, 1)
    testlib.equal(#harness.calls.tickers, 0)

    enterWorld(harness)

    local activeTicker = state.ticker
    testlib.equal(harness.calls.identity, 1)
    testlib.equal(harness.calls.getCharacter, 1)
    testlib.equal(harness.calls.startSession, 1)
    testlib.equal(harness.calls.trackerNew, 1)
    testlib.equal(harness.calls.uiInitialize, 1)
    testlib.equal(harness.calls.minimapInitialize, 1)
    testlib.equal(harness.calls.tickerAttempts, 2)
    testlib.equal(#harness.calls.tickers, 1)
    testlib.equal(activeTicker, harness.calls.tickers[1])
    testlib.equal(harness.calls.tickers[1].cancelled, false)
    testlib.equal(state.character, selectedCharacter)
    testlib.equal(state.tracker, selectedTracker)

    enterWorld(harness)

    testlib.equal(harness.calls.tickerAttempts, 2)
    testlib.equal(#harness.calls.tickers, 1)
    testlib.equal(state.ticker, activeTicker)
    testlib.equal(harness.calls.tickers[1].cancelled, false)
end)

testlib.case("native-like ticker handles are retained and cancelled on logout", function()
    local harness = newCoreHarness({
        nativeTickerHandles = true,
    })
    makeReady(harness)
    testlib.equal(#harness.calls.tickers, 1)
    testlib.equal(
        harness.addon.Core.GetState().ticker,
        harness.calls.tickers[1].handle
    )

    enterWorld(harness)
    testlib.equal(#harness.calls.tickers, 1)
    testlib.equal(harness.calls.tickers[1].cancelled, false)

    harness.fire("PLAYER_LOGOUT")
    testlib.equal(harness.calls.tickers[1].cancelled, true)
    testlib.equal(harness.addon.Core.GetState().ticker, nil)
end)

testlib.case("ticker refreshes only accepted segments while the window is shown", function()
    local harness = newCoreHarness({
        shown = true,
        sampleResults = {
            { reason = "baseline" },
            { segment = { yards = 3 } },
        },
    })
    makeReady(harness)

    local ticker = harness.calls.tickers[1]
    ticker.callback()
    testlib.equal(harness.calls.uiRefresh, 0)
    ticker.callback()
    testlib.equal(harness.calls.uiRefresh, 1)

    local hidden = newCoreHarness({
        shown = false,
        sampleResults = {
            { segment = { yards = 3 } },
        },
    })
    makeReady(hidden)
    hidden.calls.tickers[1].callback()
    testlib.equal(hidden.calls.uiRefresh, 0)
end)

testlib.case("ticker reports only explicit capability reasons once", function()
    local harness = newCoreHarness({
        sampleResults = {
            { reason = "positionUnavailable" },
            { reason = "positionUnavailable" },
            { reason = "stationary" },
            { reason = "unsupportedState" },
            { reason = "notAnApprovedCapabilityReason" },
        },
    })
    makeReady(harness)

    for _ = 1, 5 do
        harness.calls.tickers[1].callback()
    end

    testlib.equal(#harness.calls.prints, 2)
    testlib.truthy(contains(harness.calls.prints[1], "positionUnavailable"))
    testlib.truthy(contains(harness.calls.prints[2], "unsupportedState"))
end)

testlib.case("level up obtains wall clock before setting level and refreshes", function()
    local harness = newCoreHarness()
    makeReady(harness)

    harness.fire("PLAYER_LEVEL_UP", 43)

    testlib.equal(harness.calls.order[1], "getNow")
    testlib.equal(harness.calls.order[2], "setLevel")
    testlib.equal(harness.calls.levelCalls[1].level, 43)
    testlib.equal(harness.calls.levelCalls[1].now, 2000)
    testlib.equal(harness.calls.uiContext.getCurrentLevel(), 43)
    testlib.equal(harness.calls.uiRefresh, 1)
end)

testlib.case("level up rejects invalid levels and reports time or tracker failures", function()
    local invalid = newCoreHarness()
    makeReady(invalid)
    invalid.fire("PLAYER_LEVEL_UP", 0)
    testlib.equal(#invalid.calls.levelCalls, 0)
    testlib.equal(invalid.calls.uiContext.getCurrentLevel(), 42)
    testlib.equal(#invalid.calls.prints, 1)

    local noTime = newCoreHarness({
        nowError = "timeUnavailable",
    })
    makeReady(noTime)
    noTime.fire("PLAYER_LEVEL_UP", 43)
    testlib.equal(#noTime.calls.levelCalls, 0)
    testlib.equal(noTime.calls.uiContext.getCurrentLevel(), 42)
    testlib.equal(#noTime.calls.prints, 1)

    local rejected = newCoreHarness({
        setLevelResult = {
            nil,
            "invalidStoredLevel",
        },
    })
    makeReady(rejected)
    rejected.fire("PLAYER_LEVEL_UP", 43)
    testlib.equal(rejected.calls.uiContext.getCurrentLevel(), 42)
    testlib.equal(rejected.calls.uiRefresh, 0)
    testlib.equal(#rejected.calls.uiErrors, 1)
    testlib.equal(#rejected.calls.prints, 1)

    local throwingTime = newCoreHarness({
        nowThrows = true,
    })
    makeReady(throwingTime)
    local succeeded = pcall(throwingTime.fire, "PLAYER_LEVEL_UP", 43)
    testlib.equal(succeeded, true)
    testlib.equal(#throwingTime.calls.levelCalls, 0)
    testlib.equal(throwingTime.calls.uiContext.getCurrentLevel(), 42)
    testlib.equal(#throwingTime.calls.prints, 1)
end)

testlib.case("logout cancels and clears the active ticker", function()
    local harness = newCoreHarness()
    makeReady(harness)

    harness.fire("PLAYER_LOGOUT")

    testlib.equal(harness.calls.tickers[1].cancelled, true)
    testlib.equal(harness.addon.Core.GetState().ticker, nil)
end)

testlib.case("slash commands toggle and persist units and diagnostics", function()
    local harness = newCoreHarness()
    makeReady(harness)
    local slash = harness.environment.SlashCmdList.AZEROTHTRAVELMETRICS

    slash("")
    slash("show")
    testlib.equal(harness.calls.uiToggle, 2)

    slash("units imperial")
    testlib.equal(harness.db.settings.units, "imperial")
    slash("units metric")
    testlib.equal(harness.db.settings.units, "metric")
    slash("diagnostics on")
    testlib.equal(harness.db.settings.showDiagnostics, true)
    slash("diagnostics off")
    testlib.equal(harness.db.settings.showDiagnostics, false)
    testlib.equal(harness.calls.uiRefresh, 4)
end)

testlib.case("reset command opens confirmation without resetting immediately", function()
    local harness = newCoreHarness()
    makeReady(harness)

    harness.environment.SlashCmdList.AZEROTHTRAVELMETRICS("reset session")

    testlib.equal(harness.calls.uiConfirmReset, 1)
end)

testlib.case("status prints capabilities and sorted diagnostic counts", function()
    local harness = newCoreHarness({
        capabilities = {
            position = true,
            map = false,
            time = true,
            taxi = true,
            swimming = false,
            mounted = true,
            grounded = true,
            taxiReady = false,
            swimmingReady = false,
            onFootReady = false,
        },
    })
    makeReady(harness)

    harness.environment.SlashCmdList.AZEROTHTRAVELMETRICS("status")

    testlib.equal(#harness.calls.prints, 4)
    testlib.truthy(contains(harness.calls.prints[1], "position=true"))
    testlib.truthy(contains(harness.calls.prints[1], "map=false"))
    testlib.truthy(contains(harness.calls.prints[2], "taxiReady=false"))
    testlib.truthy(contains(harness.calls.prints[3], "alpha=1"))
    testlib.truthy(contains(harness.calls.prints[4], "zeta=3"))
end)

testlib.case("slash commands report not-ready and concise usage without throwing", function()
    local harness = newCoreHarness()
    local slash = harness.environment.SlashCmdList.AZEROTHTRAVELMETRICS

    local readySucceeded = pcall(slash, "status")
    testlib.equal(readySucceeded, true)
    testlib.equal(#harness.calls.prints, 1)
    testlib.truthy(contains(harness.calls.prints[1], "not ready"))

    makeReady(harness)
    slash("units")
    slash("diagnostics maybe")
    slash("unknown")
    testlib.equal(#harness.calls.prints, 4)
    testlib.truthy(contains(harness.calls.prints[2], "Usage:"))
    testlib.truthy(contains(harness.calls.prints[3], "Usage:"))
    testlib.truthy(contains(harness.calls.prints[4], "Usage:"))
end)

local function newFrame(frameType, name, parent, template, options)
    options = options or {}
    local frame = {
        frameType = frameType,
        name = name,
        parent = parent,
        template = template,
        scripts = {},
        children = {},
        shown = false,
        textures = {},
    }

    function frame:SetSize(width, height)
        self.width = width
        self.height = height
    end

    function frame:SetPoint(...)
        self.point = { ... }
        self.points = self.points or {}
        table.insert(self.points, self.point)
    end

    function frame:GetPoint()
        if self.malformedPoint then
            return self.malformedPoint[1],
                self.malformedPoint[2],
                self.malformedPoint[3],
                self.malformedPoint[4],
                self.malformedPoint[5]
        end
        return table.unpack(self.point or {})
    end

    function frame:ClearAllPoints()
        self.point = nil
    end

    function frame:SetFrameStrata(strata)
        self.strata = strata
    end

    function frame:SetFrameLevel(level)
        self.frameLevel = level
    end

    function frame:GetFrameLevel()
        return self.frameLevel or 1
    end

    function frame:SetDrawLayer(layer, sublevel)
        self.layer = layer
        self.sublevel = sublevel
    end

    function frame:SetID(id)
        self.id = id
    end

    function frame:GetID()
        return self.id
    end

    function frame:SetButtonState(state, locked)
        self.buttonState = state
        self.buttonStateLocked = locked
    end

    function frame:LockHighlight()
        self.highlightLocked = true
    end

    function frame:UnlockHighlight()
        self.highlightLocked = false
    end

    function frame:SetMovable(value)
        self.movable = value
    end

    function frame:EnableMouse(value)
        self.mouseEnabled = value
    end

    function frame:RegisterForDrag(button)
        self.dragButton = button
    end

    function frame:SetScript(scriptName, callback)
        self.scripts[scriptName] = callback
    end

    function frame:GetScript(scriptName)
        return self.scripts[scriptName]
    end

    function frame:HookScript(scriptName, callback)
        local previous = self.scripts[scriptName]
        self.scripts[scriptName] = function(...)
            if previous then
                previous(...)
            end
            callback(...)
        end
    end

    function frame:StartMoving()
        self.startedMoving = true
    end

    function frame:StopMovingOrSizing()
        self.stoppedMoving = true
    end

    function frame:SetText(text)
        self.text = text
    end

    function frame:GetText()
        return self.text
    end

    function frame:SetWidth(width)
        self.width = width
    end

    function frame:SetHeight(height)
        self.height = height
    end

    function frame:EnableMouseWheel(value)
        self.mouseWheelEnabled = value
    end

    function frame:SetScrollChild(child)
        self.scrollChild = child
    end

    function frame:SetVerticalScroll(offset)
        self.verticalScroll = offset
    end

    function frame:GetVerticalScroll()
        return self.verticalScroll or 0
    end

    function frame:GetVerticalScrollRange()
        if options.rejectLevelScrollRange
            and self.template == "UIPanelScrollFrameTemplate"
        then
            error("vertical scroll range unavailable")
        end
        if not self.scrollChild then
            return 0
        end
        return math.max(0, (self.scrollChild.height or 0) - (self.height or 0))
    end

    function frame:SetJustifyH(value)
        self.justifyH = value
    end

    function frame:SetJustifyV(value)
        self.justifyV = value
    end

    function frame:SetWordWrap(value)
        self.wordWrap = value
    end

    function frame:SetNonSpaceWrap(value)
        self.nonSpaceWrap = value
    end

    function frame:SetMaxLines(value)
        self.maxLines = value
    end

    function frame:SetTextColor(...)
        self.textColor = { ... }
    end

    function frame:GetStringHeight()
        local text = tostring(self.text or "")
        local lineCount = 1
        for _ in text:gmatch("\n") do
            lineCount = lineCount + 1
        end
        return lineCount * 12
    end

    function frame:SetAlpha(alpha)
        self.alpha = alpha
    end

    function frame:GetAlpha()
        return self.alpha
    end

    function frame:SetChecked(value)
        self.checked = value == true
    end

    function frame:GetChecked()
        return self.checked == true
    end

    function frame:SetBackdrop(...)
        if options.rejectBackdrop then
            error("backdrop unavailable")
        end
        self.backdrop = { ... }
        if options.rejectBackdropReturn then
            return false
        end
    end

    function frame:SetBackdropColor(...)
        if options.rejectBackdropColor then
            error("backdrop color unavailable")
        end
        self.backdropColor = { ... }
        if options.rejectBackdropColorReturn then
            return false
        end
    end

    function frame:SetBackdropBorderColor(...)
        self.backdropBorderColor = { ... }
    end

    function frame:SetNormalTexture(texture)
        self.normalTexture = texture
    end

    function frame:SetHighlightTexture(texture)
        self.highlightTexture = texture
    end

    function frame:Show()
        self.shown = true
    end

    function frame:Hide()
        self.shown = false
        self.hideCalls = (self.hideCalls or 0) + 1
    end

    function frame:IsShown()
        return self.shown
    end

    function frame:IsMouseOver()
        return self.mouseOver == true
    end

    function frame:CreateFontString(childName, layer, font)
        local child = newFrame("FontString", childName, self, font, options)
        child.layer = layer
        table.insert(self.children, child)
        return child
    end

    function frame:CreateTexture(childName, layer)
        local child = newFrame("Texture", childName, self, nil, options)
        child.layer = layer
        table.insert(self.children, child)
        table.insert(self.textures, child)
        return child
    end

    function frame:GetChildren()
        return table.unpack(self.children)
    end

    function frame:SetAtlas(atlas, useAtlasSize)
        if options.rejectAtlases and options.rejectAtlases[atlas] then
            error("atlas unavailable")
        end
        self.atlas = atlas
        self.useAtlasSize = useAtlasSize
        return true
    end

    function frame:SetColorTexture(red, green, blue, alpha)
        self.color = { red, green, blue, alpha }
    end

    function frame:SetGradientAlpha(...)
        if options.rejectGradients then
            error("gradient unavailable")
        end
        self.gradient = { ... }
        if options.rejectGradientReturn then
            return false
        end
    end

    function frame:SetVertexColor(...)
        self.vertexColor = { ... }
    end

    function frame:SetTexCoord(...)
        self.texCoord = { ... }
    end

    if options.missingGradientAPI then
        frame.SetGradientAlpha = nil
    end

    if options.missingHookScript then
        frame.HookScript = nil
    end

    function frame:SetTexture(texture)
        self.texture = texture
    end

    function frame:SetAllPoints(target)
        self.allPoints = target or true
    end

    return frame
end

local function newUIHarness(options)
    options = options or {}

    local created = {}
    local strataAttempts = {}
    local order = options.order or {}
    local calls = {
        overview = 0,
        overviewCharacters = {},
        overviewArguments = {},
        rows = 0,
        rowCharacters = {},
        rowArguments = {},
        diagnostics = 0,
        diagnosticCharacters = {},
        diagnosticArguments = {},
        uiInitialize = 0,
        modernMetadata = 0,
        legacyMetadata = 0,
        reset = 0,
        baselineReset = 0,
        baselineResetReceivers = {},
        now = 0,
        protected = 0,
        order = order,
        templates = {},
        hudStrataAttempts = {},
    }
    local globals = {
        UIParent = {
            name = "UIParent",
        },
        StaticPopupDialogs = {},
        YES = "Yes",
        NO = "No",
    }
    if not options.legacyMetadataOnly then
        globals.C_AddOns = {
            GetAddOnMetadata = function(receivedAddonName, field)
                calls.modernMetadata = calls.modernMetadata + 1
                calls.metadataAddonName = receivedAddonName
                calls.metadataField = field
                if options.metadataThrows then
                    error("metadata exploded")
                end
                if options.metadataReturnsNil then
                    return nil
                end
                if options.metadataValue ~= nil then
                    return options.metadataValue
                end
                return "1.0.0-beta"
            end,
        }
    end
    globals.GetAddOnMetadata = function(receivedAddonName, field)
        calls.legacyMetadata = calls.legacyMetadata + 1
        calls.metadataAddonName = receivedAddonName
        calls.metadataField = field
        if options.legacyMetadataThrows then
            error("legacy metadata exploded")
        end
        if options.legacyMetadataValue ~= nil then
            return options.legacyMetadataValue
        end
        return nil
    end
    if options.uispecialframes == nil then
        globals.UISpecialFrames = {}
    elseif options.uispecialframes ~= false then
        globals.UISpecialFrames = options.uispecialframes
    end

    globals.CreateFrame = function(frameType, name, parent, template)
        table.insert(calls.templates, template or false)
        if options.inCombat
            and type(template) == "string"
            and contains(template, "Secure")
        then
            calls.protected = calls.protected + 1
            error("protected template used in combat")
        end
        if (template == "PortraitFrameTemplate"
                or template == "BasicFrameTemplateWithInset")
            and options.rejectMainTemplate
        then
            error("template unavailable")
        end
        if options.rejectTemplates and options.rejectTemplates[template] then
            error("template unavailable")
        end

        local frame = newFrame(frameType, name, parent, template, options)
        if template == "MaximizeMinimizeButtonFrameTemplate" then
            frame.MaximizeButton = newFrame(
                "Button",
                nil,
                frame,
                nil,
                options
            )
            frame.MinimizeButton = newFrame(
                "Button",
                nil,
                frame,
                nil,
                options
            )
            function frame:SetMinimizedLook()
                self.MaximizeButton:Hide()
                self.MinimizeButton:Show()
            end
            function frame:SetMaximizedLook()
                self.MaximizeButton:Show()
                self.MinimizeButton:Hide()
            end
        end
        if template == "PortraitFrameTemplate" then
            frame.TitleContainer = newFrame(
                "Frame",
                nil,
                frame,
                nil,
                options
            )
            frame.TitleContainer.TitleText = newFrame(
                "FontString",
                nil,
                frame.TitleContainer,
                "GameFontNormal",
                options
            )
            frame.PortraitContainer = newFrame(
                "Frame",
                nil,
                frame,
                nil,
                options
            )
            frame.PortraitContainer.portrait = newFrame(
                "Texture",
                nil,
                frame.PortraitContainer,
                nil,
                options
            )
            if not options.portraitMissingClose then
                frame.CloseButton = newFrame("Button", nil, frame, nil, options)
            end
        end
        if template == "LargeSideTabButtonTemplate" then
            frame.Icon = newFrame("Texture", nil, frame, nil, options)
            frame.SelectedTexture = newFrame("Texture", nil, frame, nil, options)
        end
        if template == "UIPanelScrollFrameTemplate" then
            local scrollBar = newFrame("Slider", nil, frame, nil, options)
            scrollBar.ScrollUpButton =
                newFrame("Button", nil, scrollBar, nil, options)
            scrollBar.ScrollDownButton =
                newFrame("Button", nil, scrollBar, nil, options)
            scrollBar.ThumbTexture =
                newFrame("Texture", nil, scrollBar, nil, options)
            table.insert(frame.children, scrollBar)
            if not options.levelScrollbarDirectChildOnly then
                frame.ScrollBar = scrollBar
            end
            if options.levelScrollUnrelatedDirectChild then
                local unrelated = newFrame(
                    "Frame",
                    nil,
                    frame,
                    nil,
                    options
                )
                unrelated:Show()
                table.insert(frame.children, unrelated)
            end
        end
        if name == "AzerothTravelMetricsFrame"
            or name == "AzerothTravelMetricsHUD"
        then
            local original = frame.SetFrameStrata
            frame.SetFrameStrata = function(self, strata)
                local attempts = name == "AzerothTravelMetricsFrame"
                    and strataAttempts
                    or calls.hudStrataAttempts
                table.insert(attempts, strata)
                if options.rejectStrata and options.rejectStrata[strata] then
                    error("strata unavailable")
                end
                original(self, strata)
            end
        end
        table.insert(created, frame)
        return frame
    end

    globals.SetPortraitToTexture = function(frame, texture)
        if options.portraitHelperThrows then
            error("portrait helper unavailable")
        end
        frame.portraitTexture = texture
    end

    globals.GameTooltip = {
        SetOwner = function(_, owner, anchor)
            calls.tooltipOwner = owner
            calls.tooltipAnchor = anchor
        end,
        SetText = function(_, text)
            calls.tooltipText = text
        end,
        Show = function()
            calls.tooltipShown = true
        end,
        Hide = function()
            calls.tooltipHidden = true
        end,
    }

    globals.StaticPopup_Show = function(key)
        globals.shownPopup = key
        return globals.StaticPopupDialogs[key]
    end

    globals.InCombatLockdown = function()
        return options.inCombat == true
    end

    local addon, environment = testlib.loadAddon(UI_FILES, globals)
    local character = options.character or {
        identity = {
            name = "Traveler",
            realm = "TestRealm",
        },
        session = {
            startedAt = 1000,
            totals = {
                onFoot = 12,
            },
        },
    }
    local db = options.db or {
        settings = {
            units = "metric",
            showMinimap = true,
            showDiagnostics = true,
            hudPoint = "CENTER",
            hudX = 0,
            hudY = 0,
        },
    }

    addon.UIModel = {
        BuildOverview = function(receivedCharacter, currentLevel, units)
            calls.overview = calls.overview + 1
            table.insert(calls.overviewCharacters, receivedCharacter)
            table.insert(calls.overviewArguments, {
                character = receivedCharacter,
                currentLevel = currentLevel,
                units = units,
            })
            table.insert(order, "refresh")
            if options.overviewSequence then
                local result = options.overviewSequence[
                    math.min(calls.overview, #options.overviewSequence)
                ]
                return result.overview, result.error
            end
            if options.overviewError then
                return nil, options.overviewError
            end
            return options.overview or {
                lifetime = {
                    steps = "12.5K",
                    onFoot = "1.00 km",
                    swimming = "2.00 km",
                    taxi = "3.00 km",
                    total = "3.53 km",
                },
                session = {
                    steps = "10",
                    onFoot = "100 m",
                    swimming = "200 m",
                    taxi = "300 m",
                    total = "600 m",
                },
                currentLevel = {
                    steps = "5",
                    onFoot = "50 m",
                    swimming = "60 m",
                    taxi = "70 m",
                    total = "180 m",
                },
            }
        end,
        BuildLevelRows = function(receivedCharacter, units)
            calls.rows = calls.rows + 1
            table.insert(calls.rowCharacters, receivedCharacter)
            table.insert(calls.rowArguments, {
                character = receivedCharacter,
                units = units,
            })
            if options.levelRowsSequence then
                return options.levelRowsSequence[
                    math.min(calls.rows, #options.levelRowsSequence)
                ]
            end
            return options.levelRows or {
                {
                    level = 42,
                    steps = "12.5K",
                    onFoot = "50 m",
                    swimming = "60 m",
                    taxi = "70 m",
                    total = "603 yd",
                },
                {
                    level = 41,
                    steps = "50",
                    onFoot = "500 m",
                    swimming = "600 m",
                    taxi = "700 m",
                    total = "1.80 km",
                },
            }
        end,
        BuildDiagnostics = function(receivedCharacter, enabled)
            calls.diagnostics = calls.diagnostics + 1
            table.insert(calls.diagnosticCharacters, receivedCharacter)
            table.insert(calls.diagnosticArguments, {
                character = receivedCharacter,
                enabled = enabled,
            })
            return options.diagnostics or {
                {
                    reason = "alpha",
                    count = 2,
                },
            }
        end,
    }

    addon.Storage = {
        ResetSession = function(receivedCharacter, now)
            calls.reset = calls.reset + 1
            table.insert(order, "storageReset")
            calls.resetCharacter = receivedCharacter
            calls.resetNow = now
            if options.resetThrows then
                error("reset exploded")
            end
            if options.resetError then
                return false, options.resetError
            end
            receivedCharacter.session = {
                startedAt = now,
                totals = {
                    onFoot = 0,
                },
            }
            return true
        end,
    }
    addon.Compat = {}
    addon.Minimap = {
        UpdateVisibility = function()
            calls.minimapVisibility = (calls.minimapVisibility or 0) + 1
        end,
    }
    if not options.nowUnavailable then
        addon.Compat.GetNow = function()
            calls.now = calls.now + 1
            if options.nowError then
                return nil, options.nowError
            end
            return 3000
        end
    end

    local tracker = options.tracker or {}
    if type(tracker.ResetBaseline) ~= "function" then
        function tracker:ResetBaseline()
            calls.baselineReset = calls.baselineReset + 1
            table.insert(calls.baselineResetReceivers, self)
            table.insert(order, "baselineReset")
            if options.baselineResetThrows then
                error("baseline exploded")
            end
            self.previous = nil
        end
    end

    local context = {
        db = db,
        character = character,
        tracker = tracker,
        capabilities = {
            position = true,
        },
        getCurrentLevel = function()
            return 42
        end,
    }
    local initializeUI = addon.UI.Initialize
    addon.UI.Initialize = function(initialContext)
        calls.uiInitialize = calls.uiInitialize + 1
        calls.uiInitializeContext = initialContext
        return initializeUI(initialContext)
    end
    addon.UI.Initialize(context)

    return {
        addon = addon,
        environment = environment,
        created = created,
        calls = calls,
        character = character,
        db = db,
        tracker = tracker,
        context = context,
        strataAttempts = strataAttempts,
        hudStrataAttempts = calls.hudStrataAttempts,
    }
end

testlib.case("ui creation is lazy idempotent and preserves the fallback warm shell", function()
    local harness = newUIHarness({
        rejectTemplates = {
            PortraitFrameTemplate = true,
        },
    })

    testlib.equal(#harness.created, 0)
    local first = harness.addon.UI.Create()
    local createdCount = #harness.created
    local second = harness.addon.UI.Create()

    testlib.equal(first, second)
    testlib.equal(#harness.created, createdCount)
    testlib.equal(first.template, "BackdropTemplate")
    testlib.equal(first.width, 420)
    testlib.equal(first.height, 470)
    testlib.equal(first.strata, "MEDIUM")
    testlib.equal(first:GetFrameLevel(), 100)
    testlib.truthy(first.backdrop ~= nil)
    testlib.equal(
        first.backdrop[1].bgFile,
        "Interface\\Tooltips\\UI-Tooltip-Background"
    )
    testlib.equal(
        first.backdrop[1].edgeFile,
        "Interface\\Tooltips\\UI-Tooltip-Border"
    )
    testlib.near(first.backdropColor[1], 0.08, 0.001)
    testlib.near(first.backdropColor[2], 0.06, 0.001)
    testlib.near(first.backdropColor[3], 0.035, 0.001)
    testlib.near(first.backdropColor[4], 0.95, 0.001)
    testlib.near(first.backdropBorderColor[1], 0.67, 0.001)
    testlib.near(first.backdropBorderColor[2], 0.53, 0.001)
    testlib.near(first.backdropBorderColor[3], 0.27, 0.001)
    testlib.near(first.backdropBorderColor[4], 0.96, 0.001)
    testlib.equal(first.movable, true)
    testlib.equal(first.mouseEnabled, true)
    testlib.equal(first.dragButton, "LeftButton")
    testlib.equal(type(first.scripts.OnDragStart), "function")
    testlib.equal(type(first.scripts.OnDragStop), "function")
    testlib.equal(harness.addon.UI.mainBackground, nil)
    testlib.equal(harness.addon.UI.shell.fallbackBackground, nil)
    testlib.equal(
        harness.addon.UI.shell.darkTexture.texture,
        "Interface\\DialogFrame\\UI-DialogBox-Background-Dark"
    )
    testlib.near(harness.addon.UI.shell.darkTexture.vertexColor[1], 0.86, 0.001)
    testlib.near(harness.addon.UI.shell.darkTexture.vertexColor[2], 0.64, 0.001)
    testlib.near(harness.addon.UI.shell.darkTexture.vertexColor[3], 0.20, 0.001)
    testlib.near(harness.addon.UI.shell.darkTexture.vertexColor[4], 0.26, 0.001)
    testlib.equal(
        harness.addon.UI.shell.goldTexture.texture,
        "Interface\\DialogFrame\\UI-DialogBox-Gold-Background"
    )
    testlib.near(harness.addon.UI.shell.goldTexture.vertexColor[1], 0.80, 0.001)
    testlib.near(harness.addon.UI.shell.goldTexture.vertexColor[2], 0.58, 0.001)
    testlib.near(harness.addon.UI.shell.goldTexture.vertexColor[3], 0.18, 0.001)
    testlib.near(harness.addon.UI.shell.goldTexture.vertexColor[4], 0.08, 0.001)
    testlib.truthy(harness.addon.UI.shell.vignette.gradient ~= nil)
    testlib.equal(harness.addon.UI.shell.vignette.layer, "BORDER")
    testlib.equal(harness.addon.UI.shell.vignette.gradient[2], 0.02)
    testlib.equal(harness.addon.UI.shell.vignette.gradient[3], 0.01)
    testlib.equal(harness.addon.UI.shell.vignette.gradient[4], 0.00)
    testlib.equal(harness.addon.UI.shell.vignette.gradient[5], 0.16)
    testlib.equal(harness.addon.UI.shell.vignette.gradient[6], 0.00)
    testlib.equal(harness.addon.UI.shell.vignette.gradient[7], 0.00)
    testlib.equal(harness.addon.UI.shell.vignette.gradient[8], 0.00)
    testlib.equal(harness.addon.UI.shell.vignette.gradient[9], 0.03)
    testlib.truthy(harness.addon.UI.shell.topGlow.color ~= nil)
    testlib.equal(harness.addon.UI.shell.topGlow.height, 44)
    testlib.equal(harness.addon.UI.shell.topGlow.color[1], 0.95)
    testlib.equal(harness.addon.UI.shell.topGlow.color[2], 0.72)
    testlib.equal(harness.addon.UI.shell.topGlow.color[3], 0.22)
    testlib.equal(harness.addon.UI.shell.topGlow.color[4], 0.14)
    testlib.equal(harness.addon.UI.shell.topGlow.layer, "BORDER")
    testlib.truthy(harness.addon.UI.shell.titleSeparator ~= nil)
    testlib.equal(harness.addon.UI.shell.titleSeparator.height, 1)
    testlib.equal(harness.addon.UI.shell.titleSeparator.point[5], -52)
    testlib.near(
        harness.addon.UI.shell.titleSeparator.color[4],
        0.22,
        0.001
    )
    testlib.equal(
        harness.addon.UITheme.Icons.TITLE,
        "Interface\\Icons\\inv_misc_pocketwatch_01"
    )
    testlib.equal(harness.addon.UI.titleRegion.height, 28)
    testlib.equal(harness.addon.UI.titleRegion.point[1], "TOPLEFT")
    testlib.equal(harness.addon.UI.titleRegion.point[2], first)
    testlib.equal(harness.addon.UI.titleRegion.point[3], "TOPLEFT")
    testlib.equal(harness.addon.UI.titleRegion.point[4], 8)
    testlib.equal(harness.addon.UI.titleRegion.point[5], -8)
    testlib.equal(harness.addon.UI.titleRegion:IsShown(), true)
    testlib.equal(harness.addon.UI.titleIconFrame.width, 28)
    testlib.equal(harness.addon.UI.titleIconFrame.height, 28)
    testlib.equal(harness.addon.UI.titleIconFrame:IsShown(), true)
    testlib.equal(harness.addon.UI.titleIcon:IsShown(), true)
    testlib.equal(harness.addon.UI.titleIconFrame.point[1], "LEFT")
    testlib.equal(harness.addon.UI.titleIconFrame.point[4], 4)
    testlib.equal(harness.addon.UI.titleIconFrame.point[5], 0)
    testlib.equal(
        harness.addon.UI.titleIconFrame.point[2],
        harness.addon.UI.titleRegion
    )
    testlib.equal(
        harness.addon.UI.titleIcon.texture,
        harness.addon.UITheme.Icons.TITLE
    )
    testlib.equal(harness.addon.UI.titleIcon.texCoord[1], 0.08)
    testlib.equal(harness.addon.UI.titleIcon.texCoord[2], 0.92)
    testlib.equal(harness.addon.UI.titleIcon.texCoord[3], 0.08)
    testlib.equal(harness.addon.UI.titleIcon.texCoord[4], 0.92)
    testlib.truthy(harness.addon.UI.titleIconBackground.color ~= nil)
    testlib.equal(#harness.addon.UI.titleIconBorder, 4)
    testlib.truthy(
        harness.addon.UI.titleIconFrame.frameLevel
            > harness.addon.UI.shell.topGlow.parent:GetFrameLevel()
    )
    testlib.equal(harness.addon.UI.title:GetText(), "Azeroth Travel Metrics")
    testlib.equal(harness.addon.UI.title.justifyH, "LEFT")
    testlib.equal(harness.addon.UI.title.points[1][1], "LEFT")
    testlib.equal(
        harness.addon.UI.title.points[1][2],
        harness.addon.UI.titleIconFrame
    )
    testlib.equal(harness.addon.UI.title.points[1][3], "RIGHT")
    testlib.near(harness.addon.UI.title.textColor[1], 1, 0.001)
    testlib.near(harness.addon.UI.title.textColor[2], 0.82, 0.001)
    testlib.near(harness.addon.UI.title.textColor[3], 0.32, 0.001)
    testlib.equal(harness.addon.UI.summaryGroups, nil)
    testlib.equal(#harness.addon.UI.summarySections, 3)
    local expectedLabels = {
        "Estimated Steps",
        "On Foot",
        "Swimming",
        "Flight Path",
        "Total Distance",
    }
    local expectedTitles = {
        "Lifetime",
        "This Session",
        "Current Level",
    }
    for sectionIndex, section in ipairs(harness.addon.UI.summarySections) do
        testlib.equal(section.title:GetText(), expectedTitles[sectionIndex])
        testlib.equal(section.title.template, "GameFontNormalSmall")
        testlib.equal(section.title.justifyH, "CENTER")
        testlib.equal(section.title.justifyV, "MIDDLE")
        testlib.equal(section.title.wordWrap, false)
        testlib.equal(section.title.nonSpaceWrap, false)
        testlib.equal(section.title.maxLines, 1)
        testlib.equal(#section.title.points, 2)
        testlib.equal(section.title.points[1][2], section.header)
        testlib.equal(section.title.points[1][4], 13)
        testlib.equal(section.title.points[2][2], section.header)
        testlib.equal(section.title.points[2][4], -13)
        testlib.equal(#section.rows, 5)
        testlib.equal(section.frame.height, 100)
        testlib.equal(section.footer, section.rows[5])
        testlib.equal(section.footer.separator.color[4], 0.95)
        testlib.equal(section.rows[1].frame.points[1][2], section.header)
        testlib.equal(section.rows[1].frame.points[1][3], "BOTTOMLEFT")
        testlib.equal(section.rows[1].frame.points[2][2], section.header)
        testlib.equal(section.rows[1].frame.points[2][3], "BOTTOMRIGHT")
        for index, label in ipairs(expectedLabels) do
            testlib.equal(section.rows[index].label:GetText(), label)
            testlib.equal(section.rows[index].value.justifyH, "RIGHT")
        end
    end
    testlib.equal(
        harness.addon.UI.summarySections[2].frame.point[1],
        "TOPLEFT"
    )
    testlib.equal(
        harness.addon.UI.summarySections[2].frame.point[2],
        harness.addon.UI.summarySections[1].frame
    )
    testlib.equal(
        harness.addon.UI.summarySections[2].frame.point[3],
        "BOTTOMLEFT"
    )
    testlib.equal(
        harness.addon.UI.summarySections[2].frame.point[5],
        -10
    )
    testlib.equal(
        harness.addon.UI.summarySections[3].frame.point[5],
        -10
    )
    testlib.equal(harness.addon.UI.overviewPanel.height, 320)
    testlib.equal(harness.addon.UI.resetButton.template, "UIPanelButtonTemplate")
    testlib.truthy(harness.addon.UI.settingsButton ~= nil)
    testlib.truthy(harness.addon.UI.closeButton.frameLevel > first:GetFrameLevel())
    testlib.truthy(harness.addon.UI.minimizeControl.frameLevel > first:GetFrameLevel())
    testlib.equal(harness.addon.UI.closeButton:IsShown(), true)
    testlib.equal(harness.addon.UI.minimizeButton:IsShown(), true)
    testlib.equal(harness.addon.UI.closeButton.width, 24)
    testlib.equal(harness.addon.UI.closeButton.height, 24)
    testlib.equal(harness.addon.UI.closeButton.point[1], "RIGHT")
    testlib.equal(
        harness.addon.UI.closeButton.point[2],
        harness.addon.UI.titleRegion
    )
    testlib.equal(harness.addon.UI.closeButton.point[5], 0)
    testlib.equal(harness.addon.UI.minimizeControl.point[1], "RIGHT")
    testlib.equal(
        harness.addon.UI.minimizeControl.point[2],
        harness.addon.UI.closeButton
    )
    testlib.equal(harness.addon.UI.minimizeControl.point[3], "LEFT")
    testlib.equal(harness.addon.UI.minimizeControl.point[5], 0)
    testlib.equal(
        harness.addon.UI.minimizeControl.template,
        "MaximizeMinimizeButtonFrameTemplate"
    )
    testlib.equal(
        harness.addon.UI.minimizeButton,
        harness.addon.UI.minimizeControl.MinimizeButton
    )
    testlib.equal(harness.addon.UI.minimizeControl.width, 24)
    testlib.equal(harness.addon.UI.minimizeControl.height, 24)
    testlib.equal(harness.addon.UI.minimizeButton.width, 24)
    testlib.equal(harness.addon.UI.minimizeButton.height, 24)
    testlib.equal(harness.addon.UI.versionLabel:GetText(), "ATM v1.0.0-beta")
    testlib.equal(harness.addon.UI.versionLabel.template, "GameFontDisableSmall")
    testlib.equal(harness.addon.UI.versionLabel.justifyH, "RIGHT")
    testlib.equal(harness.addon.UI.versionLabel.point[1], "BOTTOMRIGHT")
    testlib.equal(harness.addon.UI.shell.topGlow.points[1][4], 7)
    testlib.equal(harness.addon.UI.shell.topGlow.points[2][4], -7)
    testlib.equal(harness.addon.UI.shell.topGlow.height, 44)
    testlib.equal(harness.calls.modernMetadata, 1)
    testlib.equal(harness.calls.legacyMetadata, 0)
    testlib.equal(harness.calls.metadataAddonName, "AzerothTravelMetrics")
    testlib.equal(harness.calls.metadataField, "Version")
    testlib.equal(harness.addon.UI.contentInset, nil)
    testlib.truthy(harness.addon.UI.errorInset ~= nil)
    testlib.equal(harness.addon.UI.settingsPanel:IsShown(), false)
    testlib.equal(
        harness.addon.UI.settingsPanel.parent,
        harness.addon.UI.frame
    )
    testlib.equal(
        harness.addon.UI.overviewTab.template,
        "LargeSideTabButtonTemplate"
    )
    testlib.equal(
        harness.addon.UI.levelTab.template,
        "LargeSideTabButtonTemplate"
    )
    testlib.equal(
        harness.addon.UITheme.Icons.OVERVIEW,
        "Interface\\Icons\\inv_misc_spyglass_02"
    )
    testlib.equal(
        harness.addon.UITheme.Icons.LEVELS,
        "Interface\\Icons\\inv_misc_book_09"
    )
    testlib.equal(
        harness.addon.UI.overviewTab.Icon.texture,
        harness.addon.UITheme.Icons.OVERVIEW
    )
    testlib.equal(
        harness.addon.UI.levelTab.Icon.texture,
        harness.addon.UITheme.Icons.LEVELS
    )
    testlib.equal(harness.addon.UI.overviewTab.point[1], "TOPLEFT")
    testlib.equal(harness.addon.UI.overviewTab.point[2], first)
    testlib.equal(harness.addon.UI.overviewTab.point[3], "TOPRIGHT")
    testlib.equal(harness.addon.UI.levelTab.point[1], "TOP")
    testlib.equal(harness.addon.UI.levelTab.point[2], harness.addon.UI.overviewTab)
    testlib.equal(harness.addon.UI.levelTab.point[3], "BOTTOM")

    for _, template in ipairs(harness.calls.templates) do
        testlib.truthy(template ~= "CharacterFrameTabButtonTemplate")
        testlib.truthy(template ~= "PanelTabButtonTemplate")
        testlib.truthy(template ~= "BasicFrameTemplateWithInset")
    end

    first.scripts.OnDragStart(first)
    first.scripts.OnDragStop(first)
    testlib.equal(first.startedMoving, true)
    testlib.equal(first.stoppedMoving, true)
end)

testlib.case("ui settings gear toggles a synchronized popup", function()
    local harness = newUIHarness()
    harness.addon.UI.Create()
    local UI = harness.addon.UI

    harness.db.settings.units = "imperial"
    harness.db.settings.showMinimap = false
    harness.db.settings.showDiagnostics = true
    UI.settingsButton.scripts.OnClick()

    testlib.equal(UI.settingsPanel.parent, UI.frame)
    testlib.equal(UI.settingsPanel.template, "InsetFrameTemplate3")
    testlib.equal(UI.settingsPanel.width, 205)
    testlib.equal(UI.settingsPanel.height, 128)
    testlib.equal(UI.settingsPanel:IsShown(), true)
    testlib.equal(UI.overviewPanel:IsShown(), true)
    testlib.equal(UI.levelPanel:IsShown(), false)
    testlib.equal(UI.metricCheck:GetChecked(), false)
    testlib.equal(UI.imperialCheck:GetChecked(), true)
    testlib.equal(UI.minimapCheck:GetChecked(), false)
    testlib.equal(UI.diagnosticsCheck:GetChecked(), true)
    testlib.equal(UI.resetButton.parent, UI.frame)
    testlib.equal(UI.resetButton:GetText(), "Reset Session")
    UI.settingsButton.scripts.OnClick()
    testlib.equal(UI.settingsPanel:IsShown(), false)
end)

testlib.case("ui keeps portrait chrome with right tabs and classic center", function()
    local harness = newUIHarness()
    local frame = harness.addon.UI.Create()
    local UI = harness.addon.UI

    testlib.equal(frame.template, "PortraitFrameTemplate")
    testlib.equal(UI.closeButton, frame.CloseButton)
    testlib.equal(frame.CloseButton:IsShown(), true)
    testlib.equal(UI.minimizeButton.parent, frame)
    testlib.equal(UI.minimizeButton.template, "UIPanelHideButtonNoScripts")
    testlib.equal(UI.minimizeButton.point[1], "RIGHT")
    testlib.equal(UI.minimizeButton.point[2], frame.CloseButton)
    testlib.equal(UI.minimizeButton.point[3], "LEFT")
    testlib.truthy(UI.minimizeButton.frameLevel >= 510)
    testlib.equal(
        frame.PortraitContainer.portrait.texture,
        harness.addon.UITheme.Icons.TITLE
    )
    testlib.equal(
        frame.TitleContainer.TitleText:GetText(),
        "Azeroth Travel Metrics"
    )
    testlib.equal(harness.addon.UI.titleRegion.height, 28)
    testlib.equal(harness.addon.UI.overviewTab.point[1], "TOPLEFT")
    testlib.equal(harness.addon.UI.overviewTab.point[2], frame)
    testlib.equal(harness.addon.UI.overviewTab.point[3], "TOPRIGHT")
    testlib.equal(harness.addon.UI.levelTab.point[1], "TOP")
    testlib.equal(harness.addon.UI.levelTab.point[2], harness.addon.UI.overviewTab)
    testlib.equal(harness.addon.UI.levelTab.point[3], "BOTTOM")
    testlib.equal(UI.settingsTab, nil)
    testlib.equal(UI.parchmentPage, nil)
    testlib.equal(UI.pageArtFrame, nil)
    testlib.equal(UI.contentFrame.point[4], 16)
    testlib.equal(UI.contentFrame.point[5], -50)
    testlib.equal(UI.contentFrame.width, 388)
    testlib.equal(UI.contentFrame.height, 350)
    testlib.equal(UI.errorInset.parent, UI.errorPanel)
    testlib.equal(UI.overviewPanel.parent, frame)
    testlib.equal(UI.overviewPanel.point[4], 22)
    testlib.equal(UI.overviewPanel.point[5], -54)
    testlib.equal(UI.levelPanel.parent, frame)
    testlib.equal(UI.levelPanel.point[4], 22)
    testlib.equal(UI.levelPanel.point[5], -54)
end)

testlib.case("ui creates a safe close button when portrait chrome omits one", function()
    local harness = newUIHarness({
        portraitMissingClose = true,
    })
    local succeeded, frame = pcall(harness.addon.UI.Create)

    testlib.equal(succeeded, true)
    testlib.equal(frame.template, "PortraitFrameTemplate")
    testlib.truthy(harness.addon.UI.closeButton ~= nil)
    testlib.equal(harness.addon.UI.closeButton.template, "UIPanelCloseButton")
    testlib.equal(harness.addon.UI.closeButton.parent, frame)
    testlib.truthy(harness.addon.UI.closeButton.frameLevel >= 510)
end)

testlib.case("ui unit controls remain mutually exclusive persist and refresh", function()
    local harness = newUIHarness()
    harness.addon.UI.Create()

    testlib.equal(harness.addon.UI.metricCheck:GetChecked(), true)
    testlib.equal(harness.addon.UI.imperialCheck:GetChecked(), false)

    harness.addon.UI.imperialCheck.scripts.OnClick()
    testlib.equal(harness.db.settings.units, "imperial")
    testlib.equal(harness.addon.UI.metricCheck:GetChecked(), false)
    testlib.equal(harness.addon.UI.imperialCheck:GetChecked(), true)
    testlib.equal(harness.calls.overview, 1)

    harness.addon.UI.metricCheck.scripts.OnClick()
    testlib.equal(harness.db.settings.units, "metric")
    testlib.equal(harness.addon.UI.metricCheck:GetChecked(), true)
    testlib.equal(harness.addon.UI.imperialCheck:GetChecked(), false)
    testlib.equal(harness.calls.overview, 2)
end)

testlib.case("ui settings checkboxes persist and invoke focused updates", function()
    local harness = newUIHarness()
    harness.addon.UI.Create()

    harness.addon.UI.minimapCheck:SetChecked(false)
    harness.addon.UI.minimapCheck.scripts.OnClick()
    testlib.equal(harness.db.settings.showMinimap, false)
    testlib.equal(harness.calls.minimapVisibility, 1)
    testlib.equal(harness.calls.overview, 0)

    harness.addon.UI.diagnosticsCheck:SetChecked(false)
    harness.addon.UI.diagnosticsCheck.scripts.OnClick()
    testlib.equal(harness.db.settings.showDiagnostics, false)
    testlib.equal(harness.calls.overview, 1)
end)

testlib.case("ui falls back from BackdropTemplate to a visible bare shell", function()
    local harness = newUIHarness({
        rejectTemplates = {
            PortraitFrameTemplate = true,
            BackdropTemplate = true,
        },
    })
    local frame = harness.addon.UI.Create()

    testlib.equal(frame.template, nil)
    testlib.truthy(harness.addon.UI.shell.fallbackBackground.color ~= nil)
    testlib.equal(harness.addon.UI.shell.fallbackBackground.color[1], 0.08)
    testlib.equal(harness.addon.UI.shell.fallbackBackground.color[2], 0.06)
    testlib.equal(harness.addon.UI.shell.fallbackBackground.color[3], 0.035)
    testlib.equal(harness.addon.UI.shell.fallbackBackground.color[4], 0.95)
    testlib.equal(#harness.addon.UI.shell.fallbackBorder, 4)
    for _, edge in ipairs(harness.addon.UI.shell.fallbackBorder) do
        testlib.truthy(edge.color ~= nil)
        testlib.near(edge.color[1], 0.67, 0.001)
        testlib.near(edge.color[2], 0.53, 0.001)
        testlib.near(edge.color[3], 0.27, 0.001)
        testlib.near(edge.color[4], 0.96, 0.001)
    end
    testlib.truthy(harness.addon.UI.closeButton ~= nil)
end)

testlib.case("ui fallback owns title icon text and controls without native chrome", function()
    local harness = newUIHarness({
        rejectTemplates = {
            PortraitFrameTemplate = true,
        },
    })
    local frame = harness.addon.UI.Create()

    testlib.equal(frame.TitleText, nil)
    testlib.equal(frame.PortraitContainer, nil)
    testlib.truthy(harness.addon.UI.titleRegion ~= nil)
    testlib.truthy(harness.addon.UI.titleIconFrame ~= nil)
    testlib.truthy(harness.addon.UI.closeButton ~= nil)
    testlib.truthy(harness.addon.UI.minimizeButton ~= nil)
    testlib.equal(harness.addon.UI.title:GetText(), "Azeroth Travel Metrics")
end)

testlib.case("ui remains visible when all shell side-tab and atlas assets fail", function()
    local noTemplate = newUIHarness({
        rejectTemplates = {
            PortraitFrameTemplate = true,
            BackdropTemplate = true,
            LargeSideTabButtonTemplate = true,
            MaximizeMinimizeButtonFrameTemplate = true,
        },
        rejectAtlases = {
            ["common-insideframe"] = true,
        },
    })
    local succeeded, templateFrame = pcall(noTemplate.addon.UI.Create)
    testlib.equal(succeeded, true)
    testlib.equal(templateFrame.template, nil)
    testlib.truthy(noTemplate.addon.UI.closeButton ~= nil)
    testlib.equal(noTemplate.addon.UI.overviewTab.template, nil)
    testlib.equal(noTemplate.addon.UI.levelTab.template, nil)
    testlib.equal(noTemplate.addon.UI.overviewTab:IsShown(), true)
    testlib.equal(noTemplate.addon.UI.levelTab:IsShown(), true)
    testlib.equal(noTemplate.addon.UI.contentInset, nil)
    testlib.truthy(noTemplate.addon.UI.errorInset.color ~= nil)
    testlib.truthy(noTemplate.addon.UI.settingsButton.Icon.texture ~= nil)
    testlib.equal(
        noTemplate.addon.UI.resetButton:GetText(),
        "Reset Session"
    )
    testlib.equal(noTemplate.addon.UI.summarySections[1].title:GetText(), "Lifetime")
    testlib.equal(
        noTemplate.addon.UI.summarySections[1].rows[1].label:GetText(),
        "Estimated Steps"
    )
    testlib.equal(noTemplate.addon.UI.title:GetText(), "Azeroth Travel Metrics")
    testlib.truthy(noTemplate.addon.UI.shell.fallbackBackground.color ~= nil)
    testlib.equal(#noTemplate.addon.UI.shell.fallbackBorder, 4)
end)

testlib.case("ui version footer trims metadata and falls back safely", function()
    local metadata = newUIHarness({
        metadataValue = "  2.4.6-rc1  ",
    })
    metadata.addon.UI.Create()
    testlib.equal(metadata.addon.UI.versionLabel:GetText(), "ATM v2.4.6-rc1")
    testlib.equal(metadata.calls.modernMetadata, 1)
    testlib.equal(metadata.calls.legacyMetadata, 0)

    local legacy = newUIHarness({
        legacyMetadataOnly = true,
        legacyMetadataValue = "  3.5.7  ",
    })
    legacy.addon.UI.Create()
    testlib.equal(legacy.addon.UI.versionLabel:GetText(), "ATM v3.5.7")
    testlib.equal(legacy.calls.modernMetadata, 0)
    testlib.equal(legacy.calls.legacyMetadata, 1)

    local fallbackCases = {
        {
            metadataReturnsNil = true,
        },
        {
            metadataValue = "   ",
        },
        {
            metadataThrows = true,
        },
        {
            legacyMetadataOnly = true,
            legacyMetadataThrows = true,
        },
    }
    for _, options in ipairs(fallbackCases) do
        local harness = newUIHarness(options)
        local succeeded = pcall(harness.addon.UI.Create)
        testlib.equal(succeeded, true)
        testlib.equal(
            harness.addon.UI.versionLabel:GetText(),
            "ATM v" .. harness.addon.VERSION_FALLBACK
        )
        testlib.equal(harness.addon.UI.errorText:IsShown(), false)
    end
end)

testlib.case("ui shell stays visible when backdrop or gradient APIs fail", function()
    local noBackdrop = newUIHarness({
        rejectBackdrop = true,
        rejectTemplates = { PortraitFrameTemplate = true },
    })
    noBackdrop.addon.UI.Create()
    testlib.truthy(noBackdrop.addon.UI.shell.fallbackBackground.color ~= nil)
    testlib.equal(#noBackdrop.addon.UI.shell.fallbackBorder, 4)

    local noBackdropColor = newUIHarness({
        rejectBackdropColor = true,
        rejectTemplates = { PortraitFrameTemplate = true },
    })
    noBackdropColor.addon.UI.Create()
    testlib.truthy(
        noBackdropColor.addon.UI.shell.fallbackBackground.color ~= nil
    )
    testlib.equal(#noBackdropColor.addon.UI.shell.fallbackBorder, 4)

    local rejectedBackdrop = newUIHarness({
        rejectBackdropReturn = true,
        rejectTemplates = { PortraitFrameTemplate = true },
    })
    rejectedBackdrop.addon.UI.Create()
    testlib.truthy(
        rejectedBackdrop.addon.UI.shell.fallbackBackground.color ~= nil
    )

    local rejectedBackdropColor = newUIHarness({
        rejectBackdropColorReturn = true,
        rejectTemplates = { PortraitFrameTemplate = true },
    })
    rejectedBackdropColor.addon.UI.Create()
    testlib.truthy(
        rejectedBackdropColor.addon.UI.shell.fallbackBackground.color ~= nil
    )

    local noGradient = newUIHarness({
        rejectGradients = true,
        rejectTemplates = { PortraitFrameTemplate = true },
    })
    noGradient.addon.UI.Create()
    testlib.equal(noGradient.addon.UI.shell.vignette.gradient, nil)
    testlib.truthy(noGradient.addon.UI.shell.vignette.color ~= nil)
    testlib.near(noGradient.addon.UI.shell.vignette.color[4], 0.16, 0.001)

    local missingGradient = newUIHarness({
        missingGradientAPI = true,
        rejectTemplates = { PortraitFrameTemplate = true },
    })
    missingGradient.addon.UI.Create()
    testlib.equal(missingGradient.addon.UI.shell.vignette.gradient, nil)
    testlib.truthy(missingGradient.addon.UI.shell.vignette.color ~= nil)

    local rejectedGradient = newUIHarness({
        rejectGradientReturn = true,
        rejectTemplates = { PortraitFrameTemplate = true },
    })
    rejectedGradient.addon.UI.Create()
    testlib.truthy(rejectedGradient.addon.UI.shell.vignette.color ~= nil)
end)

testlib.case("ui registers the regular frame once for Escape handling", function()
    local harness = newUIHarness()

    harness.addon.UI.Create()
    harness.addon.UI.Create()

    testlib.equal(#harness.environment.UISpecialFrames, 1)
    testlib.equal(
        harness.environment.UISpecialFrames[1],
        "AzerothTravelMetricsFrame"
    )
end)

testlib.case("ui does not duplicate an existing Escape registration", function()
    local harness = newUIHarness({
        uispecialframes = {
            "OtherFrame",
            "AzerothTravelMetricsFrame",
        },
    })

    harness.addon.UI.Create()

    testlib.equal(#harness.environment.UISpecialFrames, 2)
    testlib.equal(
        harness.environment.UISpecialFrames[2],
        "AzerothTravelMetricsFrame"
    )
end)

testlib.case("ui finds an existing Escape registration after sparse entries", function()
    local specialFrames = {
        [1] = "OtherFrame",
        [3] = "AzerothTravelMetricsFrame",
    }
    local harness = newUIHarness({
        uispecialframes = specialFrames,
    })

    harness.addon.UI.Create()

    local registrations = 0
    for _, frameName in pairs(harness.environment.UISpecialFrames) do
        if frameName == "AzerothTravelMetricsFrame" then
            registrations = registrations + 1
        end
    end
    testlib.equal(registrations, 1)
end)

testlib.case("ui safely ignores missing or malformed Escape globals", function()
    for _, value in ipairs({ false, "not-a-table", 17 }) do
        local harness = newUIHarness({
            uispecialframes = value,
        })
        local succeeded = pcall(harness.addon.UI.Create)
        testlib.equal(succeeded, true)
    end
end)

testlib.case("ui selects only safe non-fullscreen strata for main and HUD", function()
    local cases = {
        {
            rejected = {},
            expected = "MEDIUM",
            attempts = { "MEDIUM" },
        },
        {
            rejected = {
                MEDIUM = true,
            },
            expected = "HIGH",
            attempts = { "MEDIUM", "HIGH" },
        },
        {
            rejected = {
                MEDIUM = true,
                HIGH = true,
            },
            expected = "DIALOG",
            attempts = { "MEDIUM", "HIGH", "DIALOG" },
        },
        {
            rejected = {
                MEDIUM = true,
                HIGH = true,
                DIALOG = true,
            },
            expected = nil,
            attempts = { "MEDIUM", "HIGH", "DIALOG" },
        },
    }

    for _, case in ipairs(cases) do
        local harness = newUIHarness({
            rejectStrata = case.rejected,
        })
        local frame = harness.addon.UI.Create()
        testlib.equal(frame.strata, case.expected)
        testlib.equal(#harness.strataAttempts, #case.attempts)
        for index, expectedStrata in ipairs(case.attempts) do
            testlib.equal(harness.strataAttempts[index], expectedStrata)
        end
        for _, strata in ipairs(harness.strataAttempts) do
            testlib.truthy(strata ~= "FULLSCREEN")
            testlib.truthy(strata ~= "FULLSCREEN_DIALOG")
        end

        harness.addon.UI.Minimize()
        testlib.equal(harness.addon.UI.hud.frame.strata, case.expected)
        testlib.equal(harness.addon.UI.hud.frame:GetFrameLevel(), 100)
        testlib.equal(#harness.calls.hudStrataAttempts, #case.attempts)
        for index, expectedStrata in ipairs(case.attempts) do
            testlib.equal(
                harness.calls.hudStrataAttempts[index],
                expectedStrata
            )
        end
        for _, strata in ipairs(harness.calls.hudStrataAttempts) do
            testlib.truthy(strata ~= "FULLSCREEN")
            testlib.truthy(strata ~= "FULLSCREEN_DIALOG")
        end
    end
end)

testlib.case("ui native tabs switch panels and selected visual state", function()
    local harness = newUIHarness()
    harness.addon.UI.Create()

    testlib.equal(harness.addon.UI.overviewPanel:IsShown(), true)
    testlib.equal(harness.addon.UI.levelPanel:IsShown(), false)
    testlib.equal(harness.addon.UI.overviewTab.selected, true)
    testlib.equal(harness.addon.UI.levelTab.selected, false)

    harness.addon.UI.levelTab.scripts.OnClick()
    testlib.equal(harness.addon.UI.overviewPanel:IsShown(), false)
    testlib.equal(harness.addon.UI.levelPanel:IsShown(), true)
    testlib.equal(harness.addon.UI.overviewTab.selected, false)
    testlib.equal(harness.addon.UI.levelTab.selected, true)
    testlib.equal(harness.addon.UI.levelTab.SelectedTexture:IsShown(), true)

    harness.addon.UI.overviewTab.scripts.OnClick()
    testlib.equal(harness.addon.UI.overviewPanel:IsShown(), true)
    testlib.equal(harness.addon.UI.levelPanel:IsShown(), false)
    testlib.equal(harness.addon.UI.overviewTab.selected, true)
    testlib.equal(harness.addon.UI.levelTab.selected, false)
    testlib.equal(harness.addon.UI.overviewTab.SelectedTexture:IsShown(), true)

end)

testlib.case("ui side tabs fall back safely when native template is unavailable", function()
    local safeFallback = newUIHarness({
        rejectTemplates = {
            LargeSideTabButtonTemplate = true,
        },
    })
    local succeeded = pcall(safeFallback.addon.UI.Create)
    testlib.equal(succeeded, true)
    testlib.equal(safeFallback.addon.UI.overviewTab.template, nil)
    testlib.equal(safeFallback.addon.UI.levelTab.template, nil)
    testlib.equal(safeFallback.addon.UI.overviewTab.selected, true)
    testlib.equal(safeFallback.addon.UI.overviewTab.SelectedTexture.shown, true)
end)

testlib.case("ui action buttons remain visible and interactive without panel templates", function()
    local harness = newUIHarness({
        rejectTemplates = {
            PortraitFrameTemplate = true,
            BackdropTemplate = true,
            UIPanelButtonTemplate = true,
            UIPanelCloseButton = true,
            MaximizeMinimizeButtonFrameTemplate = true,
        },
    })
    local UI = harness.addon.UI
    local succeeded, frame = pcall(UI.Create)

    testlib.equal(succeeded, true)
    testlib.truthy(frame ~= nil)
    testlib.equal(UI.resetButton.template, nil)
    testlib.equal(UI.resetButton.width, 96)
    testlib.equal(UI.resetButton.height, 22)
    testlib.equal(UI.resetButton:IsShown(), true)
    testlib.equal(UI.resetButton:GetText(), "Reset Session")
    testlib.truthy(UI.resetButton.Background.color ~= nil)
    testlib.truthy(#UI.resetButton.Border == 4)
    testlib.truthy(UI.resetButton.Highlight.color ~= nil)

    testlib.equal(UI.closeButton.template, nil)
    testlib.equal(UI.closeButton.width, 24)
    testlib.equal(UI.closeButton.height, 24)
    testlib.equal(UI.closeButton:IsShown(), true)
    testlib.equal(UI.closeButton.FallbackText:GetText(), "x")
    testlib.truthy(UI.closeButton.Background.color ~= nil)
    testlib.truthy(#UI.closeButton.Border == 4)
    testlib.truthy(UI.closeButton.Highlight.color ~= nil)

    UI.ShowMain()
    UI.closeButton.scripts.OnClick()
    testlib.equal(frame:IsShown(), false)

    UI.resetButton.scripts.OnClick()
    testlib.equal(
        harness.environment.shownPopup,
        "AZEROTH_TRAVEL_METRICS_RESET_SESSION"
    )

    UI.Minimize()
    testlib.truthy(UI.hud.frame ~= nil)
    testlib.equal(UI.hud.restoreButton.template, nil)
    testlib.equal(UI.hud.restoreButton.controlKind, "restore")
    testlib.equal(UI.hud.restoreButton.width, 20)
    testlib.equal(UI.hud.restoreButton.height, 20)
    testlib.equal(UI.hud.restoreButton:GetText(), nil)
    testlib.truthy(UI.hud.restoreButton.Background.color ~= nil)
    testlib.truthy(UI.hud.restoreButton.HighlightTexture.color ~= nil)
    testlib.equal(#UI.hud.restoreButton.GlyphTextures, 3)

    testlib.equal(UI.hud.closeButton.template, nil)
    testlib.equal(UI.hud.closeButton.width, 20)
    testlib.equal(UI.hud.closeButton.height, 20)
    testlib.equal(UI.hud.closeButton.FallbackText:GetText(), "x")
    testlib.truthy(UI.hud.closeButton.Background.color ~= nil)
    testlib.truthy(#UI.hud.closeButton.Border == 4)
    testlib.truthy(UI.hud.closeButton.Highlight.color ~= nil)
    testlib.truthy(
        UI.hud.restoreButton.frameLevel > UI.hud.frame:GetFrameLevel()
    )
    testlib.truthy(
        UI.hud.closeButton.frameLevel > UI.hud.frame:GetFrameLevel()
    )
    testlib.equal(UI.hud.restoreButton.point[1], "RIGHT")
    testlib.equal(UI.hud.restoreButton.point[2], UI.hud.closeButton)
    testlib.equal(UI.hud.restoreButton.point[3], "LEFT")
    testlib.equal(UI.hud.restoreButton.point[4], -2)
    testlib.equal(UI.hud.restoreButton.point[5], 0)
    testlib.equal(UI.hud.closeButton.point[5], -2)
    testlib.truthy(UI.hud.cells[1].point[5] <= -29)

    UI.hud.frame.scripts.OnEnter()
    testlib.equal(UI.hud.restoreButton:IsShown(), true)
    testlib.equal(UI.hud.closeButton:IsShown(), true)

    UI.hud.restoreButton.scripts.OnClick()
    testlib.equal(UI.hud.frame:IsShown(), false)
    testlib.equal(frame:IsShown(), true)

    UI.Minimize()
    UI.hud.closeButton.scripts.OnClick()
    testlib.equal(UI.hud.frame:IsShown(), false)
    testlib.equal(UI.IsShown(), false)
end)

testlib.case("ui regular close hides only the window and reopens without state mutation", function()
    local tracker = {
        previous = {
            x = 17,
            y = 23,
        },
        acceptedSegments = 9,
    }
    local character = {
        identity = {
            name = "Traveler",
            realm = "TestRealm",
            firstSeenAt = 1000,
        },
        lifetime = {
            onFoot = 111,
            swimming = 222,
            taxi = 333,
        },
        session = {
            startedAt = 2000,
            onFoot = 11,
            swimming = 22,
            taxi = 33,
        },
        levels = {
            [42] = {
                onFoot = 44,
                swimming = 55,
                taxi = 66,
                reachedAt = 3000,
            },
        },
        diagnostics = {
            samples = 77,
        },
    }
    local overview = {
        lifetime = {
            steps = "111",
            onFoot = "1.11 km",
            swimming = "2.22 km",
            taxi = "3.33 km",
            total = "6.66 km",
        },
        session = {
            steps = "11",
            onFoot = "110 m",
            swimming = "220 m",
            taxi = "330 m",
            total = "660 m",
        },
        currentLevel = {
            steps = "44",
            onFoot = "440 m",
            swimming = "550 m",
            taxi = "660 m",
            total = "1.65 km",
        },
    }
    local levelRows = {
        {
            level = 42,
            steps = "44",
            onFoot = "440 m",
            swimming = "550 m",
            taxi = "660 m",
            total = "1.65 km",
        },
    }
    local harness = newUIHarness({
        tracker = tracker,
        character = character,
        overview = overview,
        levelRows = levelRows,
    })
    local UI = harness.addon.UI
    local frame = UI.Create()
    testlib.equal(harness.calls.uiInitialize, 1)
    local db = harness.db
    local settings = db.settings
    local lifetime = character.lifetime
    local session = character.session
    local levels = character.levels
    local currentLevel = levels[42]
    local diagnostics = character.diagnostics
    local previous = tracker.previous
    local runtimeTracker = harness.tracker
    local expectedSummaryValues = {
        { "111", "1.11 km", "2.22 km", "3.33 km", "6.66 km" },
        { "11", "110 m", "220 m", "330 m", "660 m" },
        { "44", "440 m", "550 m", "660 m", "1.65 km" },
    }

    local function assertVisibleValues()
        for sectionIndex, expectedValues in ipairs(expectedSummaryValues) do
            local section = UI.summarySections[sectionIndex]
            for rowIndex, expectedValue in ipairs(expectedValues) do
                testlib.equal(
                    section.rows[rowIndex].value:GetText(),
                    expectedValue
                )
            end
        end
        for rowIndex, expectedValue in ipairs(expectedSummaryValues[3]) do
            testlib.equal(
                UI.levelRows[1].rows[rowIndex].value:GetText(),
                expectedValue
            )
        end
    end

    local function assertRefreshUsedOriginalValues(callIndex)
        local overviewArguments = harness.calls.overviewArguments[callIndex]
        local rowArguments = harness.calls.rowArguments[callIndex]
        local diagnosticArguments = harness.calls.diagnosticArguments[callIndex]

        testlib.equal(overviewArguments.character, character)
        testlib.equal(rowArguments.character, character)
        testlib.equal(diagnosticArguments.character, character)

        local function assertCharacterValues(receivedCharacter)
            testlib.equal(receivedCharacter, character)
            testlib.equal(receivedCharacter.lifetime, lifetime)
            testlib.equal(receivedCharacter.session, session)
            testlib.equal(receivedCharacter.levels, levels)
            testlib.equal(receivedCharacter.levels[42], currentLevel)
            testlib.equal(receivedCharacter.lifetime.onFoot, 111)
            testlib.equal(receivedCharacter.lifetime.swimming, 222)
            testlib.equal(receivedCharacter.lifetime.taxi, 333)
            testlib.equal(receivedCharacter.session.startedAt, 2000)
            testlib.equal(receivedCharacter.session.onFoot, 11)
            testlib.equal(receivedCharacter.session.swimming, 22)
            testlib.equal(receivedCharacter.session.taxi, 33)
            testlib.equal(receivedCharacter.levels[42].onFoot, 44)
            testlib.equal(receivedCharacter.levels[42].swimming, 55)
            testlib.equal(receivedCharacter.levels[42].taxi, 66)
            testlib.equal(receivedCharacter.levels[42].reachedAt, 3000)
        end

        assertCharacterValues(overviewArguments.character)
        assertCharacterValues(rowArguments.character)
        assertCharacterValues(diagnosticArguments.character)
        testlib.equal(overviewArguments.currentLevel, 42)
        testlib.equal(overviewArguments.units, "metric")
        testlib.equal(rowArguments.units, "metric")
        testlib.equal(diagnosticArguments.enabled, true)
    end

    UI.ShowMain()
    assertRefreshUsedOriginalValues(1)
    assertVisibleValues()
    UI.closeButton.scripts.OnClick()

    testlib.equal(frame:IsShown(), false)
    testlib.equal(UI.hud, nil)
    testlib.equal(UI.IsShown(), false)
    testlib.equal(harness.db, db)
    testlib.equal(harness.db.settings, settings)
    testlib.equal(runtimeTracker, tracker)
    testlib.equal(harness.tracker, runtimeTracker)
    testlib.equal(harness.character, character)
    testlib.equal(harness.character.lifetime, lifetime)
    testlib.equal(harness.character.session, session)
    testlib.equal(harness.character.levels, levels)
    testlib.equal(harness.character.levels[42], currentLevel)
    testlib.equal(harness.character.diagnostics, diagnostics)
    testlib.equal(lifetime.onFoot, 111)
    testlib.equal(lifetime.swimming, 222)
    testlib.equal(lifetime.taxi, 333)
    testlib.equal(session.startedAt, 2000)
    testlib.equal(session.onFoot, 11)
    testlib.equal(session.swimming, 22)
    testlib.equal(session.taxi, 33)
    testlib.equal(currentLevel.onFoot, 44)
    testlib.equal(currentLevel.swimming, 55)
    testlib.equal(currentLevel.taxi, 66)
    testlib.equal(currentLevel.reachedAt, 3000)
    testlib.equal(harness.tracker.previous, previous)
    testlib.equal(harness.tracker.acceptedSegments, 9)
    testlib.equal(harness.calls.reset, 0)
    testlib.equal(harness.calls.baselineReset, 0)

    UI.ShowMain()
    testlib.equal(harness.calls.uiInitialize, 1)
    testlib.equal(frame:IsShown(), true)
    testlib.equal(UI.IsShown(), true)
    testlib.equal(harness.tracker, runtimeTracker)
    testlib.equal(harness.character, character)
    testlib.equal(harness.character.lifetime, lifetime)
    testlib.equal(harness.character.session, session)
    testlib.equal(harness.character.levels, levels)
    testlib.equal(harness.character.levels[42], currentLevel)
    testlib.equal(harness.character.diagnostics, diagnostics)
    testlib.equal(harness.tracker.previous, previous)
    testlib.equal(harness.tracker.acceptedSegments, 9)
    testlib.equal(harness.calls.reset, 0)
    testlib.equal(harness.calls.baselineReset, 0)
    assertRefreshUsedOriginalValues(2)
    assertVisibleValues()

    UI.ConfirmResetSession()
    local dialog = harness.environment.StaticPopupDialogs[
        "AZEROTH_TRAVEL_METRICS_RESET_SESSION"
    ]
    dialog.OnAccept()

    testlib.equal(harness.calls.baselineReset, 1)
    testlib.equal(harness.calls.baselineResetReceivers[1], tracker)
end)

testlib.case("ui minimize restore close and toggle coordinate both surfaces", function()
    local harness = newUIHarness()
    local UI = harness.addon.UI
    UI.Create()

    UI.ShowMain()
    testlib.equal(UI.frame:IsShown(), true)
    testlib.equal(UI.hud, nil)

    UI.minimizeButton.scripts.OnClick()
    testlib.equal(UI.frame:IsShown(), false)
    testlib.equal(UI.hud.frame:IsShown(), true)
    testlib.equal(UI.hud.frame.width, 220)
    testlib.equal(UI.hud.frame.height, 96)
    testlib.equal(UI.hud.frame.movable, true)
    testlib.equal(UI.hud.frame.dragButton, "LeftButton")
    testlib.equal(#UI.hud.cells, 4)
    testlib.equal(UI.hud.title:GetText(), "Session")
    testlib.equal(
        UI.hud.restoreControl.template,
        "MaximizeMinimizeButtonFrameTemplate"
    )
    testlib.equal(UI.hud.restoreButton, UI.hud.restoreControl.MaximizeButton)
    testlib.equal(UI.hud.restoreButton.width, 20)
    testlib.equal(UI.hud.restoreButton.height, 20)
    testlib.equal(UI.hud.restoreButton:GetText(), nil)
    testlib.equal(UI.hud.restoreControl.point[1], "RIGHT")
    testlib.equal(UI.hud.restoreControl.point[2], UI.hud.closeButton)
    testlib.equal(UI.hud.restoreControl.point[3], "LEFT")
    testlib.truthy(UI.hud.restoreControl.frameLevel > UI.hud.frame:GetFrameLevel())
    testlib.truthy(UI.hud.closeButton.frameLevel > UI.hud.frame:GetFrameLevel())
    testlib.truthy(UI.hud.cells[1].point[5] <= -29)
    testlib.truthy(UI.hud.cells[1].icon)
    testlib.equal(
        UI.hud.cells[1].icon.texture,
        "Interface\\Icons\\inv_misc_pocketwatch_01"
    )
    testlib.truthy(UI.hud.cells[2].icon)
    testlib.equal(
        UI.hud.cells[2].icon.texture,
        "Interface\\Icons\\INV_Boots_05"
    )
    testlib.truthy(UI.hud.cells[3].icon)
    testlib.equal(
        UI.hud.cells[3].icon.texture,
        "Interface\\Icons\\Ability_Druid_AquaticForm"
    )
    testlib.truthy(UI.hud.cells[4].icon)
    testlib.equal(
        UI.hud.cells[4].icon.texture,
        "Interface\\Icons\\Ability_Mount_Wyvern_01"
    )
    testlib.equal(UI.IsShown(), true)

    UI.hud.restoreButton.scripts.OnClick()
    testlib.equal(UI.hud.frame:IsShown(), false)
    testlib.equal(UI.frame:IsShown(), true)

    UI.Minimize()
    UI.hud.closeButton.scripts.OnClick()
    testlib.equal(UI.hud.frame:IsShown(), false)
    testlib.equal(UI.IsShown(), false)

    UI.ShowMain()
    UI.Toggle()
    testlib.equal(UI.frame:IsShown(), false)
    testlib.equal(UI.hud.frame:IsShown(), false)
    UI.Toggle()
    testlib.equal(UI.frame:IsShown(), true)
    testlib.equal(UI.hud.frame:IsShown(), false)
end)

testlib.case("ui HUD hover reveals controls and refreshes current session values", function()
    local harness = newUIHarness({
        overview = {
            lifetime = {
                steps = "1",
                onFoot = "1 m",
                swimming = "2 m",
                taxi = "3 m",
            },
            session = {
                steps = "12.5K",
                onFoot = "100 m",
                swimming = "200 m",
                taxi = "300 m",
            },
            currentLevel = {
                steps = "4",
                onFoot = "4 m",
                swimming = "5 m",
                taxi = "6 m",
            },
        },
    })
    local UI = harness.addon.UI
    UI.Minimize()

    testlib.equal(UI.hud.frame:GetAlpha(), 0.45)
    testlib.equal(UI.hud.restoreControl:IsShown(), false)
    testlib.equal(UI.hud.restoreButton:IsShown(), false)
    testlib.equal(UI.hud.closeButton:IsShown(), false)
    testlib.equal(UI.hud.cells[1].value:GetText(), "12.5K")
    testlib.equal(UI.hud.cells[2].value:GetText(), "100 m")
    testlib.equal(UI.hud.cells[3].value:GetText(), "200 m")
    testlib.equal(UI.hud.cells[4].value:GetText(), "300 m")

    UI.hud.frame.scripts.OnEnter()
    testlib.truthy(UI.hud.frame:GetAlpha() > 0.45)
    testlib.equal(UI.hud.restoreControl:IsShown(), true)
    testlib.equal(UI.hud.restoreButton:IsShown(), true)
    testlib.equal(UI.hud.closeButton:IsShown(), true)

    UI.hud.restoreButton.mouseOver = true
    UI.hud.frame.scripts.OnLeave()
    testlib.truthy(UI.hud.frame:GetAlpha() > 0.45)
    testlib.equal(UI.hud.restoreButton:IsShown(), true)
    UI.hud.restoreButton.mouseOver = false

    UI.hud.closeButton.mouseOver = true
    UI.hud.frame.scripts.OnLeave()
    testlib.truthy(UI.hud.frame:GetAlpha() > 0.45)
    testlib.equal(UI.hud.restoreButton:IsShown(), true)
    testlib.equal(UI.hud.closeButton:IsShown(), true)
    UI.hud.closeButton.mouseOver = false

    UI.hud.frame.scripts.OnLeave()
    testlib.equal(UI.hud.frame:GetAlpha(), 0.45)
    testlib.equal(UI.hud.restoreControl:IsShown(), false)
    testlib.equal(UI.hud.restoreButton:IsShown(), false)
    testlib.equal(UI.hud.closeButton:IsShown(), false)
end)

testlib.case("ui HUD restore hover preserves tooltip scripts with HookScript", function()
    local harness = newUIHarness()
    local UI = harness.addon.UI
    UI.Minimize()

    UI.hud.restoreButton.scripts.OnEnter(UI.hud.restoreButton)
    testlib.equal(UI.hud.restoreButton:IsShown(), true)
    testlib.equal(UI.hud.closeButton:IsShown(), true)
    testlib.equal(harness.calls.tooltipOwner, UI.hud.restoreButton)
    testlib.equal(harness.calls.tooltipText, "Restore")
    testlib.equal(harness.calls.tooltipShown, true)

    UI.hud.restoreButton.mouseOver = false
    UI.hud.restoreButton.scripts.OnLeave(UI.hud.restoreButton)
    testlib.equal(UI.hud.restoreButton:IsShown(), false)
    testlib.equal(UI.hud.closeButton:IsShown(), false)
    testlib.equal(harness.calls.tooltipHidden, true)
end)

testlib.case("ui HUD restore hover composes tooltip scripts without HookScript", function()
    local harness = newUIHarness({
        missingHookScript = true,
    })
    local UI = harness.addon.UI
    UI.Minimize()

    UI.hud.restoreButton.scripts.OnEnter(UI.hud.restoreButton)
    testlib.equal(UI.hud.restoreButton:IsShown(), true)
    testlib.equal(UI.hud.closeButton:IsShown(), true)
    testlib.equal(harness.calls.tooltipOwner, UI.hud.restoreButton)
    testlib.equal(harness.calls.tooltipText, "Restore")
    testlib.equal(harness.calls.tooltipShown, true)

    UI.hud.restoreButton.mouseOver = false
    UI.hud.restoreButton.scripts.OnLeave(UI.hud.restoreButton)
    testlib.equal(UI.hud.restoreButton:IsShown(), false)
    testlib.equal(UI.hud.closeButton:IsShown(), false)
    testlib.equal(harness.calls.tooltipHidden, true)
end)

testlib.case("ui HUD resets hover state after restore and minimize", function()
    local harness = newUIHarness()
    local UI = harness.addon.UI
    UI.Minimize()

    UI.hud.frame.scripts.OnEnter()
    UI.hud.restoreButton.scripts.OnClick()
    UI.Minimize()

    testlib.equal(UI.hud.frame:GetAlpha(), 0.45)
    testlib.equal(UI.hud.restoreButton:IsShown(), false)
    testlib.equal(UI.hud.closeButton:IsShown(), false)
end)

testlib.case("ui HUD resets hover state after close and minimize", function()
    local harness = newUIHarness()
    local UI = harness.addon.UI
    UI.Minimize()

    UI.hud.frame.scripts.OnEnter()
    UI.hud.closeButton.scripts.OnClick()
    UI.Minimize()

    testlib.equal(UI.hud.frame:GetAlpha(), 0.45)
    testlib.equal(UI.hud.restoreButton:IsShown(), false)
    testlib.equal(UI.hud.closeButton:IsShown(), false)
end)

testlib.case("ui HUD persists valid drag positions and ignores malformed points", function()
    local harness = newUIHarness()
    local UI = harness.addon.UI
    UI.Minimize()

    UI.hud.frame:SetPoint("TOPLEFT", harness.environment.UIParent, "TOPLEFT", 25, -35)
    UI.hud.frame.scripts.OnDragStop(UI.hud.frame)
    testlib.equal(harness.db.settings.hudPoint, "TOPLEFT")
    testlib.equal(harness.db.settings.hudX, 25)
    testlib.equal(harness.db.settings.hudY, -35)

    UI.hud.frame.malformedPoint = {
        "SIDEWAYS",
        harness.environment.UIParent,
        "TOPLEFT",
        "bad",
        math.huge,
    }
    UI.hud.frame.scripts.OnDragStop(UI.hud.frame)
    testlib.equal(harness.db.settings.hudPoint, "TOPLEFT")
    testlib.equal(harness.db.settings.hudX, 25)
    testlib.equal(harness.db.settings.hudY, -35)
end)

testlib.case("ui refresh consumes overview levels and diagnostics models", function()
    local harness = newUIHarness()
    harness.addon.UI.Create()

    local succeeded = pcall(harness.addon.UI.Refresh)

    testlib.equal(succeeded, true)
    testlib.equal(harness.calls.overview, 1)
    testlib.equal(harness.calls.rows, 1)
    testlib.equal(harness.calls.diagnostics, 1)
    local UI = harness.addon.UI
    testlib.equal(UI.summarySections[1].rows[1].value:GetText(), "12.5K")
    testlib.equal(UI.summarySections[1].rows[2].value:GetText(), "1.00 km")
    testlib.equal(UI.summarySections[1].rows[3].value:GetText(), "2.00 km")
    testlib.equal(UI.summarySections[1].rows[4].value:GetText(), "3.00 km")
    testlib.equal(UI.summarySections[1].rows[5].value:GetText(), "3.53 km")
    testlib.equal(UI.summarySections[2].rows[1].value:GetText(), "10")
    testlib.equal(UI.summarySections[2].rows[2].value:GetText(), "100 m")
    testlib.equal(UI.summarySections[3].rows[4].value:GetText(), "70 m")
    testlib.equal(UI.levelRows[1].title:GetText(), "Level 42")
    testlib.equal(UI.levelRows[1].rows[1].value:GetText(), "12.5K")
    testlib.equal(UI.levelRows[1].rows[2].value:GetText(), "50 m")
    testlib.equal(UI.levelRows[1].rows[3].value:GetText(), "60 m")
    testlib.equal(UI.levelRows[1].rows[4].value:GetText(), "70 m")
    testlib.equal(UI.levelRows[1].rows[5].value:GetText(), "603 yd")
    testlib.equal(UI.levelRows[1].frame.height, 104)
    testlib.equal(UI.levelRows[1].footer, UI.levelRows[1].rows[5])
    testlib.equal(UI.levelRows[1].footer.separator.color[4], 0.95)
    testlib.equal(UI.levelRows[2].title:GetText(), "Level 41")
    testlib.equal(UI.levelRows[2].frame.point[5], -114)
    local expectedLabels = {
        "Estimated Steps",
        "On Foot",
        "Swimming",
        "Flight Path",
        "Total Distance",
    }
    for index, label in ipairs(expectedLabels) do
        testlib.equal(UI.levelRows[1].rows[index].label:GetText(), label)
    end
    testlib.equal(UI.levelHeader:GetText(), "Travel by Level")
    testlib.equal(contains(UI.levelRows[1].title:GetText(), "|"), false)
    testlib.equal(contains(UI.levelHeader:GetText(), "|"), false)
    testlib.truthy(contains(harness.addon.UI.diagnosticsText:GetText(), "alpha: 2"))
    testlib.equal(harness.addon.UI.diagnosticsText:IsShown(), true)
    testlib.equal(harness.addon.UI.errorText:IsShown(), false)
end)

testlib.case("ui level cards use exact gaps without trailing space", function()
    local harness = newUIHarness({
        levelRows = {
            {
                level = 3,
                steps = "3",
                onFoot = "3 m",
                swimming = "0 m",
                taxi = "0 m",
            },
            {
                level = 2,
                steps = "2",
                onFoot = "2 m",
                swimming = "0 m",
                taxi = "0 m",
            },
            {
                level = 1,
                steps = "1",
                onFoot = "1 m",
                swimming = "0 m",
                taxi = "0 m",
            },
        },
    })
    local UI = harness.addon.UI
    UI.Create()
    UI.Refresh()

    testlib.equal(UI.levelRows[1].frame.point[5], 0)
    testlib.equal(UI.levelRows[2].frame.point[5], -114)
    testlib.equal(UI.levelRows[3].frame.point[5], -228)
    testlib.equal(UI.levelScrollChild.height, 332)
end)

testlib.case("ui level content keeps its minimum without a trailing gap", function()
    local cases = {
        { rows = {}, expectedHeight = 282 },
        {
            rows = {
                {
                    level = 1,
                    steps = "1",
                    onFoot = "1 m",
                    swimming = "0 m",
                    taxi = "0 m",
                },
            },
            expectedHeight = 282,
        },
        {
            rows = {
                {
                    level = 2,
                    steps = "2",
                    onFoot = "2 m",
                    swimming = "0 m",
                    taxi = "0 m",
                },
                {
                    level = 1,
                    steps = "1",
                    onFoot = "1 m",
                    swimming = "0 m",
                    taxi = "0 m",
                },
            },
            expectedHeight = 282,
        },
    }

    for _, case in ipairs(cases) do
        local harness = newUIHarness({
            levelRows = case.rows,
        })
        harness.addon.UI.Create()
        harness.addon.UI.Refresh()
        testlib.equal(
            harness.addon.UI.levelScrollChild.height,
            case.expectedHeight
        )
    end
end)

testlib.case("ui hides level scrollbar chrome when content fits", function()
    local harness = newUIHarness({
        levelRows = {
            {
                level = 5,
                steps = "5",
                onFoot = "5 m",
                swimming = "0 m",
                taxi = "0 m",
            },
        },
    })
    local UI = harness.addon.UI
    UI.Create()
    UI.Refresh()

    testlib.equal(UI.levelPanel.width, 376)
    testlib.equal(UI.levelPanel.height, 310)
    testlib.equal(UI.levelScrollFrame.width, 348)
    testlib.equal(UI.levelScrollChild.width, 348)
    testlib.equal(UI.levelRows[1].frame.width, 348)
    testlib.equal(UI.levelScrollFrame.ScrollBar:IsShown(), false)
    testlib.equal(
        UI.levelScrollFrame.ScrollBar.ScrollUpButton:IsShown(),
        false
    )
    testlib.equal(
        UI.levelScrollFrame.ScrollBar.ScrollDownButton:IsShown(),
        false
    )
    testlib.equal(
        UI.levelScrollFrame.ScrollBar.ThumbTexture:IsShown(),
        false
    )
end)

local function levelScrollbarButtonBounds(UI)
    local scrollFrameLeft = UI.levelScrollFrame.point[4]
    local scrollFrameTop = -UI.levelScrollFrame.point[5]
    local scrollFrameBottom = scrollFrameTop + UI.levelScrollFrame.height
    local scrollBar = UI.levelScrollFrame.ScrollBar
    local scrollBarLeft =
        scrollFrameLeft + UI.levelScrollFrame.width + scrollBar.points[1][4]
    local topInset = -scrollBar.points[1][5]
    local bottomInset = scrollBar.points[2][5]
    local nativeButtonSize = 16

    return {
        up = {
            left = scrollBarLeft,
            right = scrollBarLeft + nativeButtonSize,
            top = scrollFrameTop + topInset - nativeButtonSize,
            bottom = scrollFrameTop + topInset,
        },
        down = {
            left = scrollBarLeft,
            right = scrollBarLeft + nativeButtonSize,
            top = scrollFrameBottom - bottomInset,
            bottom = scrollFrameBottom - bottomInset + nativeButtonSize,
        },
    }
end

local function assertBoundsInsidePanel(bounds, panel)
    testlib.truthy(bounds.left >= 0)
    testlib.truthy(bounds.right <= panel.width)
    testlib.truthy(bounds.top >= 0)
    testlib.truthy(bounds.bottom <= panel.height)
end

testlib.case("ui level list exposes every row through scrollable content", function()
    local rows = {}
    for level = 16, 1, -1 do
        table.insert(rows, {
            level = level,
            steps = level * 10,
            onFoot = level .. " m",
            swimming = level .. " m",
            taxi = level .. " m",
        })
    end
    local harness = newUIHarness({
        levelRows = rows,
    })
    harness.addon.UI.Create()
    harness.addon.UI.Refresh()

    testlib.equal(#harness.addon.UI.levelRows, 16)
    testlib.equal(harness.addon.UI.levelRows[16].title:GetText(), "Level 1")
    testlib.equal(harness.addon.UI.levelRows[16].rows[4].value:GetText(), "1 m")
    testlib.equal(harness.addon.UI.levelRows[16].frame:IsShown(), true)
    testlib.equal(
        harness.addon.UI.levelRows[16].frame.parent,
        harness.addon.UI.levelScrollChild
    )
    testlib.truthy(
        harness.addon.UI.levelScrollChild.height
            >= (#rows * 104)
    )
    testlib.truthy(
        harness.addon.UI.levelScrollChild.height
            > harness.addon.UI.levelScrollFrame.height
    )
    testlib.truthy(
        harness.addon.UI.levelScrollFrame:GetVerticalScrollRange() > 0
    )
    testlib.equal(harness.addon.UI.levelScrollFrame.width, 348)
    testlib.equal(harness.addon.UI.levelScrollChild.width, 348)
    testlib.equal(harness.addon.UI.levelRows[1].frame.width, 348)
    local scrollBar = harness.addon.UI.levelScrollFrame.ScrollBar
    testlib.equal(scrollBar:IsShown(), true)
    testlib.equal(scrollBar.points[1][1], "TOPLEFT")
    testlib.equal(scrollBar.points[1][2], harness.addon.UI.levelScrollFrame)
    testlib.equal(scrollBar.points[1][3], "TOPRIGHT")
    testlib.truthy(scrollBar.points[1][4] >= 2)
    testlib.equal(scrollBar.points[1][4], 4)
    testlib.equal(scrollBar.points[1][5], -14)
    testlib.equal(scrollBar.points[2][1], "BOTTOMLEFT")
    testlib.equal(scrollBar.points[2][2], harness.addon.UI.levelScrollFrame)
    testlib.equal(scrollBar.points[2][3], "BOTTOMRIGHT")
    testlib.equal(scrollBar.points[2][4], 4)
    testlib.equal(scrollBar.points[2][5], 16)
    local buttonBounds = levelScrollbarButtonBounds(harness.addon.UI)
    assertBoundsInsidePanel(buttonBounds.up, harness.addon.UI.levelPanel)
    assertBoundsInsidePanel(buttonBounds.down, harness.addon.UI.levelPanel)
    testlib.equal(scrollBar.ScrollUpButton:IsShown(), true)
    testlib.equal(scrollBar.ScrollDownButton:IsShown(), true)
    testlib.equal(scrollBar.ThumbTexture:IsShown(), true)
end)

testlib.case("ui falls back when the native level scroll template is rejected", function()
    local harness = newUIHarness({
        rejectTemplates = {
            UIPanelScrollFrameTemplate = true,
        },
    })
    local UI = harness.addon.UI

    testlib.equal(pcall(UI.Create), true)
    testlib.equal(pcall(UI.Refresh), true)
    testlib.equal(UI.levelScrollFrame.ScrollBar, nil)
    testlib.equal(UI.levelScrollFrame.width, 348)
end)

testlib.case("ui protects level scrollbar range checks", function()
    local harness = newUIHarness({
        rejectLevelScrollRange = true,
    })
    local UI = harness.addon.UI

    UI.Create()
    UI.levelScrollFrame:SetVerticalScroll(100)
    testlib.equal(pcall(UI.Refresh), true)
    testlib.equal(UI.levelScrollFrame.ScrollBar:IsShown(), false)
    testlib.equal(UI.levelScrollFrame:GetVerticalScroll(), 100)
end)

testlib.case("ui toggles only direct-child level scrollbar chrome", function()
    local overflowRows = {}
    for level = 16, 1, -1 do
        table.insert(overflowRows, {
            level = level,
            steps = level,
            onFoot = level .. " m",
            swimming = level .. " m",
            taxi = level .. " m",
        })
    end
    local harness = newUIHarness({
        levelRowsSequence = {
            {
                {
                    level = 1,
                    steps = "1",
                    onFoot = "1 m",
                    swimming = "0 m",
                    taxi = "0 m",
                },
            },
            overflowRows,
        },
        levelScrollbarDirectChildOnly = true,
        levelScrollUnrelatedDirectChild = true,
    })
    local UI = harness.addon.UI

    UI.Create()
    UI.Refresh()

    local scrollBar = UI.levelScrollFrame.children[1]
    local unrelated = UI.levelScrollFrame.children[2]
    testlib.equal(UI.levelScrollFrame.ScrollBar, nil)
    testlib.equal(scrollBar:IsShown(), false)
    testlib.equal(scrollBar.ScrollUpButton:IsShown(), false)
    testlib.equal(scrollBar.ScrollDownButton:IsShown(), false)
    testlib.equal(scrollBar.ThumbTexture:IsShown(), false)
    testlib.equal(unrelated:IsShown(), true)

    UI.Refresh()

    testlib.equal(scrollBar:IsShown(), true)
    testlib.equal(scrollBar.points[1][1], "TOPLEFT")
    testlib.equal(scrollBar.points[1][2], UI.levelScrollFrame)
    testlib.equal(scrollBar.ScrollUpButton:IsShown(), true)
    testlib.equal(scrollBar.ScrollDownButton:IsShown(), true)
    testlib.equal(scrollBar.ThumbTexture:IsShown(), true)
    testlib.equal(unrelated:IsShown(), true)
end)

testlib.case("ui preserves valid level scroll offsets and clamps after shrinking", function()
    local overflowRows = {}
    local shorterRows = {}
    for level = 16, 1, -1 do
        table.insert(overflowRows, {
            level = level,
            steps = level,
            onFoot = level .. " m",
            swimming = level .. " m",
            taxi = level .. " m",
        })
        if level > 8 then
            table.insert(shorterRows, overflowRows[#overflowRows])
        end
    end
    local harness = newUIHarness({
        levelRowsSequence = {
            overflowRows,
            shorterRows,
            {
                {
                    level = 1,
                    steps = "1",
                    onFoot = "1 m",
                    swimming = "0 m",
                    taxi = "0 m",
                },
            },
        },
    })
    local UI = harness.addon.UI
    UI.Create()
    UI.Refresh()
    UI.levelScrollFrame:SetVerticalScroll(200)

    UI.Refresh()
    testlib.equal(UI.levelScrollFrame:GetVerticalScroll(), 200)

    UI.Refresh()
    testlib.equal(UI.levelScrollFrame:GetVerticalScroll(), 0)
end)

testlib.case("ui level cards reuse frames and hide stale data after shrinking", function()
    local harness = newUIHarness({
        levelRowsSequence = {
            {
                {
                    level = 42,
                    steps = "420",
                    onFoot = "42 m",
                    swimming = "4 m",
                    taxi = "2 m",
                },
                {
                    level = 41,
                    steps = "410",
                    onFoot = "41 m",
                    swimming = "3 m",
                    taxi = "1 m",
                },
            },
            {
                {
                    level = 42,
                    steps = "421",
                    onFoot = "43 m",
                    swimming = "5 m",
                    taxi = "3 m",
                },
            },
        },
    })
    local UI = harness.addon.UI
    UI.Create()
    UI.Refresh()
    local firstCard = UI.levelRows[1]
    local staleCard = UI.levelRows[2]

    UI.Refresh()

    testlib.equal(UI.levelRows[1], firstCard)
    testlib.equal(UI.levelRows[2], staleCard)
    testlib.equal(firstCard.rows[1].value:GetText(), "421")
    testlib.equal(staleCard.frame:IsShown(), false)
    testlib.equal(staleCard.title:GetText(), "")
    for _, row in ipairs(staleCard.rows) do
        testlib.equal(row.value:GetText(), "")
    end
    testlib.equal(UI.levelScrollChild.height, UI.levelScrollFrame.height)
end)

testlib.case("ui diagnostics use no visible space when disabled", function()
    local disabled = newUIHarness({
        db = {
            settings = {
                units = "metric",
                showMinimap = true,
                showDiagnostics = false,
                hudPoint = "CENTER",
                hudX = 0,
                hudY = 0,
            },
        },
    })
    disabled.addon.UI.Create()
    disabled.addon.UI.Refresh()
    testlib.equal(disabled.addon.UI.diagnosticsScrollFrame:IsShown(), false)
    testlib.equal(disabled.addon.UI.diagnosticsText:GetText(), "")
    testlib.equal(disabled.addon.UI.overviewPanel.height, 320)
end)

testlib.case("ui diagnostics retain and scroll realistic multi-reason output", function()
    local diagnostics = {
        { reason = "baseline", count = 3 },
        { reason = "falling", count = 12 },
        { reason = "mounted", count = 27 },
        { reason = "speedExceeded", count = 4 },
        { reason = "stateTransition", count = 6 },
        { reason = "timeGap", count = 9 },
        { reason = "unsupportedMap", count = 2 },
        { reason = "zoning", count = 5 },
    }
    local enabled = newUIHarness({
        diagnostics = diagnostics,
    })
    enabled.addon.UI.Create()
    enabled.addon.UI.Refresh()

    local UI = enabled.addon.UI
    testlib.equal(UI.frame.width, 420)
    testlib.equal(UI.frame.height, 470)
    testlib.equal(UI.diagnosticsScrollFrame:IsShown(), true)
    testlib.equal(UI.diagnosticsScrollFrame.mouseWheelEnabled, true)
    testlib.equal(UI.diagnosticsScrollFrame.point[1], "TOPLEFT")
    testlib.equal(
        UI.diagnosticsScrollFrame.point[2],
        UI.overviewPanel
    )
    testlib.equal(UI.diagnosticsScrollFrame.point[3], "TOPLEFT")
    testlib.equal(UI.diagnosticsScrollFrame.point[5], -324)
    testlib.equal(UI.overviewPanel.height, 346)
    local overviewTopOffset =
        UI.contentFrame.point[5] - UI.overviewPanel.point[5]
    testlib.truthy(
        overviewTopOffset + UI.overviewPanel.height
            <= UI.contentFrame.height
    )
    testlib.truthy(
        UI.diagnosticsScrollChild.height > UI.diagnosticsScrollFrame.height
    )
    testlib.truthy(UI.diagnosticsScrollFrame:GetVerticalScrollRange() > 0)
    for _, diagnostic in ipairs(diagnostics) do
        testlib.truthy(contains(
            UI.diagnosticsText:GetText(),
            diagnostic.reason .. ": " .. tostring(diagnostic.count)
        ))
    end

    UI.diagnosticsScrollFrame.scripts.OnMouseWheel(
        UI.diagnosticsScrollFrame,
        -1
    )
    testlib.truthy(UI.diagnosticsScrollFrame:GetVerticalScroll() > 0)
end)

testlib.case("ui errors replace overview content inside the compact inset", function()
    local harness = newUIHarness()

    harness.addon.UI.ShowError("before create")
    harness.addon.UI.Create()
    testlib.equal(harness.addon.UI.errorText:GetText(), "before create")
    testlib.equal(harness.addon.UI.errorPanel:IsShown(), true)
    testlib.equal(harness.addon.UI.overviewPanel:IsShown(), false)
    testlib.equal(harness.addon.UI.levelPanel:IsShown(), false)
    testlib.equal(harness.addon.UI.errorPanel.parent, harness.addon.UI.contentFrame)
    local errorTopOffset = -harness.addon.UI.errorPanel.point[5]
    testlib.truthy(
        errorTopOffset + harness.addon.UI.errorPanel.height
            <= harness.addon.UI.contentFrame.height
    )
    testlib.equal(
        errorTopOffset + harness.addon.UI.errorPanel.height,
        harness.addon.UI.contentFrame.height
    )

    harness.addon.UI.ShowError("after create")
    testlib.equal(harness.addon.UI.errorText:GetText(), "after create")
    testlib.equal(harness.addon.UI.errorPanel:IsShown(), true)
    testlib.equal(harness.addon.UI.overviewPanel:IsShown(), false)
    testlib.equal(harness.addon.UI.levelPanel:IsShown(), false)
end)

testlib.case("ui refresh failure replaces level content with the inset error", function()
    local refreshFailure = newUIHarness({
        overviewError = "invalidStatistics",
    })
    refreshFailure.addon.UI.Create()
    refreshFailure.addon.UI.levelTab.scripts.OnClick()
    refreshFailure.addon.UI.Refresh()
    testlib.equal(refreshFailure.addon.UI.errorPanel:IsShown(), true)
    testlib.equal(refreshFailure.addon.UI.overviewPanel:IsShown(), false)
    testlib.equal(refreshFailure.addon.UI.levelPanel:IsShown(), false)
    testlib.truthy(
        contains(refreshFailure.addon.UI.errorText:GetText(), "invalidStatistics")
    )
end)

testlib.case("ui successful refresh clears error and restores active panel", function()
    local harness = newUIHarness({
        overviewSequence = {
            {
                error = "invalidStatistics",
            },
            {
                overview = {
                    lifetime = {
                        steps = "12.5K",
                        onFoot = "1.00 km",
                        swimming = "2.00 km",
                        taxi = "3.00 km",
                    },
                    session = {
                        steps = "10",
                        onFoot = "100 m",
                        swimming = "200 m",
                        taxi = "300 m",
                    },
                    currentLevel = {
                        steps = "5",
                        onFoot = "50 m",
                        swimming = "60 m",
                        taxi = "70 m",
                    },
                },
            },
        },
    })
    local UI = harness.addon.UI
    UI.Create()
    UI.levelTab.scripts.OnClick()

    testlib.equal(UI.Refresh(), false)
    testlib.equal(UI.errorPanel:IsShown(), true)
    testlib.equal(UI.overviewPanel:IsShown(), false)
    testlib.equal(UI.levelPanel:IsShown(), false)

    testlib.equal(UI.Refresh(), true)
    testlib.equal(UI.errorPanel:IsShown(), false)
    testlib.equal(UI.errorText:GetText(), "")
    testlib.equal(UI.overviewPanel:IsShown(), false)
    testlib.equal(UI.levelPanel:IsShown(), true)
    testlib.equal(UI.levelTab.selected, true)
end)

testlib.case("ui confirmation resets only the session after acceptance", function()
    local harness = newUIHarness()
    harness.addon.UI.Create()

    harness.addon.UI.ConfirmResetSession()
    testlib.equal(
        harness.environment.shownPopup,
        "AZEROTH_TRAVEL_METRICS_RESET_SESSION"
    )
    testlib.equal(harness.calls.reset, 0)

    local dialog = harness.environment.StaticPopupDialogs[
        "AZEROTH_TRAVEL_METRICS_RESET_SESSION"
    ]
    dialog.OnAccept()

    testlib.equal(harness.calls.now, 1)
    testlib.equal(harness.calls.reset, 1)
    testlib.equal(harness.calls.resetCharacter, harness.character)
    testlib.equal(harness.calls.resetNow, 3000)
    testlib.equal(harness.calls.baselineReset, 1)
    testlib.equal(harness.calls.order[1], "storageReset")
    testlib.equal(harness.calls.order[2], "baselineReset")
    testlib.equal(harness.calls.order[3], "refresh")
    testlib.equal(harness.calls.overview, 1)
end)

testlib.case("ui reset clears the prior baseline before the next sample", function()
    local order = {}
    local tracker = {
        previous = {
            x = 1,
        },
    }
    function tracker:ResetBaseline()
        table.insert(order, "baselineReset")
        self.previous = nil
    end
    function tracker:Sample()
        if self.previous ~= nil then
            return {
                bridged = true,
            }
        end
        self.previous = {
            x = 2,
        }
        return nil, "baseline"
    end

    local harness = newUIHarness({
        order = order,
        tracker = tracker,
    })
    harness.addon.UI.Create()
    harness.addon.UI.ConfirmResetSession()
    local dialog = harness.environment.StaticPopupDialogs[
        "AZEROTH_TRAVEL_METRICS_RESET_SESSION"
    ]
    dialog.OnAccept()

    testlib.equal(order[1], "storageReset")
    testlib.equal(order[2], "baselineReset")
    testlib.equal(order[3], "refresh")
    local segment, reason = tracker:Sample()
    testlib.equal(segment, nil)
    testlib.equal(reason, "baseline")
end)

testlib.case("ui preserves a successful reset when baseline reset errors", function()
    local harness = newUIHarness({
        baselineResetThrows = true,
    })
    harness.addon.UI.Create()
    local previousSession = harness.character.session

    harness.addon.UI.ConfirmResetSession()
    local dialog = harness.environment.StaticPopupDialogs[
        "AZEROTH_TRAVEL_METRICS_RESET_SESSION"
    ]
    local succeeded = pcall(dialog.OnAccept)

    testlib.equal(succeeded, true)
    testlib.equal(harness.calls.reset, 1)
    testlib.equal(harness.calls.baselineReset, 1)
    testlib.truthy(harness.character.session ~= previousSession)
    testlib.equal(harness.character.session.startedAt, 3000)
    testlib.equal(harness.calls.overview, 1)
    testlib.equal(harness.addon.UI.errorText:IsShown(), true)
    testlib.truthy(contains(
        harness.addon.UI.errorText:GetText(),
        "reset succeeded"
    ))
    testlib.truthy(contains(
        harness.addon.UI.errorText:GetText(),
        "baseline exploded"
    ))
end)

testlib.case("ui reset preserves session and reports unavailable time", function()
    local harness = newUIHarness({
        nowUnavailable = true,
    })
    harness.addon.UI.Create()
    local session = harness.character.session

    harness.addon.UI.ConfirmResetSession()
    local dialog = harness.environment.StaticPopupDialogs[
        "AZEROTH_TRAVEL_METRICS_RESET_SESSION"
    ]
    local succeeded = pcall(dialog.OnAccept)

    testlib.equal(succeeded, true)
    testlib.equal(harness.calls.reset, 0)
    testlib.equal(harness.calls.overview, 0)
    testlib.equal(harness.character.session, session)
    testlib.equal(harness.addon.UI.errorText:IsShown(), true)
    testlib.truthy(contains(
        harness.addon.UI.errorText:GetText(),
        "timeUnavailable"
    ))
end)

testlib.case("ui reset preserves session and reports storage exceptions", function()
    local harness = newUIHarness({
        resetThrows = true,
    })
    harness.addon.UI.Create()
    local session = harness.character.session

    harness.addon.UI.ConfirmResetSession()
    local dialog = harness.environment.StaticPopupDialogs[
        "AZEROTH_TRAVEL_METRICS_RESET_SESSION"
    ]
    local succeeded = pcall(dialog.OnAccept)

    testlib.equal(succeeded, true)
    testlib.equal(harness.calls.reset, 1)
    testlib.equal(harness.calls.overview, 0)
    testlib.equal(harness.character.session, session)
    testlib.equal(harness.addon.UI.errorText:IsShown(), true)
    testlib.truthy(contains(
        harness.addon.UI.errorText:GetText(),
        "reset exploded"
    ))
end)

testlib.case("ui reset preserves session and reports storage rejection", function()
    local harness = newUIHarness({
        resetError = "resetRejected",
    })
    harness.addon.UI.Create()
    local session = harness.character.session

    harness.addon.UI.ConfirmResetSession()
    local dialog = harness.environment.StaticPopupDialogs[
        "AZEROTH_TRAVEL_METRICS_RESET_SESSION"
    ]
    local succeeded = pcall(dialog.OnAccept)

    testlib.equal(succeeded, true)
    testlib.equal(harness.calls.reset, 1)
    testlib.equal(harness.calls.overview, 0)
    testlib.equal(harness.character.session, session)
    testlib.equal(harness.addon.UI.errorText:IsShown(), true)
    testlib.truthy(contains(
        harness.addon.UI.errorText:GetText(),
        "resetRejected"
    ))
end)

testlib.case("ui lifecycle remains safe during combat lockdown", function()
    local harness = newUIHarness({
        inCombat = true,
    })

    local succeeded, failure = pcall(function()
        harness.addon.UI.Create()
        harness.addon.UI.Toggle()
        harness.addon.UI.levelTab.scripts.OnClick()
        harness.addon.UI.overviewTab.scripts.OnClick()
        harness.addon.UI.settingsButton.scripts.OnClick()
        harness.addon.UI.metricCheck.scripts.OnClick()
        harness.addon.UI.minimapCheck:SetChecked(false)
        harness.addon.UI.minimapCheck.scripts.OnClick()
        harness.addon.UI.diagnosticsCheck:SetChecked(true)
        harness.addon.UI.diagnosticsCheck.scripts.OnClick()
        harness.addon.UI.Refresh()
        harness.addon.UI.ConfirmResetSession()
    end)

    testlib.equal(succeeded, true, failure)
    testlib.equal(harness.calls.protected, 0)
    testlib.equal(harness.addon.UI.overviewPanel:IsShown(), true)
    testlib.equal(harness.addon.UI.levelPanel:IsShown(), false)
    testlib.equal(harness.addon.UI.settingsPanel:IsShown(), true)
    testlib.equal(
        harness.environment.shownPopup,
        "AZEROTH_TRAVEL_METRICS_RESET_SESSION"
    )
end)

testlib.case("ui reset button opens confirmation and toggle reflects visibility", function()
    local harness = newUIHarness()
    local frame = harness.addon.UI.Create()

    testlib.equal(harness.addon.UI.IsShown(), false)
    harness.addon.UI.Toggle()
    testlib.equal(harness.addon.UI.IsShown(), true)
    harness.addon.UI.Toggle()
    testlib.equal(harness.addon.UI.IsShown(), false)

    harness.addon.UI.resetButton.scripts.OnClick()
    testlib.equal(
        harness.environment.shownPopup,
        "AZEROTH_TRAVEL_METRICS_RESET_SESSION"
    )
    testlib.equal(harness.calls.reset, 0)
    testlib.equal(frame:IsShown(), false)
end)

testlib.case("addon manifest references only files present in this task", function()
    local source = debug.getinfo(1, "S").source:sub(2)
    local testsDirectory = source:match("^(.*)[\\/][^\\/]+$") or "."
    local projectDirectory = testsDirectory:match("^(.*)[\\/][^\\/]+$") or "."
    local separator = package.config:sub(1, 1)
    local tocPath = projectDirectory
        .. separator
        .. "AzerothTravelMetrics"
        .. separator
        .. "AzerothTravelMetrics.toc"
    local toc = assert(io.open(tocPath, "r"))

    local files = {}
    for line in toc:lines() do
        if line:match("%.lua%s*$") then
            table.insert(files, line)
            local relativePath = line:gsub("[\\/]", separator)
            local filePath = projectDirectory
                .. separator
                .. "AzerothTravelMetrics"
                .. separator
                .. relativePath
            local referenced = io.open(filePath, "r")
            testlib.truthy(referenced ~= nil, "missing TOC file " .. line)
            if referenced then
                referenced:close()
            end
        end
    end

    toc:close()
    local minimapIndex
    local uiThemeIndex
    local uiIndex
    local coreIndex
    for index, fileName in ipairs(files) do
        if fileName == "UITheme.lua" then
            uiThemeIndex = index
        elseif fileName == "UI.lua" then
            uiIndex = index
        elseif fileName == "Minimap.lua" then
            minimapIndex = index
        elseif fileName == "Core.lua" then
            coreIndex = index
        end
    end
    testlib.truthy(uiThemeIndex ~= nil, "UITheme.lua missing from TOC")
    testlib.truthy(uiIndex ~= nil, "UI.lua missing from TOC")
    testlib.truthy(minimapIndex ~= nil, "Minimap.lua missing from TOC")
    testlib.truthy(coreIndex ~= nil, "Core.lua missing from TOC")
    testlib.truthy(uiThemeIndex < uiIndex, "UITheme.lua must load before UI.lua")
    testlib.truthy(uiIndex < minimapIndex, "Minimap.lua must load after UI.lua")
    testlib.truthy(minimapIndex < coreIndex, "Minimap.lua must load before Core.lua")
end)

testlib.case("addon manifest declares the native travel listing icon", function()
    local source = debug.getinfo(1, "S").source:sub(2)
    local testsDirectory = source:match("^(.*)[\\/][^\\/]+$") or "."
    local projectDirectory = testsDirectory:match("^(.*)[\\/][^\\/]+$") or "."
    local separator = package.config:sub(1, 1)
    local tocPath = projectDirectory
        .. separator
        .. "AzerothTravelMetrics"
        .. separator
        .. "AzerothTravelMetrics.toc"
    local toc = assert(io.open(tocPath, "r"))
    local iconTextureLines = {}

    for line in toc:lines() do
        if line:match("^##%s*IconTexture:") then
            table.insert(iconTextureLines, line)
        end
    end

    toc:close()
    testlib.equal(#iconTextureLines, 1)
    testlib.equal(
        iconTextureLines[1],
        "## IconTexture: Interface\\Icons\\inv_misc_pocketwatch_01"
    )
end)

testlib.case("fallback version matches the single addon manifest version", function()
    local source = debug.getinfo(1, "S").source:sub(2)
    local testsDirectory = source:match("^(.*)[\\/][^\\/]+$") or "."
    local projectDirectory = testsDirectory:match("^(.*)[\\/][^\\/]+$") or "."
    local separator = package.config:sub(1, 1)
    local tocPath = projectDirectory
        .. separator
        .. "AzerothTravelMetrics"
        .. separator
        .. "AzerothTravelMetrics.toc"
    local toc = assert(io.open(tocPath, "r"))
    local versions = {}

    for line in toc:lines() do
        local version = line:match("^##%s*Version:%s*(.-)%s*$")
        if version then
            table.insert(versions, version)
        end
    end

    toc:close()
    testlib.equal(
        #versions,
        1,
        string.format(
            "expected exactly one ## Version: value in addon manifest, found %d",
            #versions
        )
    )

    local addon = testlib.loadAddon("AzerothTravelMetrics\\Namespace.lua")
    testlib.equal(
        versions[1],
        addon.VERSION_FALLBACK,
        string.format(
            "addon manifest Version %q does not match addon.VERSION_FALLBACK %q",
            versions[1],
            addon.VERSION_FALLBACK
        )
    )
end)
