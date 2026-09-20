local _, ATT = ...

ATT.UI = {}

local UI = ATT.UI
local RESET_DIALOG_KEY = "AZEROTH_TRAVEL_TRACKER_RESET_SESSION"
local LEVEL_ROW_HEIGHT = 20
local LEVEL_VIEW_HEIGHT = 252
local LEVEL_CONTENT_WIDTH = 456

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

local function createTab(name, parent, text)
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

    local tab = CreateFrame("Button", name, parent)
    local label = tab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("CENTER", tab, "CENTER", 0, 0)
    label:SetText(text)
    label:Show()
    tab.fallbackLabel = label
    return tab
end

local function createLabel(parent, text, font)
    local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
    label:SetText(text)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    return label
end

local function createCheckButton(parent, text)
    local succeeded, checkButton = pcall(
        CreateFrame,
        "CheckButton",
        nil,
        parent,
        "UICheckButtonTemplate"
    )
    if not succeeded then
        checkButton = CreateFrame("CheckButton", nil, parent)
    end

    local label = checkButton.Text
    if not label then
        label = createLabel(checkButton, text, "GameFontHighlight")
        label:SetPoint("LEFT", checkButton, "RIGHT", 2, 0)
    end
    label:SetText(text)
    checkButton.label = label
    return checkButton
end

local function syncSettingsControls()
    if not context or not context.db or not context.db.settings then
        return
    end

    local settings = context.db.settings
    UI.metricCheck:SetChecked(settings.units ~= "imperial")
    UI.imperialCheck:SetChecked(settings.units == "imperial")
    UI.minimapCheck:SetChecked(settings.showMinimap == true)
    UI.diagnosticsCheck:SetChecked(settings.showDiagnostics == true)
end

local function setUnits(units)
    if not context or not context.db or not context.db.settings then
        return
    end

    context.db.settings.units = units
    syncSettingsControls()
    UI.Refresh()
end

local function setFallbackTabColor(tab, selected)
    if not tab.fallbackLabel then
        return
    end

    if selected then
        tab.fallbackLabel:SetTextColor(1, 0.82, 0)
    else
        tab.fallbackLabel:SetTextColor(0.6, 0.6, 0.6)
    end
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
            setFallbackTabColor(tab, selected)
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

    setFallbackTabColor(tab, selected)
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

local function ensureLevelRows(count)
    while #UI.levelRows < count do
        local index = #UI.levelRows + 1
        local row = createLabel(
            UI.levelScrollChild,
            "",
            "GameFontHighlightSmall"
        )
        row:SetPoint(
            "TOPLEFT",
            UI.levelScrollChild,
            "TOPLEFT",
            0,
            -((index - 1) * LEVEL_ROW_HEIGHT)
        )
        row:SetWidth(LEVEL_CONTENT_WIDTH)
        row:Hide()
        table.insert(UI.levelRows, row)
    end
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

    UI.overviewTab = createTab(
        "AzerothTravelTrackerFrameTab1",
        frame,
        "Overview"
    )
    UI.overviewTab:SetID(1)
    UI.overviewTab:SetSize(110, 24)
    UI.overviewTab:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -46)
    UI.overviewTab:SetText("Overview")
    UI.overviewTab:SetScript("OnClick", function()
        activeTab = "overview"
        setPanelVisibility()
    end)

    UI.levelTab = createTab(
        "AzerothTravelTrackerFrameTab2",
        frame,
        "By Level"
    )
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

    UI.settingsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    UI.settingsButton:SetSize(82, 24)
    UI.settingsButton:SetPoint(
        "RIGHT",
        UI.resetButton,
        "LEFT",
        -8,
        0
    )
    UI.settingsButton:SetText("Settings")

    local settingsPanelSucceeded, settingsPanel = pcall(
        CreateFrame,
        "Frame",
        nil,
        frame,
        "InsetFrameTemplate3"
    )
    if not settingsPanelSucceeded then
        settingsPanel = CreateFrame("Frame", nil, frame)
    end
    UI.settingsPanel = settingsPanel
    settingsPanel:SetSize(205, 128)
    settingsPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -18, -76)
    if type(settingsPanel.SetFrameLevel) == "function"
        and type(frame.GetFrameLevel) == "function"
    then
        settingsPanel:SetFrameLevel(frame:GetFrameLevel() + 10)
    end

    UI.settingsHeading = createLabel(
        settingsPanel,
        "Settings",
        "GameFontNormal"
    )
    UI.settingsHeading:SetPoint(
        "TOPLEFT",
        settingsPanel,
        "TOPLEFT",
        12,
        -10
    )

    UI.metricCheck = createCheckButton(settingsPanel, "Metric")
    UI.metricCheck:SetSize(24, 24)
    UI.metricCheck:SetPoint(
        "TOPLEFT",
        settingsPanel,
        "TOPLEFT",
        8,
        -28
    )
    UI.metricCheck:SetScript("OnClick", function()
        setUnits("metric")
    end)

    UI.imperialCheck = createCheckButton(settingsPanel, "Imperial")
    UI.imperialCheck:SetSize(24, 24)
    UI.imperialCheck:SetPoint(
        "LEFT",
        UI.metricCheck,
        "RIGHT",
        68,
        0
    )
    UI.imperialCheck:SetScript("OnClick", function()
        setUnits("imperial")
    end)

    UI.minimapCheck = createCheckButton(settingsPanel, "Show minimap button")
    UI.minimapCheck:SetSize(24, 24)
    UI.minimapCheck:SetPoint(
        "TOPLEFT",
        UI.metricCheck,
        "BOTTOMLEFT",
        0,
        -4
    )
    UI.minimapCheck:SetScript("OnClick", function()
        if not context or not context.db or not context.db.settings then
            return
        end
        context.db.settings.showMinimap = UI.minimapCheck:GetChecked() == true
        if ATT.Minimap
            and type(ATT.Minimap.UpdateVisibility) == "function"
        then
            ATT.Minimap.UpdateVisibility()
        end
    end)

    UI.diagnosticsCheck = createCheckButton(
        settingsPanel,
        "Show diagnostics"
    )
    UI.diagnosticsCheck:SetSize(24, 24)
    UI.diagnosticsCheck:SetPoint(
        "TOPLEFT",
        UI.minimapCheck,
        "BOTTOMLEFT",
        0,
        -2
    )
    UI.diagnosticsCheck:SetScript("OnClick", function()
        if not context or not context.db or not context.db.settings then
            return
        end
        context.db.settings.showDiagnostics =
            UI.diagnosticsCheck:GetChecked() == true
        UI.Refresh()
    end)

    UI.settingsButton:SetScript("OnClick", function()
        if settingsPanel:IsShown() then
            settingsPanel:Hide()
        else
            syncSettingsControls()
            settingsPanel:Show()
        end
    end)
    syncSettingsControls()
    settingsPanel:Hide()

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

    local scrollSucceeded, levelScrollFrame = pcall(
        CreateFrame,
        "ScrollFrame",
        nil,
        UI.levelPanel,
        "UIPanelScrollFrameTemplate"
    )
    if not scrollSucceeded then
        levelScrollFrame = CreateFrame("ScrollFrame", nil, UI.levelPanel)
    end
    UI.levelScrollFrame = levelScrollFrame
    levelScrollFrame:SetPoint(
        "TOPLEFT",
        UI.levelPanel,
        "TOPLEFT",
        0,
        -24
    )
    levelScrollFrame:SetSize(484, LEVEL_VIEW_HEIGHT)
    levelScrollFrame:EnableMouseWheel(true)

    UI.levelScrollChild = CreateFrame("Frame", nil, levelScrollFrame)
    UI.levelScrollChild:SetSize(
        LEVEL_CONTENT_WIDTH,
        LEVEL_VIEW_HEIGHT
    )
    levelScrollFrame:SetScrollChild(UI.levelScrollChild)
    levelScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = 0
        if type(self.GetVerticalScroll) == "function" then
            current = self:GetVerticalScroll()
        end
        local scrollRange = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(
            0,
            math.min(
                scrollRange,
                current - (delta * LEVEL_ROW_HEIGHT)
            )
        ))
    end)

    UI.levelRows = {}

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
    syncSettingsControls()
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

    ensureLevelRows(#levelRows)
    UI.levelScrollChild:SetHeight(math.max(
        LEVEL_VIEW_HEIGHT,
        #levelRows * LEVEL_ROW_HEIGHT
    ))

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

    local baselineResetSucceeded, baselineResetError
    if context.tracker
        and type(context.tracker.ResetBaseline) == "function"
    then
        baselineResetSucceeded, baselineResetError = pcall(
            context.tracker.ResetBaseline,
            context.tracker
        )
    else
        baselineResetSucceeded = false
        baselineResetError = "baselineUnavailable"
    end

    UI.Refresh()
    if not baselineResetSucceeded then
        UI.ShowError(
            "Session reset succeeded, but tracking baseline reset failed: "
                .. tostring(baselineResetError)
        )
    end
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
