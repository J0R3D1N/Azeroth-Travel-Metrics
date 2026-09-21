local _, ATT = ...

local Theme = {
    Icons = {
        PORTRAIT = "Interface\\Icons\\INV_Misc_Map_01",
        TITLE = "Interface\\Icons\\Ability_Rogue_Sprint",
        OVERVIEW = "Interface\\Icons\\INV_Misc_Map_01",
        LEVELS = "Interface\\Icons\\INV_Misc_Book_09",
        SETTINGS = "Interface\\Icons\\INV_Misc_Gear_01",
    },
    Atlases = {
        SECTION = "UI-Character-Info-Title",
        ROW = "UI-Character-Info-Line-Bounce",
        ROW_ALTERNATE = "UI-Character-Info-Line-Bounce2",
        INSET = "common-insideframe",
    },
}

ATT.UITheme = Theme

local SIDE_TAB_SIZE = 50
local SECTION_HEADER_HEIGHT = 20
local SECTION_ROW_HEIGHT = 16
local SHELL_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {
        left = 4,
        right = 4,
        top = 4,
        bottom = 4,
    },
}

local function setTooltip(frame, text)
    frame:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end

        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if type(GameTooltip.SetText) == "function" then
            GameTooltip:SetText(text)
        elseif type(GameTooltip.AddLine) == "function" then
            GameTooltip:AddLine(text)
        end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
end

local function createColorTexture(parent, layer, red, green, blue, alpha)
    local texture = parent:CreateTexture(nil, layer)
    texture:SetAllPoints(parent)
    texture:SetColorTexture(red, green, blue, alpha)
    return texture
end

local function createFallbackBorder(parent)
    local border = {}
    local edges = {
        { "TOPLEFT", "TOPRIGHT", "horizontal" },
        { "BOTTOMLEFT", "BOTTOMRIGHT", "horizontal" },
        { "TOPLEFT", "BOTTOMLEFT", "vertical" },
        { "TOPRIGHT", "BOTTOMRIGHT", "vertical" },
    }

    for _, edge in ipairs(edges) do
        local texture = parent:CreateTexture(nil, "BORDER")
        texture:SetPoint(edge[1], parent, edge[1], 0, 0)
        texture:SetPoint(edge[2], parent, edge[2], 0, 0)
        if edge[3] == "horizontal" then
            texture:SetHeight(1)
        else
            texture:SetWidth(1)
        end
        texture:SetColorTexture(0.67, 0.53, 0.27, 0.96)
        table.insert(border, texture)
    end

    return border
end

function Theme.ApplyWindowShell(frame, useBackdrop)
    local shell = {}
    local backdropApplied = false

    if useBackdrop and type(frame.SetBackdrop) == "function" then
        local backdropSucceeded, backdropAccepted = pcall(
            frame.SetBackdrop,
            frame,
            SHELL_BACKDROP
        )
        if backdropSucceeded
            and backdropAccepted ~= false
            and type(frame.SetBackdropColor) == "function"
        then
            local colorSucceeded, colorAccepted = pcall(
                frame.SetBackdropColor,
                frame,
                0.08,
                0.06,
                0.035,
                0.95
            )
            backdropApplied = colorSucceeded and colorAccepted ~= false
            if backdropApplied
                and type(frame.SetBackdropBorderColor) == "function"
            then
                pcall(
                    frame.SetBackdropBorderColor,
                    frame,
                    0.67,
                    0.53,
                    0.27,
                    0.96
                )
            end
        end
    end

    if not backdropApplied then
        shell.fallbackBackground = createColorTexture(
            frame,
            "BACKGROUND",
            0.08,
            0.06,
            0.035,
            0.95
        )
        shell.fallbackBorder = createFallbackBorder(frame)
    end

    shell.darkTexture = frame:CreateTexture(nil, "BACKGROUND")
    shell.darkTexture:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -7)
    shell.darkTexture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -7, 7)
    shell.darkTexture:SetTexture(
        "Interface\\DialogFrame\\UI-DialogBox-Background-Dark"
    )
    shell.darkTexture:SetVertexColor(0.86, 0.64, 0.20, 0.26)

    shell.goldTexture = frame:CreateTexture(nil, "BACKGROUND")
    shell.goldTexture:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    shell.goldTexture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    shell.goldTexture:SetTexture(
        "Interface\\DialogFrame\\UI-DialogBox-Gold-Background"
    )
    shell.goldTexture:SetVertexColor(0.80, 0.58, 0.18, 0.08)

    shell.vignette = frame:CreateTexture(nil, "BORDER")
    shell.vignette:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    shell.vignette:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    local gradientApplied = false
    if type(shell.vignette.SetGradientAlpha) == "function" then
        local gradientSucceeded, gradientAccepted = pcall(
            shell.vignette.SetGradientAlpha,
            shell.vignette,
            "VERTICAL",
            0.02, 0.01, 0.00, 0.16,
            0.00, 0.00, 0.00, 0.03
        )
        gradientApplied = gradientSucceeded and gradientAccepted ~= false
    end
    if not gradientApplied then
        shell.vignette:SetColorTexture(0.02, 0.01, 0.00, 0.16)
    end

    shell.topGlow = frame:CreateTexture(nil, "BORDER")
    shell.topGlow:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
    shell.topGlow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -8)
    shell.topGlow:SetHeight(28)
    shell.topGlow:SetColorTexture(0.95, 0.72, 0.22, 0.14)

    shell.titleSeparator = frame:CreateTexture(nil, "BORDER")
    shell.titleSeparator:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -52)
    shell.titleSeparator:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -52)
    shell.titleSeparator:SetHeight(1)
    shell.titleSeparator:SetColorTexture(0.88, 0.69, 0.24, 0.22)

    return shell
end

local function createSelectedBorder(parent)
    local border = {
        BorderTextures = {},
        color = { 1, 0.82, 0, 0.9 },
        shown = true,
    }
    local edges = {
        { "TOPLEFT", "TOPRIGHT", SIDE_TAB_SIZE, 2 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", SIDE_TAB_SIZE, 2 },
        { "TOPLEFT", "BOTTOMLEFT", 2, SIDE_TAB_SIZE - 4 },
        { "TOPRIGHT", "BOTTOMRIGHT", 2, SIDE_TAB_SIZE - 4 },
    }

    for _, edge in ipairs(edges) do
        local texture = parent:CreateTexture(nil, "OVERLAY")
        texture:SetColorTexture(1, 0.82, 0, 0.9)
        texture:SetSize(edge[3], edge[4])
        texture:SetPoint(edge[1], parent, edge[1], 0, 0)
        texture:SetPoint(edge[2], parent, edge[2], 0, 0)
        table.insert(border.BorderTextures, texture)
    end

    function border:Show()
        self.shown = true
        for _, texture in ipairs(self.BorderTextures) do
            texture:Show()
        end
    end

    function border:Hide()
        self.shown = false
        for _, texture in ipairs(self.BorderTextures) do
            texture:Hide()
        end
    end

    border:Hide()
    return border
end

function Theme.SetAtlasOrColor(texture, atlas, red, green, blue, alpha)
    if texture and type(texture.SetAtlas) == "function" then
        local succeeded, accepted = pcall(texture.SetAtlas, texture, atlas, true)
        if succeeded and accepted ~= false then
            return true
        end
    end

    if texture and type(texture.SetColorTexture) == "function" then
        texture:SetColorTexture(red, green, blue, alpha)
    end
    return false
end

function Theme.CreateInset(parent)
    local inset = parent:CreateTexture(nil, "BACKGROUND")
    inset:SetAllPoints(parent)
    Theme.SetAtlasOrColor(inset, Theme.Atlases.INSET, 0.08, 0.05, 0.03, 0.95)
    return inset
end

function Theme.CreateFramedIcon(parent, texturePath, size)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)

    local background = createColorTexture(
        frame,
        "BACKGROUND",
        0.20,
        0.11,
        0.035,
        0.98
    )

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
    icon:SetTexture(texturePath)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Show()

    local border = {}
    local edges = {
        { "TOPLEFT", "TOPRIGHT", size, 2 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", size, 2 },
        { "TOPLEFT", "BOTTOMLEFT", 2, size },
        { "TOPRIGHT", "BOTTOMRIGHT", 2, size },
    }
    for _, edge in ipairs(edges) do
        local line = frame:CreateTexture(nil, "OVERLAY")
        line:SetColorTexture(0.82, 0.58, 0.22, 1)
        line:SetSize(edge[3], edge[4])
        line:SetPoint(edge[1], frame, edge[1], 0, 0)
        line:SetPoint(edge[2], frame, edge[2], 0, 0)
        table.insert(border, line)
    end

    frame:Show()
    return frame, icon, background, border
end

function Theme.CreateSideTab(name, parent, options)
    options = options or {}

    local created, tab = pcall(
        CreateFrame,
        "Button",
        name,
        parent,
        "LargeSideTabButtonTemplate"
    )
    local nativeTemplate = created and tab ~= nil
    if not nativeTemplate then
        tab = CreateFrame("Button", name, parent)
        tab:SetSize(SIDE_TAB_SIZE, SIDE_TAB_SIZE)
    end

    if not tab.Icon then
        tab.Icon = tab:CreateTexture(nil, "ARTWORK")
    end
    tab.Icon:SetTexture(options.icon)
    if not nativeTemplate then
        tab.Icon:SetSize(32, 32)
        tab.Icon:SetPoint("CENTER", tab, "CENTER", 0, 0)
    end

    if not tab.SelectedTexture then
        tab.SelectedTexture = createSelectedBorder(tab)
    end
    tab.SelectedTexture:Hide()

    if not nativeTemplate then
        tab.Background = createColorTexture(
            tab,
            "BACKGROUND",
            0.18,
            0.10,
            0.04,
            0.95
        )
        tab.HighlightTexture = createColorTexture(
            tab,
            "HIGHLIGHT",
            1,
            0.72,
            0.18,
            0.25
        )
    end

    setTooltip(tab, options.tooltip or "")
    return tab
end

function Theme.SetSideTabSelected(tab, selected)
    tab.selected = selected == true
    if not tab.SelectedTexture then
        return
    end

    if tab.selected then
        tab.SelectedTexture:Show()
    else
        tab.SelectedTexture:Hide()
    end
end

function Theme.CreateSection(parent, title, rowCount, options)
    rowCount = rowCount or 4
    options = options or {}

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(1, SECTION_HEADER_HEIGHT + (rowCount * SECTION_ROW_HEIGHT))

    local header = frame:CreateTexture(nil, "BACKGROUND")
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    header:SetHeight(SECTION_HEADER_HEIGHT)
    Theme.SetAtlasOrColor(header, Theme.Atlases.SECTION, 0.24, 0.13, 0.05, 1)

    local titleText = frame:CreateFontString(
        nil,
        "ARTWORK",
        "GameFontNormalSmall"
    )
    titleText:SetPoint("LEFT", header, "LEFT", 13, 0)
    titleText:SetPoint("RIGHT", header, "RIGHT", -13, 0)
    titleText:SetJustifyH("CENTER")
    titleText:SetJustifyV("MIDDLE")
    if type(titleText.SetWordWrap) == "function" then
        titleText:SetWordWrap(false)
    end
    if type(titleText.SetNonSpaceWrap) == "function" then
        titleText:SetNonSpaceWrap(false)
    end
    if type(titleText.SetMaxLines) == "function" then
        titleText:SetMaxLines(1)
    end
    titleText:SetText(title)

    local section = {
        frame = frame,
        header = header,
        title = titleText,
        rows = {},
    }

    local previous = header
    for index = 1, rowCount do
        local rowFrame = CreateFrame("Frame", nil, frame)
        rowFrame:SetHeight(SECTION_ROW_HEIGHT)
        rowFrame:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, 0)
        rowFrame:SetPoint("TOPRIGHT", previous, "BOTTOMRIGHT", 0, 0)

        local background = rowFrame:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(rowFrame)
        Theme.SetAtlasOrColor(
            background,
            Theme.Atlases.ROW,
            0.12,
            0.075,
            0.035,
            index % 2 == 0 and 0.82 or 0.68
        )

        local label = rowFrame:CreateFontString(
            nil,
            "ARTWORK",
            "GameFontNormalSmall"
        )
        label:SetPoint("LEFT", rowFrame, "LEFT", 8, 0)
        label:SetTextColor(1, 0.82, 0, 1)

        local value = rowFrame:CreateFontString(
            nil,
            "ARTWORK",
            "GameFontHighlightSmall"
        )
        value:SetPoint("RIGHT", rowFrame, "RIGHT", -8, 0)
        value:SetTextColor(1, 1, 1, 1)
        value:SetJustifyH("RIGHT")

        local row = {
            frame = rowFrame,
            background = background,
            label = label,
            value = value,
        }
        table.insert(section.rows, row)

        if index == options.footerIndex then
            label:SetTextColor(1, 0.82, 0, 1)
            value:SetTextColor(1, 0.82, 0, 1)

            local separator = rowFrame:CreateTexture(nil, "OVERLAY")
            separator:SetHeight(1)
            separator:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", 4, 0)
            separator:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -4, 0)
            separator:SetColorTexture(0.72, 0.43, 0.16, 0.95)

            row.separator = separator
            section.footer = row
        end
        previous = rowFrame
    end

    return section
end

function Theme.SetSectionValues(section, values)
    values = values or {}
    for index, row in ipairs(section.rows) do
        local rowValues = values[index] or {}
        row.label:SetText(rowValues.label or "")
        row.value:SetText(rowValues.value or "")
    end
end

function Theme.CreateIconButton(parent, icon, tooltip)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(24, 24)

    button.Background = createColorTexture(
        button,
        "BACKGROUND",
        0.18,
        0.10,
        0.04,
        0.95
    )
    button.HighlightTexture = createColorTexture(
        button,
        "HIGHLIGHT",
        1,
        0.72,
        0.18,
        0.28
    )
    button.Icon = button:CreateTexture(nil, "ARTWORK")
    button.Icon:SetTexture(icon)
    button.Icon:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
    button.Icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -3, 3)

    setTooltip(button, tooltip or "")
    return button
end
