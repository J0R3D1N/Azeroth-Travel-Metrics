local addonName, ATM = ...

ATM.name = addonName
ATM.SCHEMA_VERSION = 1
ATM.VERSION_FALLBACK = "1.0.0-beta"
ATM.SAMPLE_INTERVAL_SECONDS = 0.5
ATM.MAX_SAMPLE_GAP_SECONDS = 3

ATM.Categories = {
    ON_FOOT = "onFoot",
    SWIMMING = "swimming",
    TAXI = "taxi",
}

local callbacks = {}

function ATM.Subscribe(eventName, callback)
    callbacks[eventName] = callbacks[eventName] or {}
    table.insert(callbacks[eventName], callback)
end

function ATM.Emit(eventName, payload)
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
