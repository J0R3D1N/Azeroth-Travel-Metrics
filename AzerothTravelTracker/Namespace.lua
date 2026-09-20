local addonName, ATT = ...

ATT.name = addonName
ATT.SCHEMA_VERSION = 1
ATT.SAMPLE_INTERVAL_SECONDS = 0.5
ATT.MAX_SAMPLE_GAP_SECONDS = 3

ATT.Categories = {
    ON_FOOT = "onFoot",
    SWIMMING = "swimming",
    TAXI = "taxi",
}

local callbacks = {}

function ATT.Subscribe(eventName, callback)
    callbacks[eventName] = callbacks[eventName] or {}
    table.insert(callbacks[eventName], callback)
end

function ATT.Emit(eventName, payload)
    local failures = {}

    for index, callback in ipairs(callbacks[eventName] or {}) do
        local succeeded, callbackError = pcall(callback, payload)
        if not succeeded then
            table.insert(failures, {
                subscriber = index,
                error = callbackError,
            })
        end
    end

    if #failures > 0 then
        return false, "subscriberFailed", failures
    end

    return nil
end
