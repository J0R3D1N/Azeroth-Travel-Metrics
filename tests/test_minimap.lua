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
        return options.scale or 1
    end

    local globals = {
        Minimap = minimapFrame,
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

    local addon, environment = testlib.loadAddon(MINIMAP_FILES, globals)
    addon.UI = {
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
    testlib.truthy(contains(first.textures[2].texture, "Icons"))
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
    testlib.truthy(contains(harness.calls.tooltipLines[2], "Left-click"))
    testlib.truthy(contains(harness.calls.tooltipLines[3], "Drag"))
    first.scripts.OnLeave(first)
    testlib.equal(harness.calls.tooltipHidden, true)
    first.scripts.OnEnter(first)
    testlib.equal(harness.calls.tooltipClears, 2)
    testlib.equal(#harness.calls.tooltipLines, 3)

    first.scripts.OnClick(first, "LeftButton")
    testlib.equal(harness.calls.toggles, 1)
end)

testlib.case("minimap drag accounts for UI scale and persists normalized angle", function()
    local harness = newHarness({
        centerX = 300,
        centerY = 200,
        scale = 2,
        cursorX = 600,
        cursorY = 600,
    })
    local button = harness.addon.Minimap.Create()

    button.scripts.OnDragStart(button, "LeftButton")
    button.scripts.OnUpdate(button)
    button.scripts.OnDragStop(button)

    testlib.near(harness.db.settings.minimapAngle, 90, 0.0001)
    testlib.near(button.point[4], 0, 0.0001)
    testlib.near(button.point[5], 80, 0.0001)
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
    testlib.equal(harness.calls.toggles, 1)
end)
