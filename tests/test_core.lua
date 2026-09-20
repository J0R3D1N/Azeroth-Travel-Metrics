local testlib = require("testlib")

local CORE_FILES = {
    "AzerothTravelTracker\\Namespace.lua",
    "AzerothTravelTracker\\Core.lua",
}

local UI_FILES = {
    "AzerothTravelTracker\\Namespace.lua",
    "AzerothTravelTracker\\UI.lua",
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
    globals.AzerothTravelTrackerDB = options.savedDB

    local addon, environment = testlib.loadAddon(CORE_FILES, globals)
    local calls = {
        initialize = 0,
        identity = 0,
        getCharacter = 0,
        trackerNew = 0,
        uiInitialize = 0,
        minimapInitialize = 0,
        uiRefresh = 0,
        uiToggle = 0,
        uiConfirmReset = 0,
        uiErrors = {},
        prints = {},
        tickers = {},
        samples = 0,
        resets = 0,
        levelCalls = {},
        order = {},
        initializationOrder = {},
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
            return result.segment, result.reason
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
            calls.characterArguments = {
                db = db,
                key = key,
                identity = receivedIdentity,
            }
            if options.getCharacterThrows then
                error("character exploded")
            end
            return character
        end,
    }

    addon.Compat = {
        GetCharacterIdentity = function()
            calls.identity = calls.identity + 1
            if options.identityThrows then
                error("identity exploded")
            end
            if options.identityError then
                return nil, options.identityError
            end
            return identity
        end,
        GetCapabilities = function()
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

local function initialize(harness)
    harness.fire("ADDON_LOADED", "AzerothTravelTracker")
end

testlib.case("core registers one frame for all lifecycle events and slash commands", function()
    local harness = newCoreHarness()

    testlib.equal(countKeys(harness.eventFrame.events), 4)
    testlib.equal(harness.eventFrame.events.ADDON_LOADED, true)
    testlib.equal(harness.eventFrame.events.PLAYER_ENTERING_WORLD, true)
    testlib.equal(harness.eventFrame.events.PLAYER_LEVEL_UP, true)
    testlib.equal(harness.eventFrame.events.PLAYER_LOGOUT, true)
    testlib.equal(harness.environment.SLASH_AZEROTHTRAVELTRACKER1, "/att")
    testlib.equal(
        harness.environment.SLASH_AZEROTHTRAVELTRACKER2,
        "/azerothtraveltracker"
    )
    testlib.equal(
        type(harness.environment.SlashCmdList.AZEROTHTRAVELTRACKER),
        "function"
    )
end)

testlib.case("core ignores nonmatching ADDON_LOADED and initializes matching addon once", function()
    local harness = newCoreHarness({
        savedDB = {
            sentinel = true,
        },
    })

    harness.fire("ADDON_LOADED", "OtherAddon")
    testlib.equal(harness.calls.initialize, 0)

    initialize(harness)
    testlib.equal(harness.calls.initialize, 1)
    testlib.equal(harness.calls.identity, 1)
    testlib.equal(harness.calls.getCharacter, 1)
    testlib.equal(harness.calls.trackerNew, 1)
    testlib.equal(harness.calls.uiInitialize, 1)
    testlib.equal(harness.calls.minimapInitialize, 1)
    testlib.equal(harness.calls.initializationOrder[1], "uiInitialize")
    testlib.equal(harness.calls.initializationOrder[2], "minimapInitialize")
    testlib.equal(harness.calls.minimapContext.db, harness.db)
    testlib.equal(harness.environment.AzerothTravelTrackerDB, harness.db)
    testlib.equal(harness.calls.characterArguments.db, harness.db)
    testlib.equal(
        harness.calls.characterArguments.key,
        "Traveler-TestRealm"
    )
    testlib.equal(
        harness.calls.characterArguments.identity.name,
        "Traveler"
    )
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

    harness.fire("ADDON_LOADED", "AzerothTravelTracker")
    testlib.equal(harness.calls.initialize, 1)
    testlib.equal(harness.calls.getCharacter, 1)
end)

testlib.case("core tolerates missing minimap for load-order safety", function()
    local harness = newCoreHarness({
        missingMinimap = true,
    })

    initialize(harness)

    testlib.equal(harness.addon.Core.GetState().ready, true)
    testlib.equal(harness.calls.uiInitialize, 1)
    testlib.equal(#harness.calls.uiErrors, 0)
end)

testlib.case("core reports minimap initialization failure without disabling tracking", function()
    local harness = newCoreHarness({
        minimapThrows = true,
    })

    initialize(harness)
    initialize(harness)

    testlib.equal(harness.addon.Core.GetState().ready, true)
    testlib.equal(harness.calls.minimapInitialize, 1)
    testlib.equal(#harness.calls.prints, 1)
    testlib.equal(#harness.calls.uiErrors, 1)
    testlib.truthy(contains(harness.calls.prints[1], "minimap"))
    testlib.truthy(contains(harness.calls.uiErrors[1], "minimap"))

    harness.fire("PLAYER_ENTERING_WORLD")
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
    harness.fire("PLAYER_ENTERING_WORLD")

    testlib.equal(harness.environment.AzerothTravelTrackerDB, savedDB)
    testlib.equal(harness.calls.identity, 0)
    testlib.equal(harness.calls.getCharacter, 0)
    testlib.equal(#harness.calls.tickers, 0)
    testlib.equal(#harness.calls.uiErrors, 1)
    testlib.equal(#harness.calls.prints, 1)
    testlib.truthy(contains(harness.calls.prints[1], "unsupportedSchema"))
end)

testlib.case("identity failure prevents tracking and throttles its reason", function()
    local savedDB = {
        sentinel = true,
    }
    local harness = newCoreHarness({
        savedDB = savedDB,
        identityError = "identityUnavailable",
    })

    initialize(harness)
    harness.addon.Core.ReportOnce("identityUnavailable")
    harness.fire("PLAYER_ENTERING_WORLD")

    testlib.equal(harness.environment.AzerothTravelTrackerDB, savedDB)
    testlib.equal(harness.calls.getCharacter, 0)
    testlib.equal(harness.calls.trackerNew, 0)
    testlib.equal(#harness.calls.tickers, 0)
    testlib.equal(#harness.calls.uiErrors, 1)
    testlib.equal(#harness.calls.prints, 1)
end)

testlib.case("entering world retries transient identity initialization once", function()
    local harness = newCoreHarness({
        identityError = "identityUnavailable",
    })

    initialize(harness)
    testlib.equal(harness.calls.getCharacter, 0)

    harness.options.identityError = nil
    harness.fire("PLAYER_ENTERING_WORLD")

    testlib.equal(harness.calls.getCharacter, 1)
    testlib.equal(harness.calls.trackerNew, 1)
    testlib.equal(harness.calls.uiInitialize, 1)
    testlib.equal(#harness.calls.tickers, 1)
end)

testlib.case("entering world refreshes capabilities without replacing UI context", function()
    local initialCapabilities = {
        position = false,
        onFootReady = false,
    }
    local harness = newCoreHarness({
        capabilities = initialCapabilities,
    })
    initialize(harness)
    local exposedCapabilities = harness.calls.uiContext.capabilities

    harness.options.capabilities = {
        position = true,
        onFootReady = true,
    }
    harness.fire("PLAYER_ENTERING_WORLD")

    testlib.equal(harness.calls.uiContext.capabilities, exposedCapabilities)
    testlib.equal(exposedCapabilities.position, true)
    testlib.equal(exposedCapabilities.onFootReady, true)
end)

testlib.case("entering world resets baseline and maintains one half-second ticker", function()
    local harness = newCoreHarness()
    initialize(harness)

    harness.fire("PLAYER_ENTERING_WORLD")
    testlib.equal(harness.calls.resets, 1)
    testlib.equal(#harness.calls.tickers, 1)
    testlib.near(harness.calls.tickers[1].interval, 0.5, 0.0001)

    harness.fire("PLAYER_ENTERING_WORLD")
    testlib.equal(harness.calls.resets, 2)
    testlib.equal(#harness.calls.tickers, 2)
    testlib.equal(harness.calls.tickers[1].cancelled, true)
    testlib.equal(harness.calls.tickers[2].cancelled, false)
end)

testlib.case("native-like ticker handles are retained and cancelled before restart", function()
    local harness = newCoreHarness({
        nativeTickerHandles = true,
    })
    initialize(harness)

    harness.fire("PLAYER_ENTERING_WORLD")
    testlib.equal(#harness.calls.tickers, 1)
    testlib.equal(
        harness.addon.Core.GetState().ticker,
        harness.calls.tickers[1].handle
    )

    harness.fire("PLAYER_ENTERING_WORLD")
    testlib.equal(#harness.calls.tickers, 2)
    testlib.equal(harness.calls.tickers[1].cancelled, true)
    testlib.equal(harness.calls.tickers[2].cancelled, false)

    harness.fire("PLAYER_LOGOUT")
    testlib.equal(harness.calls.tickers[2].cancelled, true)
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
    initialize(harness)
    harness.fire("PLAYER_ENTERING_WORLD")

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
    initialize(hidden)
    hidden.fire("PLAYER_ENTERING_WORLD")
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
    initialize(harness)
    harness.fire("PLAYER_ENTERING_WORLD")

    for _ = 1, 5 do
        harness.calls.tickers[1].callback()
    end

    testlib.equal(#harness.calls.prints, 2)
    testlib.truthy(contains(harness.calls.prints[1], "positionUnavailable"))
    testlib.truthy(contains(harness.calls.prints[2], "unsupportedState"))
end)

testlib.case("level up obtains wall clock before setting level and refreshes", function()
    local harness = newCoreHarness()
    initialize(harness)

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
    initialize(invalid)
    invalid.fire("PLAYER_LEVEL_UP", 0)
    testlib.equal(#invalid.calls.levelCalls, 0)
    testlib.equal(invalid.calls.uiContext.getCurrentLevel(), 42)
    testlib.equal(#invalid.calls.prints, 1)

    local noTime = newCoreHarness({
        nowError = "timeUnavailable",
    })
    initialize(noTime)
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
    initialize(rejected)
    rejected.fire("PLAYER_LEVEL_UP", 43)
    testlib.equal(rejected.calls.uiContext.getCurrentLevel(), 42)
    testlib.equal(rejected.calls.uiRefresh, 0)
    testlib.equal(#rejected.calls.uiErrors, 1)
    testlib.equal(#rejected.calls.prints, 1)

    local throwingTime = newCoreHarness({
        nowThrows = true,
    })
    initialize(throwingTime)
    local succeeded = pcall(throwingTime.fire, "PLAYER_LEVEL_UP", 43)
    testlib.equal(succeeded, true)
    testlib.equal(#throwingTime.calls.levelCalls, 0)
    testlib.equal(throwingTime.calls.uiContext.getCurrentLevel(), 42)
    testlib.equal(#throwingTime.calls.prints, 1)
end)

testlib.case("logout cancels and clears the active ticker", function()
    local harness = newCoreHarness()
    initialize(harness)
    harness.fire("PLAYER_ENTERING_WORLD")

    harness.fire("PLAYER_LOGOUT")

    testlib.equal(harness.calls.tickers[1].cancelled, true)
    testlib.equal(harness.addon.Core.GetState().ticker, nil)
end)

testlib.case("slash commands toggle and persist units and diagnostics", function()
    local harness = newCoreHarness()
    initialize(harness)
    local slash = harness.environment.SlashCmdList.AZEROTHTRAVELTRACKER

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
    initialize(harness)

    harness.environment.SlashCmdList.AZEROTHTRAVELTRACKER("reset session")

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
    initialize(harness)

    harness.environment.SlashCmdList.AZEROTHTRAVELTRACKER("status")

    testlib.equal(#harness.calls.prints, 4)
    testlib.truthy(contains(harness.calls.prints[1], "position=true"))
    testlib.truthy(contains(harness.calls.prints[1], "map=false"))
    testlib.truthy(contains(harness.calls.prints[2], "taxiReady=false"))
    testlib.truthy(contains(harness.calls.prints[3], "alpha=1"))
    testlib.truthy(contains(harness.calls.prints[4], "zeta=3"))
end)

testlib.case("slash commands report not-ready and concise usage without throwing", function()
    local harness = newCoreHarness()
    local slash = harness.environment.SlashCmdList.AZEROTHTRAVELTRACKER

    local readySucceeded = pcall(slash, "status")
    testlib.equal(readySucceeded, true)
    testlib.equal(#harness.calls.prints, 1)
    testlib.truthy(contains(harness.calls.prints[1], "not ready"))

    initialize(harness)
    slash("units")
    slash("diagnostics maybe")
    slash("unknown")
    testlib.equal(#harness.calls.prints, 4)
    testlib.truthy(contains(harness.calls.prints[2], "Usage:"))
    testlib.truthy(contains(harness.calls.prints[3], "Usage:"))
    testlib.truthy(contains(harness.calls.prints[4], "Usage:"))
end)

local function newFrame(frameType, name, parent, template)
    local frame = {
        frameType = frameType,
        name = name,
        parent = parent,
        template = template,
        scripts = {},
        children = {},
        shown = false,
    }

    function frame:SetSize(width, height)
        self.width = width
        self.height = height
    end

    function frame:SetPoint(...)
        self.point = { ... }
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

    function frame:GetVerticalScrollRange()
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

    function frame:SetTextColor(...)
        self.textColor = { ... }
    end

    function frame:SetChecked(value)
        self.checked = value == true
    end

    function frame:GetChecked()
        return self.checked == true
    end

    function frame:SetBackdrop(...)
        self.backdrop = { ... }
    end

    function frame:SetBackdropColor(...)
        self.backdropColor = { ... }
    end

    function frame:Show()
        self.shown = true
    end

    function frame:Hide()
        self.shown = false
    end

    function frame:IsShown()
        return self.shown
    end

    function frame:CreateFontString(childName, layer, font)
        local child = newFrame("FontString", childName, self, font)
        child.layer = layer
        table.insert(self.children, child)
        return child
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
        rows = 0,
        diagnostics = 0,
        reset = 0,
        baselineReset = 0,
        now = 0,
        protected = 0,
        order = order,
    }
    local globals = {
        UIParent = {
            name = "UIParent",
        },
        StaticPopupDialogs = {},
        YES = "Yes",
        NO = "No",
    }

    globals.CreateFrame = function(frameType, name, parent, template)
        if options.inCombat
            and type(template) == "string"
            and contains(template, "Secure")
        then
            calls.protected = calls.protected + 1
            error("protected template used in combat")
        end
        if template == "BasicFrameTemplateWithInset" and options.rejectMainTemplate then
            error("template unavailable")
        end
        if options.rejectTemplates and options.rejectTemplates[template] then
            error("template unavailable")
        end

        local frame = newFrame(frameType, name, parent, template)
        if name == "AzerothTravelTrackerFrame" then
            local original = frame.SetFrameStrata
            frame.SetFrameStrata = function(self, strata)
                table.insert(strataAttempts, strata)
                if (options.rejectFullscreen and strata == "FULLSCREEN_DIALOG")
                    or (options.rejectStrata and options.rejectStrata[strata])
                then
                    error("strata unavailable")
                end
                original(self, strata)
            end
        end
        table.insert(created, frame)
        return frame
    end

    if not options.noPanelTemplates then
        if not options.missingSelectTabHelper then
            globals.PanelTemplates_SelectTab = function(tab)
                tab.selected = true
                tab:SetButtonState("PUSHED", true)
                tab:LockHighlight()
            end
        end
        globals.PanelTemplates_DeselectTab = function(tab)
            tab.selected = false
            tab:SetButtonState("NORMAL", false)
            tab:UnlockHighlight()
        end
        globals.PanelTemplates_SetNumTabs = function(frame, count)
            frame.numTabs = count
        end
    end

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
        },
    }

    addon.UIModel = {
        BuildOverview = function()
            calls.overview = calls.overview + 1
            table.insert(order, "refresh")
            if options.overviewError then
                return nil, options.overviewError
            end
            return options.overview or {
                lifetime = {
                    steps = 100,
                    onFoot = "1.00 km",
                    swimming = "2.00 km",
                    taxi = "3.00 km",
                },
                session = {
                    steps = 10,
                    onFoot = "100 m",
                    swimming = "200 m",
                    taxi = "300 m",
                },
                currentLevel = {
                    steps = 5,
                    onFoot = "50 m",
                    swimming = "60 m",
                    taxi = "70 m",
                },
            }
        end,
        BuildLevelRows = function()
            calls.rows = calls.rows + 1
            return options.levelRows or {
                {
                    level = 42,
                    steps = 5,
                    onFoot = "50 m",
                    swimming = "60 m",
                    taxi = "70 m",
                },
                {
                    level = 41,
                    steps = 50,
                    onFoot = "500 m",
                    swimming = "600 m",
                    taxi = "700 m",
                },
            }
        end,
        BuildDiagnostics = function()
            calls.diagnostics = calls.diagnostics + 1
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
            table.insert(order, "baselineReset")
            if options.baselineResetThrows then
                error("baseline exploded")
            end
            self.previous = nil
        end
    end

    addon.UI.Initialize({
        db = db,
        character = character,
        tracker = tracker,
        capabilities = {
            position = true,
        },
        getCurrentLevel = function()
            return 42
        end,
    })

    return {
        addon = addon,
        environment = environment,
        created = created,
        calls = calls,
        character = character,
        db = db,
        tracker = tracker,
        strataAttempts = strataAttempts,
    }
end

testlib.case("ui creation is lazy idempotent and uses requested native structure", function()
    local harness = newUIHarness()

    testlib.equal(#harness.created, 0)
    local first = harness.addon.UI.Create()
    local createdCount = #harness.created
    local second = harness.addon.UI.Create()

    testlib.equal(first, second)
    testlib.equal(#harness.created, createdCount)
    testlib.equal(first.template, "BasicFrameTemplateWithInset")
    testlib.equal(first.strata, "FULLSCREEN_DIALOG")
    testlib.equal(first.movable, true)
    testlib.equal(first.mouseEnabled, true)
    testlib.equal(first.dragButton, "LeftButton")
    testlib.equal(type(first.scripts.OnDragStart), "function")
    testlib.equal(type(first.scripts.OnDragStop), "function")
    testlib.equal(#harness.addon.UI.summaryGroups, 3)
    testlib.equal(harness.addon.UI.resetButton.template, "UIPanelButtonTemplate")
    testlib.equal(harness.addon.UI.settingsButton.template, "UIPanelButtonTemplate")
    testlib.equal(harness.addon.UI.settingsPanel:IsShown(), false)
    testlib.truthy(
        harness.addon.UI.settingsPanel:GetFrameLevel() > first:GetFrameLevel()
    )
    testlib.equal(
        harness.addon.UI.overviewTab.template,
        "PanelTabButtonTemplate"
    )
    testlib.equal(
        harness.addon.UI.levelTab.template,
        "PanelTabButtonTemplate"
    )

    first.scripts.OnDragStart(first)
    first.scripts.OnDragStop(first)
    testlib.equal(first.startedMoving, true)
    testlib.equal(first.stoppedMoving, true)
end)

testlib.case("ui settings button toggles a compact panel", function()
    local harness = newUIHarness()
    harness.addon.UI.Create()

    testlib.equal(harness.addon.UI.settingsPanel:IsShown(), false)
    harness.addon.UI.settingsButton.scripts.OnClick()
    testlib.equal(harness.addon.UI.settingsPanel:IsShown(), true)
    harness.addon.UI.settingsButton.scripts.OnClick()
    testlib.equal(harness.addon.UI.settingsPanel:IsShown(), false)
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

testlib.case("ui falls back when the main template is rejected", function()
    local noTemplate = newUIHarness({
        rejectMainTemplate = true,
    })
    local templateFrame = noTemplate.addon.UI.Create()
    testlib.equal(templateFrame.template, nil)
    testlib.truthy(noTemplate.addon.UI.closeButton ~= nil)
end)

testlib.case("ui selects the highest accepted non-tooltip strata", function()
    local cases = {
        {
            rejected = {},
            expected = "FULLSCREEN_DIALOG",
            attempts = 1,
        },
        {
            rejected = {
                FULLSCREEN_DIALOG = true,
            },
            expected = "FULLSCREEN",
            attempts = 2,
        },
        {
            rejected = {
                FULLSCREEN_DIALOG = true,
                FULLSCREEN = true,
            },
            expected = "DIALOG",
            attempts = 3,
        },
        {
            rejected = {
                FULLSCREEN_DIALOG = true,
                FULLSCREEN = true,
                DIALOG = true,
            },
            expected = "HIGH",
            attempts = 4,
        },
    }

    for _, case in ipairs(cases) do
        local harness = newUIHarness({
            rejectStrata = case.rejected,
        })
        local frame = harness.addon.UI.Create()
        testlib.equal(frame.strata, case.expected)
        testlib.equal(#harness.strataAttempts, case.attempts)
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
    testlib.equal(harness.addon.UI.levelTab.buttonState, "PUSHED")

    harness.addon.UI.overviewTab.scripts.OnClick()
    testlib.equal(harness.addon.UI.overviewPanel:IsShown(), true)
    testlib.equal(harness.addon.UI.levelPanel:IsShown(), false)
    testlib.equal(harness.addon.UI.overviewTab.selected, true)
    testlib.equal(harness.addon.UI.levelTab.selected, false)
end)

testlib.case("ui native tabs fall back safely when modern template is unavailable", function()
    local safeFallback = newUIHarness({
        rejectTemplates = {
            PanelTabButtonTemplate = true,
        },
        noPanelTemplates = true,
    })
    local succeeded = pcall(safeFallback.addon.UI.Create)
    testlib.equal(succeeded, true)
    testlib.equal(safeFallback.addon.UI.overviewTab.template, nil)
    testlib.equal(safeFallback.addon.UI.levelTab.template, nil)
    testlib.equal(safeFallback.addon.UI.overviewTab.buttonState, "PUSHED")
end)

testlib.case("ui native tab selection tolerates a missing select helper", function()
    local harness = newUIHarness({
        missingSelectTabHelper = true,
    })
    harness.addon.UI.Create()

    testlib.equal(harness.addon.UI.overviewTab.buttonState, "PUSHED")
    testlib.equal(harness.addon.UI.levelTab.buttonState, "NORMAL")
end)

testlib.case("ui bare fallback tabs expose visible labels and selection colors", function()
    local harness = newUIHarness({
        rejectTemplates = {
            PanelTabButtonTemplate = true,
        },
    })
    harness.addon.UI.Create()

    local overviewLabel = harness.addon.UI.overviewTab.fallbackLabel
    local levelLabel = harness.addon.UI.levelTab.fallbackLabel
    testlib.truthy(overviewLabel ~= nil)
    testlib.truthy(levelLabel ~= nil)
    testlib.equal(overviewLabel:GetText(), "Overview")
    testlib.equal(levelLabel:GetText(), "By Level")
    testlib.equal(overviewLabel:IsShown(), true)
    testlib.equal(levelLabel:IsShown(), true)
    testlib.equal(overviewLabel.textColor[1], 1)
    testlib.equal(levelLabel.textColor[1], 0.6)

    harness.addon.UI.levelTab.scripts.OnClick()
    testlib.equal(overviewLabel.textColor[1], 0.6)
    testlib.equal(levelLabel.textColor[1], 1)
end)

testlib.case("ui refresh consumes overview levels and diagnostics models", function()
    local harness = newUIHarness()
    harness.addon.UI.Create()

    harness.addon.UI.Refresh()

    testlib.equal(harness.calls.overview, 1)
    testlib.equal(harness.calls.rows, 1)
    testlib.equal(harness.calls.diagnostics, 1)
    testlib.truthy(
        contains(harness.addon.UI.summaryGroups[1].value:GetText(), "Estimated steps: 100")
    )
    testlib.truthy(
        contains(harness.addon.UI.summaryGroups[2].value:GetText(), "On foot: 100 m")
    )
    testlib.truthy(
        contains(harness.addon.UI.summaryGroups[3].value:GetText(), "Flight path: 70 m")
    )
    testlib.truthy(contains(harness.addon.UI.levelRows[1]:GetText(), "Level 42"))
    testlib.truthy(contains(harness.addon.UI.diagnosticsText:GetText(), "alpha: 2"))
    testlib.equal(harness.addon.UI.errorText:IsShown(), false)
end)

testlib.case("ui level list exposes every row through scrollable content", function()
    local rows = {}
    for level = 15, 1, -1 do
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

    testlib.equal(#harness.addon.UI.levelRows, 15)
    testlib.truthy(contains(
        harness.addon.UI.levelRows[15]:GetText(),
        "Level 1"
    ))
    testlib.equal(
        harness.addon.UI.levelRows[15].parent,
        harness.addon.UI.levelScrollChild
    )
    testlib.equal(harness.addon.UI.levelScrollChild.height, 300)
    testlib.truthy(
        harness.addon.UI.levelScrollFrame:GetVerticalScrollRange() > 0
    )
end)

testlib.case("ui errors are visible before and after creation", function()
    local harness = newUIHarness()

    harness.addon.UI.ShowError("before create")
    harness.addon.UI.Create()
    testlib.equal(harness.addon.UI.errorText:GetText(), "before create")
    testlib.equal(harness.addon.UI.errorText:IsShown(), true)

    harness.addon.UI.ShowError("after create")
    testlib.equal(harness.addon.UI.errorText:GetText(), "after create")
    testlib.equal(harness.addon.UI.errorText:IsShown(), true)

    local refreshFailure = newUIHarness({
        overviewError = "invalidStatistics",
    })
    refreshFailure.addon.UI.Create()
    refreshFailure.addon.UI.Refresh()
    testlib.equal(refreshFailure.addon.UI.errorText:IsShown(), true)
    testlib.truthy(
        contains(refreshFailure.addon.UI.errorText:GetText(), "invalidStatistics")
    )
end)

testlib.case("ui confirmation resets only the session after acceptance", function()
    local harness = newUIHarness()
    harness.addon.UI.Create()

    harness.addon.UI.ConfirmResetSession()
    testlib.equal(
        harness.environment.shownPopup,
        "AZEROTH_TRAVEL_TRACKER_RESET_SESSION"
    )
    testlib.equal(harness.calls.reset, 0)

    local dialog = harness.environment.StaticPopupDialogs[
        "AZEROTH_TRAVEL_TRACKER_RESET_SESSION"
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
        "AZEROTH_TRAVEL_TRACKER_RESET_SESSION"
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
        "AZEROTH_TRAVEL_TRACKER_RESET_SESSION"
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
        "AZEROTH_TRAVEL_TRACKER_RESET_SESSION"
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
        "AZEROTH_TRAVEL_TRACKER_RESET_SESSION"
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
        "AZEROTH_TRAVEL_TRACKER_RESET_SESSION"
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
    testlib.equal(
        harness.environment.shownPopup,
        "AZEROTH_TRAVEL_TRACKER_RESET_SESSION"
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
        "AZEROTH_TRAVEL_TRACKER_RESET_SESSION"
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
        .. "AzerothTravelTracker"
        .. separator
        .. "AzerothTravelTracker.toc"
    local toc = assert(io.open(tocPath, "r"))

    local files = {}
    for line in toc:lines() do
        if line:match("%.lua%s*$") then
            table.insert(files, line)
            local relativePath = line:gsub("[\\/]", separator)
            local filePath = projectDirectory
                .. separator
                .. "AzerothTravelTracker"
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
    local uiIndex
    local coreIndex
    for index, fileName in ipairs(files) do
        if fileName == "UI.lua" then
            uiIndex = index
        elseif fileName == "Minimap.lua" then
            minimapIndex = index
        elseif fileName == "Core.lua" then
            coreIndex = index
        end
    end
    testlib.truthy(uiIndex ~= nil, "UI.lua missing from TOC")
    testlib.truthy(minimapIndex ~= nil, "Minimap.lua missing from TOC")
    testlib.truthy(coreIndex ~= nil, "Core.lua missing from TOC")
    testlib.truthy(uiIndex < minimapIndex, "Minimap.lua must load after UI.lua")
    testlib.truthy(minimapIndex < coreIndex, "Minimap.lua must load before Core.lua")
end)
