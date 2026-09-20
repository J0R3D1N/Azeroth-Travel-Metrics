local testlib = {
    cases = {},
}

function testlib.case(name, callback)
    table.insert(testlib.cases, {
        name = name,
        callback = callback,
    })
end

function testlib.equal(actual, expected, message)
    if actual ~= expected then
        error(message or string.format("expected %s, got %s", tostring(expected), tostring(actual)), 2)
    end
end

function testlib.near(actual, expected, tolerance, message)
    if actual ~= actual or expected ~= expected or tolerance ~= tolerance then
        error(message or "near does not accept NaN", 2)
    end

    if math.abs(actual - expected) > tolerance then
        error(
            message
                or string.format(
                    "expected %s to be within %s of %s",
                    tostring(actual),
                    tostring(tolerance),
                    tostring(expected)
                ),
            2
        )
    end
end

function testlib.truthy(value, message)
    if not value then
        error(message or "expected a truthy value", 2)
    end
end

local separator = package.config:sub(1, 1)
local testlibPath = debug.getinfo(1, "S").source:sub(2)
local testsDirectory = testlibPath:match("^(.*)[\\/][^\\/]+$") or "."
local projectDirectory = testsDirectory:match("^(.*)[\\/][^\\/]+$") or "."

local function resolvePath(path)
    if path:match("^%a:[\\/]") or path:match("^[\\/]") then
        return path
    end

    local normalizedPath = path:gsub("[\\/]", separator)
    return projectDirectory .. separator .. normalizedPath
end

local function loadChunk(path, environment)
    local resolvedPath = resolvePath(path)

    if setfenv then
        local chunk, loadError = loadfile(resolvedPath)
        if not chunk then
            error(loadError, 3)
        end

        setfenv(chunk, environment)
        return chunk
    end

    local chunk, loadError = loadfile(resolvedPath, "t", environment)
    if not chunk then
        error(loadError, 3)
    end

    return chunk
end

function testlib.loadAddon(files, globals)
    if type(files) == "string" then
        files = { files }
    end

    local environment = globals or {}
    if getmetatable(environment) == nil then
        setmetatable(environment, { __index = _G })
    end
    environment._G = environment

    local addon = {}
    for _, path in ipairs(files) do
        local chunk = loadChunk(path, environment)
        chunk("AzerothTravelTracker", addon)
    end

    return addon, environment
end

return testlib
