# Travel State and Statistics Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Exclude mounted, flying-form, and vehicle movement from on-foot totals, keep ground and aquatic forms in their correct categories, refresh capability diagnostics after transient state changes, and reject non-finite derived step estimates.

**Architecture:** Extend the existing compatibility sample with normalized `flying` and `vehicle` state, then keep classification inside `Movement` so class and spell IDs never leak into tracking. Forward each sample's capability snapshot through `Tracker` to `Core`, updating the existing shared table in place. Reject derived overflow at the `Stride`/`UIModel` boundary without modifying authoritative yard totals.

**Tech Stack:** World of Warcraft Lua, the repository's custom Lua test harness, PowerShell packaging tests, and the WoW Forever MCP API/UI indexes.

---

## File Map

- `AzerothTravelMetrics/Compat.lua`: Normalize Forever travel-state APIs and expose capability snapshots.
- `AzerothTravelMetrics/Movement.lua`: Apply state-based category semantics.
- `AzerothTravelMetrics/Tracker.lua`: Preserve the added state fields and forward capability snapshots.
- `AzerothTravelMetrics/Core.lua`: Refresh the shared capability table after every sample.
- `AzerothTravelMetrics/Stride.lua`: Reject invalid and overflowing step calculations.
- `AzerothTravelMetrics/UIModel.lua`: Convert rejected step estimates into `invalidStatistics`.
- `tests/test_compat.lua`: Cover flying/vehicle API guards and capability dependencies.
- `tests/test_movement.lua`: Cover ground forms, aquatic forms, flight forms, vehicles, mounts, and taxi priority.
- `tests/test_tracker.lua`: Cover state snapshots and capability forwarding.
- `tests/test_core.lua`: Cover failure-to-recovery capability updates.
- `tests/test_stride.lua`: Cover invalid and overflowing step calculations.
- `tests/test_ui_model.lua`: Cover malformed SavedVariables that overflow only during step derivation.
- `README.md`: Document form classification.
- `docs/BETA-SMOKE-TESTS.md`: Add explicit in-game form and vehicle checks.

### Task 1: Normalize Forever Flying and Vehicle State

**Files:**
- Modify: `tests/test_compat.lua:9-325`
- Modify: `AzerothTravelMetrics/Compat.lua:20-167`

- [ ] **Step 1: Add flying and vehicle APIs to the complete compatibility fixture**

Add these globals after `IsMounted` in `completeGlobals`:

```lua
        IsFlying = function()
            return false
        end,
        UnitInVehicle = function()
            return false
        end,
```

Extend `"compat reads a complete normalized sample"`:

```lua
    testlib.equal(value.flying, false)
    testlib.equal(value.vehicle, false)
```

Extend the nil-predicate fixture and assertions:

```lua
        IsFlying = function()
            return nil
        end,
        UnitInVehicle = function()
            return nil
        end,
```

```lua
    testlib.equal(value.flying, false)
    testlib.equal(value.vehicle, false)
    testlib.equal(capabilities.flying, true)
    testlib.equal(capabilities.vehicle, true)
```

- [ ] **Step 2: Add failing guard and dependency tests**

Add flying and vehicle entries to `stateCases`:

```lua
        { name = "flying", globalName = "IsFlying", field = "flying", capability = "flying" },
        { name = "vehicle", globalName = "UnitInVehicle", field = "vehicle", capability = "vehicle" },
```

Add `flying` and `vehicle` to the expected capability field list.

Add these dependency expectations:

```lua
        flying = { taxiReady = true, swimmingReady = true, onFootReady = false },
        vehicle = { taxiReady = true, swimmingReady = false, onFootReady = false },
```

Add their global mappings:

```lua
        flying = "IsFlying",
        vehicle = "UnitInVehicle",
```

Add a test that essential failures still return the attempted capability snapshot:

```lua
testlib.case("compat returns capabilities with essential sample failures", function()
    local addon = loadCompat(completeGlobals({
        C_Map = false,
    }))

    local value, reason, capabilities = addon.Compat.ReadSample()

    testlib.equal(value, nil)
    testlib.equal(reason, "mapUnavailable")
    testlib.equal(type(capabilities), "table")
    testlib.equal(capabilities.position, true)
    testlib.equal(capabilities.map, false)
    testlib.equal(capabilities.flying, true)
    testlib.equal(capabilities.vehicle, true)
    testlib.equal(capabilities.onFootReady, false)
end)
```

- [ ] **Step 3: Run the compatibility tests and verify the new cases fail**

Run:

```powershell
lua .\tests\run.lua
```

Expected: failures mentioning missing `flying`, `vehicle`, or the third capabilities return.

- [ ] **Step 4: Implement normalized flying and vehicle state**

In `readCapabilities`, add:

```lua
    local flyingValue, flying = callBoolean(IsFlying)
    local vehicleValue, vehicle = callBoolean(UnitInVehicle, "player")
```

Extend the capability table:

```lua
        flying = flying,
        vehicle = vehicle,
```

Use this dependency matrix:

```lua
    capabilities.taxiReady = capabilities.position
        and capabilities.map
        and capabilities.time
        and capabilities.taxi
    capabilities.swimmingReady = capabilities.taxiReady
        and capabilities.swimming
        and capabilities.mounted
        and capabilities.vehicle
    capabilities.onFootReady = capabilities.swimmingReady
        and capabilities.grounded
        and capabilities.flying
```

Extend the values table:

```lua
        flying = flyingValue,
        vehicle = vehicleValue,
```

Return capability snapshots for all essential failures:

```lua
    if not capabilities.position then
        return nil, "positionUnavailable", capabilities
    end
    if not capabilities.map then
        return nil, "mapUnavailable", capabilities
    end
    if not capabilities.time then
        return nil, "timeUnavailable", capabilities
    end
```

Extend successful samples:

```lua
        flying = values.flying,
        vehicle = values.vehicle,
```

- [ ] **Step 5: Run the Lua suite**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass with the count increased from 232.

- [ ] **Step 6: Commit the compatibility adapter change**

```powershell
git add -- AzerothTravelMetrics\Compat.lua tests\test_compat.lua
git commit -m "fix: normalize Forever travel states" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 2: Classify Forms, Mounts, and Vehicles by State

**Files:**
- Modify: `tests/test_movement.lua:9-247`
- Modify: `AzerothTravelMetrics/Movement.lua:27-64`

- [ ] **Step 1: Extend the movement sample fixture**

Add these defaults after `mounted = false`:

```lua
        flying = false,
        vehicle = false,
```

- [ ] **Step 2: Add failing travel-semantics tests**

Extend the taxi case so taxi remains valid while flying:

```lua
                flying = true,
                vehicle = false,
```

Extend the swimming case:

```lua
                flying = false,
                vehicle = false,
```

Add explicit form behavior:

```lua
testlib.case("movement keeps ground and aquatic forms in distance categories", function()
    local addon = loadMovement()
    local groundForm = sample({
        swimming = false,
        mounted = false,
        flying = false,
        vehicle = false,
        grounded = true,
    })
    local aquaticForm = sample({
        swimming = true,
        mounted = false,
        flying = false,
        vehicle = false,
        grounded = false,
    })

    testlib.equal(
        addon.Movement.Classify(groundForm),
        addon.Categories.ON_FOOT
    )
    testlib.equal(
        addon.Movement.Classify(aquaticForm),
        addon.Categories.SWIMMING
    )
end)
```

Add exclusion coverage:

```lua
testlib.case("movement excludes mounts flying forms and vehicles", function()
    local addon = loadMovement()
    local cases = {
        { name = "mounted", overrides = { mounted = true } },
        { name = "flying form", overrides = { flying = true } },
        { name = "vehicle", overrides = { vehicle = true } },
    }

    for _, case in ipairs(cases) do
        local value = sample(case.overrides)
        local category, reason = addon.Movement.Classify(value)

        testlib.equal(category, nil, case.name .. " was classified")
        testlib.equal(reason, "unsupportedState", case.name .. " returned the wrong reason")
    end
end)
```

Add missing and malformed `flying` and `vehicle` cases to
`"movement rejects missing and non-boolean state flags"`.

- [ ] **Step 3: Run the Lua suite and verify classification failures**

Run:

```powershell
lua .\tests\run.lua
```

Expected: the flight-form and vehicle cases fail because the classifier ignores those fields.

- [ ] **Step 4: Implement the state-based classifier**

Keep taxi priority, then replace the non-taxi validation and exclusions with:

```lua
    if type(sample.swimming) ~= "boolean"
        or type(sample.mounted) ~= "boolean"
        or type(sample.flying) ~= "boolean"
        or type(sample.vehicle) ~= "boolean"
    then
        return nil, "unsupportedState"
    end

    if sample.mounted or sample.flying or sample.vehicle then
        return nil, "unsupportedState"
    end

    if sample.swimming then
        return ATM.Categories.SWIMMING
    end
```

Leave the existing grounded check for on-foot classification.

- [ ] **Step 5: Run the Lua suite**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass.

- [ ] **Step 6: Commit the classifier**

```powershell
git add -- AzerothTravelMetrics\Movement.lua tests\test_movement.lua
git commit -m "fix: classify form and vehicle travel" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 3: Forward Capability Snapshots Through Tracker

**Files:**
- Modify: `tests/test_tracker.lua:9-380`
- Modify: `AzerothTravelMetrics/Tracker.lua:8-151`

- [ ] **Step 1: Extend tracker test samples and sequence returns**

Add defaults:

```lua
        flying = false,
        vehicle = false,
```

Extend `sequenceReader`:

```lua
        return entry.value, entry.reason, entry.capabilities
```

Extend `assertSampleSnapshot`:

```lua
    testlib.equal(actual.flying, expected.flying)
    testlib.equal(actual.vehicle, expected.vehicle)
```

- [ ] **Step 2: Add failing capability-forwarding tests**

Add:

```lua
testlib.case("tracker forwards capabilities on baseline rejection and read failure", function()
    local addon = loadTracker()
    local ready = {
        position = true,
        onFootReady = true,
    }
    local unavailable = {
        position = false,
        onFootReady = false,
    }
    local first = sample({
        capabilities = ready,
    })
    local deps = validDependencies()
    deps.compat.ReadSample = sequenceReader({
        { value = first },
        {
            value = nil,
            reason = "positionUnavailable",
            capabilities = unavailable,
        },
    })
    local tracker = addon.Tracker.New(deps)

    local firstSegment, firstReason, firstCapabilities = tracker:Sample()
    local secondSegment, secondReason, secondCapabilities = tracker:Sample()

    testlib.equal(firstSegment, nil)
    testlib.equal(firstReason, "baseline")
    testlib.equal(firstCapabilities, ready)
    testlib.equal(secondSegment, nil)
    testlib.equal(secondReason, "positionUnavailable")
    testlib.equal(secondCapabilities, unavailable)
end)
```

Extend an accepted-segment test to assert its third return equals the second
sample's capability table.

- [ ] **Step 3: Run the Lua suite and verify forwarding tests fail**

Run:

```powershell
lua .\tests\run.lua
```

Expected: capability return assertions fail.

- [ ] **Step 4: Preserve new state and forward capabilities**

Extend `copySample`:

```lua
        flying = sample.flying,
        vehicle = sample.vehicle,
```

At the start of `TrackerPrototype:Sample`:

```lua
    local current, reason, capabilities = self.compat.ReadSample()
    if current == nil then
        reason = reason or "sampleUnavailable"
        incrementDiagnostic(self.character, reason)
        self.previous = nil
        return nil, reason, capabilities
    end

    capabilities = current.capabilities or capabilities
```

Append `capabilities` to every return after a successful read:

```lua
        return nil, "baseline", capabilities
```

```lua
        return nil, reason, capabilities
```

```lua
        return segment, "emitFailed", capabilities
```

```lua
    return segment, nil, capabilities
```

- [ ] **Step 5: Run the Lua suite**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass.

- [ ] **Step 6: Commit tracker forwarding**

```powershell
git add -- AzerothTravelMetrics\Tracker.lua tests\test_tracker.lua
git commit -m "fix: forward sampling capabilities" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 4: Refresh Core Capabilities After Every Sample

**Files:**
- Modify: `tests/test_core.lua:51-280`
- Modify: `tests/test_core.lua:1209-1354`
- Modify: `AzerothTravelMetrics/Core.lua:7-168`
- Modify: `AzerothTravelMetrics/Core.lua:348-380`

- [ ] **Step 1: Extend the core harness**

Add `flying` and `vehicle` to the default capabilities returned by
`GetCapabilities`.

Change the harness tracker return:

```lua
            return result.segment, result.reason, result.capabilities
```

- [ ] **Step 2: Add the failing recovery test**

Add after the existing world-entry capability refresh test:

```lua
testlib.case("ticker refreshes shared capabilities after failure and recovery", function()
    local harness = newCoreHarness({
        capabilities = {
            position = true,
            map = true,
            onFootReady = true,
            stale = true,
        },
        sampleResults = {
            {
                reason = "positionUnavailable",
                capabilities = {
                    position = false,
                    map = true,
                    onFootReady = false,
                },
            },
            {
                reason = "baseline",
                capabilities = {
                    position = true,
                    map = true,
                    onFootReady = true,
                },
            },
        },
    })
    makeReady(harness)
    local capabilities = harness.calls.uiContext.capabilities
    local ticker = harness.calls.tickers[1]

    ticker.callback()
    testlib.equal(capabilities.position, false)
    testlib.equal(capabilities.onFootReady, false)
    testlib.equal(capabilities.stale, nil)

    ticker.callback()
    testlib.equal(capabilities.position, true)
    testlib.equal(capabilities.onFootReady, true)
    testlib.equal(harness.calls.capabilities, 1)
end)
```

- [ ] **Step 3: Run the Lua suite and verify the recovery test fails**

Run:

```powershell
lua .\tests\run.lua
```

Expected: the shared capability values remain unchanged after ticker callbacks.

- [ ] **Step 4: Extract an in-place capability replacement helper**

Replace `refreshCapabilities` with:

```lua
local function replaceCapabilities(capabilities)
    if type(capabilities) ~= "table" then
        return false
    end

    for key in pairs(state.capabilities) do
        state.capabilities[key] = nil
    end
    for key, value in pairs(capabilities) do
        state.capabilities[key] = value
    end
    return true
end

local function refreshCapabilities()
    return replaceCapabilities(readCapabilities())
end
```

Add `flying` and `vehicle` to `CAPABILITY_KEYS`.

- [ ] **Step 5: Consume tracker capability returns**

Change the protected tracker call:

```lua
    local succeeded, segment, reason, capabilities = pcall(
        state.tracker.Sample,
        state.tracker
    )
```

After the failure guard, add:

```lua
    replaceCapabilities(capabilities)
```

Keep reason reporting and UI refresh behavior unchanged.

- [ ] **Step 6: Run the Lua suite**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass and the capability table identity remains stable.

- [ ] **Step 7: Commit runtime capability recovery**

```powershell
git add -- AzerothTravelMetrics\Core.lua tests\test_core.lua
git commit -m "fix: refresh recovered capabilities" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 5: Reject Derived Step Overflow

**Files:**
- Modify: `tests/test_stride.lua:55-80`
- Modify: `tests/test_ui_model.lua:280-329`
- Modify: `AzerothTravelMetrics/Stride.lua:34-44`
- Modify: `AzerothTravelMetrics/UIModel.lua:55-131`

- [ ] **Step 1: Add failing stride validation tests**

Add:

```lua
testlib.case("stride rejects invalid and overflowing estimates", function()
    local addon = loadStride()
    local invalidYards = {
        { name = "missing", value = nil },
        { name = "negative", value = -1 },
        { name = "NaN", value = 0 / 0 },
        { name = "infinite", value = math.huge },
        { name = "derived overflow", value = 1.7e308 },
    }

    for _, invalid in ipairs(invalidYards) do
        local steps, reason = addon.Stride.EstimateSteps(
            invalid.value,
            "Human"
        )
        testlib.equal(steps, nil, invalid.name .. " returned steps")
        testlib.equal(
            reason,
            "invalidDistance",
            invalid.name .. " returned the wrong reason"
        )
    end
end)
```

- [ ] **Step 2: Add failing UI model overflow tests**

Add:

```lua
testlib.case("ui model rejects finite totals whose derived steps overflow", function()
    local addon = loadUIModel()
    local character = newCharacter()
    character.lifetime.onFoot = 1.7e308
    character.lifetime.swimming = 0
    character.lifetime.taxi = 0

    assertInvalidStatistics(function()
        return addon.UIModel.BuildOverview(character, 20, "metric")
    end, "overflowing derived lifetime steps")

    character = newCharacter()
    character.levels[20].onFoot = 1.7e308
    character.levels[20].swimming = 0
    character.levels[20].taxi = 0

    assertInvalidStatistics(function()
        return addon.UIModel.BuildLevelRows(character, "metric")
    end, "overflowing derived level steps")
end)
```

- [ ] **Step 3: Run the Lua suite and verify overflow failures**

Run:

```powershell
lua .\tests\run.lua
```

Expected: `math.floor` or `infB` behavior causes the new tests to fail.

- [ ] **Step 4: Validate calculations inside Stride**

Add:

```lua
local function isFiniteNumber(value)
    return type(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end
```

Replace `EstimateSteps`:

```lua
function Stride.EstimateSteps(yards, raceFile)
    if not isFiniteNumber(yards) or yards < 0 then
        return nil, "invalidDistance"
    end

    local meters = ATM.Distance.YardsToMeters(yards)
    local rawSteps = meters / Stride.GetMeters(raceFile)
    if not isFiniteNumber(rawSteps) or rawSteps < 0 then
        return nil, "invalidDistance"
    end

    local steps = math.floor(rawSteps + 0.5)
    if not isFiniteNumber(steps) then
        return nil, "invalidDistance"
    end

    return steps
end
```

- [ ] **Step 5: Propagate invalid derived values through UIModel**

Change `buildSummary` so it returns `nil` when `rawSteps` is not a finite
nonnegative integer:

```lua
local function buildSummary(totals, raceFile, units)
    local rawSteps = ATM.Stride.EstimateSteps(totals.onFoot, raceFile)
    if not isNonnegativeInteger(rawSteps) then
        return nil
    end

    local totalYards = totals.onFoot + totals.swimming + totals.taxi
    return {
        rawSteps = rawSteps,
        steps = ATM.Distance.FormatNumber(rawSteps),
        onFootYards = totals.onFoot,
        swimmingYards = totals.swimming,
        taxiYards = totals.taxi,
        totalYards = totalYards,
        onFoot = ATM.Distance.Format(totals.onFoot, units),
        swimming = ATM.Distance.Format(totals.swimming, units),
        taxi = ATM.Distance.Format(totals.taxi, units),
        total = ATM.Distance.Format(totalYards, units),
    }
end
```

In `BuildOverview`, build the summaries before returning:

```lua
    local lifetime = buildSummary(character.lifetime, raceFile, displayUnits)
    local session = buildSummary(character.session, raceFile, displayUnits)
    local currentLevelSummary = buildSummary(
        levelTotals,
        raceFile,
        displayUnits
    )
    if not lifetime or not session or not currentLevelSummary then
        return nil, "invalidStatistics"
    end

    return {
        lifetime = lifetime,
        session = session,
        currentLevel = currentLevelSummary,
    }
```

In `BuildLevelRows`, reject a nil row:

```lua
        local row = buildSummary(totals, raceFile, displayUnits)
        if not row then
            return nil, "invalidStatistics"
        end
```

- [ ] **Step 6: Run the Lua suite**

Run:

```powershell
lua .\tests\run.lua
```

Expected: all tests pass with no `inf`, `nan`, or `infB` model values.

- [ ] **Step 7: Commit statistics hardening**

```powershell
git add -- AzerothTravelMetrics\Stride.lua AzerothTravelMetrics\UIModel.lua tests\test_stride.lua tests\test_ui_model.lua
git commit -m "fix: reject derived step overflow" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

### Task 6: Document and Validate Travel Semantics

**Files:**
- Modify: `README.md`
- Modify: `docs/BETA-SMOKE-TESTS.md`

- [ ] **Step 1: Document classification rules in README**

Add after the feature list:

```markdown
Travel categories follow movement state rather than class or form IDs. Ground
forms such as Druid Cat and Bear forms count as on-foot travel, and Aquatic
Form counts as swimming. Mounts, flying forms, and vehicles are excluded.
Flight paths remain the only movement recorded in the taxi category.
```

- [ ] **Step 2: Add focused Forever smoke cases**

Add these rows near the existing walking, swimming, and mounted cases:

```markdown
| Ground travel forms | Move the same measured route in normal form and in available ground forms such as Druid Cat and Bear. | Each route increases on-foot distance; neither route increases swimming or taxi totals; ground-form travel does not report unsupported state. | Not run in this automated session | PENDING |
| Aquatic travel form | Enter swimmable water, move in normal swimming state and in Druid Aquatic Form, then leave the water. | Both swimming routes increase only swimming distance; entry and exit transitions add no bridge segment. | Not run in this automated session | PENDING |
| Flying forms and vehicles excluded | Travel in Druid Flight Form and in an available vehicle, then return to ordinary ground movement. | Flight-form and vehicle movement add no distance; subsequent ground movement resumes without a bridge segment. | Not run in this automated session | PENDING |
```

Keep the existing mounted test. Do not add a mounted-flying case because
Forever does not have mounted flying.

- [ ] **Step 3: Run all documented validation suites**

Run:

```powershell
$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') +
    ';' +
    [System.Environment]::GetEnvironmentVariable('Path','User')
lua .\tests\run.lua
.\tests\Test-PackageAddon.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentityContent.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-ReleaseIdentity.ps1
```

Expected:

- Lua suite: all tests pass;
- packaging fixtures: 40 pass, zero fail, with the administrator-only symlink case allowed to skip;
- release identity content: 7 pass, zero fail;
- standalone release identity: pass.

- [ ] **Step 4: Run repository hygiene checks**

Run:

```powershell
git diff --check
git status --short
```

Expected: no whitespace errors; only intentional files plus the pre-existing
untracked `.gsd\` and `.gsd-worktrees\` directories appear.

- [ ] **Step 5: Commit documentation**

```powershell
git add -- README.md docs\BETA-SMOKE-TESTS.md
git commit -m "docs: define travel form behavior" `
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>" `
  -m "Copilot-Session: 9b68d91d-485e-4826-b6bd-f7143572f938"
```

- [ ] **Step 6: Verify the final commit range**

Run:

```powershell
git --no-pager log -6 --oneline --decorate
git status --short
```

Expected: the design, plan, and six focused implementation/documentation
commits are present; the working tree has no tracked changes.
