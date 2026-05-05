--[[
	RecordFight v2 — Deathball Data Recorder
	Watches game's own health UI + ball data
	
	loadstring(game:HttpGet("https://raw.githubusercontent.com/FxckingAngel/Explore/main/Scripts/RecordFight.lua"))()
]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local plr        = Players.LocalPlayer

local events     = {}
local startTime  = tick()
local lastLogTime = 0
local cachedBall = nil
local recording  = false

-- Find the game's health display
local function findGameHP()
	-- Search PlayerGui for health-related values
	for _, v in pairs(plr.PlayerGui:GetDescendants()) do
		local name = v.Name:lower()
		if (name:find("health") or name:find("hp") or name:find("life") or name:find("heart"))
		and (v:IsA("TextLabel") or v:IsA("IntValue") or v:IsA("NumberValue") or v:IsA("Frame")) then
			print("[REC] Found HP element: " .. v:GetFullName() .. " (" .. v.ClassName .. ")")
			if v:IsA("TextLabel") then
				print("[REC]   Text: " .. v.Text)
			elseif v:IsA("IntValue") or v:IsA("NumberValue") then
				print("[REC]   Value: " .. v.Value)
			end
		end
	end
	-- Also check ReplicatedStorage and workspace
	for _, v in pairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
		local name = v.Name:lower()
		if (name:find("health") or name:find("hp") or name:find("life"))
		and v:IsA("NumberValue") or v:IsA("IntValue") then
			print("[REC] Found HP in RS: " .. v:GetFullName() .. " = " .. tostring(v.Value))
		end
	end
end

-- Track ball
local function watchFX(fx)
	local rock = fx:FindFirstChild("RockTemplate")
	if rock then cachedBall = rock end
	fx.ChildAdded:Connect(function(c)
		if c.Name == "RockTemplate" then cachedBall = c end
	end)
	fx.ChildRemoved:Connect(function(c)
		if c.Name == "RockTemplate" and cachedBall == c then cachedBall = nil end
	end)
end
local _fx = workspace:FindFirstChild("FX")
if _fx then watchFX(_fx) end
workspace.ChildAdded:Connect(function(c) if c.Name == "FX" then watchFX(c) end end)

-- Watch for any value that changes during gameplay
local watchedValues = {}
local function watchAllValues()
	print("[REC] Watching all IntValue/NumberValue/StringValue for changes...")
	local function watchV(v)
		if watchedValues[v] then return end
		watchedValues[v] = v.Value
		v.Changed:Connect(function(newVal)
			if not recording then return end
			local old = watchedValues[v]
			watchedValues[v] = newVal
			-- Only log significant changes
			if type(newVal) == "number" and math.abs((newVal or 0) - (old or 0)) > 0 then
				local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
				local dist = -1
				local spd = -1
				if root and cachedBall and cachedBall.Parent then
					dist = math.floor(Vector3.new(cachedBall.Position.X-root.Position.X,0,cachedBall.Position.Z-root.Position.Z).Magnitude)
					spd = math.floor(cachedBall.AssemblyLinearVelocity.Magnitude)
				end
				print(string.format("[REC] VALUE_CHANGE: %s  %s->%s  dist=%d spd=%d",
					v:GetFullName(), tostring(old), tostring(newVal), dist, spd))
				table.insert(events, {
					t=tick()-startTime, e="VALUE_CHANGE",
					path=v:GetFullName(), old=old, new=newVal,
					dist=dist, spd=spd
				})
			end
		end)
	end
	-- Watch PlayerGui values
	for _, v in pairs(plr.PlayerGui:GetDescendants()) do
		if v:IsA("IntValue") or v:IsA("NumberValue") or v:IsA("StringValue") then
			pcall(watchV, v)
		end
	end
	-- Watch character values
	if plr.Character then
		for _, v in pairs(plr.Character:GetDescendants()) do
			if v:IsA("IntValue") or v:IsA("NumberValue") then
				pcall(watchV, v)
			end
		end
	end
end

-- Ball distance logger
RunService.Heartbeat:Connect(function()
	if not recording then return end
	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not cachedBall or not cachedBall.Parent then return end

	local now = tick()
	if now - lastLogTime < 0.5 then return end
	lastLogTime = now

	local dist = math.floor(Vector3.new(
		cachedBall.Position.X-root.Position.X,0,
		cachedBall.Position.Z-root.Position.Z).Magnitude)
	local spd = math.floor(cachedBall.AssemblyLinearVelocity.Magnitude)

	if spd > 5 or dist < 20 then
		print(string.format("[REC] t=%.1f BALL dist=%d spd=%d", tick()-startTime, dist, spd))
		table.insert(events, {t=tick()-startTime, e="BALL", dist=dist, spd=spd})
	end
end)

local function startRec()
	events = {}
	startTime = tick()
	lastLogTime = 0
	recording = true
	watchAllValues()
	print("[REC] ======= RECORDING STARTED =======")
	print("[REC] All value changes will be logged.")
	print("[REC] Play normally, get hit, then run _G.stopRec()")
end

local function stopRec()
	recording = false
	print("\n[REC] ======= DONE =======")
	print("[REC] Total events: "..#events)
	print("[REC] Events with VALUE_CHANGE (game health changes):")
	for _, e in pairs(events) do
		if e.e == "VALUE_CHANGE" then
			print(string.format("  t=%.1f %s: %s->%s  dist=%d spd=%d",
				e.t, e.path, tostring(e.old), tostring(e.new), e.dist, e.spd))
		end
	end
end

_G.startRec  = startRec
_G.stopRec   = stopRec
_G.findHP    = findGameHP

print("[RecordFight v2] Commands:")
print("  _G.findHP()    - scan for health elements")  
print("  _G.startRec()  - start recording")
print("  _G.stopRec()   - stop and show results")
print("Run _G.findHP() first to find the health system")
