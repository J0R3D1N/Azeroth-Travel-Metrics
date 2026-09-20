local separator = package.config:sub(1, 1)
package.path = "tests" .. separator .. "?.lua;" .. package.path

local testlib = require("testlib")

local modules = {
    "test_namespace",
    "test_distance",
    "test_stride",
    "test_storage",
    "test_movement",
    "test_compat",
    "test_tracker",
    "test_ui_model",
    "test_core",
    "test_minimap",
}

for _, moduleName in ipairs(modules) do
    local path = "tests" .. separator .. moduleName .. ".lua"
    local file = io.open(path, "r")
    if file then
        file:close()
        require(moduleName)
    end
end

local passed = 0
local failed = 0

for _, testCase in ipairs(testlib.cases) do
    local success, failure = pcall(testCase.callback)
    if success then
        passed = passed + 1
        print("PASS " .. testCase.name)
    else
        failed = failed + 1
        print("FAIL " .. testCase.name)
        print("  " .. tostring(failure))
    end
end

print(string.format("%d passed, %d failed", passed, failed))

if failed > 0 then
    os.exit(1)
end
