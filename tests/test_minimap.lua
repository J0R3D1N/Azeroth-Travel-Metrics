local testlib = require("testlib")

local MINIMAP_FILES = {
    "AzerothTravelTracker\\Namespace.lua",
    "AzerothTravelTracker\\Minimap.lua",
}

local function contains(text, fragment)
    return type(text) == "string"
        and text:find(fragment, 1, true) ~= nil
end

local function newRegion(kind, parent)
    local region = {
        kind = kind,
        parent = parent,
        shown = true,
    }

    function region:SetTexture(texture)
        self.texture = texture
    end

    function region:SetSize(width, height)
        self.width = width
        self.height = height
    end

    function region:SetPoint(...)
        self.point = { ... }
    end

    function region:SetAllPoints()
        self.allPoints = true
    end

    function region:SetText(text)
        self.text = text
    end

    function region:Show()
        self.shown = true
    end

    function region:Hide()
        self.shown = false
    end

    return region
end

local function newButton(parent)
    local button = {
        parent = parent,
        scripts = {},
        textures = {},
        fontStrings = {},
        shown = true,
    }

    function button:SetSize(width, height)
        self.width = width
        self.height = height
    end

    function button:SetPoint(...)
        self.point = { ... }
    end

    function button:ClearAllPoints()
        self.point = nil
    end

    function button:RegisterForClicks(...)
        self.clicks = { ... }
    end

    function button:RegisterForDrag(...)
        self.dragButtons = { ... }
    end

    function button:SetScript(name, callback)
        self.scripts[name] = callback
    end

    function button:CreateTexture(name, layer)
        local texture = newRegion("Texture", self)
        texture.name = name
        texture.layer = layer
        table.insert(self.textures, texture)
        return texture
    end

    function button:CreateFontString(name, layer, template)
        local text = newRegion("FontString", self)
        text.name = name
        text.layer = layer
        text.template = template
        table.insert(self.fontStrings, text)
        return text
    end

    function button:Show()
        self.shown = true
    end

    function button:Hide()
        self.shown = false
    end

    function button:IsShown()
        return self.shown
    end

    return button
end

local function newHarness(options)
    options = options or {}
    local calls = {
        showMain = 0,
        toggles = 0,
        tooltipLines = {},
    }
    local minimapFrame = {
        name = "Minimap",
    }
    function minimapFrame:GetCenter()
        return options.centerX or 500, options.centerY or 400
    end
    function minimapFrame:GetEffectiveScale()
        return options.minimapScale or 1
    end
    if not options.omitDimensions then
        function minimapFrame:GetWidth()
            if options.widthThrows then
                error("width unavailable")
            end
            if options.width ~= nil then
                return options.width
            end
            return 140
        end
        function minimapFrame:GetHeight()
            if options.heightThrows then
                error("height unavailable")
            end
            if options.height ~= nil then
                return options.height
            end
            return 140
        end
    end

    local uiParentFrame = {
        name = "UIParent",
    }
    function uiParentFrame:GetEffectiveScale()
        return options.uiParentScale or 1
    end

    local globals = {
        Minimap = minimapFrame,
        UIParent = uiParentFrame,
        GetCursorPosition = function()
            return options.cursorX or 500, options.cursorY or 400
        end,
        CreateFrame = function(frameType, name, parent)
            testlib.equal(frameType, "Button")
            local button = newButton(parent)
            button.name = name
            return button
        end,
        GameTooltip = {
            ClearLines = function()
                calls.tooltipClears = (calls.tooltipClears or 0) + 1
                calls.tooltipLines = {}
            end,
            SetOwner = function(_, owner, anchor)
                calls.tooltipOwner = owner
                calls.tooltipAnchor = anchor
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
    if options.shape ~= nil or options.shapeThrows then
        globals.GetMinimapShape = function()
            if options.shapeThrows then
                error("shape unavailable")
            end
            return options.shape
        end
    end

    local addon, environment = testlib.loadAddon(MINIMAP_FILES, globals)
    addon.UI = {
        ShowMain = function()
            calls.showMain = calls.showMain + 1
        end,
        Toggle = function()
            calls.toggles = calls.toggles + 1
        end,
    }
    local db = options.db or {
        settings = {
            showMinimap = true,
            minimapAngle = options.angle or 225,
        },
    }
    addon.Minimap.Initialize({
        db = db,
    })

    return {
        addon = addon,
        environment = environment,
        calls = calls,
        db = db,
        minimapFrame = minimapFrame,
        uiParentFrame = uiParentFrame,
        options = options,
    }
end

testlib.case("minimap calculates cardinal offsets", function()
    local addon = testlib.loadAddon(MINIMAP_FILES, {
        CreateFrame = function()
            error("not needed")
        end,
    })

    local cases = {
        { angle = 0, x = 10, y = 0 },
        { angle = 90, x = 0, y = 10 },
        { angle = 180, x = -10, y = 0 },
        { angle = 270, x = 0, y = -10 },
    }
    for _, case in ipairs(cases) do
        local x, y = addon.Minimap.CalculateOffset(case.angle, 10)
        testlib.near(x, case.x, 0.0001)
        testlib.near(y, case.y, 0.0001)
    end
    local x, y = addon.Minimap.CalculateOffset(0, -1)
    testlib.equal(x, nil)
    testlib.equal(y, nil)
end)

testlib.case("minimap calculates offsets from live rectangular dimensions", function()
    local addon = testlib.loadAddon(MINIMAP_FILES, {
        CreateFrame = function()
            error("not needed")
        end,
    })

    local x, y = addon.Minimap.CalculateMinimapOffset(0, 200, 160)
    testlib.near(x, 105, 0.0001)
    testlib.near(y, 0, 0.0001)

    x, y = addon.Minimap.CalculateMinimapOffset(90, 200, 160)
    testlib.near(x, 0, 0.0001)
    testlib.near(y, 85, 0.0001)

    x, y = addon.Minimap.CalculateMinimapOffset(45, 200, 160)
    testlib.near(x, 66.0050, 0.0001)
    testlib.near(y, 66.0050, 0.0001)
    testlib.near(math.deg(math.atan(y / x)), 45, 0.0001)
end)

testlib.case("minimap square diagonals stay outside the rim", function()
    local addon = testlib.loadAddon(MINIMAP_FILES, {
        CreateFrame = function()
            error("not needed")
        end,
    })

    local x, y = addon.Minimap.CalculateMinimapOffset(
        45,
        140,
        140,
        5,
        "SQUARE"
    )
    testlib.near(x, 73.5355, 0.0001)
    testlib.near(y, 73.5355, 0.0001)
    testlib.near(math.deg(math.atan(y / x)), 45, 0.0001)
end)

testlib.case("minimap shape table selects curved quadrants", function()
    local addon = testlib.loadAddon(MINIMAP_FILES, {
        CreateFrame = function()
            error("not needed")
        end,
    })

    local quadrantAngles = { 315, 225, 45, 135 }
    local shapes = {
        ROUND = { true, true, true, true },
        SQUARE = { false, false, false, false },
        ["CORNER-TOPLEFT"] = { false, false, false, true },
        ["CORNER-TOPRIGHT"] = { false, false, true, false },
        ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
        ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
        ["SIDE-LEFT"] = { false, true, false, true },
        ["SIDE-RIGHT"] = { true, false, true, false },
        ["SIDE-TOP"] = { false, false, true, true },
        ["SIDE-BOTTOM"] = { true, true, false, false },
        ["TRICORNER-TOPLEFT"] = { false, true, true, true },
        ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
        ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
        ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
    }

    for shape, curvedQuadrants in pairs(shapes) do
        for quadrant, angle in ipairs(quadrantAngles) do
            local x, y = addon.Minimap.CalculateMinimapOffset(
                angle,
                140,
                140,
                5,
                shape
            )
            local expectedMagnitude = curvedQuadrants[quadrant]
                and 53.0330
                or 73.5355
            testlib.near(math.abs(x), expectedMagnitude, 0.0001)
            testlib.near(math.abs(y), expectedMagnitude, 0.0001)
        end
    end
end)

testlib.case("minimap dimensions fall back independently", function()
    local addon = testlib.loadAddon(MINIMAP_FILES, {
        CreateFrame = function()
            error("not needed")
        end,
    })

    local x, y = addon.Minimap.CalculateMinimapOffset(0, 200, 0 / 0)
    testlib.near(x, 105, 0.0001)
    testlib.near(y, 0, 0.0001)

    x, y = addon.Minimap.CalculateMinimapOffset(90, -1, 160)
    testlib.near(x, 0, 0.0001)
    testlib.near(y, 85, 0.0001)

    x, y = addon.Minimap.CalculateMinimapOffset(0, nil, nil)
    testlib.near(x, 80, 0.0001)
    testlib.near(y, 0, 0.0001)
end)

testlib.case("minimap offsets reject invalid angle and padding", function()
    local addon = testlib.loadAddon(MINIMAP_FILES, {
        CreateFrame = function()
            error("not needed")
        end,
    })

    local invalidCases = {
        { 0 / 0, 200, 160, 5 },
        { 0, 200, 160, 0 },
        { 0, 200, 160, math.huge },
    }
    for _, values in ipairs(invalidCases) do
        local x, y = addon.Minimap.CalculateMinimapOffset(
            values[1],
            values[2],
            values[3],
            values[4]
        )
        testlib.equal(x, nil)
        testlib.equal(y, nil)
    end
end)

testlib.case("minimap default placement uses live dimensions", function()
    local harness = newHarness({
        angle = 0,
        width = 200,
        height = 160,
    })
    local button = harness.addon.Minimap.Create()

    testlib.near(button.point[4], 105, 0.0001)
    testlib.near(button.point[5], 0, 0.0001)
end)

testlib.case("minimap placement falls back when dimensions are invalid", function()
    local harness = newHarness({
        angle = 0,
        width = 200,
        height = -1,
    })
    local button = harness.addon.Minimap.Create()

    testlib.near(button.point[4], 105, 0.0001)
    testlib.near(button.point[5], 0, 0.0001)

    local missingHarness = newHarness({
        angle = 90,
        omitDimensions = true,
    })
    local missingButton = missingHarness.addon.Minimap.Create()
    testlib.near(missingButton.point[4], 0, 0.0001)
    testlib.near(missingButton.point[5], 80, 0.0001)
end)

testlib.case("minimap shape lookup safely defaults to round", function()
    local cases = {
        {},
        { shapeThrows = true },
        { shape = "UNKNOWN-SHAPE" },
    }

    for _, options in ipairs(cases) do
        options.angle = 45
        options.width = 140
        options.height = 140
        local harness = newHarness(options)
        local button = harness.addon.Minimap.Create()
        testlib.near(button.point[4], 53.0330, 0.0001)
        testlib.near(button.point[5], 53.0330, 0.0001)
    end
end)

testlib.case("minimap live shape selects the current quadrant geometry", function()
    local curvedHarness = newHarness({
        angle = 135,
        width = 140,
        height = 140,
        shape = "CORNER-TOPLEFT",
    })
    testlib.near(curvedHarness.addon.Minimap.button.point[4], -53.0330, 0.0001)
    testlib.near(curvedHarness.addon.Minimap.button.point[5], 53.0330, 0.0001)

    local edgeHarness = newHarness({
        angle = 45,
        width = 140,
        height = 140,
        shape = "CORNER-TOPLEFT",
    })
    testlib.near(edgeHarness.addon.Minimap.button.point[4], 73.5355, 0.0001)
    testlib.near(edgeHarness.addon.Minimap.button.point[5], 73.5355, 0.0001)
end)

testlib.case("minimap normalizes angles and rejects invalid values", function()
    local harness = newHarness()
    local button = harness.addon.Minimap.Create()

    testlib.equal(harness.addon.Minimap.SetAngle(-90), true)
    testlib.equal(harness.db.settings.minimapAngle, 270)
    testlib.equal(harness.addon.Minimap.SetAngle(450), true)
    testlib.equal(harness.db.settings.minimapAngle, 90)
    local priorPoint = button.point
    testlib.equal(harness.addon.Minimap.SetAngle(0 / 0), false)
    testlib.equal(harness.addon.Minimap.SetAngle(math.huge), false)
    testlib.equal(harness.addon.Minimap.SetAngle("90"), false)
    testlib.equal(harness.db.settings.minimapAngle, 90)
    testlib.equal(button.point, priorPoint)
end)

testlib.case("minimap create is idempotent native and interactive", function()
    local harness = newHarness()
    local first = harness.addon.Minimap.Create()
    local second = harness.addon.Minimap.Create()

    testlib.equal(first, second)
    testlib.equal(first.parent, harness.minimapFrame)
    testlib.equal(first.width, 32)
    testlib.equal(first.height, 32)
    testlib.truthy(#first.textures >= 3)
    testlib.truthy(contains(first.textures[1].texture, "Minimap"))
    testlib.equal(
        first.textures[2].texture,
        "Interface\\Icons\\Ability_Rogue_Sprint"
    )
    testlib.truthy(type(first.scripts.OnEnter) == "function")
    testlib.truthy(type(first.scripts.OnLeave) == "function")
    testlib.truthy(type(first.scripts.OnClick) == "function")
    testlib.truthy(type(first.scripts.OnDragStart) == "function")
    testlib.truthy(type(first.scripts.OnDragStop) == "function")
    testlib.truthy(type(first.scripts.OnUpdate) == "function")

    first.scripts.OnEnter(first)
    testlib.equal(harness.calls.tooltipOwner, first)
    testlib.equal(harness.calls.tooltipShown, true)
    testlib.equal(harness.calls.tooltipClears, 1)
    testlib.truthy(contains(harness.calls.tooltipLines[1], "Azeroth Travel Tracker"))
    testlib.equal(harness.calls.tooltipLines[2], "Left-click to open")
    testlib.truthy(contains(harness.calls.tooltipLines[3], "Drag"))
    first.scripts.OnLeave(first)
    testlib.equal(harness.calls.tooltipHidden, true)
    first.scripts.OnEnter(first)
    testlib.equal(harness.calls.tooltipClears, 2)
    testlib.equal(#harness.calls.tooltipLines, 3)

    first.scripts.OnClick(first, "LeftButton")
    testlib.equal(harness.calls.showMain, 1)
    testlib.equal(harness.calls.toggles, 0)
end)

testlib.case("minimap drag uses UI parent scale when minimap scale differs", function()
    local harness = newHarness({
        centerX = 300,
        centerY = 200,
        uiParentScale = 2,
        minimapScale = 0.5,
        cursorX = 800,
        cursorY = 600,
    })
    local button = harness.addon.Minimap.Create()

    button.scripts.OnDragStart(button, "LeftButton")
    button.scripts.OnUpdate(button)
    button.scripts.OnDragStop(button)

    testlib.near(harness.db.settings.minimapAngle, 45, 0.0001)
    testlib.near(button.point[4], 53.0330, 0.0001)
    testlib.near(button.point[5], 53.0330, 0.0001)
end)

testlib.case("minimap drag persists angle across recreation", function()
    local db = {
        settings = {
            showMinimap = true,
            minimapAngle = 225,
        },
    }
    local dragHarness = newHarness({
        db = db,
        centerX = 300,
        centerY = 200,
        cursorX = 400,
        cursorY = 300,
        shape = "SQUARE",
    })
    local button = dragHarness.addon.Minimap.button
    button.scripts.OnDragStart(button, "LeftButton")
    button.scripts.OnUpdate(button)
    button.scripts.OnDragStop(button)

    testlib.near(db.settings.minimapAngle, 45, 0.0001)

    local recreatedHarness = newHarness({
        db = db,
        width = 140,
        height = 140,
        shape = "SQUARE",
    })
    local recreatedButton = recreatedHarness.addon.Minimap.button
    testlib.near(recreatedButton.point[4], 73.5355, 0.0001)
    testlib.near(recreatedButton.point[5], 73.5355, 0.0001)
    testlib.near(
        math.deg(math.atan(recreatedButton.point[5] / recreatedButton.point[4])),
        db.settings.minimapAngle,
        0.0001
    )
end)

testlib.case("minimap drag release suppresses only its generated click", function()
    local harness = newHarness({
        centerX = 300,
        centerY = 200,
        cursorX = 300,
        cursorY = 300,
    })
    local button = harness.addon.Minimap.Create()

    button.scripts.OnDragStart(button, "LeftButton")
    button.scripts.OnUpdate(button)
    button.scripts.OnDragStop(button)
    button.scripts.OnClick(button, "LeftButton")

    testlib.equal(harness.calls.showMain, 0)
    testlib.near(harness.db.settings.minimapAngle, 90, 0.0001)

    button.scripts.OnClick(button, "LeftButton")
    testlib.equal(harness.calls.showMain, 1)
end)

testlib.case("minimap invalid drag data does not corrupt settings", function()
    local harness = newHarness({
        cursorX = 0 / 0,
        cursorY = 600,
    })
    local button = harness.addon.Minimap.Create()
    local originalAngle = harness.db.settings.minimapAngle
    local originalPoint = button.point

    button.scripts.OnDragStart(button, "LeftButton")
    local succeeded = pcall(button.scripts.OnUpdate, button)
    button.scripts.OnDragStop(button)

    testlib.equal(succeeded, true)
    testlib.equal(harness.db.settings.minimapAngle, originalAngle)
    testlib.equal(button.point, originalPoint)
end)

testlib.case("minimap visibility follows settings without affecting slash UI", function()
    local harness = newHarness()
    local button = harness.addon.Minimap.Create()

    harness.db.settings.showMinimap = false
    harness.addon.Minimap.UpdateVisibility()
    testlib.equal(button:IsShown(), false)
    harness.addon.UI.Toggle()
    testlib.equal(harness.calls.toggles, 1)

    harness.db.settings.showMinimap = true
    harness.addon.Minimap.UpdateVisibility()
    testlib.equal(button:IsShown(), true)
end)

testlib.case("minimap operations remain nonprotected during combat lockdown", function()
    local harness = newHarness()
    harness.environment.InCombatLockdown = function()
        return true
    end

    local succeeded, failure = pcall(function()
        local button = harness.addon.Minimap.Create()
        button.scripts.OnClick(button, "LeftButton")
        button.scripts.OnDragStart(button, "LeftButton")
        button.scripts.OnUpdate(button)
        button.scripts.OnDragStop(button)
        harness.addon.Minimap.UpdateVisibility()
    end)

    testlib.equal(succeeded, true, failure)
    testlib.equal(harness.calls.showMain, 1)
end)
