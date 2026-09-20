local _, ATT = ...

ATT.Distance = {}

local Distance = ATT.Distance

Distance.YARDS_TO_METERS = 0.9144
Distance.YARDS_PER_MILE = 1760

local function isFiniteNonnegativeNumber(value)
    return type(value) == "number"
        and value == value
        and value >= 0
        and value < math.huge
end

local function formatScaledNumber(value, suffix)
    if value < 10 then
        return string.format("%.2f%s", value, suffix)
    end

    if value < 100 then
        return string.format("%.1f%s", value, suffix)
    end

    return string.format("%.0f%s", value, suffix)
end

function Distance.YardsToMeters(yards)
    return yards * Distance.YARDS_TO_METERS
end

function Distance.FormatNumber(value)
    if not isFiniteNonnegativeNumber(value) then
        return nil
    end

    if value < 10000 then
        return tostring(value)
    end

    if value >= 1000000000 then
        return formatScaledNumber(value / 1000000000, "B")
    end

    if value >= 1000000 then
        return formatScaledNumber(value / 1000000, "M")
    end

    return formatScaledNumber(value / 1000, "K")
end

function Distance.Format(yards, units)
    if not isFiniteNonnegativeNumber(yards) then
        return nil
    end

    if units == "imperial" then
        if yards < Distance.YARDS_PER_MILE then
            return string.format("%.0f yd", yards)
        end

        local miles = yards / Distance.YARDS_PER_MILE
        if miles >= 10000 then
            return Distance.FormatNumber(miles) .. " mi"
        end

        return string.format("%.2f mi", miles)
    end

    local meters = Distance.YardsToMeters(yards)
    if meters < 1000 then
        return string.format("%.1f m", meters)
    end

    local kilometers = meters / 1000
    if kilometers >= 10000 then
        return Distance.FormatNumber(kilometers) .. " km"
    end

    return string.format("%.2f km", kilometers)
end
