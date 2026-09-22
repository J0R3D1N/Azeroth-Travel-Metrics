local addonName, ATM = ...

ATM.Core = {}

local Core = ATM.Core

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
    databaseReady = false,
    ready = false,
    db = nil,
    character = nil,
    tracker = nil,
    currentLevel = nil,
    capabilities = {},
    ticker = nil,
    reportedReasons = {},
    preserveSessionOnStartup = false,
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
    if ATM.Compat and type(ATM.Compat.Print) == "function" then
        pcall(ATM.Compat.Print, "[Azeroth Travel Metrics] " .. message)
    end
end

local function showError(message)
    if ATM.UI and type(ATM.UI.ShowError) == "function" then
        pcall(ATM.UI.ShowError, message)
    end
end

local function getTickerCancel(ticker)
    if ticker == nil then
        return nil
    end

    local succeeded, cancel = pcall(function()
        return ticker.Cancel
    end)
    if succeeded and type(cancel) == "function" then
        return cancel
    end

    return nil
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
        local cancel = getTickerCancel(state.ticker)
        if cancel then
            pcall(cancel, state.ticker)
        end
        state.ticker = nil
    end
end

local function failDatabaseInitialization(reason)
    Core.StopTicker()
    state.databaseReady = false
    state.ready = false
    state.db = nil
    state.character = nil
    state.tracker = nil
    state.currentLevel = nil
    Core.ReportOnce(
        reason,
        "Initialization failed: " .. safeText(reason),
        true
    )
end

local function failRuntimeInitialization(reason)
    Core.StopTicker()
    state.ready = false
    Core.ReportOnce(
        reason,
        "Initialization failed: " .. safeText(reason),
        true
    )
end

local function readCapabilities()
    if not ATM.Compat or type(ATM.Compat.GetCapabilities) ~= "function" then
        Core.ReportOnce("capabilitiesUnavailable")
        return {}
    end

    local succeeded, capabilities = pcall(ATM.Compat.GetCapabilities)
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

function Core.Initialize(allowCreate)
    if state.databaseReady then
        return true
    end
    state.initialized = true

    if not ATM.Storage or type(ATM.Storage.Initialize) ~= "function" then
        failDatabaseInitialization("storageUnavailable")
        return false
    end

    local savedDB = AzerothTravelMetricsDB
    if savedDB == nil and allowCreate ~= true then
        return false
    end

    local initializeCallSucceeded, db, initializationError = pcall(
        ATM.Storage.Initialize,
        savedDB
    )
    if not initializeCallSucceeded then
        failDatabaseInitialization("storageInitializeFailed")
        return false
    end
    if db == nil or initializationError ~= nil then
        failDatabaseInitialization(initializationError or "storageInitializeFailed")
        return false
    end

    state.db = db
    state.databaseReady = true
    AzerothTravelMetricsDB = db
    return true
end

local function initializeRuntime(preserveSession)
    if not state.databaseReady or state.ready then
        return state.ready
    end

    if state.character == nil then
        if not ATM.Compat
            or type(ATM.Compat.GetCharacterIdentity) ~= "function"
        then
            failRuntimeInitialization("identityUnavailable")
            return false
        end

        local identityCallSucceeded, identity, identityError = pcall(
            ATM.Compat.GetCharacterIdentity
        )
        if not identityCallSucceeded
            or type(identity) ~= "table"
            or type(identity.name) ~= "string"
            or identity.name == ""
            or type(identity.realm) ~= "string"
            or identity.realm == ""
            or not isFinitePositiveInteger(identity.level)
            or not isFinitePositiveInteger(identity.now)
        then
            failRuntimeInitialization(identityError or "identityUnavailable")
            return false
        end

        if not ATM.Storage or type(ATM.Storage.GetCharacter) ~= "function" then
            failRuntimeInitialization("characterInitializeFailed")
            return false
        end

        local characterKey = identity.name .. "-" .. identity.realm
        local characterCallSucceeded, character = pcall(
            ATM.Storage.GetCharacter,
            state.db,
            characterKey,
            identity
        )
        if not characterCallSucceeded or type(character) ~= "table" then
            failRuntimeInitialization("characterInitializeFailed")
            return false
        end

        local validSavedSession = false
        if preserveSession
            and type(ATM.Storage.IsValidSession) == "function"
        then
            local validationSucceeded, isValid = pcall(
                ATM.Storage.IsValidSession,
                character.session
            )
            validSavedSession = validationSucceeded and isValid == true
        end

        if not validSavedSession then
            if type(ATM.Storage.StartSession) ~= "function" then
                failRuntimeInitialization("sessionInitializeFailed")
                return false
            end

            local sessionCallSucceeded, session = pcall(
                ATM.Storage.StartSession,
                character,
                identity.now
            )
            if not sessionCallSucceeded or type(session) ~= "table" then
                failRuntimeInitialization("sessionInitializeFailed")
                return false
            end
        end

        state.character = character
        state.currentLevel = identity.level
    end

    if state.tracker == nil then
        if not ATM.Tracker or type(ATM.Tracker.New) ~= "function" then
            failRuntimeInitialization("trackerInitializeFailed")
            return false
        end

        local trackerCallSucceeded, tracker = pcall(ATM.Tracker.New, {
            compat = ATM.Compat,
            storage = ATM.Storage,
            movement = ATM.Movement,
            character = state.character,
            level = state.currentLevel,
            emit = function(eventName, payload)
                return ATM.Emit(eventName, payload)
            end,
        })
        if not trackerCallSucceeded or type(tracker) ~= "table" then
            failRuntimeInitialization("trackerInitializeFailed")
            return false
        end

        state.tracker = tracker
    end

    refreshCapabilities()

    if not ATM.UI or type(ATM.UI.Initialize) ~= "function" then
        failRuntimeInitialization("uiUnavailable")
        return false
    end

    local runtimeContext = {
        db = state.db,
        character = state.character,
        tracker = state.tracker,
        capabilities = state.capabilities,
        getCurrentLevel = function()
            return state.currentLevel
        end,
    }
    local uiCallSucceeded = pcall(ATM.UI.Initialize, runtimeContext)
    if not uiCallSucceeded then
        failRuntimeInitialization("uiInitializeFailed")
        return false
    end

    if ATM.Minimap and type(ATM.Minimap.Initialize) == "function" then
        local minimapCallSucceeded = pcall(
            ATM.Minimap.Initialize,
            runtimeContext
        )
        if not minimapCallSucceeded then
            Core.ReportOnce(
                "minimapInitializeFailed",
                "Minimap launcher unavailable: minimapInitializeFailed",
                true
            )
        end
    end

    state.ready = true
    Core.StartTicker()
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
        and ATM.UI
        and type(ATM.UI.IsShown) == "function"
        and ATM.UI.IsShown()
        and type(ATM.UI.Refresh) == "function"
    then
        ATM.UI.Refresh()
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
        ATM.SAMPLE_INTERVAL_SECONDS,
        sample
    )
    if not succeeded or getTickerCancel(ticker) == nil then
        Core.ReportOnce("tickerUnavailable", nil, true)
        return false
    end

    state.ticker = ticker
    return true
end

local function refreshUI()
    if ATM.UI and type(ATM.UI.Refresh) == "function" then
        ATM.UI.Refresh()
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

    local timeCallSucceeded, now, timeError = pcall(ATM.Compat.GetNow)
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
        "Usage: /atm [show | reset session | units metric|imperial"
            .. " | diagnostics on|off | status]"
    )
end

function Core.HandleSlashCommand(message)
    if not state.ready then
        printMessage("Azeroth Travel Metrics is not ready.")
        return
    end

    message = type(message) == "string" and message or ""
    message = message:lower():match("^%s*(.-)%s*$")

    if message == "" or message == "show" then
        ATM.UI.Toggle()
        return
    end

    if message == "reset session" then
        ATM.UI.ConfirmResetSession()
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
            Core.Initialize(false)
        end
    elseif eventName == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin, isReloadingUi = ...
        if isReloadingUi == true then
            state.preserveSessionOnStartup = true
        elseif isInitialLogin == true then
            state.preserveSessionOnStartup = false
        end
        if not state.databaseReady and not Core.Initialize(true) then
            return
        end
        if not state.ready then
            if initializeRuntime(state.preserveSessionOnStartup) then
                state.preserveSessionOnStartup = false
            end
        else
            refreshCapabilities()
            if state.ticker == nil then
                Core.StartTicker()
            elseif type(state.tracker.ResetBaseline) == "function" then
                pcall(state.tracker.ResetBaseline, state.tracker)
            end
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

SLASH_AZEROTHTRAVELMETRICS1 = "/atm"
if type(SlashCmdList) == "table" then
    SlashCmdList.AZEROTHTRAVELMETRICS = function(message)
        Core.HandleSlashCommand(message)
    end
end
