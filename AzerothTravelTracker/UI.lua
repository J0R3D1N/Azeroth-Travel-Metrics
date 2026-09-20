local _, ATT = ...

ATT.UI = {}

local UI = ATT.UI
local RESET_DIALOG_KEY = "AZEROTH_TRAVEL_TRACKER_RESET_SESSION"
local MAX_LEVEL_ROWS = 12

local context
local pendingError
local activeTab = "overview"

local function safeSetFrameStrata(frame)
    local strataOptions = {
        "FULLSCREEN_DIALOG",
        "FULLSCREEN",
        "DIALOG",
        "HIGH",
    }

    for _, strata in ipairs(strataOptions) do
        local succeeded = pcall(frame.SetFrameStrata, frame, strata)
        if succeeded then
            return strata
        end
    end

    return nil
end

local function createMainFrame()
    local succeeded, frame = pcall(
        CreateFrame,
        "Frame",
        "AzerothTravelTrackerFrame",
        UIParent,
        "BasicFrameTemplateWithInset"
    )
    if succeeded then
        return frame
    end

    return CreateFrame(
        "Frame",
        "AzerothTravelTrackerFrame",
        UIParent
    )
end

local function createTab(name, parent)
    local templates = {
        "CharacterFrameTabButtonTemplate",
        "OptionsFrameTabButtonTemplate",
    }

    for _, template in ipairs(templates) do
        local succeeded, tab = pcall(
            CreateFrame,
            "Button",
            name,
            parent,
            template
        )
        if succeeded then
            return tab
        end
    end

    return CreateFrame("Button", name, parent)
end

local function createLabel(parent, text, font)
    local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
    label:SetText(text)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    return label
end

local function setTabSelected(tab, selected)
    local helper
    if selected then
        helper = PanelTemplates_SelectTab
    else
        helper = PanelTemplates_DeselectTab
    end
    if type(helper) == "function" then
        local succeeded = pcall(helper, tab)
        if succeeded then
            return
        end
    end

    if type(tab.SetButtonState) == "function" then
        pcall(
            tab.SetButtonState,
            tab,
            selected and "PUSHED" or "NORMAL",
            selected
        )
    end

    local highlightMethod = selected and tab.LockHighlight or tab.UnlockHighlight
    if type(highlightMethod) == "function" then
        pcall(highlightMethod, tab)
    end
end

local function setPanelVisibility()
    if not UI.frame then
        return
    end

    if activeTab == "levels" then
        UI.overviewPanel:Hide()
        UI.levelPanel:Show()
        setTabSelected(UI.overviewTab, false)
        setTabSelected(UI.levelTab, true)
    else
        UI.levelPanel:Hide()
        UI.overviewPanel:Show()
        setTabSelected(UI.levelTab, false)
        setTabSelected(UI.overviewTab, true)
    end
end

local function summaryText(summary)
    return table.concat({
        "Estimated steps: " .. tostring(summary.steps),
        "On foot: " .. tostring(summary.onFoot),
        "Swimming: " .. tostring(summary.swimming),
        "Flight path: " .. tostring(summary.taxi),
    }, "\n")
end

local function showModelError(reason)
    UI.ShowError("Statistics unavailable: " .. tostring(reason or "unknownError"))
end

function UI.Initialize(initialContext)
    context = initialContext
end

function UI.Create()
    if UI.frame then
        return UI.frame
    end

    local frame = createMainFrame()
    UI.frame = frame
    frame:SetSize(520, 430)
    frame:SetPoint("CENTER")
    safeSetFrameStrata(frame)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    UI.closeButton = frame.CloseButton
    if not UI.closeButton then
        UI.closeButton = CreateFrame(
            "Button",
            nil,
            frame,
            "UIPanelCloseButton"
        )
        UI.closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
        UI.closeButton:SetScript("OnClick", function()
            frame:Hide()
        end)
    end

    UI.title = createLabel(frame, "Azeroth Travel Tracker", "GameFontNormalLarge")
    UI.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -16)

    UI.overviewTab = createTab("AzerothTravelTrackerFrameTab1", frame)
    UI.overviewTab:SetID(1)
    UI.overviewTab:SetSize(110, 24)
    UI.overviewTab:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -46)
    UI.overviewTab:SetText("Overview")
    UI.overviewTab:SetScript("OnClick", function()
        activeTab = "overview"
        setPanelVisibility()
    end)

    UI.levelTab = createTab("AzerothTravelTrackerFrameTab2", frame)
    UI.levelTab:SetID(2)
    UI.levelTab:SetSize(110, 24)
    UI.levelTab:SetPoint("LEFT", UI.overviewTab, "RIGHT", 8, 0)
    UI.levelTab:SetText("By Level")
    UI.levelTab:SetScript("OnClick", function()
        activeTab = "levels"
        setPanelVisibility()
    end)

    if type(PanelTemplates_SetNumTabs) == "function" then
        pcall(PanelTemplates_SetNumTabs, frame, 2)
    end

    UI.resetButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    UI.resetButton:SetSize(120, 24)
    UI.resetButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -46)
    UI.resetButton:SetText("Reset Session")
    UI.resetButton:SetScript("OnClick", function()
        UI.ConfirmResetSession()
    end)

    UI.errorText = createLabel(frame, "", "GameFontHighlight")
    UI.errorText:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -80)
    UI.errorText:SetWidth(484)
    UI.errorText:SetTextColor(1, 0.25, 0.25)
    UI.errorText:Hide()

    UI.overviewPanel = CreateFrame("Frame", nil, frame)
    UI.overviewPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -105)
    UI.overviewPanel:SetSize(484, 245)

    UI.summaryGroups = {}
    local groupDefinitions = {
        {
            key = "lifetime",
            title = "Lifetime",
        },
        {
            key = "session",
            title = "This Session",
        },
        {
            key = "currentLevel",
            title = "Current Level",
        },
    }

    for index, definition in ipairs(groupDefinitions) do
        local group = CreateFrame("Frame", nil, UI.overviewPanel)
        group:SetSize(148, 190)
        if index == 1 then
            group:SetPoint("TOPLEFT", UI.overviewPanel, "TOPLEFT", 0, 0)
        else
            group:SetPoint(
                "LEFT",
                UI.summaryGroups[index - 1],
                "RIGHT",
                20,
                0
            )
        end
        group.key = definition.key
        group.heading = createLabel(group, definition.title, "GameFontNormalLarge")
        group.heading:SetPoint("TOPLEFT", group, "TOPLEFT", 0, 0)
        group.value = createLabel(group, "", "GameFontHighlight")
        group.value:SetPoint("TOPLEFT", group, "TOPLEFT", 0, -32)
        group.value:SetWidth(148)
        table.insert(UI.summaryGroups, group)
    end

    UI.diagnosticsText = createLabel(
        UI.overviewPanel,
        "",
        "GameFontDisableSmall"
    )
    UI.diagnosticsText:SetPoint(
        "TOPLEFT",
        UI.overviewPanel,
        "TOPLEFT",
        0,
        -205
    )
    UI.diagnosticsText:SetWidth(484)

    UI.levelPanel = CreateFrame("Frame", nil, frame)
    UI.levelPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -105)
    UI.levelPanel:SetSize(484, 285)
    UI.levelHeader = createLabel(
        UI.levelPanel,
        "Level  |  Estimated steps  |  On foot  |  Swimming  |  Flight path",
        "GameFontNormal"
    )
    UI.levelHeader:SetPoint("TOPLEFT", UI.levelPanel, "TOPLEFT", 0, 0)

    UI.levelRows = {}
    for index = 1, MAX_LEVEL_ROWS do
        local row = createLabel(UI.levelPanel, "", "GameFontHighlightSmall")
        row:SetPoint(
            "TOPLEFT",
            UI.levelPanel,
            "TOPLEFT",
            0,
            -24 - ((index - 1) * 20)
        )
        row:SetWidth(484)
        row:Hide()
        table.insert(UI.levelRows, row)
    end

    if pendingError then
        UI.errorText:SetText(pendingError)
        UI.errorText:Show()
    end

    setPanelVisibility()
    frame:Hide()
    return frame
end

function UI.Refresh()
    if not context or not UI.frame then
        return false
    end

    local units = context.db
        and context.db.settings
        and context.db.settings.units
        or "metric"
    local currentLevel = context.getCurrentLevel()

    local overview, overviewError = ATT.UIModel.BuildOverview(
        context.character,
        currentLevel,
        units
    )
    if not overview then
        showModelError(overviewError)
        return false
    end

    local levelRows, levelError = ATT.UIModel.BuildLevelRows(
        context.character,
        units
    )
    if not levelRows then
        showModelError(levelError)
        return false
    end

    local diagnostics, diagnosticsError = ATT.UIModel.BuildDiagnostics(
        context.character,
        context.db.settings.showDiagnostics
    )
    if not diagnostics then
        showModelError(diagnosticsError)
        return false
    end

    for _, group in ipairs(UI.summaryGroups) do
        group.value:SetText(summaryText(overview[group.key]))
    end

    for index, rowLabel in ipairs(UI.levelRows) do
        local row = levelRows[index]
        if row then
            rowLabel:SetText(string.format(
                "Level %d  |  %d est.  |  %s  |  %s  |  %s",
                row.level,
                row.steps,
                row.onFoot,
                row.swimming,
                row.taxi
            ))
            rowLabel:Show()
        else
            rowLabel:SetText("")
            rowLabel:Hide()
        end
    end

    local diagnosticLines = {}
    for _, diagnostic in ipairs(diagnostics) do
        table.insert(
            diagnosticLines,
            diagnostic.reason .. ": " .. tostring(diagnostic.count)
        )
    end
    UI.diagnosticsText:SetText(table.concat(diagnosticLines, "  |  "))

    pendingError = nil
    UI.errorText:SetText("")
    UI.errorText:Hide()
    return true
end

function UI.Toggle()
    local frame = UI.Create()
    if frame:IsShown() then
        frame:Hide()
    else
        UI.Refresh()
        frame:Show()
    end
end

function UI.IsShown()
    return UI.frame ~= nil and UI.frame:IsShown()
end

function UI.ShowError(message)
    pendingError = tostring(message or "Unknown error")
    if UI.frame then
        UI.errorText:SetText(pendingError)
        UI.errorText:Show()
    end
end

local function acceptReset()
    if not context then
        return
    end

    if not ATT.Compat or type(ATT.Compat.GetNow) ~= "function" then
        UI.ShowError("Session reset failed: timeUnavailable")
        return
    end

    local timeCallSucceeded, now, reason = pcall(ATT.Compat.GetNow)
    if not timeCallSucceeded then
        UI.ShowError("Session reset failed: " .. tostring(now))
        return
    end
    if not now then
        UI.ShowError(
            "Session reset failed: " .. tostring(reason or "timeUnavailable")
        )
        return
    end

    local resetCallSucceeded, resetResult, resetError = pcall(
        ATT.Storage.ResetSession,
        context.character,
        now
    )
    if not resetCallSucceeded then
        UI.ShowError("Session reset failed: " .. tostring(resetResult))
        return
    end
    if not resetResult then
        UI.ShowError(
            "Session reset failed: " .. tostring(resetError or "resetRejected")
        )
        return
    end

    UI.Refresh()
end

function UI.ConfirmResetSession()
    StaticPopupDialogs[RESET_DIALOG_KEY] = {
        text = "Reset this character's current travel session?",
        button1 = YES,
        button2 = NO,
        OnAccept = acceptReset,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show(RESET_DIALOG_KEY)
end
