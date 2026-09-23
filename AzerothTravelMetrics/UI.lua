local addonName, ATM = ...

ATM.UI = {}

local UI = ATM.UI
local RESET_DIALOG_KEY = "AZEROTH_TRAVEL_METRICS_RESET_SESSION"
local SECTION_HEIGHT = 100
local SECTION_GAP = 10
local SUMMARY_CONTENT_HEIGHT = (SECTION_HEIGHT * 3) + (SECTION_GAP * 2)
local DIAGNOSTICS_GAP = 4
local DIAGNOSTICS_VIEW_HEIGHT = 22
local DIAGNOSTICS_LINE_HEIGHT = 12
local DIAGNOSTICS_CONTENT_WIDTH = 348
local LEVEL_CARD_HEIGHT = 104
local LEVEL_CARD_GAP = 10
local LEVEL_VIEW_HEIGHT = 282
local LEVEL_PANEL_WIDTH = 376
local LEVEL_CONTENT_WIDTH = 348
local LEVEL_SCROLLBAR_GAP = 4
local LEVEL_SCROLLBAR_TOP_INSET = 14
local LEVEL_SCROLLBAR_BOTTOM_INSET = 16
local MAIN_FRAME_LEVEL = 100
local HUD_REST_ALPHA = 0.45
local HUD_HOVER_ALPHA = 0.92
local HUD_WIDTH = 220
local HUD_HEIGHT = 96
local SUMMARY_ROWS = {
    { key = "steps", label = "Estimated Steps" },
    { key = "onFoot", label = "On Foot" },
    { key = "swimming", label = "Swimming" },
    { key = "taxi", label = "Flight Path" },
    { key = "total", label = "Total Distance", footer = true },
}
local SUMMARY_DEFINITIONS = {
    { key = "lifetime", title = "Lifetime" },
    { key = "session", title = "This Session" },
    { key = "currentLevel", title = "Current Level" },
}
local VALID_FRAME_POINTS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local context
local pendingError
local activeTab = "overview"

local function safeSetFrameStrata(frame)
    local strataOptions = {
        "MEDIUM",
        "HIGH",
        "DIALOG",
    }

    for _, strata in ipairs(strataOptions) do
        local succeeded = pcall(frame.SetFrameStrata, frame, strata)
        if succeeded then
            return strata
        end
    end

    return nil
end

local function registerEscapeFrame(frameName)
    if type(UISpecialFrames) ~= "table" then
        return false
    end

    local succeeded = pcall(function()
        for _, registeredName in pairs(UISpecialFrames) do
            if registeredName == frameName then
                return
            end
        end
        table.insert(UISpecialFrames, frameName)
    end)
    return succeeded
end

local function createMainFrame()
    local portraitSucceeded, portraitFrame = pcall(
        CreateFrame,
        "Frame",
        "AzerothTravelMetricsFrame",
        UIParent,
        "PortraitFrameBaseTemplate"
    )
    if portraitSucceeded and portraitFrame then
        return portraitFrame, false, true
    end

    local succeeded, frame = pcall(
        CreateFrame,
        "Frame",
        "AzerothTravelMetricsFrame",
        UIParent,
        "BackdropTemplate"
    )
    if succeeded and frame then
        return frame, true, false
    end

    return CreateFrame(
        "Frame",
        "AzerothTravelMetricsFrame",
        UIParent
    ), false, false
end

local function createLabel(parent, text, font)
    local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
    label:SetText(text)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("TOP")
    return label
end

local function trimNonblank(value)
    if type(value) ~= "string" then
        return nil
    end

    local trimmed = value:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end
    return trimmed
end

local function getVersion()
    local getter
    if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
        getter = C_AddOns.GetAddOnMetadata
    elseif type(GetAddOnMetadata) == "function" then
        getter = GetAddOnMetadata
    end

    if getter then
        local succeeded, value = pcall(getter, addonName, "Version")
        if succeeded then
            local version = trimNonblank(value)
            if version then
                return version
            end
        end
    end

    return ATM.VERSION_FALLBACK
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

local function setPanelVisibility()
    if not UI.frame then
        return
    end

    local hasError = pendingError ~= nil
    if UI.errorPanel then
        if hasError then
            UI.errorPanel:Show()
        else
            UI.errorPanel:Hide()
        end
    end

    if hasError then
        UI.overviewPanel:Hide()
        UI.levelPanel:Hide()
    elseif activeTab == "levels" then
        UI.overviewPanel:Hide()
        UI.levelPanel:Show()
    else
        UI.levelPanel:Hide()
        UI.overviewPanel:Show()
    end

    if activeTab == "levels" then
        ATM.UITheme.SetTopTabSelected(UI.overviewTab, false)
        ATM.UITheme.SetTopTabSelected(UI.levelTab, true)
    else
        ATM.UITheme.SetTopTabSelected(UI.levelTab, false)
        ATM.UITheme.SetTopTabSelected(UI.overviewTab, true)
    end
end

local function showModelError(reason)
    UI.ShowError("Statistics unavailable: " .. tostring(reason or "unknownError"))
end

local function sectionValues(summary)
    local values = {}
    for index, definition in ipairs(SUMMARY_ROWS) do
        local value = summary[definition.key]
        values[index] = {
            label = definition.label,
            value = value == nil and "" or tostring(value),
        }
    end
    return values
end

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function getHUDPosition()
    local settings = context and context.db and context.db.settings
    if settings
        and VALID_FRAME_POINTS[settings.hudPoint]
        and isFiniteNumber(settings.hudX)
        and isFiniteNumber(settings.hudY)
    then
        return settings.hudPoint, settings.hudX, settings.hudY
    end
    return "CENTER", 0, 0
end

local function saveHUDPosition(frame)
    local settings = context and context.db and context.db.settings
    if not settings or type(frame.GetPoint) ~= "function" then
        return
    end

    local succeeded, point, _, _, x, y = pcall(frame.GetPoint, frame)
    if not succeeded
        or not VALID_FRAME_POINTS[point]
        or not isFiniteNumber(x)
        or not isFiniteNumber(y)
    then
        return
    end

    settings.hudPoint = point
    settings.hudX = x
    settings.hudY = y
end

local function createColorTexture(parent, layer, red, green, blue, alpha)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetAllPoints(parent)
    texture:SetColorTexture(red, green, blue, alpha)
    return texture
end

local function raiseAboveParent(frame, parent, amount)
    if type(frame.SetFrameLevel) == "function"
        and type(parent.GetFrameLevel) == "function"
    then
        frame:SetFrameLevel(parent:GetFrameLevel() + (amount or 10))
    end
end

local function createSafeButton(
    parent,
    template,
    width,
    height,
    text,
    fallbackText
)
    local succeeded, button = pcall(
        CreateFrame,
        "Button",
        nil,
        parent,
        template
    )
    if succeeded and button then
        button:SetSize(width, height)
        if text then
            button:SetText(text)
        end
        return button
    end

    button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button.Background = createColorTexture(
        button,
        "BACKGROUND",
        0.18,
        0.10,
        0.04,
        0.98
    )
    button.Highlight = createColorTexture(
        button,
        "HIGHLIGHT",
        0.42,
        0.24,
        0.08,
        0.75
    )
    button.Border = {}
    local edges = {
        { "TOPLEFT", "TOPRIGHT", width, 1 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", width, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, height },
        { "TOPRIGHT", "BOTTOMRIGHT", 1, height },
    }
    for _, edge in ipairs(edges) do
        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetColorTexture(0.82, 0.58, 0.22, 1)
        border:SetSize(edge[3], edge[4])
        border:SetPoint(edge[1], button, edge[1], 0, 0)
        border:SetPoint(edge[2], button, edge[2], 0, 0)
        table.insert(button.Border, border)
    end

    local visibleText = fallbackText or text
    if visibleText then
        button:SetText(visibleText)
        button.FallbackText = createLabel(
            button,
            visibleText,
            "GameFontHighlightSmall"
        )
        button.FallbackText:SetPoint("CENTER", button, "CENTER", 0, 0)
        button.FallbackText:SetTextColor(1, 0.82, 0, 1)
    end
    button:Show()
    return button
end

local function setHUDHovering(hovering)
    if not UI.hud then
        return
    end

    UI.hud.frame:SetAlpha(hovering and HUD_HOVER_ALPHA or HUD_REST_ALPHA)
    if hovering then
        UI.hud.restoreControl:Show()
        UI.hud.restoreButton:Show()
        UI.hud.closeButton:Show()
    else
        UI.hud.restoreControl:Hide()
        UI.hud.restoreButton:Hide()
        UI.hud.closeButton:Hide()
    end
end

local function isMouseOver(region)
    if not region or type(region.IsMouseOver) ~= "function" then
        return false
    end

    local succeeded, hovered = pcall(region.IsMouseOver, region)
    return succeeded and hovered == true
end

local function updateHUDHover()
    if not UI.hud then
        return
    end

    setHUDHovering(
        isMouseOver(UI.hud.frame)
            or isMouseOver(UI.hud.restoreControl)
            or isMouseOver(UI.hud.restoreButton)
            or isMouseOver(UI.hud.closeButton)
    )
end

local function composeScript(frame, scriptName, callback)
    if type(frame.HookScript) == "function" then
        local succeeded, accepted = pcall(
            frame.HookScript,
            frame,
            scriptName,
            callback
        )
        if succeeded and accepted ~= false then
            return
        end
    end

    local previous
    if type(frame.GetScript) == "function" then
        local succeeded, existing = pcall(
            frame.GetScript,
            frame,
            scriptName
        )
        if succeeded then
            previous = existing
        end
    end

    frame:SetScript(scriptName, function(...)
        if previous then
            previous(...)
        end
        callback(...)
    end)
end

local function createHUDCell(parent, index, labelText, iconTexture)
    local cell = CreateFrame("Frame", nil, parent)
    cell:SetSize(104, 29)

    local column = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    cell:SetPoint(
        "TOPLEFT",
        parent,
        "TOPLEFT",
        4 + (column * 106),
        -29 - (row * 31)
    )

    cell.background = createColorTexture(
        cell,
        "BACKGROUND",
        0.12,
        0.065,
        0.025,
        0.72
    )
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetTexture(iconTexture)
    cell.icon:SetSize(18, 18)
    cell.icon:SetPoint("LEFT", cell, "LEFT", 4, 0)
    cell.label = createLabel(cell, labelText, "GameFontNormalSmall")
    cell.label:SetPoint("TOPLEFT", cell, "TOPLEFT", 26, -3)
    cell.label:SetTextColor(1, 0.82, 0, 1)
    cell.value = createLabel(cell, "", "GameFontHighlightSmall")
    cell.value:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -5, 3)
    cell.value:SetTextColor(1, 1, 1, 1)
    cell.value:SetJustifyH("RIGHT")
    return cell
end

local function createHUD()
    if UI.hud then
        return UI.hud
    end

    local frame = CreateFrame(
        "Frame",
        "AzerothTravelMetricsHUD",
        UIParent
    )
    frame:SetSize(HUD_WIDTH, HUD_HEIGHT)
    local point, x, y = getHUDPosition()
    frame:SetPoint(point, UIParent, point, x, y)
    safeSetFrameStrata(frame)
    frame:SetFrameLevel(MAIN_FRAME_LEVEL)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetAlpha(HUD_REST_ALPHA)

    local background = createColorTexture(
        frame,
        "BACKGROUND",
        0.16,
        0.085,
        0.035,
        0.94
    )
    local border = {}
    local edges = {
        { "TOPLEFT", "TOPRIGHT", HUD_WIDTH, 2 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", HUD_WIDTH, 2 },
        { "TOPLEFT", "BOTTOMLEFT", 2, HUD_HEIGHT - 4 },
        { "TOPRIGHT", "BOTTOMRIGHT", 2, HUD_HEIGHT - 4 },
    }
    for _, edge in ipairs(edges) do
        local texture = frame:CreateTexture(nil, "OVERLAY")
        texture:SetColorTexture(0.72, 0.43, 0.16, 0.95)
        texture:SetSize(edge[3], edge[4])
        texture:SetPoint(edge[1], frame, edge[1], 0, 0)
        texture:SetPoint(edge[2], frame, edge[2], 0, 0)
        table.insert(border, texture)
    end

    local title = createLabel(frame, "Session", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -7)
    title:SetTextColor(1, 0.82, 0, 1)

    local cells = {
        createHUDCell(
            frame,
            1,
            "Steps",
            ATM.UITheme.Icons.TITLE
        ),
        createHUDCell(
            frame,
            2,
            "On Foot",
            "Interface\\Icons\\INV_Boots_05"
        ),
        createHUDCell(
            frame,
            3,
            "Swimming",
            "Interface\\Icons\\Ability_Druid_AquaticForm"
        ),
        createHUDCell(
            frame,
            4,
            "Flight Path",
            "Interface\\Icons\\Ability_Mount_Wyvern_01"
        ),
    }

    local closeButton = createSafeButton(
        frame,
        "UIPanelCloseButton",
        20,
        20,
        nil,
        "x"
    )
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    raiseAboveParent(closeButton, frame, 20)
    closeButton:SetScript("OnClick", function()
        UI.CloseHUD()
    end)
    closeButton:SetScript("OnEnter", function()
        setHUDHovering(true)
    end)
    closeButton:SetScript("OnLeave", updateHUDHover)
    closeButton:Hide()

    local restoreControl, restoreButton =
        ATM.UITheme.CreateWindowSizeControl(
            frame,
            "restore",
            "Restore"
        )
    restoreControl:SetPoint("RIGHT", closeButton, "LEFT", -2, 0)
    raiseAboveParent(restoreControl, frame, 20)
    restoreButton:SetScript("OnClick", function()
        UI.ShowMain()
    end)
    composeScript(restoreButton, "OnEnter", function()
        setHUDHovering(true)
    end)
    composeScript(restoreButton, "OnLeave", updateHUDHover)
    restoreControl:Hide()
    restoreButton:Hide()

    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveHUDPosition(self)
    end)
    frame:SetScript("OnEnter", function()
        setHUDHovering(true)
    end)
    frame:SetScript("OnLeave", updateHUDHover)

    UI.hud = {
        frame = frame,
        background = background,
        border = border,
        title = title,
        cells = cells,
        restoreControl = restoreControl,
        restoreButton = restoreButton,
        closeButton = closeButton,
    }
    frame:Hide()
    return UI.hud
end

local function refreshHUD(session)
    if not UI.hud then
        return
    end

    local values = {
        session.steps,
        session.onFoot,
        session.swimming,
        session.taxi,
    }
    for index, value in ipairs(values) do
        UI.hud.cells[index].value:SetText(tostring(value))
    end
end

local function setRegionShown(region, shown)
    if not region then
        return
    end

    local method = shown and region.Show or region.Hide
    if type(method) == "function" then
        pcall(method, region)
    end
end

local function collectLevelScrollbarChrome(scrollFrame)
    if scrollFrame.levelScrollbarChrome then
        return scrollFrame.levelScrollbarChrome
    end

    local chrome = {
        regions = {},
    }
    local seen = {}
    local function addRegion(region)
        if region and not seen[region] then
            seen[region] = true
            table.insert(chrome.regions, region)
        end
        return region
    end
    local function getField(region, field)
        if not region then
            return nil
        end
        local succeeded, value = pcall(function()
            return region[field]
        end)
        if succeeded then
            return value
        end
        return nil
    end
    local function getRegionName(region)
        if not region or type(region.GetName) ~= "function" then
            return nil
        end
        local succeeded, value = pcall(region.GetName, region)
        if succeeded and type(value) == "string" then
            return value
        end
        return nil
    end
    local function addScrollBar(scrollBar)
        if not scrollBar then
            return
        end
        addRegion(scrollBar)
        addRegion(getField(scrollBar, "ScrollUpButton"))
        addRegion(getField(scrollBar, "ScrollDownButton"))
        addRegion(getField(scrollBar, "ThumbTexture"))
    end

    chrome.scrollBar = addRegion(getField(scrollFrame, "ScrollBar"))

    local frameName
    if type(scrollFrame.GetName) == "function" then
        local succeeded, value = pcall(scrollFrame.GetName, scrollFrame)
        if succeeded and type(value) == "string" and value ~= "" then
            frameName = value
        end
    end
    if not chrome.scrollBar and frameName and type(_G) == "table" then
        chrome.scrollBar = addRegion(_G[frameName .. "ScrollBar"])
    end

    if type(scrollFrame.GetChildren) == "function" then
        local children = {
            pcall(scrollFrame.GetChildren, scrollFrame),
        }
        if children[1] then
            for index = 2, #children do
                local child = children[index]
                local childName = getRegionName(child)
                local hasScrollbarPieces =
                    getField(child, "ScrollUpButton")
                    or getField(child, "ScrollDownButton")
                    or getField(child, "ThumbTexture")
                if not chrome.scrollBar
                    and (hasScrollbarPieces
                        or (frameName
                            and childName == frameName .. "ScrollBar"))
                then
                    chrome.scrollBar = child
                end
            end
        end
    end

    addScrollBar(chrome.scrollBar)

    if frameName and type(_G) == "table" then
        local scrollBarName = frameName .. "ScrollBar"
        addRegion(_G[scrollBarName .. "ScrollUpButton"])
        addRegion(_G[scrollBarName .. "ScrollDownButton"])
        addRegion(_G[scrollBarName .. "ThumbTexture"])
    end

    scrollFrame.levelScrollbarChrome = chrome
    return chrome
end

local function getVerticalScrollRange(scrollFrame)
    if not scrollFrame
        or type(scrollFrame.GetVerticalScrollRange) ~= "function"
    then
        return nil
    end

    local succeeded, value = pcall(
        scrollFrame.GetVerticalScrollRange,
        scrollFrame
    )
    if succeeded and isFiniteNumber(value) and value >= 0 then
        return value
    end
    return nil
end

local function updateLevelScrollbar()
    local scrollFrame = UI.levelScrollFrame
    if not scrollFrame then
        return
    end

    local scrollRange = getVerticalScrollRange(scrollFrame)
    local chrome = collectLevelScrollbarChrome(scrollFrame)
    for _, region in ipairs(chrome.regions) do
        setRegionShown(region, scrollRange ~= nil and scrollRange > 0)
    end

    if scrollRange == nil
        or type(scrollFrame.GetVerticalScroll) ~= "function"
        or type(scrollFrame.SetVerticalScroll) ~= "function"
    then
        return
    end

    local succeeded, current = pcall(
        scrollFrame.GetVerticalScroll,
        scrollFrame
    )
    if succeeded
        and isFiniteNumber(current)
        and current > scrollRange
    then
        pcall(scrollFrame.SetVerticalScroll, scrollFrame, scrollRange)
    end
end

local function ensureLevelRows(count)
    while #UI.levelRows < count do
        local index = #UI.levelRows + 1
        local card = ATM.UITheme.CreateSection(
            UI.levelScrollChild,
            "",
            #SUMMARY_ROWS,
            { footerIndex = #SUMMARY_ROWS }
        )
        card.frame:SetHeight(LEVEL_CARD_HEIGHT)
        local topOffset = (index - 1)
            * (LEVEL_CARD_HEIGHT + LEVEL_CARD_GAP)
        card.frame:SetPoint(
            "TOPLEFT",
            UI.levelScrollChild,
            "TOPLEFT",
            0,
            -topOffset
        )
        card.frame:SetWidth(LEVEL_CONTENT_WIDTH)
        ATM.UITheme.SetSectionValues(card, sectionValues({}))
        card.frame:Hide()
        table.insert(UI.levelRows, card)
    end
end

function UI.Initialize(initialContext)
    context = initialContext
end

function UI.Create()
    if UI.frame then
        return UI.frame
    end

    local frame, useBackdrop, nativePortrait = createMainFrame()
    UI.frame = frame
    registerEscapeFrame("AzerothTravelMetricsFrame")
    frame:SetSize(420, 470)
    frame:SetPoint("CENTER")
    safeSetFrameStrata(frame)
    frame:SetFrameLevel(MAIN_FRAME_LEVEL)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    if nativePortrait then
        UI.shell = {}
    else
        UI.shell = ATM.UITheme.ApplyWindowShell(frame, useBackdrop)
    end

    UI.titleRegion = CreateFrame("Frame", nil, frame)
    UI.titleRegion:SetSize(404, 28)
    UI.titleRegion:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    raiseAboveParent(UI.titleRegion, frame, 20)
    UI.titleRegion:Show()

    if nativePortrait then
        UI.title = frame.TitleText
        UI.closeButton = frame.CloseButton
        UI.titleIcon = frame.PortraitContainer
            and frame.PortraitContainer.portrait
        if UI.titleIcon then
            if type(UI.titleIcon.SetTexture) == "function" then
                pcall(
                    UI.titleIcon.SetTexture,
                    UI.titleIcon,
                    ATM.UITheme.Icons.TITLE
                )
            end
        end
    else
        UI.titleIconFrame,
            UI.titleIcon,
            UI.titleIconBackground,
            UI.titleIconBorder = ATM.UITheme.CreateFramedIcon(
                UI.titleRegion,
                ATM.UITheme.Icons.TITLE,
                28
            )
        UI.titleIconFrame:SetPoint("LEFT", UI.titleRegion, "LEFT", 4, 0)
        raiseAboveParent(UI.titleIconFrame, UI.titleRegion, 2)
        UI.closeButton = createSafeButton(
            UI.titleRegion,
            "UIPanelCloseButton",
            24,
            24,
            nil,
            "x"
        )
        UI.closeButton:SetPoint("RIGHT", UI.titleRegion, "RIGHT", -2, 0)
    end
    raiseAboveParent(UI.closeButton, UI.titleRegion, 3)
    UI.closeButton:Show()
    UI.closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    if not UI.title then
        UI.title = createLabel(
            UI.titleRegion,
            "Azeroth Travel Metrics",
            "GameFontNormal"
        )
        UI.title:SetPoint("LEFT", UI.titleIconFrame, "RIGHT", 10, 0)
        UI.title:SetPoint("RIGHT", UI.titleRegion, "RIGHT", -58, 0)
    end
    UI.title:SetJustifyH("LEFT")
    UI.title:SetJustifyV("MIDDLE")
    UI.title:SetTextColor(1, 0.82, 0.32, 1)
    UI.title:SetText("Azeroth Travel Metrics")

    UI.minimizeControl, UI.minimizeButton =
        ATM.UITheme.CreateWindowSizeControl(
            UI.titleRegion,
            "minimize",
            "Minimize"
        )
    UI.minimizeControl:SetPoint(
        "RIGHT",
        UI.closeButton,
        "LEFT",
        -1,
        0
    )
    raiseAboveParent(UI.minimizeControl, UI.titleRegion, 3)
    UI.minimizeControl:Show()
    UI.minimizeButton:Show()
    UI.minimizeButton:SetScript("OnClick", function()
        UI.Minimize()
    end)

    UI.overviewTab = ATM.UITheme.CreateTopTab(
        "AzerothTravelMetricsFrameOverviewTab",
        frame,
        {
            icon = ATM.UITheme.Icons.OVERVIEW,
            tooltip = "Overview",
        }
    )
    UI.overviewTab:SetPoint("TOPLEFT", frame, "TOPLEFT", 152, -36)
    UI.overviewTab:Show()
    UI.overviewTab:SetScript("OnClick", function()
        activeTab = "overview"
        setPanelVisibility()
    end)

    UI.levelTab = ATM.UITheme.CreateTopTab(
        "AzerothTravelMetricsFrameLevelTab",
        frame,
        {
            icon = ATM.UITheme.Icons.LEVELS,
            tooltip = "By Level",
        }
    )
    UI.levelTab:SetPoint("LEFT", UI.overviewTab, "RIGHT", 6, 0)
    UI.levelTab:Show()
    UI.levelTab:SetScript("OnClick", function()
        activeTab = "levels"
        setPanelVisibility()
    end)

    UI.resetButton = createSafeButton(
        frame,
        "UIPanelButtonTemplate",
        96,
        22,
        "Reset Session"
    )
    UI.resetButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 12)
    UI.resetButton:SetScript("OnClick", function()
        UI.ConfirmResetSession()
    end)

    UI.versionLabel = createLabel(
        frame,
        "ATM v" .. getVersion(),
        "GameFontDisableSmall"
    )
    UI.versionLabel:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -18,
        13
    )
    UI.versionLabel:SetWidth(160)
    UI.versionLabel:SetJustifyH("RIGHT")
    UI.versionLabel:SetJustifyV("BOTTOM")
    UI.versionLabel:SetTextColor(0.58, 0.50, 0.38, 1)

    UI.settingsButton = ATM.UITheme.CreateIconButton(
        frame,
        ATM.UITheme.Icons.SETTINGS,
        "Settings"
    )
    UI.settingsButton:SetPoint(
        "RIGHT",
        UI.versionLabel,
        "LEFT",
        -8,
        0
    )
    raiseAboveParent(UI.settingsButton, frame, 20)

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
    settingsPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 64)
    if type(settingsPanel.SetFrameStrata) == "function" then
        pcall(settingsPanel.SetFrameStrata, settingsPanel, "DIALOG")
    end
    if type(settingsPanel.SetFrameLevel) == "function"
        and type(frame.GetFrameLevel) == "function"
    then
        settingsPanel:SetFrameLevel(frame:GetFrameLevel() + 100)
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
        if ATM.Minimap
            and type(ATM.Minimap.UpdateVisibility) == "function"
        then
            ATM.Minimap.UpdateVisibility()
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

    UI.contentFrame = CreateFrame("Frame", nil, frame)
    UI.contentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -76)
    UI.contentFrame:SetSize(388, 382)
    UI.parchmentPage = ATM.UITheme.CreateParchmentPage(UI.contentFrame)

    UI.errorPanel = CreateFrame("Frame", nil, UI.contentFrame)
    UI.errorPanel:SetPoint(
        "TOPLEFT",
        UI.contentFrame,
        "TOPLEFT",
        6,
        -8
    )
    UI.errorPanel:SetSize(376, 374)
    UI.errorInset = ATM.UITheme.CreateInset(UI.errorPanel)

    UI.errorText = createLabel(
        UI.errorPanel,
        "",
        "GameFontHighlight"
    )
    UI.errorText:SetPoint("TOPLEFT", UI.errorPanel, "TOPLEFT", 14, -14)
    UI.errorText:SetWidth(348)
    UI.errorText:SetTextColor(1, 0.25, 0.25)
    UI.errorText:Hide()
    UI.errorPanel:Hide()

    UI.overviewPanel = CreateFrame("Frame", nil, UI.contentFrame)
    UI.overviewPanel:SetPoint("TOPLEFT", UI.contentFrame, "TOPLEFT", 6, -8)
    UI.overviewPanel:SetSize(376, SUMMARY_CONTENT_HEIGHT)

    UI.summarySections = {}
    for index, definition in ipairs(SUMMARY_DEFINITIONS) do
        local section = ATM.UITheme.CreateSection(
            UI.overviewPanel,
            definition.title,
            #SUMMARY_ROWS,
            { footerIndex = #SUMMARY_ROWS }
        )
        section.key = definition.key
        section.frame:SetWidth(376)
        if index == 1 then
            section.frame:SetPoint(
                "TOPLEFT",
                UI.overviewPanel,
                "TOPLEFT",
                0,
                0
            )
        else
            section.frame:SetPoint(
                "TOPLEFT",
                UI.summarySections[index - 1].frame,
                "BOTTOMLEFT",
                0,
                -SECTION_GAP
            )
        end
        ATM.UITheme.SetSectionValues(section, sectionValues({}))
        table.insert(UI.summarySections, section)
    end

    local diagnosticsScrollFrame = CreateFrame(
        "ScrollFrame",
        nil,
        UI.overviewPanel
    )
    UI.diagnosticsScrollFrame = diagnosticsScrollFrame
    diagnosticsScrollFrame:SetPoint(
        "TOPLEFT",
        UI.overviewPanel,
        "TOPLEFT",
        0,
        -(SUMMARY_CONTENT_HEIGHT + DIAGNOSTICS_GAP)
    )
    diagnosticsScrollFrame:SetSize(376, DIAGNOSTICS_VIEW_HEIGHT)
    diagnosticsScrollFrame:EnableMouseWheel(true)

    UI.diagnosticsScrollChild = CreateFrame(
        "Frame",
        nil,
        diagnosticsScrollFrame
    )
    UI.diagnosticsScrollChild:SetSize(
        DIAGNOSTICS_CONTENT_WIDTH,
        DIAGNOSTICS_VIEW_HEIGHT
    )
    diagnosticsScrollFrame:SetScrollChild(UI.diagnosticsScrollChild)
    diagnosticsScrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = 0
        if type(self.GetVerticalScroll) == "function" then
            current = self:GetVerticalScroll()
        end
        local scrollRange = self:GetVerticalScrollRange()
        self:SetVerticalScroll(math.max(
            0,
            math.min(
                scrollRange,
                current - (delta * DIAGNOSTICS_LINE_HEIGHT * 2)
            )
        ))
    end)

    UI.diagnosticsText = createLabel(
        UI.diagnosticsScrollChild,
        "",
        "GameFontDisableSmall"
    )
    UI.diagnosticsText:SetPoint(
        "TOPLEFT",
        UI.diagnosticsScrollChild,
        "TOPLEFT",
        0,
        0
    )
    UI.diagnosticsText:SetWidth(DIAGNOSTICS_CONTENT_WIDTH)
    UI.diagnosticsText:Hide()
    diagnosticsScrollFrame:Hide()

    UI.levelPanel = CreateFrame("Frame", nil, UI.contentFrame)
    UI.levelPanel:SetPoint("TOPLEFT", UI.contentFrame, "TOPLEFT", 6, -8)
    UI.levelPanel:SetSize(LEVEL_PANEL_WIDTH, 310)
    UI.levelHeadingSection = ATM.UITheme.CreateSection(
        UI.levelPanel,
        "Travel by Level",
        0
    )
    UI.levelHeadingSection.frame:SetPoint(
        "TOPLEFT",
        UI.levelPanel,
        "TOPLEFT",
        0,
        0
    )
    UI.levelHeadingSection.frame:SetWidth(LEVEL_PANEL_WIDTH)
    UI.levelHeader = UI.levelHeadingSection.title

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
        -28
    )
    levelScrollFrame:SetSize(LEVEL_CONTENT_WIDTH, LEVEL_VIEW_HEIGHT)
    levelScrollFrame:EnableMouseWheel(true)

    local scrollbarChrome = collectLevelScrollbarChrome(levelScrollFrame)
    if scrollbarChrome.scrollBar then
        local scrollBar = scrollbarChrome.scrollBar
        if type(scrollBar.ClearAllPoints) == "function" then
            pcall(scrollBar.ClearAllPoints, scrollBar)
        end
        if type(scrollBar.SetPoint) == "function" then
            pcall(
                scrollBar.SetPoint,
                scrollBar,
                "TOPLEFT",
                levelScrollFrame,
                "TOPRIGHT",
                LEVEL_SCROLLBAR_GAP,
                -LEVEL_SCROLLBAR_TOP_INSET
            )
            pcall(
                scrollBar.SetPoint,
                scrollBar,
                "BOTTOMLEFT",
                levelScrollFrame,
                "BOTTOMRIGHT",
                LEVEL_SCROLLBAR_GAP,
                LEVEL_SCROLLBAR_BOTTOM_INSET
            )
        end
    end

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
        local scrollRange = getVerticalScrollRange(self) or 0
        self:SetVerticalScroll(math.max(
            0,
            math.min(
                scrollRange,
                current - (delta * 36)
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

    local overview, overviewError = ATM.UIModel.BuildOverview(
        context.character,
        currentLevel,
        units
    )
    if not overview then
        showModelError(overviewError)
        return false
    end

    local levelRows, levelError = ATM.UIModel.BuildLevelRows(
        context.character,
        units
    )
    if not levelRows then
        showModelError(levelError)
        return false
    end

    local diagnostics, diagnosticsError = ATM.UIModel.BuildDiagnostics(
        context.character,
        context.db.settings.showDiagnostics
    )
    if not diagnostics then
        showModelError(diagnosticsError)
        return false
    end

    for index, definition in ipairs(SUMMARY_DEFINITIONS) do
        ATM.UITheme.SetSectionValues(
            UI.summarySections[index],
            sectionValues(overview[definition.key])
        )
    end
    refreshHUD(overview.session)

    ensureLevelRows(#levelRows)
    local levelContentHeight = 0
    if #levelRows > 0 then
        levelContentHeight = (#levelRows * LEVEL_CARD_HEIGHT)
            + ((#levelRows - 1) * LEVEL_CARD_GAP)
    end
    UI.levelScrollChild:SetHeight(math.max(
        LEVEL_VIEW_HEIGHT,
        levelContentHeight
    ))
    updateLevelScrollbar()

    for index, card in ipairs(UI.levelRows) do
        local row = levelRows[index]
        if row then
            card.title:SetText("Level " .. tostring(row.level))
            ATM.UITheme.SetSectionValues(card, sectionValues(row))
            card.frame:Show()
        else
            card.title:SetText("")
            ATM.UITheme.SetSectionValues(card, sectionValues({}))
            card.frame:Hide()
        end
    end

    local diagnosticLines = {}
    for _, diagnostic in ipairs(diagnostics) do
        table.insert(
            diagnosticLines,
            diagnostic.reason .. ": " .. tostring(diagnostic.count)
        )
    end
    local diagnosticsEnabled = context.db
        and context.db.settings
        and context.db.settings.showDiagnostics == true
    if diagnosticsEnabled and #diagnosticLines > 0 then
        UI.diagnosticsText:SetText(table.concat(diagnosticLines, "\n"))
        local contentHeight = #diagnosticLines * DIAGNOSTICS_LINE_HEIGHT
        if type(UI.diagnosticsText.GetStringHeight) == "function" then
            local measured, height = pcall(
                UI.diagnosticsText.GetStringHeight,
                UI.diagnosticsText
            )
            if measured and isFiniteNumber(height) and height > 0 then
                contentHeight = math.ceil(height)
            end
        end
        UI.diagnosticsScrollChild:SetHeight(math.max(
            DIAGNOSTICS_VIEW_HEIGHT,
            contentHeight
        ))
        UI.diagnosticsScrollFrame:SetVerticalScroll(0)
        UI.diagnosticsText:Show()
        UI.diagnosticsScrollFrame:Show()
        UI.overviewPanel:SetHeight(
            SUMMARY_CONTENT_HEIGHT
                + DIAGNOSTICS_GAP
                + DIAGNOSTICS_VIEW_HEIGHT
        )
    else
        UI.diagnosticsText:SetText("")
        UI.diagnosticsText:Hide()
        UI.diagnosticsScrollFrame:SetVerticalScroll(0)
        UI.diagnosticsScrollFrame:Hide()
        UI.diagnosticsScrollChild:SetHeight(DIAGNOSTICS_VIEW_HEIGHT)
        UI.overviewPanel:SetHeight(SUMMARY_CONTENT_HEIGHT)
    end

    pendingError = nil
    UI.errorText:SetText("")
    UI.errorText:Hide()
    setPanelVisibility()
    return true
end

function UI.Toggle()
    UI.Create()
    if UI.IsShown() then
        UI.frame:Hide()
        if UI.hud then
            UI.hud.frame:Hide()
        end
    else
        UI.ShowMain()
    end
end

function UI.IsShown()
    return (UI.frame ~= nil and UI.frame:IsShown())
        or (UI.hud ~= nil and UI.hud.frame:IsShown())
end

function UI.Minimize()
    local frame = UI.Create()
    local hud = createHUD()
    frame:Hide()
    UI.Refresh()
    setHUDHovering(false)
    hud.frame:Show()
end

function UI.ShowMain()
    local frame = UI.Create()
    if UI.hud then
        setHUDHovering(false)
        UI.hud.frame:Hide()
    end
    UI.Refresh()
    frame:Show()
end

function UI.CloseHUD()
    if UI.hud then
        setHUDHovering(false)
        UI.hud.frame:Hide()
    end
end

function UI.ShowError(message)
    pendingError = tostring(message or "Unknown error")
    if UI.frame then
        UI.errorText:SetText(pendingError)
        UI.errorText:Show()
        setPanelVisibility()
    end
end

local function acceptReset()
    if not context then
        return
    end

    if not ATM.Compat or type(ATM.Compat.GetNow) ~= "function" then
        UI.ShowError("Session reset failed: timeUnavailable")
        return
    end

    local timeCallSucceeded, now, reason = pcall(ATM.Compat.GetNow)
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
        ATM.Storage.ResetSession,
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
