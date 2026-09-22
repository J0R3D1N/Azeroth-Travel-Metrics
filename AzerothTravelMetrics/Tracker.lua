local _, ATM = ...

ATM.Tracker = {}

local Tracker = ATM.Tracker
local TrackerPrototype = {}
TrackerPrototype.__index = TrackerPrototype

local function copySample(sample)
    return {
        x = sample.x,
        y = sample.y,
        z = sample.z,
        mapID = sample.mapID,
        instanceID = sample.instanceID,
        time = sample.time,
        onTaxi = sample.onTaxi,
        swimming = sample.swimming,
        mounted = sample.mounted,
        grounded = sample.grounded,
    }
end

local function isFinitePositiveInteger(value)
    return type(value) == "number"
        and value == value
        and value > 0
        and value < math.huge
        and value % 1 == 0
end

local function requireFunction(container, containerName, functionName)
    if type(container) ~= "table" or type(container[functionName]) ~= "function" then
        error(
            string.format("Tracker.New requires deps.%s.%s", containerName, functionName),
            3
        )
    end
end

function Tracker.New(deps)
    if type(deps) ~= "table" then
        error("Tracker.New requires deps", 2)
    end

    requireFunction(deps.compat, "compat", "ReadSample")
    requireFunction(deps.storage, "storage", "AddDistance")
    requireFunction(deps.storage, "storage", "EnsureLevel")
    requireFunction(deps.movement, "movement", "BuildSegment")

    if type(deps.character) ~= "table"
        or type(deps.character.diagnostics) ~= "table"
    then
        error("Tracker.New requires deps.character.diagnostics", 2)
    end
    if not isFinitePositiveInteger(deps.level) then
        error("Tracker.New requires a finite positive integer deps.level", 2)
    end
    if type(deps.emit) ~= "function" then
        error("Tracker.New requires deps.emit", 2)
    end

    return setmetatable({
        compat = deps.compat,
        storage = deps.storage,
        movement = deps.movement,
        character = deps.character,
        level = deps.level,
        emit = deps.emit,
        previous = nil,
    }, TrackerPrototype)
end

local function incrementDiagnostic(character, reason)
    local current = character.diagnostics[reason]
    if type(current) ~= "number"
        or current ~= current
        or current < 0
        or current >= math.huge
        or current % 1 ~= 0
    then
        current = 0
    end

    character.diagnostics[reason] = current + 1
end

function TrackerPrototype:ResetBaseline()
    self.previous = nil
end

function TrackerPrototype:SetLevel(level, now)
    if not isFinitePositiveInteger(level) then
        return nil, "invalidLevel"
    end
    if not isFinitePositiveInteger(now) then
        return nil, "invalidTime"
    end

    local levelBucket, reason = self.storage.EnsureLevel(self.character, level, now)
    if not levelBucket then
        return nil, reason or "ensureLevelFailed"
    end

    self.level = level
    self.previous = nil

    return true
end

function TrackerPrototype:Sample()
    local current, reason = self.compat.ReadSample()
    if current == nil then
        reason = reason or "sampleUnavailable"
        incrementDiagnostic(self.character, reason)
        self.previous = nil
        return nil, reason
    end

    local previous = self.previous
    self.previous = copySample(current)

    if previous == nil then
        return nil, "baseline"
    end

    local segment
    segment, reason = self.movement.BuildSegment(previous, current)
    if segment == nil then
        reason = reason or "segmentRejected"
        if reason ~= "stationary" then
            incrementDiagnostic(self.character, reason)
        end
        return nil, reason
    end

    local stored
    stored, reason = self.storage.AddDistance(
        self.character,
        self.level,
        segment.category,
        segment.yards
    )
    if not stored then
        reason = reason or "storageRejected"
        incrementDiagnostic(self.character, reason)
        return nil, reason
    end

    local emitCallSucceeded, emitSucceeded = pcall(
        self.emit,
        "movementSegment",
        segment
    )
    if not emitCallSucceeded or emitSucceeded == false then
        incrementDiagnostic(self.character, "emitFailed")
        return segment, "emitFailed"
    end

    return segment
end
