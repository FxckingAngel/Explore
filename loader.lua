--[[
	Dex Loader
	FxckingAngel/Explore
	
	Single-line executor entry point.
	Fetches and initializes all modules in dependency order.
	
	Usage:
	  loadstring(game:HttpGet("https://raw.githubusercontent.com/FxckingAngel/Explore/main/loader.lua"))()
]]

local BASE_URL = "https://raw.githubusercontent.com/FxckingAngel/Explore/main/Modules/"
local HTTP = game:GetService("HttpService")

local function fetch(module)
	local ok, src = pcall(game.HttpGet, game, BASE_URL .. module .. ".lua")
	if not ok or not src or #src == 0 then
		error(("[Dex Loader] Failed to fetch module '%s': %s"):format(module, tostring(src)), 2)
	end
	local fn, err = loadstring(src)
	if not fn then
		error(("[Dex Loader] Failed to compile module '%s': %s"):format(module, tostring(err)), 2)
	end
	local ok2, result = pcall(fn)
	if not ok2 then
		error(("[Dex Loader] Failed to run module '%s': %s"):format(module, tostring(result)), 2)
	end
	return result
end

-- Load order matters: Lib must be first, others depend on it
local modules = {"Lib", "Explorer", "Properties", "ScriptViewer"}

print("[Dex Loader] Starting...")
for _, name in ipairs(modules) do
	print(("[Dex Loader] Loading %s..."):format(name))
	fetch(name)
end
print("[Dex Loader] Done.")
