local _, ATT = ...

ATT.Storage = {}

local Storage = ATT.Storage

local validCategories = {
    [ATT.Categories.ON_FOOT] = true,
    [ATT.Categories.SWIMMING] = true,
    [ATT.Categories.TAXI] = true,
}

local migrations = {}

local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function isFiniteNonnegativeNumber(value)
    return isFiniteNumber(value) and value >= 0
end

local function newTotals()
    return {
        onFoot = 0,
        swimming = 0,
        taxi = 0,
    }
end

local function ensureTotals(totals)
    totals = totals or {}

    if totals.onFoot == nil then
        totals.onFoot = 0
    end
    if totals.swimming == nil then
        totals.swimming = 0
    end
    if totals.taxi == nil then
        totals.taxi = 0
    end

    return totals
end

local function initializeVersionOne(db)
    db.schemaVersion = ATT.SCHEMA_VERSION
    db.settings = db.settings or {}

    if db.settings.units == nil then
        db.settings.units = "metric"
    end
    if db.settings.showMinimap == nil then
        db.settings.showMinimap = true
    end
    if db.settings.minimapAngle == nil then
        db.settings.minimapAngle = 225
    end
    if db.settings.showDiagnostics == nil then
        db.settings.showDiagnostics = false
    end

    db.characters = db.characters or {}

    return db
end

function Storage.Initialize(existing)
    local db = existing or {}
    local schemaVersion = db.schemaVersion

    if schemaVersion == nil then
        if next(db) ~= nil then
            return db, "unsupportedSchema"
        end

        return initializeVersionOne(db)
    end

    if not isFiniteNumber(schemaVersion)
        or schemaVersion % 1 ~= 0
        or schemaVersion < 1
    then
        return db, "unsupportedSchema"
    end

    if schemaVersion > ATT.SCHEMA_VERSION then
        return db, "unsupportedSchema"
    end

    while schemaVersion < ATT.SCHEMA_VERSION do
        local migrate = migrations[schemaVersion]
        if migrate == nil then
            return db, "unsupportedSchema"
        end

        db = migrate(db)
        schemaVersion = db.schemaVersion
    end

    return initializeVersionOne(db)
end

function Storage.EnsureLevel(character, level, now)
    character.levels = character.levels or {}

    local levelTotals = character.levels[level]
    if levelTotals == nil then
        levelTotals = newTotals()
        levelTotals.reachedAt = now
        character.levels[level] = levelTotals
    else
        ensureTotals(levelTotals)
        if levelTotals.reachedAt == nil then
            levelTotals.reachedAt = now
        end
    end

    return levelTotals
end

function Storage.ResetSession(character, now)
    character.session = newTotals()
    character.session.startedAt = now

    return character.session
end

function Storage.GetCharacter(db, key, identity)
    local character = db.characters[key]

    if character == nil then
        character = {
            identity = {
                name = identity.name,
                realm = identity.realm,
                raceFile = identity.raceFile,
                firstSeenAt = identity.now,
            },
            lifetime = newTotals(),
            levels = {},
            diagnostics = {},
        }
        db.characters[key] = character
    else
        character.identity = character.identity or {}
        character.lifetime = ensureTotals(character.lifetime)
        character.levels = character.levels or {}
        character.diagnostics = character.diagnostics or {}

        if character.identity.firstSeenAt == nil then
            character.identity.firstSeenAt = identity.now
        end
        if identity.name ~= nil then
            character.identity.name = identity.name
        end
        if identity.realm ~= nil then
            character.identity.realm = identity.realm
        end
        if identity.raceFile ~= nil then
            character.identity.raceFile = identity.raceFile
        end
    end

    Storage.EnsureLevel(character, identity.level, identity.now)
    Storage.ResetSession(character, identity.now)

    return character
end

function Storage.AddDistance(character, level, category, yards)
    if not validCategories[category] then
        return nil, "invalidCategory"
    end

    if not isFiniteNonnegativeNumber(yards) then
        return nil, "invalidDistance"
    end

    local levelTotals = character.levels and character.levels[level]
    if levelTotals == nil then
        return nil, "missingLevel"
    end

    if not isFiniteNonnegativeNumber(character.session[category])
        or not isFiniteNonnegativeNumber(character.lifetime[category])
        or not isFiniteNonnegativeNumber(levelTotals[category])
    then
        return nil, "invalidStoredTotal"
    end

    if yards == 0 then
        return true
    end

    local sessionTotal = character.session[category] + yards
    local lifetimeTotal = character.lifetime[category] + yards
    local levelTotal = levelTotals[category] + yards

    if not isFiniteNonnegativeNumber(sessionTotal)
        or not isFiniteNonnegativeNumber(lifetimeTotal)
        or not isFiniteNonnegativeNumber(levelTotal)
    then
        return nil, "invalidDistance"
    end

    character.session[category] = sessionTotal
    character.lifetime[category] = lifetimeTotal
    levelTotals[category] = levelTotal

    return true
end
