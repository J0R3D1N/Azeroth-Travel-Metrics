local testlib = require("testlib")

local FILES = {
    "AzerothTravelTracker\\Namespace.lua",
    "AzerothTravelTracker\\UITheme.lua",
}

local function newRegion(kind, parent, options)
    local region = {
        kind = kind,
        parent = parent,
        shown = true,
    }

    function region:SetAtlas(atlas, useAtlasSize)
        if options.rejectAtlases then
            error("atlas unavailable")
        end
        self.atlas = atlas
        self.useAtlasSize = useAtlasSize
        if options.returnFalseAtlases then
            return false
        end
        return true
    end

    function region:SetColorTexture(red, green, blue, alpha)
        self.color = { red, green, blue, alpha }
        self.shown = true
    end

    function region:SetTexture(texture)
        self.texture = texture
    end

    function region:SetSize(width, height)
        self.sizeCalls = (self.sizeCalls or 0) + 1
        self.width = width
        self.height = height
    end

    function region:SetHeight(height)
        self.height = height
    end

    function region:SetPoint(...)
        self.pointCalls = (self.pointCalls or 0) + 1
        self.point = { ... }
        self.points = self.points or {}
        table.insert(self.points, self.point)
    end

    function region:SetAllPoints(target)
        self.allPoints = target or true
    end

    function region:SetText(text)
        self.text = text
    end

    function region:SetTextColor(red, green, blue, alpha)
        self.textColor = { red, green, blue, alpha }
    end

    function region:SetJustifyH(justification)
        self.justifyH = justification
    end

    function region:Show()
        self.shown = true
    end

    function region:Hide()
        self.shown = false
    end

    function region:IsShown()
        return self.shown
    end

    return region
end

local function newFrame(frameType, name, parent, template, options)
    local frame = {
        frameType = frameType,
        name = name,
        parent = parent,
        template = template,
        scripts = {},
        textures = {},
        fontStrings = {},
        shown = true,
    }

    function frame:SetSize(width, height)
        self.sizeCalls = (self.sizeCalls or 0) + 1
        self.width = width
        self.height = height
    end

    function frame:SetHeight(height)
        self.height = height
    end

    function frame:SetPoint(...)
        self.point = { ... }
        self.points = self.points or {}
        table.insert(self.points, self.point)
    end

    function frame:SetAllPoints(target)
        self.allPoints = target or true
    end

    function frame:SetScript(name, callback)
        self.scripts[name] = callback
    end

    function frame:SetNormalTexture(texture)
        self.normalTexture = texture
    end

    function frame:SetHighlightTexture(texture)
        self.highlightTexture = texture
    end

    function frame:CreateTexture(regionName, layer)
        local texture = newRegion("Texture", self, options)
        texture.name = regionName
        texture.layer = layer
        table.insert(self.textures, texture)
        return texture
    end

    function frame:CreateFontString(regionName, layer, fontTemplate)
        local fontString = newRegion("FontString", self, options)
        fontString.name = regionName
        fontString.layer = layer
        fontString.fontTemplate = fontTemplate
        table.insert(self.fontStrings, fontString)
        return fontString
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

    return frame
end

local function newHarness(options)
    options = options or {}
    local calls = {
        frames = {},
        templates = {},
        tooltipLines = {},
    }
    local parent = newFrame("Frame", "Parent", nil, nil, options)
    local globals = {
        CreateFrame = function(frameType, name, frameParent, template)
            table.insert(calls.templates, template or false)
            if template == "LargeSideTabButtonTemplate"
                and options.rejectSideTabTemplate
            then
                error("template unavailable")
            end

            local frame = newFrame(
                frameType,
                name,
                frameParent,
                template,
                options
            )
            if template == "LargeSideTabButtonTemplate" then
                frame.width = 58
                frame.height = 60
                frame.Icon = newRegion("Texture", frame, options)
                frame.Icon.width = 36
                frame.Icon.height = 36
                frame.Icon.point = {
                    "TOPLEFT",
                    frame,
                    "TOPLEFT",
                    11,
                    -10,
                }
                frame.Icon.points = { frame.Icon.point }
                frame.SelectedTexture = newRegion("Texture", frame, options)
                frame.SelectedTexture:Hide()
            end
            table.insert(calls.frames, frame)
            return frame
        end,
        GameTooltip = {
            SetOwner = function(_, owner, anchor)
                calls.tooltipOwner = owner
                calls.tooltipAnchor = anchor
            end,
            SetText = function(_, text)
                calls.tooltipText = text
            end,
            AddLine = function(_, text)
                table.insert(calls.tooltipLines, text)
            end,
            Show = function()
                calls.tooltipShown = true
            end,
            Hide = function()
                calls.tooltipHidden = true
            end,
        },
    }
    local addon = testlib.loadAddon(FILES, globals)
    return addon, parent, calls
end

testlib.case("ui theme exposes approved native icons and atlases", function()
    local addon = testlib.loadAddon(FILES)
    testlib.equal(addon.UITheme.Icons.PORTRAIT, "Interface\\Icons\\INV_Misc_Map_01")
    testlib.equal(addon.UITheme.Icons.OVERVIEW, "Interface\\Icons\\INV_Misc_Map_01")
    testlib.equal(addon.UITheme.Icons.LEVELS, "Interface\\Icons\\INV_Misc_Book_09")
    testlib.equal(addon.UITheme.Icons.SETTINGS, "Interface\\Icons\\INV_Misc_Gear_01")
    testlib.equal(addon.UITheme.Atlases.SECTION, "UI-Character-Info-Title")
    testlib.equal(addon.UITheme.Atlases.ROW, "UI-Character-Info-Line-Bounce")
    testlib.equal(addon.UITheme.Atlases.ROW_ALTERNATE, "UI-Character-Info-Line-Bounce2")
    testlib.equal(addon.UITheme.Atlases.INSET, "common-insideframe")
end)

testlib.case("ui theme applies an atlas or a visible color fallback", function()
    local addon = newHarness()
    local texture = newRegion("Texture", nil, {})
    testlib.equal(
        addon.UITheme.SetAtlasOrColor(texture, "available", 0.1, 0.2, 0.3, 0.4),
        true
    )
    testlib.equal(texture.atlas, "available")
    testlib.equal(texture.useAtlasSize, true)
    testlib.equal(texture.color, nil)

    local fallback = newRegion("Texture", nil, { rejectAtlases = true })
    testlib.equal(
        addon.UITheme.SetAtlasOrColor(fallback, "missing", 0.1, 0.2, 0.3, 0.4),
        false
    )
    testlib.equal(fallback.color[1], 0.1)
    testlib.equal(fallback.color[2], 0.2)
    testlib.equal(fallback.color[3], 0.3)
    testlib.equal(fallback.color[4], 0.4)
    testlib.equal(fallback.shown, true)

    local rejected = newRegion("Texture", nil, {
        returnFalseAtlases = true,
    })
    testlib.equal(
        addon.UITheme.SetAtlasOrColor(rejected, "rejected", 0.2, 0.3, 0.4, 0.5),
        false
    )
    testlib.equal(rejected.atlas, "rejected")
    testlib.equal(rejected.color[1], 0.2)
    testlib.equal(rejected.color[2], 0.3)
    testlib.equal(rejected.color[3], 0.4)
    testlib.equal(rejected.color[4], 0.5)
    testlib.equal(rejected.shown, true)

    local missing = newRegion("Texture", nil, {})
    missing.SetAtlas = nil
    testlib.equal(
        addon.UITheme.SetAtlasOrColor(missing, "missing", 0.5, 0.6, 0.7, 0.8),
        false
    )
    testlib.equal(missing.color[1], 0.5)
    testlib.equal(missing.color[4], 0.8)
end)

testlib.case("ui theme creates native side tabs with supplied regions", function()
    local addon, parent, calls = newHarness()
    local tab = addon.UITheme.CreateSideTab("TestTab", parent, {
        icon = addon.UITheme.Icons.OVERVIEW,
        tooltip = "Overview",
    })

    testlib.equal(calls.templates[1], "LargeSideTabButtonTemplate")
    testlib.equal(#calls.templates, 1)
    testlib.equal(tab.width, 58)
    testlib.equal(tab.height, 60)
    testlib.equal(tab.sizeCalls, nil)
    testlib.equal(tab.Icon.texture, addon.UITheme.Icons.OVERVIEW)
    testlib.equal(tab.Icon.width, 36)
    testlib.equal(tab.Icon.height, 36)
    testlib.equal(tab.Icon.sizeCalls, nil)
    testlib.equal(tab.Icon.pointCalls, nil)
    testlib.equal(tab.Icon.points[1][1], "TOPLEFT")
    testlib.equal(tab.Icon.points[1][4], 11)
    testlib.equal(tab.Icon.points[1][5], -10)
    testlib.truthy(tab.scripts.OnEnter)
    tab.scripts.OnEnter(tab)
    testlib.equal(calls.tooltipOwner, tab)
    testlib.equal(calls.tooltipText, "Overview")
    testlib.equal(calls.tooltipShown, true)
    tab.scripts.OnLeave(tab)
    testlib.equal(calls.tooltipHidden, true)

    addon.UITheme.SetSideTabSelected(tab, true)
    testlib.equal(tab.SelectedTexture.shown, true)
    addon.UITheme.SetSideTabSelected(tab, false)
    testlib.equal(tab.SelectedTexture.shown, false)
    testlib.equal(tab.sizeCalls, nil)
    testlib.equal(tab.Icon.sizeCalls, nil)
    testlib.equal(tab.Icon.pointCalls, nil)
    testlib.equal(#tab.Icon.points, 1)
end)

testlib.case("ui theme creates a visible bare side tab fallback", function()
    local addon, parent, calls = newHarness({
        rejectSideTabTemplate = true,
    })
    local tab = addon.UITheme.CreateSideTab("FallbackTab", parent, {
        icon = addon.UITheme.Icons.LEVELS,
        tooltip = "By Level",
    })

    testlib.equal(calls.templates[1], "LargeSideTabButtonTemplate")
    testlib.equal(calls.templates[2], false)
    testlib.equal(#calls.templates, 2)
    testlib.equal(tab.width, 50)
    testlib.equal(tab.height, 50)
    testlib.equal(tab.sizeCalls, 1)
    testlib.truthy(tab.Icon)
    testlib.equal(tab.Icon.texture, addon.UITheme.Icons.LEVELS)
    testlib.equal(tab.Icon.width, 32)
    testlib.equal(tab.Icon.height, 32)
    testlib.equal(tab.Icon.sizeCalls, 1)
    testlib.equal(tab.Icon.pointCalls, 1)
    testlib.equal(tab.Icon.point[1], "CENTER")
    testlib.equal(tab.Icon.point[2], tab)
    testlib.equal(tab.Icon.point[3], "CENTER")
    testlib.equal(tab.Icon.point[4], 0)
    testlib.equal(tab.Icon.point[5], 0)
    testlib.truthy(tab.Background)
    testlib.truthy(tab.Background.color)
    testlib.equal(tab.Background.shown, true)
    testlib.truthy(tab.SelectedTexture)
    testlib.truthy(tab.SelectedTexture.color)
    testlib.equal(tab.SelectedTexture.shown, false)
    testlib.equal(#tab.SelectedTexture.BorderTextures, 4)
    for _, edge in ipairs(tab.SelectedTexture.BorderTextures) do
        testlib.equal(edge.allPoints, nil)
    end
    testlib.truthy(tab.HighlightTexture)
    testlib.truthy(tab.HighlightTexture.color)

    addon.UITheme.SetSideTabSelected(tab, true)
    testlib.equal(tab.SelectedTexture.shown, true)
    addon.UITheme.SetSideTabSelected(tab, false)
    testlib.equal(tab.SelectedTexture.shown, false)

    tab.scripts.OnEnter(tab)
    testlib.equal(calls.tooltipText, "By Level")
end)

testlib.case("ui theme creates native and fallback inset visuals", function()
    local addon, parent = newHarness()
    local inset = addon.UITheme.CreateInset(parent)
    testlib.equal(inset.atlas, addon.UITheme.Atlases.INSET)
    testlib.equal(inset.allPoints, parent)

    local fallbackAddon, fallbackParent = newHarness({
        rejectAtlases = true,
    })
    local fallback = fallbackAddon.UITheme.CreateInset(fallbackParent)
    testlib.truthy(fallback.color)
    testlib.equal(fallback.shown, true)
end)

testlib.case("ui theme creates character stat sections and assigns values", function()
    local addon, parent = newHarness()
    local section = addon.UITheme.CreateSection(parent, "Lifetime", 4)

    testlib.equal(section.frame.height, 96)
    testlib.equal(section.header.height, 24)
    testlib.equal(section.header.atlas, addon.UITheme.Atlases.SECTION)
    testlib.equal(section.title.text, "Lifetime")
    testlib.equal(#section.rows, 4)
    for index, row in ipairs(section.rows) do
        testlib.equal(row.frame.height, 18)
        testlib.equal(row.background.atlas, addon.UITheme.Atlases.ROW)
        testlib.equal(row.label.textColor[1], 1)
        testlib.equal(row.label.textColor[2], 0.82)
        testlib.equal(row.label.textColor[3], 0)
        testlib.equal(row.value.textColor[1], 1)
        testlib.equal(row.value.textColor[2], 1)
        testlib.equal(row.value.textColor[3], 1)
        testlib.equal(row.value.justifyH, "RIGHT")
        testlib.equal(row.frame.points[1][1], "TOPLEFT")
    end

    addon.UITheme.SetSectionValues(section, {
        { label = "Estimated Steps", value = "1.2K" },
        { label = "On Foot", value = "900 m" },
        { label = "Swimming", value = "25 m" },
        { label = "Flight Path", value = "2.5 km" },
    })
    testlib.equal(section.rows[1].label.text, "Estimated Steps")
    testlib.equal(section.rows[1].value.text, "1.2K")
    testlib.equal(section.rows[4].label.text, "Flight Path")
    testlib.equal(section.rows[4].value.text, "2.5 km")
end)

testlib.case("ui theme section keeps visible fallback shading", function()
    local addon, parent = newHarness({
        rejectAtlases = true,
    })
    local section = addon.UITheme.CreateSection(parent, "Travel by Level", 2)

    testlib.equal(section.frame.height, 60)
    testlib.truthy(section.header.color)
    testlib.equal(section.header.shown, true)
    testlib.equal(#section.rows, 2)
    for _, row in ipairs(section.rows) do
        testlib.truthy(row.background.color)
        testlib.equal(row.background.shown, true)
    end
end)

testlib.case("ui theme creates compact icon buttons with fallback visuals", function()
    local addon, parent, calls = newHarness()
    local button = addon.UITheme.CreateIconButton(
        parent,
        addon.UITheme.Icons.SETTINGS,
        "Settings"
    )

    testlib.equal(button.width, 24)
    testlib.equal(button.height, 24)
    testlib.equal(button.Icon.texture, addon.UITheme.Icons.SETTINGS)
    testlib.truthy(button.Background.color)
    testlib.truthy(button.HighlightTexture.color)
    button.scripts.OnEnter(button)
    testlib.equal(calls.tooltipText, "Settings")
    button.scripts.OnLeave(button)
    testlib.equal(calls.tooltipHidden, true)
end)
