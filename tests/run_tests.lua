local directory = arg[0]:match("(.*/)") or "./"
package.path = directory .. "../?.lua;" .. directory .. "../?/init.lua;" .. package.path
require("tests.helper")
local specs = { "tests.spec.plugin_spec", "tests.spec.renderer_spec" }
if #arg > 0 then
    specs = {}
    for _, path in ipairs(arg) do
        specs[#specs + 1] = path:gsub("^%./", ""):gsub("%.lua$", ""):gsub("/", ".")
    end
end
for _, spec in ipairs(specs) do
    require(spec)
end
os.exit(require("tests.PanelsPlusTestFramework").summary() and 0 or 1)
