local _, ATM = ...

ATM.Movement = {}

local Movement = ATM.Movement

local maxSpeedByCategory = {
    [ATM.Categories.ON_FOOT] = 20,
    [ATM.Categories.SWIMMING] = 15,
    [ATM.Categories.TAXI] = 200,
}

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function hasValidNumericFields(sample)
    return type(sample) == "table"
        and isFiniteNumber(sample.x)
        and isFiniteNumber(sample.y)
        and isFiniteNumber(sample.z)
        and isFiniteNumber(sample.mapID)
        and isFiniteNumber(sample.instanceID)
        and isFiniteNumber(sample.time)
end

function Movement.Classify(sample)
    if type(sample) ~= "table" or type(sample.onTaxi) ~= "boolean" then
        return nil, "unsupportedState"
    end

    if sample.onTaxi then
        if sample.swimming == true then
            return nil, "unsupportedState"
        end

        return ATM.Categories.TAXI
    end

    if type(sample.swimming) ~= "boolean"
        or type(sample.mounted) ~= "boolean"
        or type(sample.flying) ~= "boolean"
        or type(sample.vehicle) ~= "boolean"
    then
        return nil, "unsupportedState"
    end

    if sample.mounted or sample.flying or sample.vehicle then
        return nil, "unsupportedState"
    end

    if sample.swimming then
        return ATM.Categories.SWIMMING
    end

    if type(sample.grounded) ~= "boolean" then
        return nil, "unsupportedState"
    end

    if sample.grounded then
        return ATM.Categories.ON_FOOT
    end

    return nil, "unsupportedState"
end

function Movement.Distance(from, to)
    if type(from) ~= "table"
        or type(to) ~= "table"
        or not isFiniteNumber(from.x)
        or not isFiniteNumber(from.y)
        or not isFiniteNumber(from.z)
        or not isFiniteNumber(to.x)
        or not isFiniteNumber(to.y)
        or not isFiniteNumber(to.z)
    then
        return nil, "missingPosition"
    end

    local dx = to.x - from.x
    local dy = to.y - from.y
    local dz = to.z - from.z

    if not isFiniteNumber(dx) or not isFiniteNumber(dy) or not isFiniteNumber(dz) then
        return nil, "missingPosition"
    end

    local scale = math.max(math.abs(dx), math.abs(dy), math.abs(dz))
    if scale == 0 then
        return 0
    end

    local yards = scale * math.sqrt(
        (dx / scale) * (dx / scale)
            + (dy / scale) * (dy / scale)
            + (dz / scale) * (dz / scale)
    )

    if not isFiniteNumber(yards) then
        return nil, "missingPosition"
    end

    return yards
end

function Movement.BuildSegment(from, to)
    if not hasValidNumericFields(from) or not hasValidNumericFields(to) then
        return nil, "missingPosition"
    end

    if from.mapID ~= to.mapID then
        return nil, "mapChanged"
    end

    if from.instanceID ~= to.instanceID then
        return nil, "instanceChanged"
    end

    local elapsed = to.time - from.time
    if not isFiniteNumber(elapsed) or elapsed <= 0 then
        return nil, "invalidElapsed"
    end

    if elapsed > ATM.MAX_SAMPLE_GAP_SECONDS then
        return nil, "sampleGap"
    end

    local fromCategory = Movement.Classify(from)
    local toCategory = Movement.Classify(to)
    if fromCategory == nil or toCategory == nil or fromCategory ~= toCategory then
        return nil, "unsupportedState"
    end

    local yards, distanceError = Movement.Distance(from, to)
    if yards == nil then
        return nil, distanceError
    end

    if yards == 0 then
        return nil, "stationary"
    end

    local speed = yards / elapsed
    if not isFiniteNumber(speed) or speed > maxSpeedByCategory[toCategory] then
        return nil, "implausibleSpeed"
    end

    return {
        category = toCategory,
        yards = yards,
        elapsed = elapsed,
        from = from,
        to = to,
    }
end
