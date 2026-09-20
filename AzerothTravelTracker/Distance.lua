local _, ATT = ...

ATT.Distance = {}

local Distance = ATT.Distance

Distance.YARDS_TO_METERS = 0.9144
Distance.YARDS_PER_MILE = 1760

function Distance.YardsToMeters(yards)
    return yards * Distance.YARDS_TO_METERS
end

function Distance.Format(yards, units)
    if units == "imperial" then
        if yards < Distance.YARDS_PER_MILE then
            return string.format("%.0f yd", yards)
        end

        return string.format("%.2f mi", yards / Distance.YARDS_PER_MILE)
    end

    local meters = Distance.YardsToMeters(yards)
    if meters < 1000 then
        return string.format("%.1f m", meters)
    end

    return string.format("%.2f km", meters / 1000)
end
