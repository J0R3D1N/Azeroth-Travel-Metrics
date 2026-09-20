local addonName, ATT = ...

ATT.Core = {}

local Core = ATT.Core

local CAPABILITY_KEYS = {
    "position",
    "map",
    "time",
    "taxi",
    "swimming",
    "mounted",
    "grounded",
}

local CATEGORY_CAPABILITY_KEYS = {
    "taxiReady",
    "swimmingReady",
    "onFootReady",
}

local REPORTABLE_REASONS = {
    capabilitiesUnavailable = true,
    emitFailed = true,
    identityUnavailable = true,
    levelUnavailable = true,
    mapUnavailable = true,
    positionUnavailable = true,
    sampleFailed = true,
    sampleUnavailable = true,
    timeUnavailable = true,
    unsupportedState = true,
}

local state = {
    initialized = false,
    ready = false,
    db = nil,
    character = nil,
    tracker = nil,
    currentLevel = nil,
    capabilities = {},
    ticker = nil,
    reportedReasons = {},
    retryIdentity = false,
}

local function isFinitePositiveInteger(value)
    return type(value) == "number"
        and value == value
        and value > 0
        and value < math.huge
        and value % 1 == 0
end

local function safeText(value)
    local succeeded, text = pcall(tostring, value)
    if succeeded then
        return text
    end
    return "unknownError"
end

local function printMessage(message)
    if ATT.Compat and type(ATT.Compat.Print) == "function" then
        pcall(ATT.Compat.Print, "[Azeroth Travel Tracker] " .. message)
    end
end

local function showError(message)
    if ATT.UI and type(ATT.UI.ShowError) == "function" then
        pcall(ATT.UI.ShowError, message)
    end
end

function Core.ReportOnce(reason, message, displayInWindow)
    reason = reason or "unknownError"
    if state.reportedReasons[reason] then
        return false
    end

    state.reportedReasons[reason] = true
    message = message or ("Tracking unavailable: " .. safeText(reason))
    printMessage(message)

    if displayInWindow then
        showError(message)
    end

    return true
end

function Core.StopTicker()
    if state.ticker ~= nil then
        if type(state.ticker.Cancel) == "function" then
            pcall(state.ticker.Cancel, state.ticker)
        end
        state.ticker = nil
    end
end

local function failInitialization(reason, retryIdentity)
    Core.StopTicker()
    state.ready = false
    state.db = nil
    state.character = nil
    state.tracker = nil
    state.currentLevel = nil
    state.retryIdentity = retryIdentity == true
    state.initialized = not state.retryIdentity
    Core.ReportOnce(
        reason,
        "Initialization failed: " .. safeText(reason),
        true
    )
end

local function readCapabilities()
    if not ATT.Compat or type(ATT.Compat.GetCapabilities) ~= "function" then
        Core.ReportOnce("capabilitiesUnavailable")
        return {}
    end

    local succeeded, capabilities = pcall(ATT.Compat.GetCapabilities)
    if not succeeded or type(capabilities) ~= "table" then
        Core.ReportOnce("capabilitiesUnavailable")
        return {}
    end

    return capabilities
end

local function refreshCapabilities()
    local capabilities = readCapabilities()

    for key in pairs(state.capabilities) do
        state.capabilities[key] = nil
    end
    for key, value in pairs(capabilities) do
        state.capabilities[key] = value
    end
end

function Core.Initialize()
    if state.initialized then
        return state.ready
    end

    if not ATT.Storage or type(ATT.Storage.Initialize) ~= "function" then
        failInitialization("storageUnavailable")
        return false
    end

    local savedDB = AzerothTravelTrackerDB
    local initializeCallSucceeded, db, initializationError = pcall(
        ATT.Storage.Initialize,
        savedDB
    )
    if not initializeCallSucceeded then
        failInitialization("storageInitializeFailed")
        return false
    end
    if db == nil or initializationError ~= nil then
        failInitialization(initializationError or "storageInitializeFailed")
        return false
    end

    if not ATT.Compat
        or type(ATT.Compat.GetCharacterIdentity) ~= "function"
    then
        failInitialization("identityUnavailable")
        return false
    end

    local identityCallSucceeded, identity, identityError = pcall(
        ATT.Compat.GetCharacterIdentity
    )
    if not identityCallSucceeded or type(identity) ~= "table" then
        failInitialization(identityError or "identityUnavailable", true)
        return false
    end

    local characterKey = identity.name .. "-" .. identity.realm
    local characterCallSucceeded, character = pcall(
        ATT.Storage.GetCharacter,
        db,
        characterKey,
        identity
    )
    if not characterCallSucceeded or type(character) ~= "table" then
        failInitialization("characterInitializeFailed")
        return false
    end

    local trackerCallSucceeded, tracker = pcall(ATT.Tracker.New, {
        compat = ATT.Compat,
        storage = ATT.Storage,
        movement = ATT.Movement,
        character = character,
        level = identity.level,
        emit = function(eventName, payload)
            return ATT.Emit(eventName, payload)
        end,
    })
    if not trackerCallSucceeded or type(tracker) ~= "table" then
        failInitialization("trackerInitializeFailed")
        return false
    end

    state.db = db
    state.character = character
    state.tracker = tracker
    state.currentLevel = identity.level
    state.retryIdentity = false
    refreshCapabilities()

    if not ATT.UI or type(ATT.UI.Initialize) ~= "function" then
        failInitialization("uiUnavailable")
        return false
    end

    local uiCallSucceeded = pcall(ATT.UI.Initialize, {
        db = db,
        character = character,
        tracker = tracker,
        capabilities = state.capabilities,
        getCurrentLevel = function()
            return state.currentLevel
        end,
    })
    if not uiCallSucceeded then
        failInitialization("uiInitializeFailed")
        return false
    end

    AzerothTravelTrackerDB = db
    state.initialized = true
    state.ready = true
    return true
end

local function sample()
    if not state.ready or state.tracker == nil then
        return
    end

    local succeeded, segment, reason = pcall(
        state.tracker.Sample,
        state.tracker
    )
    if not succeeded then
        Core.ReportOnce("sampleFailed")
        return
    end

    if reason ~= nil and REPORTABLE_REASONS[reason] then
        Core.ReportOnce(reason)
    end

    if segment ~= nil
        and ATT.UI
        and type(ATT.UI.IsShown) == "function"
        and ATT.UI.IsShown()
        and type(ATT.UI.Refresh) == "function"
    then
        ATT.UI.Refresh()
    end
end

function Core.StartTicker()
    if not state.ready or state.tracker == nil then
        return false
    end

    if type(state.tracker.ResetBaseline) == "function" then
        state.tracker:ResetBaseline()
    end

    Core.StopTicker()

    if type(C_Timer) ~= "table"
        or type(C_Timer.NewTicker) ~= "function"
    then
        Core.ReportOnce("tickerUnavailable", nil, true)
        return false
    end

    local succeeded, ticker = pcall(
        C_Timer.NewTicker,
        ATT.SAMPLE_INTERVAL_SECONDS,
        sample
    )
    if not succeeded or type(ticker) ~= "table" then
        Core.ReportOnce("tickerUnavailable", nil, true)
        return false
    end

    state.ticker = ticker
    return true
end

local function refreshUI()
    if ATT.UI and type(ATT.UI.Refresh) == "function" then
        ATT.UI.Refresh()
    end
end

local function handleLevelUp(newLevel)
    if not state.ready then
        return
    end

    if not isFinitePositiveInteger(newLevel) then
        Core.ReportOnce(
            "invalidLevel",
            "Level update failed: invalidLevel",
            true
        )
        return
    end

    local timeCallSucceeded, now, timeError = pcall(ATT.Compat.GetNow)
    if not timeCallSucceeded or not isFinitePositiveInteger(now) then
        Core.ReportOnce(
            timeError or "timeUnavailable",
            "Level update failed: " .. safeText(timeError or "timeUnavailable"),
            true
        )
        return
    end

    local succeeded, updated, updateError = pcall(
        state.tracker.SetLevel,
        state.tracker,
        newLevel,
        now
    )
    if not succeeded or not updated then
        Core.ReportOnce(
            updateError or "levelUpdateFailed",
            "Level update failed: " .. safeText(updateError or "levelUpdateFailed"),
            true
        )
        return
    end

    state.currentLevel = newLevel
    refreshUI()
end

local function printStatus()
    local capabilities = state.capabilities or {}
    local lowLevel = {}
    local categories = {}

    for _, key in ipairs(CAPABILITY_KEYS) do
        table.insert(lowLevel, key .. "=" .. tostring(capabilities[key] == true))
    end
    for _, key in ipairs(CATEGORY_CAPABILITY_KEYS) do
        table.insert(categories, key .. "=" .. tostring(capabilities[key] == true))
    end

    printMessage("Capabilities: " .. table.concat(lowLevel, ", "))
    printMessage("Categories: " .. table.concat(categories, ", "))

    local diagnostics = {}
    for reason, count in pairs(state.character.diagnostics or {}) do
        if type(reason) == "string"
            and type(count) == "number"
            and count > 0
        then
            table.insert(diagnostics, {
                reason = reason,
                count = count,
            })
        end
    end
    table.sort(diagnostics, function(left, right)
        return left.reason < right.reason
    end)

    if #diagnostics == 0 then
        printMessage("Diagnostics: none")
        return
    end

    for _, diagnostic in ipairs(diagnostics) do
        printMessage(
            "Diagnostic: "
                .. diagnostic.reason
                .. "="
                .. tostring(diagnostic.count)
        )
    end
end

local function usage()
    printMessage(
        "Usage: /att [show | reset session | units metric|imperial"
            .. " | diagnostics on|off | status]"
    )
end

function Core.HandleSlashCommand(message)
    if not state.ready then
        printMessage("Azeroth Travel Tracker is not ready.")
        return
    end

    message = type(message) == "string" and message or ""
    message = message:lower():match("^%s*(.-)%s*$")

    if message == "" or message == "show" then
        ATT.UI.Toggle()
        return
    end

    if message == "reset session" then
        ATT.UI.ConfirmResetSession()
        return
    end

    local units = message:match("^units%s+(%S+)$")
    if units ~= nil then
        if units ~= "metric" and units ~= "imperial" then
            usage()
            return
        end
        state.db.settings.units = units
        refreshUI()
        return
    end

    local diagnostics = message:match("^diagnostics%s+(%S+)$")
    if diagnostics ~= nil then
        if diagnostics ~= "on" and diagnostics ~= "off" then
            usage()
            return
        end
        state.db.settings.showDiagnostics = diagnostics == "on"
        refreshUI()
        return
    end

    if message == "status" then
        printStatus()
        return
    end

    usage()
end

function Core.OnEvent(eventName, ...)
    if eventName == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            Core.Initialize()
        end
    elseif eventName == "PLAYER_ENTERING_WORLD" then
        if not state.ready and state.retryIdentity then
            Core.Initialize()
        end
        if state.ready then
            refreshCapabilities()
            Core.StartTicker()
        end
    elseif eventName == "PLAYER_LEVEL_UP" then
        handleLevelUp(...)
    elseif eventName == "PLAYER_LOGOUT" then
        Core.StopTicker()
    end
end

function Core.GetState()
    return state
end

local eventFrame = CreateFrame("Frame")
Core.eventFrame = eventFrame

for _, eventName in ipairs({
    "ADDON_LOADED",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LEVEL_UP",
    "PLAYER_LOGOUT",
}) do
    eventFrame:RegisterEvent(eventName)
end

eventFrame:SetScript("OnEvent", function(_, eventName, ...)
    Core.OnEvent(eventName, ...)
end)

SLASH_AZEROTHTRAVELTRACKER1 = "/att"
SLASH_AZEROTHTRAVELTRACKER2 = "/azerothtraveltracker"
SlashCmdList = SlashCmdList or {}
SlashCmdList.AZEROTHTRAVELTRACKER = function(message)
    Core.HandleSlashCommand(message)
end
