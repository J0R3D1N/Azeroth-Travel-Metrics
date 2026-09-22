local _, ATM = ...

ATM.Distance = {}

local Distance = ATM.Distance

Distance.YARDS_TO_METERS = 0.9144
Distance.YARDS_PER_MILE = 1760

local function precisionForScaledNumber(value)
    if value < 10 then
        return 2
    end

    if value < 100 then
        return 1
    end

    return 0
end

local function roundToPrecision(value, precision)
    local factor = 10 ^ precision
    return math.floor((value * factor) + 0.5) / factor
end

local function formatScaledNumber(value, suffix)
    local precision = precisionForScaledNumber(value)
    local rounded = roundToPrecision(value, precision)
    local roundedPrecision = precisionForScaledNumber(rounded)

    if roundedPrecision ~= precision then
        precision = roundedPrecision
        rounded = roundToPrecision(value, precision)
    end

    return string.format("%." .. precision .. "f%s", rounded, suffix)
end

function Distance.YardsToMeters(yards)
    return yards * Distance.YARDS_TO_METERS
end

function Distance.FormatNumber(value)
    if value < 10000 then
        return tostring(value)
    end

    local scales = {
        { divisor = 1000, suffix = "K" },
        { divisor = 1000000, suffix = "M" },
        { divisor = 1000000000, suffix = "B" },
    }
    local scaleIndex = 1

    if value >= 1000000 then
        scaleIndex = 2
    end
    if value >= 1000000000 then
        scaleIndex = 3
    end

    while scaleIndex < #scales do
        local scale = scales[scaleIndex]
        local scaled = value / scale.divisor
        local precision = precisionForScaledNumber(scaled)
        if roundToPrecision(scaled, precision) < 1000 then
            break
        end
        scaleIndex = scaleIndex + 1
    end

    local scale = scales[scaleIndex]
    return formatScaledNumber(value / scale.divisor, scale.suffix)
end

function Distance.Format(yards, units)
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
