local testlib = require("testlib")

local function loadStorage()
    return testlib.loadAddon({
        "AzerothTravelTracker\\Namespace.lua",
        "AzerothTravelTracker\\Storage.lua",
    })
end

local function assertTotals(totals, onFoot, swimming, taxi)
    testlib.equal(totals.onFoot, onFoot)
    testlib.equal(totals.swimming, swimming)
    testlib.equal(totals.taxi, taxi)
end

local function newCharacter(storage)
    local db = storage.Initialize(nil)
    return storage.GetCharacter(db, "Thrall-Area 52", {
        name = "Thrall",
        realm = "Area 52",
        raceFile = "Orc",
        level = 12,
        now = 1000,
    })
end

testlib.case("storage initializes nil with v1 defaults", function()
    local addon = loadStorage()
    local db, initializationError = addon.Storage.Initialize(nil)

    testlib.equal(initializationError, nil)
    testlib.equal(db.schemaVersion, addon.SCHEMA_VERSION)
    testlib.equal(db.settings.units, "metric")
    testlib.equal(db.settings.showMinimap, true)
    testlib.equal(db.settings.showDiagnostics, false)
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
    testlib.equal(db.settings.showDiagnostics, false)
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
            showDiagnostics = true,
        },
        characters = {
            ["Jaina-Proudmoore"] = character,
        },
    }

    local db = addon.Storage.Initialize(existing)

    testlib.equal(db, existing)
    testlib.equal(db.settings.units, "imperial")
    testlib.equal(db.settings.showMinimap, false)
    testlib.equal(db.settings.showDiagnostics, true)
    testlib.equal(db.characters["Jaina-Proudmoore"], character)
end)

testlib.case("storage creates a character and current level bucket", function()
    local addon = loadStorage()
    local db = addon.Storage.Initialize(nil)

    local character = addon.Storage.GetCharacter(db, "Thrall-Area 52", {
        name = "Thrall",
        realm = "Area 52",
        raceFile = "Orc",
        level = 12,
        now = 1000,
    })

    testlib.equal(db.characters["Thrall-Area 52"], character)
    testlib.equal(character.identity.name, "Thrall")
    testlib.equal(character.identity.realm, "Area 52")
    testlib.equal(character.identity.raceFile, "Orc")
    testlib.equal(character.identity.firstSeenAt, 1000)
    assertTotals(character.lifetime, 0, 0, 0)
    assertTotals(character.levels[12], 0, 0, 0)
    testlib.equal(character.levels[12].reachedAt, 1000)
    assertTotals(character.session, 0, 0, 0)
    testlib.equal(character.session.startedAt, 1000)
    testlib.truthy(type(character.diagnostics) == "table")
end)

testlib.case("storage refreshes existing identity and starts a fresh session", function()
    local addon = loadStorage()
    local db = addon.Storage.Initialize(nil)
    local character = addon.Storage.GetCharacter(db, "Thrall-Area 52", {
        name = "Thrall",
        realm = "Area 52",
        raceFile = "Orc",
        level = 12,
        now = 1000,
    })
    addon.Storage.AddDistance(character, 12, "onFoot", 25)

    local sameCharacter = addon.Storage.GetCharacter(db, "Thrall-Area 52", {
        name = "Goel",
        realm = "Area 52",
        raceFile = "MagharOrc",
        level = 13,
        now = 2000,
    })

    testlib.equal(sameCharacter, character)
    testlib.equal(character.identity.name, "Goel")
    testlib.equal(character.identity.realm, "Area 52")
    testlib.equal(character.identity.raceFile, "MagharOrc")
    testlib.equal(character.identity.firstSeenAt, 1000)
    assertTotals(character.lifetime, 25, 0, 0)
    assertTotals(character.levels[12], 25, 0, 0)
    testlib.equal(character.levels[12].reachedAt, 1000)
    assertTotals(character.levels[13], 0, 0, 0)
    testlib.equal(character.levels[13].reachedAt, 2000)
    assertTotals(character.session, 0, 0, 0)
    testlib.equal(character.session.startedAt, 2000)
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

testlib.case("storage preserves unsupported future schemas without mutation", function()
    local addon = loadStorage()
    local existing = {
        schemaVersion = addon.SCHEMA_VERSION + 1,
        sentinel = {
            value = "future-data",
        },
    }
    local sentinel = existing.sentinel

    local db, initializationError = addon.Storage.Initialize(existing)

    testlib.equal(db, existing)
    testlib.equal(initializationError, "unsupportedSchema")
    testlib.equal(existing.schemaVersion, addon.SCHEMA_VERSION + 1)
    testlib.equal(existing.sentinel, sentinel)
    testlib.equal(existing.settings, nil)
    testlib.equal(existing.characters, nil)
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
