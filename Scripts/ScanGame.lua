--[[
	ScanGame v2 — Uses setscriptable + decompile like Explorer does
	
	loadstring(game:HttpGet("https://raw.githubusercontent.com/FxckingAngel/Explore/main/Scripts/ScanGame.lua"))()
]]

local plr = game:GetService("Players").LocalPlayer
local keywords = {
	"health","damage","hit","deflect","lives","death",
	"hurt","hp","shield","block","ball","RockTemplate",
	"deflectbutton","toolbar","ability"
}

local function getSource(obj)
	-- Method 1: setscriptable
	local ok, src = pcall(function()
		setscriptable(obj, "Source", true)
		return obj.Source
	end)
	if ok and type(src)=="string" and #src > 20 then return src end

	-- Method 2: decompile
	local decompile = rawget(_G,"decompile") or rawget(_G,"decomp")
	if decompile then
		local ok2, src2 = pcall(decompile, obj)
		if ok2 and type(src2)=="string" and #src2 > 20 then return src2 end
	end

	-- Method 3: getscriptbytecode -> decompile
	local gbc = rawget(_G,"getscriptbytecode") or rawget(_G,"dumpstring")
	if gbc and decompile then
		local ok3, bc = pcall(gbc, obj)
		if ok3 then
			local ok4, src3 = pcall(decompile, bc)
			if ok4 and type(src3)=="string" and #src3 > 20 then return src3 end
		end
	end

	return nil
end

local function scan(obj, depth)
	depth = depth or 0
	if depth > 10 then return end

	local src = nil
	if obj:IsA("LocalScript") or obj:IsA("ModuleScript") or obj:IsA("Script") then
		src = getSource(obj)
		if src and #src > 20 then
			local low = src:lower()
			for _, kw in pairs(keywords) do
				if low:find(kw:lower(), 1, true) then
					print("\n[MATCH] "..obj:GetFullName().." | kw="..kw.." | len="..#src)
					-- Print lines with keywords
					for i, line in pairs(src:split("\n")) do
						local ll = line:lower()
						for _, k in pairs(keywords) do
							if ll:find(k:lower(),1,true) then
								print("  "..i..": "..line:sub(1,150))
								break
							end
						end
					end
					break
				end
			end
		end
	end

	-- Recurse children
	local ok, children = pcall(function() return obj:GetChildren() end)
	if ok then
		for _, child in pairs(children) do
			scan(child, depth+1)
		end
	end
end

print("[ScanGame v2] Scanning with Explorer-level access...")
print("[ScanGame v2] Checking PlayerGui, ReplicatedFirst, ReplicatedStorage...")

-- Focus on most likely locations
local targets = {
	plr.PlayerGui,
	game:GetService("ReplicatedFirst"),
	game:GetService("ReplicatedStorage"),
	game:GetService("StarterGui"),
}

for _, target in pairs(targets) do
	print("\n--- Scanning: "..target:GetFullName().." ---")
	scan(target)
end

print("\n[ScanGame v2] Done.")

-- Also print the HUD tree structure
print("\n[HUD Tree]")
local hud = plr.PlayerGui:FindFirstChild("HUD")
if hud then
	local function printTree(obj, indent)
		indent = indent or ""
		local extra = ""
		if obj:IsA("LocalScript") or obj:IsA("ModuleScript") then
			local src = getSource(obj)
			extra = src and (" [src:"..#src.."chars]") or " [no src]"
		end
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			extra = ' "'..obj.Text..'"'
		end
		print(indent..obj.Name.." ("..obj.ClassName..")"..extra)
		for _, child in pairs(obj:GetChildren()) do
			printTree(child, indent.."  ")
		end
	end
	printTree(hud)
end
