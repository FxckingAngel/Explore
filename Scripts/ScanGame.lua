--[[
	ScanGame — Deathball Health System Scanner
	Scans all accessible scripts for health/damage/hit logic
	
	loadstring(game:HttpGet("https://raw.githubusercontent.com/FxckingAngel/Explore/main/Scripts/ScanGame.lua"))()
]]

local plr = game:GetService("Players").LocalPlayer
local results = {}

local function getSource(script)
	local ok, src = pcall(function()
		setscriptable(script, "Source", true)
		return script.Source
	end)
	if ok and src and #src > 0 then return src end
	local decompile = rawget(_G, "decompile")
	if decompile then
		local ok2, src2 = pcall(decompile, script)
		if ok2 and src2 and #src2 > 0 then return src2 end
	end
	return nil
end

local keywords = {
	"health", "damage", "hit", "deflect", "lives", "death",
	"hurt", "hp", "shield", "block", "ball", "RockTemplate"
}

local function containsKeyword(src)
	local low = src:lower()
	for _, kw in pairs(keywords) do
		if low:find(kw:lower(), 1, true) then return kw end
	end
	return nil
end

print("[Scan] Starting scan of all accessible scripts...")
local count = 0
local found = 0

for _, obj in pairs(game:GetDescendants()) do
	if obj:IsA("LocalScript") or obj:IsA("ModuleScript") or obj:IsA("Script") then
		count = count + 1
		local src = getSource(obj)
		if src and #src > 10 then
			local kw = containsKeyword(src)
			if kw then
				found = found + 1
				print("\n[MATCH] " .. obj:GetFullName() .. " (keyword: " .. kw .. ")")
				-- Print relevant lines
				local lines = src:split("\n")
				for i, line in pairs(lines) do
					local low = line:lower()
					for _, k in pairs(keywords) do
						if low:find(k:lower(), 1, true) then
							print("  L" .. i .. ": " .. line:sub(1, 120))
							break
						end
					end
				end
			end
		end
	end
end

print("\n[Scan] Done. Scanned "..count.." scripts, found "..found.." matches.")

-- Also scan for health-related RemoteEvents
print("\n[Scan] RemoteEvents with health/damage/hit names:")
for _, obj in pairs(game:GetDescendants()) do
	if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
		local name = obj.Name:lower()
		for _, kw in pairs(keywords) do
			if name:find(kw:lower(), 1, true) then
				print("  " .. obj.ClassName .. ": " .. obj:GetFullName())
				break
			end
		end
	end
end

-- Scan for health-related values in character and PlayerGui
print("\n[Scan] Values in character:")
if plr.Character then
	for _, v in pairs(plr.Character:GetDescendants()) do
		if v:IsA("NumberValue") or v:IsA("IntValue") or v:IsA("StringValue") then
			print("  " .. v.Name .. " = " .. tostring(v.Value) .. " (" .. v:GetFullName() .. ")")
		end
	end
end

print("\n[Scan] Values in PlayerGui.HUD:")
local hud = plr.PlayerGui:FindFirstChild("HUD", true)
if hud then
	for _, v in pairs(hud:GetDescendants()) do
		if v:IsA("NumberValue") or v:IsA("IntValue") or v:IsA("StringValue") then
			print("  " .. v.Name .. " = " .. tostring(v.Value) .. " (" .. v:GetFullName() .. ")")
		end
	end
end
