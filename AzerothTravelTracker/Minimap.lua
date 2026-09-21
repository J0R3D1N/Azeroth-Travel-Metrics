local addonName, ATT = ...

ATT.Minimap = {}

local MinimapLauncher = ATT.Minimap
local DEFAULT_ANGLE = 225
local BUTTON_SIZE = 32
local BORDER_SIZE = 54
local BUTTON_OUTER_RADIUS = BORDER_SIZE / 2
local DEFAULT_MINIMAP_DIAMETER = 150
local DEFAULT_MINIMAP_SHAPE = "ROUND"
local OFFSET_SOLVE_ITERATIONS = 32
local MINIMAP_SHAPE_QUADRANTS = {
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
local QUADRANT_SIGNS = {
    { 1, -1 },
    { -1, -1 },
    { 1, 1 },
    { -1, 1 },
}
local context
local dragging = false
local dragMoved = false
local suppressNextClick = false

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function normalizeAngle(angle)
    if not isFiniteNumber(angle) then
        return nil
    end

    angle = angle % 360
    if angle < 0 then
        angle = angle + 360
    end
    return angle
end

local function atan2(y, x)
    if type(math.atan2) == "function" then
        return math.atan2(y, x)
    end
    if x > 0 then
        return math.atan(y / x)
    end
    if x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    end
    if x < 0 and y < 0 then
        return math.atan(y / x) - math.pi
    end
    if x == 0 and y > 0 then
        return math.pi / 2
    end
    if x == 0 and y < 0 then
        return -math.pi / 2
    end
    return 0
end

function MinimapLauncher.CalculateOffset(angleDegrees, radius)
    if not isFiniteNumber(angleDegrees)
        or not isFiniteNumber(radius)
        or radius < 0
    then
        return nil, nil
    end

    local radians = math.rad(angleDegrees)
    return math.cos(radians) * radius, math.sin(radians) * radius
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function distanceToQuadrant(
    x,
    y,
    radiusX,
    radiusY,
    signs,
    curved
)
    local localX = signs[1] * x
    local localY = signs[2] * y
    local projectedX = math.max(localX, 0)
    local projectedY = math.max(localY, 0)

    if curved then
        local normalized = projectedX * projectedX / (radiusX * radiusX)
            + projectedY * projectedY / (radiusY * radiusY)
        if normalized > 1 then
            local lower = 0
            local upper = math.max(radiusX, radiusY)
                * math.sqrt(projectedX * projectedX + projectedY * projectedY)
            for _ = 1, OFFSET_SOLVE_ITERATIONS do
                local lambda = (lower + upper) / 2
                local ellipseX = radiusX * radiusX * projectedX
                    / (lambda + radiusX * radiusX)
                local ellipseY = radiusY * radiusY * projectedY
                    / (lambda + radiusY * radiusY)
                local value = ellipseX * ellipseX / (radiusX * radiusX)
                    + ellipseY * ellipseY / (radiusY * radiusY)
                if value > 1 then
                    lower = lambda
                else
                    upper = lambda
                end
            end
            local lambda = (lower + upper) / 2
            projectedX = radiusX * radiusX * projectedX
                / (lambda + radiusX * radiusX)
            projectedY = radiusY * radiusY * projectedY
                / (lambda + radiusY * radiusY)
        end
    else
        projectedX = clamp(projectedX, 0, radiusX)
        projectedY = clamp(projectedY, 0, radiusY)
    end

    local deltaX = localX - projectedX
    local deltaY = localY - projectedY
    return math.sqrt(deltaX * deltaX + deltaY * deltaY)
end

local function distanceToShape(x, y, radiusX, radiusY, quadrants)
    -- Blizzard shapes combine quarter ellipses and quarter rectangles.
    local minimumDistance = math.huge
    for quadrant, signs in ipairs(QUADRANT_SIGNS) do
        minimumDistance = math.min(
            minimumDistance,
            distanceToQuadrant(
                x,
                y,
                radiusX,
                radiusY,
                signs,
                quadrants[quadrant]
            )
        )
    end
    return minimumDistance
end

local function calculateRayIntersection(unitX, unitY, radiusX, radiusY, curved)
    if curved then
        return 1 / math.sqrt(
            unitX * unitX / (radiusX * radiusX)
                + unitY * unitY / (radiusY * radiusY)
        )
    end

    local intersection
    if unitX ~= 0 then
        intersection = radiusX / math.abs(unitX)
    end
    if unitY ~= 0 then
        local verticalIntersection = radiusY / math.abs(unitY)
        if intersection == nil or verticalIntersection < intersection then
            intersection = verticalIntersection
        end
    end
    return intersection
end

function MinimapLauncher.CalculateMinimapOffset(
    angleDegrees,
    width,
    height,
    padding,
    shape
)
    padding = padding == nil and BUTTON_OUTER_RADIUS or padding
    if not isFiniteNumber(angleDegrees)
        or not isFiniteNumber(padding)
        or padding <= 0
    then
        return nil, nil
    end

    if not isFiniteNumber(width) or width <= 0 then
        width = DEFAULT_MINIMAP_DIAMETER
    end
    if not isFiniteNumber(height) or height <= 0 then
        height = DEFAULT_MINIMAP_DIAMETER
    end

    local radians = math.rad(angleDegrees)
    local unitX = math.cos(radians)
    local unitY = math.sin(radians)
    local radiusX = width / 2
    local radiusY = height / 2
    local quadrant = 1
    if unitX < 0 then
        quadrant = quadrant + 1
    end
    if unitY > 0 then
        quadrant = quadrant + 2
    end

    local shapeQuadrants = MINIMAP_SHAPE_QUADRANTS[shape]
        or MINIMAP_SHAPE_QUADRANTS[DEFAULT_MINIMAP_SHAPE]
    local lower = calculateRayIntersection(
        unitX,
        unitY,
        radiusX,
        radiusY,
        shapeQuadrants[quadrant]
    )
    local upper = math.sqrt(radiusX * radiusX + radiusY * radiusY)
        + padding

    for _ = 1, OFFSET_SOLVE_ITERATIONS do
        local distance = (lower + upper) / 2
        if distanceToShape(
            unitX * distance,
            unitY * distance,
            radiusX,
            radiusY,
            shapeQuadrants
        ) < padding then
            lower = distance
        else
            upper = distance
        end
    end

    local distance = (lower + upper) / 2
    return unitX * distance, unitY * distance
end

local function getFrameDimension(frame, methodName)
    if not frame or type(frame[methodName]) ~= "function" then
        return nil
    end

    local succeeded, value = pcall(frame[methodName], frame)
    if not succeeded or not isFiniteNumber(value) or value <= 0 then
        return nil
    end

    return value
end

local function getMinimapDimensions()
    return getFrameDimension(Minimap, "GetWidth"),
        getFrameDimension(Minimap, "GetHeight")
end

local function getMinimapShape()
    if type(GetMinimapShape) ~= "function" then
        return DEFAULT_MINIMAP_SHAPE
    end

    local succeeded, shape = pcall(GetMinimapShape)
    if not succeeded or MINIMAP_SHAPE_QUADRANTS[shape] == nil then
        return DEFAULT_MINIMAP_SHAPE
    end

    return shape
end

local function positionButton(angle)
    if not MinimapLauncher.button then
        return false
    end

    local width, height = getMinimapDimensions()
    local x, y = MinimapLauncher.CalculateMinimapOffset(
        angle,
        width,
        height,
        BUTTON_OUTER_RADIUS,
        getMinimapShape()
    )
    if not isFiniteNumber(x) or not isFiniteNumber(y) then
        return false
    end

    MinimapLauncher.button:ClearAllPoints()
    MinimapLauncher.button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    return true
end

function MinimapLauncher.SetAngle(angleDegrees)
    local angle = normalizeAngle(angleDegrees)
    if angle == nil
        or not context
        or not context.db
        or not context.db.settings
    then
        return false
    end

    context.db.settings.minimapAngle = angle
    positionButton(angle)
    return true
end

function MinimapLauncher.UpdateFromCursor()
    if not dragging
        or not Minimap
        or type(Minimap.GetCenter) ~= "function"
        or type(GetCursorPosition) ~= "function"
    then
        return false
    end

    local cursorX, cursorY = GetCursorPosition()
    local centerX, centerY = Minimap:GetCenter()
    local scale = getFrameDimension(Minimap, "GetEffectiveScale")
        or getFrameDimension(UIParent, "GetEffectiveScale")
        or getFrameDimension(UIParent, "GetScale")

    if not isFiniteNumber(cursorX)
        or not isFiniteNumber(cursorY)
        or not isFiniteNumber(centerX)
        or not isFiniteNumber(centerY)
        or not isFiniteNumber(scale)
        or scale <= 0
    then
        return false
    end

    cursorX = cursorX / scale
    cursorY = cursorY / scale
    local deltaX = cursorX - centerX
    local deltaY = cursorY - centerY
    if deltaX == 0 and deltaY == 0 then
        return false
    end

    return MinimapLauncher.SetAngle(
        math.deg(atan2(deltaY, deltaX))
    )
end

function MinimapLauncher.UpdateVisibility()
    if not MinimapLauncher.button
        or not context
        or not context.db
        or not context.db.settings
    then
        return false
    end

    if context.db.settings.showMinimap == false then
        MinimapLauncher.button:Hide()
    else
        MinimapLauncher.button:Show()
    end
    return true
end

function MinimapLauncher.Create()
    if MinimapLauncher.button then
        return MinimapLauncher.button
    end
    if not Minimap then
        error("Minimap frame unavailable")
    end

    local button = CreateFrame(
        "Button",
        "AzerothTravelTrackerMinimapButton",
        Minimap
    )
    MinimapLauncher.button = button
    button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    if type(button.SetFrameLevel) == "function"
        and type(Minimap.GetFrameLevel) == "function"
    then
        local succeeded, level = pcall(Minimap.GetFrameLevel, Minimap)
        if succeeded and isFiniteNumber(level) then
            button:SetFrameLevel(level + 10)
        end
    end
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetSize(24, 24)
    background:SetPoint("CENTER", button, "CENTER", 0, 0)
    MinimapLauncher.background = background

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Ability_Rogue_Sprint")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    MinimapLauncher.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(BORDER_SIZE, BORDER_SIZE)
    border:SetPoint("CENTER", button, "CENTER", 0, 0)
    MinimapLauncher.border = border

    button:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end
        if type(GameTooltip.ClearLines) == "function" then
            GameTooltip:ClearLines()
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Azeroth Travel Tracker")
        GameTooltip:AddLine("Left-click to open")
        GameTooltip:AddLine("Drag to reposition")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if suppressNextClick then
            suppressNextClick = false
            return
        end
        if mouseButton == "LeftButton"
            and ATT.UI
            and type(ATT.UI.ShowMain) == "function"
        then
            ATT.UI.ShowMain()
        end
    end)
    button:SetScript("OnDragStart", function(_, mouseButton)
        if mouseButton == nil or mouseButton == "LeftButton" then
            dragging = true
            dragMoved = false
        end
    end)
    button:SetScript("OnDragStop", function()
        dragging = false
        suppressNextClick = dragMoved
        dragMoved = false
    end)
    button:SetScript("OnUpdate", function()
        if MinimapLauncher.UpdateFromCursor() then
            dragMoved = true
        end
    end)

    local settings = context and context.db and context.db.settings
    local angle = settings and normalizeAngle(settings.minimapAngle)
        or DEFAULT_ANGLE
    if settings then
        settings.minimapAngle = angle
    end
    positionButton(angle)
    MinimapLauncher.UpdateVisibility()
    return button
end

function MinimapLauncher.Initialize(initialContext)
    context = initialContext
    return MinimapLauncher.Create()
end
