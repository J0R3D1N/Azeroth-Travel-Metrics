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
    for _, callback in ipairs(callbacks[eventName] or {}) do
        callback(payload)
    end
end
