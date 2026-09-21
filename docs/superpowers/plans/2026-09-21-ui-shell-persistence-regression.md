# UI Shell and Persistence Regression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the conflicting portrait-template window with an Azeroth Public Library-style custom shell and restore the correct saved character totals after relog while starting exactly one fresh session per addon runtime.

**Architecture:** Storage will separate character resolution from session creation and recover uniquely matching records through conservative name/realm normalization. Core startup will initialize only SavedVariables during `ADDON_LOADED`, then bind identity, create runtime dependencies, and start the ticker on the first valid `PLAYER_ENTERING_WORLD`. UITheme will own a dependency-free custom backdrop recipe, while UI will explicitly create the icon, title, controls, version footer, and content surfaces.

**Tech Stack:** World of Warcraft addon Lua, Blizzard frame/texture APIs, SavedVariables, dependency-free Lua tests, PowerShell packaging tests, Git.

**Approved design:** `docs/superpowers/specs/2026-09-21-ui-shell-persistence-regression-design.md`

---

## File Map

| File | Responsibility |
|---|---|
| `AzerothTravelTracker\Namespace.lua` | Add a package-version fallback used when client metadata lookup is unavailable. |
| `AzerothTravelTracker\Storage.lua` | Resolve exact/recovered/new character records without resetting sessions; expose explicit session start. |
| `AzerothTravelTracker\Core.lua` | Split database initialization from stable character/runtime initialization. |
| `AzerothTravelTracker\UITheme.lua` | Create the warm translucent outer shell, decorative layers, icon frame, and visible fallback border. |
| `AzerothTravelTracker\UI.lua` | Use the custom shell; explicitly create title controls and version text; remove the redundant content inset. |
| `tests\test_storage.lua` | Prove lookup/session separation, normalized re-keying, ambiguity handling, and totals preservation. |
| `tests\test_core.lua` | Prove deferred identity binding, one session start, retry behavior, one ticker, UI geometry, metadata, and close/reopen invariance. |
| `docs\BETA-SMOKE-TESTS.md` | Replace obsolete portrait-shell expectations and add explicit relog/reopen validation. |

## Task 1: Separate Character Resolution from Session Creation

**Files:**
- Modify: `AzerothTravelTracker\Storage.lua:19-191`
- Modify: `tests\test_storage.lua:13-205`

- [ ] **Step 1: Rewrite the existing-character test so lookup preserves the active session**

Replace the test named `storage refreshes existing identity and starts a fresh session` with:

```lua
testlib.case("storage lookup preserves existing session and refreshes identity", function()
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

    local sameCharacter, resolution = addon.Storage.GetCharacter(
        db,
        "Thrall-Area 52",
        {
            name = "Thrall",
            realm = "Area 52",
            raceFile = "MagharOrc",
            level = 13,
            now = 2000,
        }
    )

    testlib.equal(resolution, "exact")
    testlib.equal(sameCharacter, character)
    testlib.equal(character.identity.name, "Thrall")
    testlib.equal(character.identity.realm, "Area 52")
    testlib.equal(character.identity.raceFile, "MagharOrc")
    testlib.equal(character.identity.firstSeenAt, 1000)
    assertTotals(character.lifetime, 25, 0, 0)
    assertTotals(character.levels[12], 25, 0, 0)
    assertTotals(character.levels[13], 0, 0, 0)
    assertTotals(character.session, 25, 0, 0)
    testlib.equal(character.session.startedAt, 1000)
end)
```

Update `newCharacter` and the character-creation test to call `StartSession` explicitly after `GetCharacter`:

```lua
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
```

- [ ] **Step 2: Add failing tests for normalized recovery and ambiguous matches**

Add these cases after the character-creation test:

```lua
testlib.case("storage rekeys one normalized identity match without losing totals", function()
    local addon = loadStorage()
    local db = addon.Storage.Initialize(nil)
    local original = addon.Storage.GetCharacter(db, "Traveler-Old Key", {
        name = " Traveler ",
        realm = "Test Realm",
        raceFile = "Human",
        level = 42,
        now = 1000,
    })
    addon.Storage.StartSession(original, 1000)
    addon.Storage.AddDistance(original, 42, "taxi", 75)

    local recovered, resolution = addon.Storage.GetCharacter(
        db,
        "Traveler-TestRealm",
        {
            name = "traveler",
            realm = "test realm",
            raceFile = "Human",
            level = 43,
            now = 2000,
        }
    )

    testlib.equal(resolution, "rekeyed")
    testlib.equal(recovered, original)
    testlib.equal(db.characters["Traveler-Old Key"], nil)
    testlib.equal(db.characters["Traveler-TestRealm"], original)
    assertTotals(recovered.lifetime, 0, 0, 75)
    assertTotals(recovered.levels[42], 0, 0, 75)
    assertTotals(recovered.session, 0, 0, 75)
    testlib.equal(recovered.session.startedAt, 1000)
end)

testlib.case("storage does not merge ambiguous normalized identity matches", function()
    local addon = loadStorage()
    local db = addon.Storage.Initialize(nil)
    local first = addon.Storage.GetCharacter(db, "First-Key", {
        name = "Traveler",
        realm = "Test Realm",
        raceFile = "Human",
        level = 42,
        now = 1000,
    })
    local second = {
        identity = {
            name = " traveler ",
            realm = "testrealm",
            raceFile = "Human",
            firstSeenAt = 1100,
        },
        lifetime = { onFoot = 99, swimming = 0, taxi = 0 },
        levels = {},
        diagnostics = {},
    }
    db.characters["Second-Key"] = second

    local created, resolution = addon.Storage.GetCharacter(
        db,
        "Traveler-TestRealm",
        {
            name = "Traveler",
            realm = "Test Realm",
            raceFile = "Human",
            level = 42,
            now = 2000,
        }
    )

    testlib.equal(resolution, "ambiguous")
    testlib.truthy(created ~= first)
    testlib.truthy(created ~= second)
    testlib.equal(db.characters["First-Key"], first)
    testlib.equal(db.characters["Second-Key"], second)
    testlib.equal(db.characters["Traveler-TestRealm"], created)
    testlib.equal(created.diagnostics.ambiguousIdentity, 1)
    assertTotals(created.lifetime, 0, 0, 0)
    testlib.equal(created.session, nil)
end)
```

- [ ] **Step 3: Run storage tests and verify the lifecycle assertions fail**

Run:

```powershell
Set-Location 'D:\_projects\wow-forever-step-tracker'
lua tests\run.lua
```

Expected: storage failures because `Storage.StartSession` does not exist, `GetCharacter` still resets the session, and normalized recovery is absent.

- [ ] **Step 4: Implement conservative normalized character recovery**

Add these helpers below `ensureTotals` in `Storage.lua`:

```lua
local function normalizeIdentityPart(value)
    if type(value) ~= "string" then
        return nil
    end

    local normalized = value:match("^%s*(.-)%s*$")
    normalized = normalized:gsub("%s+", "")
    normalized = normalized:lower()
    if normalized == "" then
        return nil
    end
    return normalized
end

local function identityMatches(character, identity)
    local stored = character and character.identity
    return stored ~= nil
        and normalizeIdentityPart(stored.name)
            == normalizeIdentityPart(identity.name)
        and normalizeIdentityPart(stored.realm)
            == normalizeIdentityPart(identity.realm)
end

local function createCharacter(identity)
    return {
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
end

local function refreshCharacter(character, identity)
    character.identity = character.identity or {}
    character.lifetime = ensureTotals(character.lifetime)
    character.levels = character.levels or {}
    character.diagnostics = character.diagnostics or {}

    if character.identity.firstSeenAt == nil then
        character.identity.firstSeenAt = identity.now
    end
    character.identity.name = identity.name or character.identity.name
    character.identity.realm = identity.realm or character.identity.realm
    character.identity.raceFile =
        identity.raceFile or character.identity.raceFile
end
```

Replace `Storage.GetCharacter` with:

```lua
function Storage.GetCharacter(db, key, identity)
    local character = db.characters[key]
    local resolution = "exact"

    if character == nil then
        local matchedKey
        local matchCount = 0
        for candidateKey, candidate in pairs(db.characters) do
            if identityMatches(candidate, identity) then
                matchedKey = candidateKey
                character = candidate
                matchCount = matchCount + 1
            end
        end

        if matchCount == 1 then
            db.characters[matchedKey] = nil
            db.characters[key] = character
            resolution = "rekeyed"
        else
            character = createCharacter(identity)
            db.characters[key] = character
            if matchCount > 1 then
                character.diagnostics.ambiguousIdentity = 1
                resolution = "ambiguous"
            else
                resolution = "created"
            end
        end
    end

    refreshCharacter(character, identity)
    Storage.EnsureLevel(character, identity.level, identity.now)
    return character, resolution
end

function Storage.StartSession(character, now)
    return Storage.ResetSession(character, now)
end
```

- [ ] **Step 5: Run all Lua tests**

Run:

```powershell
lua tests\run.lua
```

Expected: all tests pass, including exact lookup, unique re-keying, ambiguity isolation, and explicit session start.

- [ ] **Step 6: Commit the storage lifecycle change**

```powershell
git add AzerothTravelTracker\Storage.lua tests\test_storage.lua
git commit -m "fix: preserve character totals during lookup" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 2: Defer Runtime Binding Until Entering World

**Files:**
- Modify: `AzerothTravelTracker\Core.lua:29-272,485-508`
- Modify: `tests\test_core.lua:38-620`

- [ ] **Step 1: Update the core harness to observe session starts**

Add `startSession = 0` to the harness call counters and add this storage stub beside `GetCharacter`:

```lua
StartSession = function(receivedCharacter, now)
    calls.startSession = calls.startSession + 1
    calls.startSessionArguments = {
        character = receivedCharacter,
        now = now,
    }
    receivedCharacter.session = {
        onFoot = 0,
        swimming = 0,
        taxi = 0,
        startedAt = now,
    }
    return receivedCharacter.session
end,
```

- [ ] **Step 2: Replace eager-startup tests with database/runtime phase tests**

Replace the test named `core ignores nonmatching ADDON_LOADED and initializes matching addon once` with:

```lua
testlib.case("addon loaded initializes only the saved database", function()
    local harness = newCoreHarness({
        savedDB = { sentinel = true },
    })

    harness.fire("ADDON_LOADED", "OtherAddon")
    testlib.equal(harness.calls.initialize, 0)

    initialize(harness)
    testlib.equal(harness.calls.initialize, 1)
    testlib.equal(harness.calls.identity, 0)
    testlib.equal(harness.calls.getCharacter, 0)
    testlib.equal(harness.calls.startSession, 0)
    testlib.equal(harness.calls.trackerNew, 0)
    testlib.equal(harness.calls.uiInitialize, 0)
    testlib.equal(harness.calls.minimapInitialize, 0)
    testlib.equal(#harness.calls.tickers, 0)
    testlib.equal(harness.environment.AzerothTravelTrackerDB, harness.db)
    testlib.equal(harness.addon.Core.GetState().databaseReady, true)
    testlib.equal(harness.addon.Core.GetState().ready, false)
end)

testlib.case("first entering world binds one character session and one ticker", function()
    local harness = newCoreHarness()
    initialize(harness)

    harness.fire("PLAYER_ENTERING_WORLD")

    testlib.equal(harness.calls.identity, 1)
    testlib.equal(harness.calls.getCharacter, 1)
    testlib.equal(harness.calls.startSession, 1)
    testlib.equal(harness.calls.startSessionArguments.character, harness.character)
    testlib.equal(harness.calls.startSessionArguments.now, 1000)
    testlib.equal(harness.calls.trackerNew, 1)
    testlib.equal(harness.calls.uiInitialize, 1)
    testlib.equal(harness.calls.minimapInitialize, 1)
    testlib.equal(#harness.calls.tickers, 1)
    testlib.equal(harness.addon.Core.GetState().ready, true)
end)

testlib.case("later entering world events preserve session and ticker", function()
    local harness = newCoreHarness()
    initialize(harness)
    harness.fire("PLAYER_ENTERING_WORLD")
    local firstTicker = harness.calls.tickers[1]

    harness.fire("PLAYER_ENTERING_WORLD")

    testlib.equal(harness.calls.identity, 1)
    testlib.equal(harness.calls.getCharacter, 1)
    testlib.equal(harness.calls.startSession, 1)
    testlib.equal(harness.calls.trackerNew, 1)
    testlib.equal(#harness.calls.tickers, 1)
    testlib.equal(firstTicker.cancelled, false)
    testlib.equal(harness.calls.resets, 2)
end)
```

Replace the transient identity test with:

```lua
testlib.case("entering world retries identity without creating an empty record", function()
    local harness = newCoreHarness({
        identityError = "identityUnavailable",
    })
    initialize(harness)

    harness.fire("PLAYER_ENTERING_WORLD")
    testlib.equal(harness.calls.getCharacter, 0)
    testlib.equal(harness.calls.startSession, 0)
    testlib.equal(harness.calls.trackerNew, 0)
    testlib.equal(#harness.calls.tickers, 0)

    harness.options.identityError = nil
    harness.fire("PLAYER_ENTERING_WORLD")

    testlib.equal(harness.calls.identity, 2)
    testlib.equal(harness.calls.getCharacter, 1)
    testlib.equal(harness.calls.startSession, 1)
    testlib.equal(harness.calls.trackerNew, 1)
    testlib.equal(#harness.calls.tickers, 1)
end)
```

- [ ] **Step 3: Run the Lua suite and verify the new lifecycle tests fail**

Run:

```powershell
lua tests\run.lua
```

Expected: core failures because identity, character lookup, UI initialization, and session reset still occur during `ADDON_LOADED`.

- [ ] **Step 4: Split database initialization from runtime initialization**

Change the core state fields to:

```lua
local state = {
    initialized = false,
    databaseReady = false,
    ready = false,
    db = nil,
    character = nil,
    tracker = nil,
    currentLevel = nil,
    capabilities = {},
    ticker = nil,
    reportedReasons = {},
}
```

Replace `failInitialization` with:

```lua
local function failInitialization(reason, preserveDatabase)
    Core.StopTicker()
    state.ready = false
    state.character = nil
    state.tracker = nil
    state.currentLevel = nil
    if not preserveDatabase then
        state.db = nil
        state.databaseReady = false
    end
    Core.ReportOnce(
        reason,
        "Initialization failed: " .. safeText(reason),
        true
    )
end
```

Replace `Core.Initialize` with these two functions:

```lua
function Core.InitializeDatabase()
    if state.initialized then
        return state.databaseReady
    end
    state.initialized = true

    if not ATT.Storage or type(ATT.Storage.Initialize) ~= "function" then
        failInitialization("storageUnavailable")
        return false
    end

    local savedDB = AzerothTravelTrackerDB
    local succeeded, db, initializationError = pcall(
        ATT.Storage.Initialize,
        savedDB
    )
    if not succeeded or db == nil or initializationError ~= nil then
        failInitialization(initializationError or "storageInitializeFailed")
        return false
    end

    state.db = db
    state.databaseReady = true
    AzerothTravelTrackerDB = db
    return true
end

function Core.InitializeRuntime()
    if state.ready then
        return true
    end
    if not state.databaseReady then
        return false
    end

    local identitySucceeded, identity, identityError = pcall(
        ATT.Compat.GetCharacterIdentity
    )
    if not identitySucceeded or type(identity) ~= "table" then
        Core.ReportOnce(
            identityError or "identityUnavailable",
            "Initialization failed: "
                .. safeText(identityError or "identityUnavailable"),
            true
        )
        return false
    end

    local characterKey = identity.name .. "-" .. identity.realm
    local characterSucceeded, character = pcall(
        ATT.Storage.GetCharacter,
        state.db,
        characterKey,
        identity
    )
    if not characterSucceeded or type(character) ~= "table" then
        failInitialization("characterInitializeFailed", true)
        return false
    end

    local sessionSucceeded, session = pcall(
        ATT.Storage.StartSession,
        character,
        identity.now
    )
    if not sessionSucceeded or type(session) ~= "table" then
        failInitialization("sessionInitializeFailed", true)
        return false
    end

    local trackerSucceeded, tracker = pcall(ATT.Tracker.New, {
        compat = ATT.Compat,
        storage = ATT.Storage,
        movement = ATT.Movement,
        character = character,
        level = identity.level,
        emit = function(eventName, payload)
            return ATT.Emit(eventName, payload)
        end,
    })
    if not trackerSucceeded or type(tracker) ~= "table" then
        failInitialization("trackerInitializeFailed", true)
        return false
    end

    state.character = character
    state.tracker = tracker
    state.currentLevel = identity.level
    refreshCapabilities()

    local runtimeContext = {
        db = state.db,
        character = character,
        tracker = tracker,
        capabilities = state.capabilities,
        getCurrentLevel = function()
            return state.currentLevel
        end,
    }
    local uiSucceeded = pcall(ATT.UI.Initialize, runtimeContext)
    if not uiSucceeded then
        failInitialization("uiInitializeFailed", true)
        return false
    end

    if ATT.Minimap and type(ATT.Minimap.Initialize) == "function" then
        local minimapSucceeded = pcall(ATT.Minimap.Initialize, runtimeContext)
        if not minimapSucceeded then
            Core.ReportOnce(
                "minimapInitializeFailed",
                "Minimap launcher unavailable: minimapInitializeFailed",
                true
            )
        end
    end

    state.ready = true
    return true
end
```

Replace the event branches with:

```lua
if eventName == "ADDON_LOADED" then
    local loadedAddon = ...
    if loadedAddon == addonName then
        Core.InitializeDatabase()
    end
elseif eventName == "PLAYER_ENTERING_WORLD" then
    if not state.ready then
        if Core.InitializeRuntime() then
            Core.StartTicker()
        end
    else
        refreshCapabilities()
        state.tracker:ResetBaseline()
    end
elseif eventName == "PLAYER_LEVEL_UP" then
    handleLevelUp(...)
elseif eventName == "PLAYER_LOGOUT" then
    Core.StopTicker()
end
```

- [ ] **Step 5: Update core tests that previously assumed eager initialization**

For every core test that calls only `initialize(harness)` before exercising ready-state behavior, add:

```lua
harness.fire("PLAYER_ENTERING_WORLD")
```

Keep storage-schema failure tests at database phase only. Update ticker restart expectations so later `PLAYER_ENTERING_WORLD` events assert one retained ticker and one additional baseline reset.

- [ ] **Step 6: Run all Lua tests**

Run:

```powershell
lua tests\run.lua
```

Expected: all lifecycle, ticker, slash-command, movement, storage, minimap, and UI tests pass.

- [ ] **Step 7: Commit deferred runtime initialization**

```powershell
git add AzerothTravelTracker\Core.lua tests\test_core.lua
git commit -m "fix: bind character after entering world" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 3: Build the Public Library-Style Custom Shell

**Files:**
- Modify: `AzerothTravelTracker\UITheme.lua:1-116`
- Modify: `AzerothTravelTracker\UI.lua:42-101,621-701`
- Modify: `tests\test_core.lua:760-1510`

- [ ] **Step 1: Extend the UI harness for gradient and vertex-color evidence**

Add these methods to the fake frame object in `tests\test_core.lua`:

```lua
function frame:SetGradientAlpha(...)
    self.gradient = { ... }
end

function frame:SetVertexColor(...)
    self.vertexColor = { ... }
end

function frame:SetTexCoord(...)
    self.texCoord = { ... }
end
```

- [ ] **Step 2: Replace portrait-template assertions with custom-shell assertions**

In `ui creation is lazy idempotent and uses requested native structure`, replace the portrait-shell assertions with:

```lua
testlib.equal(first.template, "BackdropTemplate")
testlib.equal(first.width, 420)
testlib.equal(first.height, 430)
testlib.equal(first.strata, "DIALOG")
testlib.truthy(first.backdrop ~= nil)
testlib.near(first.backdropColor[1], 0.08, 0.001)
testlib.near(first.backdropColor[2], 0.06, 0.001)
testlib.near(first.backdropColor[3], 0.035, 0.001)
testlib.near(first.backdropColor[4], 0.95, 0.001)
testlib.equal(harness.addon.UI.shell.darkTexture.texture,
    "Interface\\DialogFrame\\UI-DialogBox-Background-Dark")
testlib.truthy(harness.addon.UI.shell.darkTexture.vertexColor ~= nil)
testlib.truthy(harness.addon.UI.shell.vignette.gradient ~= nil)
testlib.truthy(harness.addon.UI.shell.topGlow.color ~= nil)
testlib.equal(harness.addon.UI.shell.goldTexture.texture,
    "Interface\\DialogFrame\\UI-DialogBox-Gold-Background")
```

Replace `ui falls back from portrait shell to basic shell` with:

```lua
testlib.case("ui falls back from BackdropTemplate to a visible bare shell", function()
    local harness = newUIHarness({
        rejectTemplates = {
            BackdropTemplate = true,
        },
    })
    local frame = harness.addon.UI.Create()

    testlib.equal(frame.template, nil)
    testlib.truthy(harness.addon.UI.shell.fallbackBackground.color ~= nil)
    testlib.equal(#harness.addon.UI.shell.fallbackBorder, 4)
end)
```

- [ ] **Step 3: Run the Lua suite and verify shell tests fail**

Run:

```powershell
lua tests\run.lua
```

Expected: UI failures because the main frame still uses `PortraitFrameBaseTemplate`, has no custom shell layers, and uses an opaque black backing texture.

- [ ] **Step 4: Add a reusable shell builder to UITheme**

Add this backdrop definition and helper below the UITheme constants:

```lua
local SHELL_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {
        left = 4,
        right = 4,
        top = 4,
        bottom = 4,
    },
}

local function createFallbackBorder(parent)
    local border = {}
    local edges = {
        { "TOPLEFT", "TOPRIGHT", "horizontal" },
        { "BOTTOMLEFT", "BOTTOMRIGHT", "horizontal" },
        { "TOPLEFT", "BOTTOMLEFT", "vertical" },
        { "TOPRIGHT", "BOTTOMRIGHT", "vertical" },
    }
    for _, edge in ipairs(edges) do
        local texture = parent:CreateTexture(nil, "BORDER")
        texture:SetPoint(edge[1], parent, edge[1], 0, 0)
        texture:SetPoint(edge[2], parent, edge[2], 0, 0)
        if edge[3] == "horizontal" then
            texture:SetHeight(1)
        else
            texture:SetWidth(1)
        end
        texture:SetColorTexture(0.55, 0.34, 0.12, 0.95)
        table.insert(border, texture)
    end
    return border
end

function Theme.ApplyWindowShell(frame, useBackdrop)
    local shell = {}
    local backdropApplied = false

    if useBackdrop and type(frame.SetBackdrop) == "function" then
        local succeeded = pcall(frame.SetBackdrop, frame, SHELL_BACKDROP)
        if succeeded then
            backdropApplied = pcall(
                frame.SetBackdropColor,
                frame,
                0.08,
                0.06,
                0.035,
                0.95
            )
        end
    end

    if not backdropApplied then
        shell.fallbackBackground = createColorTexture(
            frame,
            "BACKGROUND",
            0.08,
            0.06,
            0.035,
            0.95
        )
        shell.fallbackBorder = createFallbackBorder(frame)
    end

    shell.darkTexture = frame:CreateTexture(nil, "BACKGROUND")
    shell.darkTexture:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -7)
    shell.darkTexture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -7, 7)
    shell.darkTexture:SetTexture(
        "Interface\\DialogFrame\\UI-DialogBox-Background-Dark"
    )
    shell.darkTexture:SetVertexColor(0.42, 0.31, 0.16, 0.88)

    shell.goldTexture = frame:CreateTexture(nil, "BACKGROUND")
    shell.goldTexture:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    shell.goldTexture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    shell.goldTexture:SetTexture(
        "Interface\\DialogFrame\\UI-DialogBox-Gold-Background"
    )
    shell.goldTexture:SetVertexColor(0.55, 0.38, 0.15, 0.16)

    shell.vignette = frame:CreateTexture(nil, "BORDER")
    shell.vignette:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    shell.vignette:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
    local gradientApplied = type(shell.vignette.SetGradientAlpha) == "function"
        and pcall(
            shell.vignette.SetGradientAlpha,
            shell.vignette,
            "VERTICAL",
            0.04, 0.02, 0.01, 0.15,
            0.01, 0.005, 0.002, 0.72
        )
    if not gradientApplied then
        shell.vignette:SetColorTexture(0.02, 0.01, 0.005, 0.42)
    end

    shell.topGlow = frame:CreateTexture(nil, "BORDER")
    shell.topGlow:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -8)
    shell.topGlow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -8)
    shell.topGlow:SetHeight(44)
    shell.topGlow:SetColorTexture(0.78, 0.48, 0.12, 0.14)

    return shell
end
```

- [ ] **Step 5: Make the main frame use only BackdropTemplate or a bare frame**

Replace `createMainFrame` in `UI.lua` with:

```lua
local function createMainFrame()
    local succeeded, frame = pcall(
        CreateFrame,
        "Frame",
        "AzerothTravelTrackerFrame",
        UIParent,
        "BackdropTemplate"
    )
    if succeeded and frame then
        return frame, true
    end

    return CreateFrame(
        "Frame",
        "AzerothTravelTrackerFrame",
        UIParent
    ), false
end
```

In `UI.Create`, delete `UI.mainBackground`, all `SetPortraitToTexture` and `PortraitContainer` logic, and native `TitleText` lookup. Immediately after drag-script registration, add:

```lua
local frame, useBackdrop = createMainFrame()
UI.frame = frame
-- Keep the existing size, position, strata, movement, mouse, and drag setup.
UI.shell = ATT.UITheme.ApplyWindowShell(frame, useBackdrop)
```

Move the existing `local frame = createMainFrame()` and `UI.frame = frame` lines into this replacement so the frame is created exactly once.

- [ ] **Step 6: Run all Lua tests**

Run:

```powershell
lua tests\run.lua
```

Expected: all shell tests pass with `BackdropTemplate`; the bare fallback remains visible when that template is rejected.

- [ ] **Step 7: Commit the custom shell**

```powershell
git add AzerothTravelTracker\UITheme.lua AzerothTravelTracker\UI.lua tests\test_core.lua
git commit -m "feat: add custom warm tracker shell" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 4: Add Explicit Title Controls and Version Footer

**Files:**
- Modify: `AzerothTravelTracker\Namespace.lua:1-10`
- Modify: `AzerothTravelTracker\UITheme.lua:1-20`
- Modify: `AzerothTravelTracker\UI.lua:101-365,621-892`
- Modify: `tests\test_core.lua:945-1510,1660-1830`

- [ ] **Step 1: Add metadata APIs to the UI harness**

In `newUIHarness`, add:

```lua
globals.C_AddOns = {
    GetAddOnMetadata = function(name, field)
        calls.metadataName = name
        calls.metadataField = field
        if options.metadataThrows then
            error("metadata unavailable")
        end
        return options.versionMetadata
    end,
}
```

- [ ] **Step 2: Add failing title-region, footer, and inset-removal assertions**

Add these assertions to the primary UI creation test:

```lua
testlib.equal(harness.addon.UI.iconFrame.width, 36)
testlib.equal(harness.addon.UI.iconFrame.height, 36)
testlib.equal(
    harness.addon.UI.icon.texture,
    "Interface\\Icons\\Ability_Rogue_Sprint"
)
testlib.equal(harness.addon.UI.title:GetText(), "Azeroth Travel Tracker")
testlib.equal(harness.addon.UI.title.point[1], "LEFT")
testlib.equal(harness.addon.UI.title.point[2], harness.addon.UI.iconFrame)
testlib.equal(harness.addon.UI.minimizeButton.point[2], harness.addon.UI.closeButton)
testlib.equal(harness.addon.UI.minimizeButton.point[3], "LEFT")
testlib.truthy(
    harness.addon.UI.minimizeButton.frameLevel > first:GetFrameLevel()
)
testlib.equal(harness.addon.UI.contentInset, nil)
testlib.equal(harness.addon.UI.versionText:GetText(), "ATT v0.1.0-beta")
testlib.equal(harness.addon.UI.versionText.justifyH, "RIGHT")
```

Add metadata-specific tests:

```lua
testlib.case("ui reads the version footer from addon metadata", function()
    local harness = newUIHarness({
        versionMetadata = "0.2.0-test",
    })
    harness.addon.UI.Create()

    testlib.equal(harness.calls.metadataName, "AzerothTravelTracker")
    testlib.equal(harness.calls.metadataField, "Version")
    testlib.equal(
        harness.addon.UI.versionText:GetText(),
        "ATT v0.2.0-test"
    )
end)

testlib.case("ui falls back to the package version when metadata fails", function()
    local harness = newUIHarness({
        metadataThrows = true,
    })
    harness.addon.UI.Create()

    testlib.equal(
        harness.addon.UI.versionText:GetText(),
        "ATT v0.1.0-beta"
    )
end)
```

- [ ] **Step 3: Run the Lua suite and verify title/footer tests fail**

Run:

```powershell
lua tests\run.lua
```

Expected: UI failures because the icon frame and version footer do not exist, minimize is not anchored to close, and `contentInset` is still created.

- [ ] **Step 4: Add a stable fallback version and Sprint portrait icon**

In `Namespace.lua`, add:

```lua
ATT.VERSION_FALLBACK = "0.1.0-beta"
```

Change `UITheme.Icons.PORTRAIT` to:

```lua
PORTRAIT = "Interface\\Icons\\Ability_Rogue_Sprint",
```

- [ ] **Step 5: Add safe metadata lookup and explicit title-region construction**

Change the first line of `UI.lua` to retain the addon name:

```lua
local addonName, ATT = ...
```

Add this helper near `createLabel`:

```lua
local function getAddonVersion()
    local metadata
    if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
        local succeeded, value = pcall(
            C_AddOns.GetAddOnMetadata,
            addonName,
            "Version"
        )
        if succeeded then
            metadata = value
        end
    elseif type(GetAddOnMetadata) == "function" then
        local succeeded, value = pcall(
            GetAddOnMetadata,
            addonName,
            "Version"
        )
        if succeeded then
            metadata = value
        end
    end

    if type(metadata) ~= "string"
        or metadata:match("^%s*$") ~= nil
    then
        return ATT.VERSION_FALLBACK
    end
    return metadata:match("^%s*(.-)%s*$")
end
```

After `UI.shell` is created in `UI.Create`, add:

```lua
UI.iconFrame = CreateFrame("Frame", nil, frame)
UI.iconFrame:SetSize(36, 36)
UI.iconFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
raiseAboveParent(UI.iconFrame, frame, 20)

UI.iconBackground = UI.iconFrame:CreateTexture(nil, "BACKGROUND")
UI.iconBackground:SetAllPoints(UI.iconFrame)
UI.iconBackground:SetColorTexture(0.06, 0.035, 0.015, 0.96)

UI.icon = UI.iconFrame:CreateTexture(nil, "ARTWORK")
UI.icon:SetPoint("TOPLEFT", UI.iconFrame, "TOPLEFT", 3, -3)
UI.icon:SetPoint("BOTTOMRIGHT", UI.iconFrame, "BOTTOMRIGHT", -3, 3)
UI.icon:SetTexture(ATT.UITheme.Icons.PORTRAIT)
UI.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

UI.iconBorder = {}
for _, edge in ipairs({
    { "TOPLEFT", "TOPRIGHT", "horizontal" },
    { "BOTTOMLEFT", "BOTTOMRIGHT", "horizontal" },
    { "TOPLEFT", "BOTTOMLEFT", "vertical" },
    { "TOPRIGHT", "BOTTOMRIGHT", "vertical" },
}) do
    local texture = UI.iconFrame:CreateTexture(nil, "OVERLAY")
    texture:SetPoint(edge[1], UI.iconFrame, edge[1], 0, 0)
    texture:SetPoint(edge[2], UI.iconFrame, edge[2], 0, 0)
    if edge[3] == "horizontal" then
        texture:SetHeight(1)
    else
        texture:SetWidth(1)
    end
    texture:SetColorTexture(0.72, 0.45, 0.16, 1)
    table.insert(UI.iconBorder, texture)
end

UI.title = createLabel(
    frame,
    "Azeroth Travel Tracker",
    "GameFontNormalLarge"
)
UI.title:SetPoint("LEFT", UI.iconFrame, "RIGHT", 9, 0)
UI.title:SetTextColor(1, 0.82, 0, 1)
raiseAboveParent(UI.title, frame, 20)
```

- [ ] **Step 6: Create and order close/minimize controls explicitly**

Always create `UI.closeButton` with `createSafeButton`, anchor it at `TOPRIGHT`, and anchor minimize to its left:

```lua
UI.closeButton = createSafeButton(
    frame,
    "UIPanelCloseButton",
    24,
    24,
    nil,
    "x"
)
UI.closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -9)
raiseAboveParent(UI.closeButton, frame, 30)
UI.closeButton:SetScript("OnClick", function()
    frame:Hide()
end)

UI.minimizeButton = createMinimizeButton(frame)
UI.minimizeButton:ClearAllPoints()
UI.minimizeButton:SetPoint("RIGHT", UI.closeButton, "LEFT", -4, 0)
raiseAboveParent(UI.minimizeButton, frame, 30)
UI.minimizeButton:SetScript("OnClick", function()
    UI.Minimize()
end)
```

Update `createMinimizeButton` so its internal fallback artwork is unchanged but it no longer assigns a parent-relative point.

- [ ] **Step 7: Remove the redundant inset and add the version footer**

Delete:

```lua
UI.contentInset = ATT.UITheme.CreateInset(UI.contentFrame)
```

Create the footer after the settings button:

```lua
UI.versionText = createLabel(
    frame,
    "ATT v" .. getAddonVersion(),
    "GameFontDisableSmall"
)
UI.versionText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 9)
UI.versionText:SetWidth(120)
UI.versionText:SetJustifyH("RIGHT")
UI.versionText:SetTextColor(0.55, 0.50, 0.42, 1)
```

Move the settings button to `BOTTOMRIGHT, -22, 27` so the 24-pixel button sits above the version label without overlap. Keep the reset button at the existing bottom-left location.

- [ ] **Step 8: Run all Lua tests**

Run:

```powershell
lua tests\run.lua
```

Expected: all UI tests pass with an explicit Sprint icon, warm title, visible minimize/close controls, no whole-content inset, and metadata/fallback version text.

- [ ] **Step 9: Commit the title and footer changes**

```powershell
git add AzerothTravelTracker\Namespace.lua AzerothTravelTracker\UITheme.lua AzerothTravelTracker\UI.lua tests\test_core.lua
git commit -m "feat: restore tracker title controls and version" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 5: Prove Window Reopen and Relog Data Invariance

**Files:**
- Modify: `tests\test_core.lua:1180-1830`
- Modify: `docs\BETA-SMOKE-TESTS.md:10-45`

- [ ] **Step 1: Add a close/reopen test that checks table identity and values**

Add this UI test after minimize/restore/toggle coverage:

```lua
testlib.case("closing and reopening preserves tracked character data", function()
    local character = {
        identity = {
            name = "Traveler",
            realm = "TestRealm",
            raceFile = "Human",
        },
        lifetime = {
            onFoot = 120,
            swimming = 30,
            taxi = 450,
        },
        session = {
            onFoot = 12,
            swimming = 3,
            taxi = 45,
            startedAt = 1000,
        },
        levels = {
            [42] = {
                onFoot = 20,
                swimming = 5,
                taxi = 75,
                reachedAt = 900,
            },
        },
        diagnostics = {},
    }
    local harness = newUIHarness({
        character = character,
    })
    local UI = harness.addon.UI
    local lifetime = character.lifetime
    local session = character.session
    local level = character.levels[42]

    UI.ShowMain()
    UI.closeButton.scripts.OnClick()
    UI.ShowMain()

    testlib.equal(harness.character, character)
    testlib.equal(character.lifetime, lifetime)
    testlib.equal(character.session, session)
    testlib.equal(character.levels[42], level)
    testlib.equal(character.lifetime.onFoot, 120)
    testlib.equal(character.session.taxi, 45)
    testlib.equal(character.levels[42].swimming, 5)
end)
```

- [ ] **Step 2: Add a simulated relog test to the core harness**

Add:

```lua
testlib.case("runtime initialization keeps lifetime and levels but resets session", function()
    local character = {
        identity = {
            name = "Traveler",
            realm = "TestRealm",
            raceFile = "Human",
            firstSeenAt = 100,
        },
        lifetime = {
            onFoot = 500,
            swimming = 60,
            taxi = 700,
        },
        session = {
            onFoot = 50,
            swimming = 6,
            taxi = 70,
            startedAt = 900,
        },
        levels = {
            [42] = {
                onFoot = 250,
                swimming = 30,
                taxi = 350,
                reachedAt = 800,
            },
        },
        diagnostics = {},
    }
    local harness = newCoreHarness({
        character = character,
    })
    initialize(harness)
    harness.fire("PLAYER_ENTERING_WORLD")

    testlib.equal(character.lifetime.onFoot, 500)
    testlib.equal(character.lifetime.swimming, 60)
    testlib.equal(character.lifetime.taxi, 700)
    testlib.equal(character.levels[42].onFoot, 250)
    testlib.equal(character.levels[42].swimming, 30)
    testlib.equal(character.levels[42].taxi, 350)
    testlib.equal(character.session.onFoot, 0)
    testlib.equal(character.session.swimming, 0)
    testlib.equal(character.session.taxi, 0)
    testlib.equal(character.session.startedAt, 1000)
end)
```

- [ ] **Step 3: Run all Lua tests**

Run:

```powershell
lua tests\run.lua
```

Expected: all tests pass, including direct evidence that close/reopen does not replace or reset data tables and runtime initialization resets only session totals.

- [ ] **Step 4: Update the manual smoke checklist**

Replace the `Login/logout and /reload` expectation with:

```text
Lifetime, level totals, and settings persist. A new addon runtime starts a fresh This Session without adding a bridge segment; repeated zoning in the same runtime does not reset it.
```

Replace the `Character panel shell` row with:

```text
| Public Library-style shell | Open the tracker beside Azeroth Public Library and inspect the outer backdrop, title region, controls, content surface, and footer. | The tracker uses comparable warm brown translucency and title coloring; the Sprint icon, minimize, close, and version are visible; no transparent inner rectangle remains. | PENDING | PENDING |
```

Add:

```text
| Close and reopen data preservation | Record Lifetime, This Session, and Current Level values; close the regular window; reopen it from the minimap. | Every displayed value is unchanged and tracking continues while the window is hidden. | PENDING | PENDING |
| Relog character recovery | Record the current character key and totals, log out fully, then log back into the same character. | The same Lifetime and per-level totals return; This Session starts at zero; no duplicate empty character record is selected. | PENDING | PENDING |
```

- [ ] **Step 5: Commit regression coverage and smoke instructions**

```powershell
git add tests\test_core.lua docs\BETA-SMOKE-TESTS.md
git commit -m "test: cover UI and relog persistence regressions" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: e5378634-a8ef-4326-aadd-7221ab814010"
```

## Task 6: Validate, Package, Install, and Verify Snapshot Parity

**Files:**
- Verify: `AzerothTravelTracker\*.lua`
- Verify: `tests\*.lua`
- Verify: `tests\Test-PackageAddon.ps1`
- Verify: `tools\Package-Addon.ps1`
- Install: `D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\AzerothTravelTracker`

- [ ] **Step 1: Run the complete Lua suite**

```powershell
Set-Location 'D:\_projects\wow-forever-step-tracker'
lua tests\run.lua
```

Expected: zero failed tests.

- [ ] **Step 2: Run package-script regression tests**

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-PackageAddon.ps1
```

Expected: all packaging tests pass, with only the documented privilege-dependent reparse-point case allowed to skip.

- [ ] **Step 3: Check formatting and repository state**

```powershell
git --no-pager diff --check
git --no-pager status --short
```

Expected: no whitespace errors and no unintended files.

- [ ] **Step 4: Build the committed package**

If validation fails, return to the task that owns the failing file, apply a focused fix with its listed test command, and create a separate commit before continuing. Packaging must run from a clean committed addon snapshot.

```powershell
.\tools\Package-Addon.ps1 -Version '0.1.0-beta'
```

Expected: `artifacts\AzerothTravelTracker-0.1.0-beta.zip` is created from `HEAD`, contains one top-level `AzerothTravelTracker` directory, and reports the packaged commit.

- [ ] **Step 5: Install the exact package into the Forever beta**

Remove only the named installed addon directory, recreate it from the package, and preserve the SavedVariables file:

```powershell
$zip = 'D:\_projects\wow-forever-step-tracker\artifacts\AzerothTravelTracker-0.1.0-beta.zip'
$installRoot = 'D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns'
$installedAddon = Join-Path $installRoot 'AzerothTravelTracker'
$staging = Join-Path $env:TEMP 'AzerothTravelTracker-install'

if (Test-Path -LiteralPath $staging) {
    Remove-Item -LiteralPath $staging -Recurse -Force
}
Expand-Archive -LiteralPath $zip -DestinationPath $staging -Force
if (Test-Path -LiteralPath $installedAddon) {
    Remove-Item -LiteralPath $installedAddon -Recurse -Force
}
Move-Item `
    -LiteralPath (Join-Path $staging 'AzerothTravelTracker') `
    -Destination $installedAddon
Remove-Item -LiteralPath $staging -Recurse -Force
```

Expected: only the installed addon code is replaced. `WTF\Account\...\SavedVariables\AzerothTravelTracker.lua` remains untouched.

- [ ] **Step 6: Verify installed files equal the package**

```powershell
$verify = Join-Path $env:TEMP 'AzerothTravelTracker-verify'
if (Test-Path -LiteralPath $verify) {
    Remove-Item -LiteralPath $verify -Recurse -Force
}
Expand-Archive -LiteralPath $zip -DestinationPath $verify -Force

$expectedRoot = Join-Path $verify 'AzerothTravelTracker'
$expected = Get-ChildItem -LiteralPath $expectedRoot -File -Recurse |
    ForEach-Object {
        [pscustomobject]@{
            Path = $_.FullName.Substring($expectedRoot.Length + 1)
            Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    }
$actual = Get-ChildItem -LiteralPath $installedAddon -File -Recurse |
    ForEach-Object {
        [pscustomobject]@{
            Path = $_.FullName.Substring($installedAddon.Length + 1)
            Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    }

$difference = Compare-Object $expected $actual -Property Path, Hash
if ($difference) {
    $difference | Format-Table -AutoSize
    throw 'Installed addon differs from the packaged snapshot.'
}
Remove-Item -LiteralPath $verify -Recurse -Force
```

Expected: no differences.

- [ ] **Step 7: Perform the focused in-client verification**

In the Forever beta:

1. Run `/reload`.
2. Open Azeroth Travel Tracker beside Azeroth Public Library.
3. Confirm the warm translucent shell, title height/color, Sprint icon, minimize, close, and version label.
4. Confirm the transparent inner rectangle is gone.
5. Record Lifetime, This Session, and Current Level values.
6. Close the regular window and reopen it from the minimap; confirm all values are unchanged.
7. Log out fully and back into the same character; confirm Lifetime and Current Level return while This Session is zero.
8. Zone once; confirm This Session does not reset again.
9. Run `/att status`; confirm no `Tracking unavailable: unsupported state` login message appears.

Expected: every focused regression check passes without a Lua error.

## Completion Criteria

1. `ADDON_LOADED` initializes only SavedVariables.
2. The first valid `PLAYER_ENTERING_WORLD` selects one character, starts one session, initializes runtime UI/minimap, and starts one ticker.
3. Later entering-world events preserve the selected character, session, and ticker while resetting only the tracker baseline.
4. Exact and uniquely normalized character matches preserve lifetime, levels, diagnostics, and `firstSeenAt`; ambiguous matches never merge.
5. The regular window uses a custom warm translucent backdrop with an explicit Sprint icon, title, minimize, close button, and version footer.
6. The redundant whole-content inset is absent.
7. Closing and reopening the regular window does not replace or reset tracked tables.
8. Automated Lua and packaging tests pass.
9. The installed addon is byte-for-byte equal to the package created from committed `HEAD`.
10. Focused in-client shell and relog checks pass.
