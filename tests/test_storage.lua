local testlib = require("testlib")

local function loadStorage()
    return testlib.loadAddon({
        "AzerothTravelMetrics\\Namespace.lua",
        "AzerothTravelMetrics\\Storage.lua",
    })
end

local function assertTotals(totals, onFoot, swimming, taxi)
    testlib.equal(totals.onFoot, onFoot)
    testlib.equal(totals.swimming, swimming)
    testlib.equal(totals.taxi, taxi)
end

local function newCharacter(storage)
    local db = storage.Initialize(nil)
    local character = storage.GetCharacter(db, "Thrall-Area 52", {
        name = "Thrall",
        realm = "Area 52",
        raceFile = "Orc",
        level = 12,
        now = 1000,
    })
    storage.StartSession(character, 1000)
    return character
end

testlib.case("storage initializes nil with v1 defaults", function()
    local addon = loadStorage()
    local db, initializationError = addon.Storage.Initialize(nil)

    testlib.equal(initializationError, nil)
    testlib.equal(db.schemaVersion, addon.SCHEMA_VERSION)
    testlib.equal(db.settings.units, "metric")
    testlib.equal(db.settings.showMinimap, true)
    testlib.equal(db.settings.minimapAngle, 225)
    testlib.equal(db.settings.showDiagnostics, false)
    testlib.equal(db.settings.hudPoint, "CENTER")
    testlib.equal(db.settings.hudX, 0)
    testlib.equal(db.settings.hudY, 0)
    testlib.truthy(type(db.characters) == "table")
end)

testlib.case("storage initializes a schema-less empty table in place", function()
    local addon = loadStorage()
    local existing = {}
    local db, initializationError = addon.Storage.Initialize(existing)

    testlib.equal(initializationError, nil)
    testlib.equal(db, existing)
    testlib.equal(db.schemaVersion, addon.SCHEMA_VERSION)
    testlib.equal(db.settings.units, "metric")
    testlib.equal(db.settings.showMinimap, true)
    testlib.equal(db.settings.minimapAngle, 225)
    testlib.equal(db.settings.showDiagnostics, false)
    testlib.equal(db.settings.hudPoint, "CENTER")
    testlib.equal(db.settings.hudX, 0)
    testlib.equal(db.settings.hudY, 0)
    testlib.truthy(type(db.characters) == "table")
end)

testlib.case("storage preserves customized v1 settings and characters", function()
    local addon = loadStorage()
    local character = { sentinel = "preserved" }
    local existing = {
        schemaVersion = 1,
        settings = {
            units = "imperial",
            showMinimap = false,
            minimapAngle = 135,
            showDiagnostics = true,
            hudPoint = "TOPRIGHT",
            hudX = -25,
            hudY = -40,
        },
        characters = {
            ["Jaina-Proudmoore"] = character,
        },
    }

    local db = addon.Storage.Initialize(existing)

    testlib.equal(db, existing)
    testlib.equal(db.settings.units, "imperial")
    testlib.equal(db.settings.showMinimap, false)
    testlib.equal(db.settings.minimapAngle, 135)
    testlib.equal(db.settings.showDiagnostics, true)
    testlib.equal(db.settings.hudPoint, "TOPRIGHT")
    testlib.equal(db.settings.hudX, -25)
    testlib.equal(db.settings.hudY, -40)
    testlib.equal(db.characters["Jaina-Proudmoore"], character)
end)

testlib.case("storage backfills missing known v1 settings without overwriting custom values", function()
    local addon = loadStorage()
    local existing = {
        schemaVersion = 1,
        settings = {
            units = "imperial",
            showMinimap = false,
            showDiagnostics = true,
        },
        characters = {},
    }

    local db = addon.Storage.Initialize(existing)

    testlib.equal(db, existing)
    testlib.equal(db.settings.units, "imperial")
    testlib.equal(db.settings.showMinimap, false)
    testlib.equal(db.settings.minimapAngle, 225)
    testlib.equal(db.settings.showDiagnostics, true)
    testlib.equal(db.settings.hudPoint, "CENTER")
    testlib.equal(db.settings.hudX, 0)
    testlib.equal(db.settings.hudY, 0)
end)

testlib.case("storage repairs malformed HUD positions to safe center defaults", function()
    local addon = loadStorage()
    local invalidPositions = {
        { point = "MIDDLE", x = 10, y = 20 },
        { point = "TOP", x = "10", y = 20 },
        { point = "BOTTOMLEFT", x = 10, y = math.huge },
    }

    for _, invalid in ipairs(invalidPositions) do
        local db = addon.Storage.Initialize({
            schemaVersion = 1,
            settings = {
                hudPoint = invalid.point,
                hudX = invalid.x,
                hudY = invalid.y,
            },
            characters = {},
        })

        testlib.equal(db.settings.hudPoint, "CENTER")
        testlib.equal(db.settings.hudX, 0)
        testlib.equal(db.settings.hudY, 0)
    end
end)

testlib.case("storage creates a character without starting a session", function()
    local addon = loadStorage()
    local db = addon.Storage.Initialize(nil)

    local character, resolution = addon.Storage.GetCharacter(db, "Thrall-Area 52", {
        name = "Thrall",
        realm = "Area 52",
        raceFile = "Orc",
        level = 12,
        now = 1000,
    })

    testlib.equal(resolution, "created")
    testlib.equal(db.characters["Thrall-Area 52"], character)
    testlib.equal(character.identity.name, "Thrall")
    testlib.equal(character.identity.realm, "Area 52")
    testlib.equal(character.identity.raceFile, "Orc")
    testlib.equal(character.identity.firstSeenAt, 1000)
    assertTotals(character.lifetime, 0, 0, 0)
    assertTotals(character.levels[12], 0, 0, 0)
    testlib.equal(character.levels[12].reachedAt, 1000)
    testlib.equal(character.session, nil)
    testlib.truthy(type(character.diagnostics) == "table")
end)

testlib.case("storage starts a fresh session explicitly", function()
    local addon = loadStorage()
    local db = addon.Storage.Initialize(nil)
    local character = addon.Storage.GetCharacter(db, "Thrall-Area 52", {
        name = "Thrall",
        realm = "Area 52",
        raceFile = "Orc",
        level = 12,
        now = 1000,
    })

    local session = addon.Storage.StartSession(character, 1100)

    testlib.equal(session, character.session)
    assertTotals(session, 0, 0, 0)
    testlib.equal(session.startedAt, 1100)
end)

testlib.case("storage exact lookup refreshes identity without resetting data", function()
    local addon = loadStorage()
    local db = addon.Storage.Initialize(nil)
    local character = addon.Storage.GetCharacter(db, "Thrall-Area 52", {
        name = "Thrall",
        realm = "Area 52",
        raceFile = "Orc",
        level = 12,
        now = 1000,
    })
    addon.Storage.StartSession(character, 1000)
    addon.Storage.AddDistance(character, 12, "onFoot", 25)
    character.diagnostics.samples = 7
    local session = character.session
    local lifetime = character.lifetime
    local levels = character.levels
    local diagnostics = character.diagnostics

    local sameCharacter, resolution = addon.Storage.GetCharacter(db, "Thrall-Area 52", {
        name = "Goel",
        realm = "Area 52",
        raceFile = "MagharOrc",
        level = 13,
        now = 2000,
    })

    testlib.equal(resolution, "exact")
    testlib.equal(sameCharacter, character)
    testlib.equal(character.session, session)
    testlib.equal(character.lifetime, lifetime)
    testlib.equal(character.levels, levels)
    testlib.equal(character.diagnostics, diagnostics)
    testlib.equal(character.identity.name, "Goel")
    testlib.equal(character.identity.realm, "Area 52")
    testlib.equal(character.identity.raceFile, "MagharOrc")
    testlib.equal(character.identity.firstSeenAt, 1000)
    assertTotals(character.lifetime, 25, 0, 0)
    assertTotals(character.levels[12], 25, 0, 0)
    testlib.equal(character.levels[12].reachedAt, 1000)
    assertTotals(character.levels[13], 0, 0, 0)
    testlib.equal(character.levels[13].reachedAt, 2000)
    assertTotals(character.session, 25, 0, 0)
    testlib.equal(character.session.startedAt, 1000)
    testlib.equal(character.diagnostics.samples, 7)
end)

testlib.case("storage validates persisted session totals", function()
    local addon = loadStorage()

    testlib.equal(addon.Storage.IsValidSession({
        startedAt = 1000,
        onFoot = 1,
        swimming = 2,
        taxi = 3,
    }), true)
    testlib.equal(addon.Storage.IsValidSession({
        startedAt = 1000,
        onFoot = -1,
        swimming = 2,
        taxi = 3,
    }), false)
    testlib.equal(addon.Storage.IsValidSession({
        startedAt = 1000,
        onFoot = 1,
        swimming = "2",
        taxi = 3,
    }), false)
    testlib.equal(addon.Storage.IsValidSession({}), false)
    testlib.equal(addon.Storage.IsValidSession(nil), false)
end)

testlib.case("storage uniquely rekeys a normalized identity without losing data", function()
    local addon = loadStorage()
    local character = {
        identity = {
            name = " Thr all ",
            realm = " Area 52 ",
            raceFile = "Orc",
            firstSeenAt = 500,
        },
        session = {
            onFoot = 11,
            swimming = 12,
            taxi = 13,
            startedAt = 700,
        },
        lifetime = {
            onFoot = 21,
            swimming = 22,
            taxi = 23,
        },
        levels = {
            [11] = {
                onFoot = 31,
                swimming = 32,
                taxi = 33,
                reachedAt = 600,
            },
        },
        diagnostics = {
            samples = 9,
        },
    }
    local db = addon.Storage.Initialize({
        schemaVersion = addon.SCHEMA_VERSION,
        characters = {
            [" Thr all - Area 52 "] = character,
        },
    })
    local session = character.session
    local lifetime = character.lifetime
    local levels = character.levels
    local diagnostics = character.diagnostics

    local resolved, resolution = addon.Storage.GetCharacter(db, "Thrall-Area52", {
        name = "thrall",
        realm = "AREA52",
        raceFile = "MagharOrc",
        level = 12,
        now = 2000,
    })

    testlib.equal(resolution, "rekeyed")
    testlib.equal(resolved, character)
    testlib.equal(db.characters["Thrall-Area52"], character)
    testlib.equal(db.characters[" Thr all - Area 52 "], nil)
    testlib.equal(character.session, session)
    testlib.equal(character.lifetime, lifetime)
    testlib.equal(character.levels, levels)
    testlib.equal(character.diagnostics, diagnostics)
    testlib.equal(character.identity.name, "thrall")
    testlib.equal(character.identity.realm, "AREA52")
    testlib.equal(character.identity.raceFile, "MagharOrc")
    testlib.equal(character.identity.firstSeenAt, 500)
    assertTotals(character.session, 11, 12, 13)
    assertTotals(character.lifetime, 21, 22, 23)
    assertTotals(character.levels[11], 31, 32, 33)
    assertTotals(character.levels[12], 0, 0, 0)
    testlib.equal(character.levels[12].reachedAt, 2000)
    testlib.equal(character.diagnostics.samples, 9)
end)

testlib.case("storage does not recover whitespace-only normalized names", function()
    local addon = loadStorage()
    local malformed = {
        identity = {
            name = " \t ",
            realm = "Area 52",
            firstSeenAt = 500,
        },
        lifetime = { onFoot = 10, swimming = 20, taxi = 30 },
        levels = {},
        diagnostics = {},
    }
    local db = addon.Storage.Initialize({
        schemaVersion = addon.SCHEMA_VERSION,
        characters = {
            ["Legacy-BlankName"] = malformed,
        },
    })

    local character, resolution = addon.Storage.GetCharacter(db, "Canonical-Area52", {
        name = "\t \n",
        realm = "area52",
        raceFile = "Orc",
        level = 12,
        now = 1000,
    })

    testlib.equal(resolution, "created")
    testlib.equal(db.characters["Legacy-BlankName"], malformed)
    testlib.equal(db.characters["Canonical-Area52"], character)
    testlib.truthy(character ~= malformed)
    assertTotals(character.lifetime, 0, 0, 0)
end)

testlib.case("storage does not recover whitespace-only normalized realms", function()
    local addon = loadStorage()
    local malformed = {
        identity = {
            name = "Thrall",
            realm = " \t ",
            firstSeenAt = 500,
        },
        lifetime = { onFoot = 10, swimming = 20, taxi = 30 },
        levels = {},
        diagnostics = {},
    }
    local db = addon.Storage.Initialize({
        schemaVersion = addon.SCHEMA_VERSION,
        characters = {
            ["Legacy-BlankRealm"] = malformed,
        },
    })

    local character, resolution = addon.Storage.GetCharacter(db, "Thrall-Canonical", {
        name = "thrall",
        realm = "\t \n",
        raceFile = "Orc",
        level = 12,
        now = 1000,
    })

    testlib.equal(resolution, "created")
    testlib.equal(db.characters["Legacy-BlankRealm"], malformed)
    testlib.equal(db.characters["Thrall-Canonical"], character)
    testlib.truthy(character ~= malformed)
    assertTotals(character.lifetime, 0, 0, 0)
end)

testlib.case("storage leaves ambiguous identity matches separate", function()
    local addon = loadStorage()
    local first = {
        identity = {
            name = "Thrall",
            realm = "Area 52",
            firstSeenAt = 100,
        },
        session = { onFoot = 1, swimming = 2, taxi = 3, startedAt = 200 },
        lifetime = { onFoot = 4, swimming = 5, taxi = 6 },
        levels = {},
        diagnostics = {},
    }
    local second = {
        identity = {
            name = " thr all ",
            realm = "area52",
            firstSeenAt = 300,
        },
        session = { onFoot = 7, swimming = 8, taxi = 9, startedAt = 400 },
        lifetime = { onFoot = 10, swimming = 11, taxi = 12 },
        levels = {},
        diagnostics = {},
    }
    local db = addon.Storage.Initialize({
        schemaVersion = addon.SCHEMA_VERSION,
        characters = {
            ["Thrall-Area 52-old"] = first,
            ["Thrall-Area52-other"] = second,
        },
    })

    local character, resolution = addon.Storage.GetCharacter(db, "Thrall-Area52", {
        name = "THRALL",
        realm = "AREA 52",
        raceFile = "Orc",
        level = 12,
        now = 1000,
    })

    testlib.equal(resolution, "ambiguous")
    testlib.equal(db.characters["Thrall-Area 52-old"], first)
    testlib.equal(db.characters["Thrall-Area52-other"], second)
    testlib.equal(db.characters["Thrall-Area52"], character)
    testlib.truthy(character ~= first)
    testlib.truthy(character ~= second)
    testlib.equal(character.diagnostics.ambiguousIdentity, 1)
    testlib.equal(character.session, nil)
    assertTotals(character.lifetime, 0, 0, 0)
    assertTotals(character.levels[12], 0, 0, 0)
end)

testlib.case("storage adds distance to session lifetime and current level", function()
    local addon = loadStorage()
    local character = newCharacter(addon.Storage)

    local updated, addError = addon.Storage.AddDistance(character, 12, "onFoot", 37.5)

    testlib.equal(updated, true)
    testlib.equal(addError, nil)
    assertTotals(character.session, 37.5, 0, 0)
    assertTotals(character.lifetime, 37.5, 0, 0)
    assertTotals(character.levels[12], 37.5, 0, 0)
end)

testlib.case("storage isolates distance categories", function()
    local addon = loadStorage()
    local character = newCharacter(addon.Storage)

    addon.Storage.AddDistance(character, 12, "onFoot", 10)
    addon.Storage.AddDistance(character, 12, "swimming", 20)
    addon.Storage.AddDistance(character, 12, "taxi", 30)

    assertTotals(character.session, 10, 20, 30)
    assertTotals(character.lifetime, 10, 20, 30)
    assertTotals(character.levels[12], 10, 20, 30)
end)

testlib.case("storage resets only the current session", function()
    local addon = loadStorage()
    local character = newCharacter(addon.Storage)
    addon.Storage.AddDistance(character, 12, "swimming", 42)
    character.diagnostics.samples = 9

    addon.Storage.ResetSession(character, 1500)

    assertTotals(character.session, 0, 0, 0)
    testlib.equal(character.session.startedAt, 1500)
    assertTotals(character.lifetime, 0, 42, 0)
    assertTotals(character.levels[12], 0, 42, 0)
    testlib.equal(character.identity.firstSeenAt, 1000)
    testlib.equal(character.diagnostics.samples, 9)
end)

testlib.case("storage preserves level reachedAt and totals", function()
    local addon = loadStorage()
    local character = newCharacter(addon.Storage)
    addon.Storage.AddDistance(character, 12, "taxi", 15)

    local level = addon.Storage.EnsureLevel(character, 12, 2000)

    testlib.equal(level, character.levels[12])
    testlib.equal(level.reachedAt, 1000)
    assertTotals(level, 0, 0, 15)
end)

testlib.case("storage fills a missing level reachedAt only once", function()
    local addon = loadStorage()
    local character = newCharacter(addon.Storage)
    character.levels[13] = {
        onFoot = 5,
        swimming = 6,
        taxi = 7,
    }

    local level = addon.Storage.EnsureLevel(character, 13, 2000)
    addon.Storage.EnsureLevel(character, 13, 3000)

    testlib.equal(level.reachedAt, 2000)
    assertTotals(level, 5, 6, 7)
end)

testlib.case("storage rejects unsupported schema versions without mutation", function()
    local addon = loadStorage()
    local unsupportedVersions = {
        { name = "string", value = "1" },
        { name = "boolean", value = true },
        { name = "NaN", value = 0 / 0 },
        { name = "positive infinity", value = math.huge },
        { name = "negative infinity", value = -math.huge },
        { name = "fractional", value = 0.5 },
        { name = "zero", value = 0 },
        { name = "negative", value = -1 },
        { name = "future", value = addon.SCHEMA_VERSION + 1 },
        { name = "table", value = {} },
    }

    for _, unsupported in ipairs(unsupportedVersions) do
        local sentinel = {
            value = "preserved",
        }
        local existing = {
            schemaVersion = unsupported.value,
            sentinel = sentinel,
        }
        local succeeded, db, initializationError = pcall(addon.Storage.Initialize, existing)

        testlib.truthy(succeeded, unsupported.name .. " schema version raised an error")
        testlib.equal(db, existing, unsupported.name .. " schema did not return the original table")
        testlib.equal(initializationError, "unsupportedSchema", unsupported.name .. " schema returned the wrong error")
        if unsupported.value ~= unsupported.value then
            testlib.truthy(
                existing.schemaVersion ~= existing.schemaVersion,
                unsupported.name .. " schema version mutated"
            )
        else
            testlib.equal(existing.schemaVersion, unsupported.value, unsupported.name .. " schema version mutated")
        end
        testlib.equal(existing.sentinel, sentinel, unsupported.name .. " sentinel mutated")
        testlib.equal(existing.settings, nil, unsupported.name .. " settings mutated")
        testlib.equal(existing.characters, nil, unsupported.name .. " characters mutated")
    end
end)

testlib.case("storage rejects invalid categories without mutation", function()
    local addon = loadStorage()
    local character = newCharacter(addon.Storage)

    local updated, addError = addon.Storage.AddDistance(character, 12, "flying", 10)

    testlib.equal(updated, nil)
    testlib.equal(addError, "invalidCategory")
    assertTotals(character.session, 0, 0, 0)
    assertTotals(character.lifetime, 0, 0, 0)
    assertTotals(character.levels[12], 0, 0, 0)
    testlib.equal(character.session.flying, nil)
    testlib.equal(character.lifetime.flying, nil)
    testlib.equal(character.levels[12].flying, nil)
end)

testlib.case("storage rejects invalid distances without mutation", function()
    local addon = loadStorage()
    local character = newCharacter(addon.Storage)
    local invalidDistances = {
        -1,
        "10",
        0 / 0,
        math.huge,
        -math.huge,
    }

    for _, yards in ipairs(invalidDistances) do
        local updated, addError = addon.Storage.AddDistance(character, 12, "onFoot", yards)

        testlib.equal(updated, nil)
        testlib.equal(addError, "invalidDistance")
    end

    assertTotals(character.session, 0, 0, 0)
    assertTotals(character.lifetime, 0, 0, 0)
    assertTotals(character.levels[12], 0, 0, 0)
end)

testlib.case("storage rejects a corrupt session total without mutation", function()
    local addon = loadStorage()
    local character = newCharacter(addon.Storage)
    character.session.onFoot = "10"
    character.lifetime.onFoot = 20
    character.levels[12].onFoot = 30

    local updated, addError = addon.Storage.AddDistance(character, 12, "onFoot", 5)

    testlib.equal(updated, nil)
    testlib.equal(addError, "invalidStoredTotal")
    testlib.equal(character.session.onFoot, "10")
    testlib.equal(character.lifetime.onFoot, 20)
    testlib.equal(character.levels[12].onFoot, 30)
end)

testlib.case("storage rejects a corrupt lifetime total without partial mutation", function()
    local addon = loadStorage()
    local character = newCharacter(addon.Storage)
    character.session.onFoot = 10
    character.lifetime.onFoot = math.huge
    character.levels[12].onFoot = 30

    local updated, addError = addon.Storage.AddDistance(character, 12, "onFoot", 5)

    testlib.equal(updated, nil)
    testlib.equal(addError, "invalidStoredTotal")
    testlib.equal(character.session.onFoot, 10)
    testlib.equal(character.lifetime.onFoot, math.huge)
    testlib.equal(character.levels[12].onFoot, 30)
end)

testlib.case("storage rejects a corrupt level total without partial mutation", function()
    local addon = loadStorage()
    local character = newCharacter(addon.Storage)
    local corruptTotal = 0 / 0
    character.session.onFoot = 10
    character.lifetime.onFoot = 20
    character.levels[12].onFoot = corruptTotal

    local updated, addError = addon.Storage.AddDistance(character, 12, "onFoot", 5)

    testlib.equal(updated, nil)
    testlib.equal(addError, "invalidStoredTotal")
    testlib.equal(character.session.onFoot, 10)
    testlib.equal(character.lifetime.onFoot, 20)
    testlib.truthy(character.levels[12].onFoot ~= character.levels[12].onFoot)
end)

testlib.case("storage rejects overflowing additions without mutation", function()
    local addon = loadStorage()
    local character = newCharacter(addon.Storage)
    character.session.onFoot = 1e308
    character.lifetime.onFoot = 1e308
    character.levels[12].onFoot = 1e308

    local updated, addError = addon.Storage.AddDistance(character, 12, "onFoot", 1e308)

    testlib.equal(updated, nil)
    testlib.equal(addError, "invalidDistance")
    testlib.equal(character.session.onFoot, 1e308)
    testlib.equal(character.lifetime.onFoot, 1e308)
    testlib.equal(character.levels[12].onFoot, 1e308)
end)

testlib.case("storage treats zero distance as a successful no-op", function()
    local addon = loadStorage()
    local character = newCharacter(addon.Storage)

    local updated, addError = addon.Storage.AddDistance(character, 12, "onFoot", 0)

    testlib.equal(updated, true)
    testlib.equal(addError, nil)
    assertTotals(character.session, 0, 0, 0)
    assertTotals(character.lifetime, 0, 0, 0)
    assertTotals(character.levels[12], 0, 0, 0)
end)

testlib.case("storage requires an established level bucket for distance", function()
    local addon = loadStorage()
    local character = newCharacter(addon.Storage)

    local updated, addError = addon.Storage.AddDistance(character, 13, "onFoot", 10)

    testlib.equal(updated, nil)
    testlib.equal(addError, "missingLevel")
    assertTotals(character.session, 0, 0, 0)
    assertTotals(character.lifetime, 0, 0, 0)
    testlib.equal(character.levels[13], nil)
end)
