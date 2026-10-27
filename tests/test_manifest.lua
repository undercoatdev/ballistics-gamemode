-- The static file list used by remote clients must match the files on disk.
local root = "gamemodes/ballistics/gamemode/"
local failed = false
local function check(name, ok)
	print((ok and "ok " or "FAIL ") .. name)
	if not ok then failed = true end
end
BALLISTICS = {}
dofile(root .. "core/sh_manifest.lua")
local M = BALLISTICS.Manifest
local listed = {}
for _, f in ipairs(M.modules) do listed[f] = true end
local disk, missing = 0, {}
local p = io.popen("cd " .. root .. " && find modules -name '*.lua'")
for line in p:lines() do
	disk = disk + 1
	if not listed[line] then missing[#missing + 1] = line end
end
p:close()
check("every module file is in the manifest (run tools/gen_manifest.sh): " .. table.concat(missing, ", "), #missing == 0)
check("the manifest lists no extra module files", disk == #M.modules)
local core = {}
local p2 = io.popen("cd " .. root .. "core && ls *.lua")
local n = 0
for line in p2:lines() do if line ~= "sh_manifest.lua" then n = n + 1 end end
p2:close()
check("every core file is in the manifest", n == #M.core)
local loader = io.open(root .. "core/sh_loader.lua"):read("*a")
check("loader includes through pcall so one error cannot stop the rest", loader:find("pcall(include", 1, true) ~= nil and not loader:find("[^%w]include%(rel%)"))
if failed then os.exit(1) end
