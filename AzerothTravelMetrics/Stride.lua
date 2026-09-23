local _, ATM = ...

ATM.Stride = {}

local Stride = ATM.Stride

Stride.DEFAULT_METERS = 0.80

local raceMeters = {
    Human = 0.80,
    Orc = 0.86,
    Dwarf = 0.66,
    NightElf = 0.90,
    Scourge = 0.78,
    Tauren = 1.05,
    Gnome = 0.52,
    Troll = 0.94,
    BloodElf = 0.82,
    Draenei = 0.92,
    Goblin = 0.56,
    Worgen = 0.92,
    Pandaren = 0.82,
    Nightborne = 0.86,
    HighmountainTauren = 1.05,
    VoidElf = 0.82,
    LightforgedDraenei = 0.92,
    ZandalariTroll = 0.98,
    KulTiran = 0.91,
    DarkIronDwarf = 0.66,
    Vulpera = 0.58,
    MagharOrc = 0.86,
    Mechagnome = 0.52,
    Dracthyr = 0.92,
    EarthenDwarf = 0.68,
}

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end

function Stride.GetMeters(raceFile)
    return raceMeters[raceFile] or Stride.DEFAULT_METERS
end

function Stride.EstimateSteps(yards, raceFile)
    if not isFiniteNumber(yards) or yards < 0 then
        return nil, "invalidDistance"
    end

    local meters = ATM.Distance.YardsToMeters(yards)
    local rawSteps = meters / Stride.GetMeters(raceFile)
    if not isFiniteNumber(rawSteps) or rawSteps < 0 then
        return nil, "invalidDistance"
    end

    local steps = math.floor(rawSteps + 0.5)
    if not isFiniteNumber(steps) then
        return nil, "invalidDistance"
    end

    return steps
end
