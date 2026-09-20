local _, ATT = ...

ATT.UIModel = {}

local UIModel = ATT.UIModel

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function isPositiveInteger(value)
    return isFiniteNumber(value)
        and value > 0
        and value % 1 == 0
end

local function isNonnegativeInteger(value)
    return isFiniteNumber(value)
        and value >= 0
        and value % 1 == 0
end

local function isValidRaceFile(value)
    return type(value) == "string" and value ~= ""
end

local function isValidTotals(totals)
    return type(totals) == "table"
        and isFiniteNumber(totals.onFoot)
        and totals.onFoot >= 0
        and isFiniteNumber(totals.swimming)
        and totals.swimming >= 0
        and isFiniteNumber(totals.taxi)
        and totals.taxi >= 0
end

local function isValidIdentity(character)
    return type(character) == "table"
        and type(character.identity) == "table"
        and isValidRaceFile(character.identity.raceFile)
end

local function normalizedUnits(units)
    if units == "imperial" then
        return "imperial"
    end

    return "metric"
end

local function buildSummary(totals, raceFile, units)
    return {
        steps = ATT.Stride.EstimateSteps(totals.onFoot, raceFile),
        onFootYards = totals.onFoot,
        swimmingYards = totals.swimming,
        taxiYards = totals.taxi,
        onFoot = ATT.Distance.Format(totals.onFoot, units),
        swimming = ATT.Distance.Format(totals.swimming, units),
        taxi = ATT.Distance.Format(totals.taxi, units),
    }
end

function UIModel.BuildOverview(character, currentLevel, units)
    if not isValidIdentity(character)
        or not isValidTotals(character.lifetime)
        or not isValidTotals(character.session)
        or type(character.levels) ~= "table"
        or not isPositiveInteger(currentLevel)
    then
        return nil, "invalidStatistics"
    end

    local levelTotals = character.levels[currentLevel]
    if levelTotals == nil then
        return nil, "levelUnavailable"
    end

    if not isValidTotals(levelTotals)
        or not isPositiveInteger(levelTotals.reachedAt)
    then
        return nil, "invalidStatistics"
    end

    local raceFile = character.identity.raceFile
    local displayUnits = normalizedUnits(units)

    return {
        lifetime = buildSummary(character.lifetime, raceFile, displayUnits),
        session = buildSummary(character.session, raceFile, displayUnits),
        currentLevel = buildSummary(levelTotals, raceFile, displayUnits),
    }
end

function UIModel.BuildLevelRows(character, units)
    if not isValidIdentity(character)
        or type(character.levels) ~= "table"
    then
        return nil, "invalidStatistics"
    end

    local rows = {}
    local raceFile = character.identity.raceFile
    local displayUnits = normalizedUnits(units)

    for level, totals in pairs(character.levels) do
        if not isPositiveInteger(level)
            or not isValidTotals(totals)
            or not isPositiveInteger(totals.reachedAt)
        then
            return nil, "invalidStatistics"
        end

        local row = buildSummary(totals, raceFile, displayUnits)
        row.level = level
        row.reachedAt = totals.reachedAt
        table.insert(rows, row)
    end

    table.sort(rows, function(left, right)
        return left.level > right.level
    end)

    return rows
end

function UIModel.BuildDiagnostics(character, enabled)
    if not enabled then
        return {}
    end

    if type(character) ~= "table"
        or type(character.diagnostics) ~= "table"
    then
        return nil, "invalidDiagnostics"
    end

    local diagnostics = {}

    for reason, count in pairs(character.diagnostics) do
        if type(reason) ~= "string"
            or reason == ""
            or not isNonnegativeInteger(count)
        then
            return nil, "invalidDiagnostics"
        end

        if count > 0 then
            table.insert(diagnostics, {
                reason = reason,
                count = count,
            })
        end
    end

    table.sort(diagnostics, function(left, right)
        return left.reason < right.reason
    end)

    return diagnostics
end
