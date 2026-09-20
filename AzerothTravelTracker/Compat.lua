local _, ATT = ...

ATT.Compat = {}

local Compat = ATT.Compat

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function isNonemptyString(value)
    return type(value) == "string" and value ~= ""
end

local function callBoolean(api, ...)
    if type(api) ~= "function" then
        return nil, false
    end

    local succeeded, value = pcall(api, ...)
    if not succeeded or type(value) ~= "boolean" then
        return nil, false
    end

    return value, true
end

local function readPosition()
    if type(UnitPosition) ~= "function" then
        return nil
    end

    local succeeded, x, y, z, instanceID = pcall(UnitPosition, "player")
    if not succeeded
        or not isFiniteNumber(x)
        or not isFiniteNumber(y)
        or not isFiniteNumber(z)
        or not isFiniteNumber(instanceID)
    then
        return nil
    end

    return {
        x = x,
        y = y,
        z = z,
        instanceID = instanceID,
    }
end

local function readMapID()
    local api = type(C_Map) == "table" and C_Map.GetBestMapForUnit or nil
    if type(api) ~= "function" then
        return nil
    end

    local succeeded, mapID = pcall(api, "player")
    if not succeeded or not isFiniteNumber(mapID) then
        return nil
    end

    return mapID
end

local function readSampleTime()
    if type(GetTime) ~= "function" then
        return nil
    end

    local succeeded, sampleTime = pcall(GetTime)
    if not succeeded or not isFiniteNumber(sampleTime) then
        return nil
    end

    return sampleTime
end

local function readCapabilities()
    local position = readPosition()
    local mapID = readMapID()
    local sampleTime = readSampleTime()
    local onTaxi, taxi = callBoolean(UnitOnTaxi, "player")
    local swimmingValue, swimming = callBoolean(IsSwimming)
    local mountedValue, mounted = callBoolean(IsMounted)
    local falling, grounded = callBoolean(IsFalling)
    local groundedValue
    if grounded then
        groundedValue = not falling
    end

    local capabilities = {
        position = position ~= nil,
        map = mapID ~= nil,
        time = sampleTime ~= nil,
        taxi = taxi,
        swimming = swimming,
        mounted = mounted,
        grounded = grounded,
    }

    capabilities.taxiReady = capabilities.position
        and capabilities.map
        and capabilities.time
        and capabilities.taxi
    capabilities.swimmingReady = capabilities.taxiReady
        and capabilities.swimming
        and capabilities.mounted
    capabilities.onFootReady = capabilities.swimmingReady
        and capabilities.grounded

    return capabilities, {
        position = position,
        mapID = mapID,
        time = sampleTime,
        onTaxi = onTaxi,
        swimming = swimmingValue,
        mounted = mountedValue,
        grounded = groundedValue,
    }
end

function Compat.GetCapabilities()
    local capabilities = readCapabilities()
    return capabilities
end

function Compat.ReadSample()
    local capabilities, values = readCapabilities()

    if not capabilities.position then
        return nil, "positionUnavailable"
    end
    if not capabilities.map then
        return nil, "mapUnavailable"
    end
    if not capabilities.time then
        return nil, "timeUnavailable"
    end

    return {
        x = values.position.x,
        y = values.position.y,
        z = values.position.z,
        mapID = values.mapID,
        instanceID = values.position.instanceID,
        time = values.time,
        onTaxi = values.onTaxi,
        swimming = values.swimming,
        mounted = values.mounted,
        grounded = values.grounded,
        capabilities = capabilities,
    }
end

function Compat.GetCurrentLevel()
    if type(UnitLevel) ~= "function" then
        return nil, "levelUnavailable"
    end

    local succeeded, level = pcall(UnitLevel, "player")
    if not succeeded
        or not isFiniteNumber(level)
        or level <= 0
        or level % 1 ~= 0
    then
        return nil, "levelUnavailable"
    end

    return level
end

function Compat.GetNow()
    if type(GetServerTime) == "function" then
        local succeeded, now = pcall(GetServerTime)
        if succeeded and isFiniteNumber(now) then
            return now
        end
    end

    if type(time) == "function" then
        local succeeded, now = pcall(time)
        if succeeded and isFiniteNumber(now) then
            return now
        end
    end

    return nil, "timeUnavailable"
end

function Compat.GetCharacterIdentity()
    if type(UnitName) ~= "function" or type(UnitRace) ~= "function" then
        return nil, "identityUnavailable"
    end

    local nameSucceeded, name, realm = pcall(UnitName, "player")
    if not nameSucceeded or not isNonemptyString(name) then
        return nil, "identityUnavailable"
    end

    if not isNonemptyString(realm) then
        if type(GetRealmName) ~= "function" then
            return nil, "identityUnavailable"
        end

        local realmSucceeded, fallbackRealm = pcall(GetRealmName)
        if not realmSucceeded or not isNonemptyString(fallbackRealm) then
            return nil, "identityUnavailable"
        end
        realm = fallbackRealm
    end

    local raceSucceeded, _, raceFile = pcall(UnitRace, "player")
    if not raceSucceeded or not isNonemptyString(raceFile) then
        return nil, "identityUnavailable"
    end

    local level, levelReason = Compat.GetCurrentLevel()
    if level == nil then
        return nil, levelReason
    end

    local now, timeReason = Compat.GetNow()
    if now == nil then
        return nil, timeReason
    end

    return {
        name = name,
        realm = realm,
        raceFile = raceFile,
        level = level,
        now = now,
    }
end

function Compat.Print(message)
    local chatFrame = DEFAULT_CHAT_FRAME
    local addMessage = type(chatFrame) == "table" and chatFrame.AddMessage or nil
    if type(addMessage) == "function" then
        local succeeded = pcall(addMessage, chatFrame, message)
        if succeeded then
            return
        end
    end

    local output = _G and _G.print or nil
    if type(output) == "function" and output ~= Compat.Print then
        pcall(output, message)
    end
end
